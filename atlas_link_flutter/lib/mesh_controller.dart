import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'tailscale_mesh.dart';

/// Where the launcher reads the ATLAS network config (auth key is base64'd).
const String kMeshConfigUrl =
    'https://raw.githubusercontent.com/cipherfps/ATLAS-Link/main/config/mesh.json';

/// Owns all Tailscale "Network" state and side effects so the giant launcher
/// State class (and the room dialog) only render from it. Drives the official
/// Tailscale CLI: one shared ATLAS tailnet, room encoded in the hostname, peers
/// read from `tailscale status --json`.
class MeshController extends ChangeNotifier {
  MeshController({this.configUrl = kMeshConfigUrl, this.logger});

  final String configUrl;
  final void Function(String message)? logger;

  MeshConfig _config = MeshConfig.disabled;
  bool _loadingConfig = false;

  String? _tailscaleExe;
  bool _exeResolved = false;

  bool _connecting = false;
  bool _connected = false;
  MeshErrorKind? _errorKind;
  String _errorMessage = '';

  MeshStatus _status = const MeshStatus(self: null, others: <MeshPeer>[]);
  String _currentRoom = kDefaultRoom;
  String _username = kDefaultUser;

  Timer? _pollTimer;

  // --- Read-only surface for the UI -----------------------------------------

  MeshConfig get config => _config;
  bool get loadingConfig => _loadingConfig;
  bool get connecting => _connecting;
  bool get connected => _connected;
  bool get isUsable => _config.isUsable;
  bool get tailscaleInstalled => _resolveExe() != null;
  MeshErrorKind? get errorKind => _errorKind;
  String get errorMessage => _errorMessage;
  MeshStatus get status => _status;
  String get currentRoom => _currentRoom;
  MeshPeer? get self => _status.self;
  String? get selfIp => _status.self?.tailscaleIp;
  List<MeshPeer> get peers => _status.others;
  List<String> get rooms => _status.rooms;
  int get onlineCount => _status.onlineCount();
  int get maxRoomSize => _config.maxRoomSize;
  int get onlineCap => _config.onlineCap;
  bool get nearOnlineCap => onlineCount >= (onlineCap - 10);

  List<MeshPeer> membersOf(String room) => _status.membersOf(room);

  int onlineMembersOf(String room) =>
      _status.all.where((p) => p.room == room && p.online).length;

  /// Soft, client-side "lobby is full" check (not a security boundary).
  bool roomIsFull(String room) =>
      room != _currentRoom && onlineMembersOf(room) >= maxRoomSize;

  // --- Actions ---------------------------------------------------------------

  /// Re-check for the Tailscale CLI (e.g. after the user installs it).
  void recheckTailscale() {
    _exeResolved = false;
    _resolveExe();
    notifyListeners();
  }

  /// Fetch `mesh.json` (enabled flag, base64 key, caps). Keeps the previous
  /// config on failure so a transient network hiccup doesn't disable the UI.
  Future<void> loadConfig() async {
    _loadingConfig = true;
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'ATLAS-Link';
    try {
      final request = await client.getUrl(Uri.parse(configUrl));
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          _config = MeshConfig.fromJson(decoded);
        } else if (decoded is Map) {
          _config = MeshConfig.fromJson(decoded.cast<String, dynamic>());
        }
      } else {
        _log('config fetch HTTP ${response.statusCode}');
      }
    } catch (error) {
      _log('config fetch failed: $error');
    } finally {
      client.close(force: true);
      _loadingConfig = false;
      notifyListeners();
    }
  }

  /// Join the ATLAS tailnet (`tailscale up`) under [username], in [room].
  Future<bool> connect({required String username, String? room}) async {
    if (_connecting) return false;
    _username = username.trim().isEmpty ? kDefaultUser : username.trim();
    final targetRoom = _slugRoom(room ?? _currentRoom);
    _connecting = true;
    _errorKind = null;
    _errorMessage = '';
    notifyListeners();

    final exe = _resolveExe();
    if (exe == null) {
      return _failConnect(
        MeshErrorKind.generic,
        'Tailscale is not installed.',
      );
    }
    if (!_config.isUsable) {
      return _failConnect(
        MeshErrorKind.generic,
        'ATLAS Network is unavailable right now.',
      );
    }

    final hostname = buildAtlasHostname(targetRoom, _username);
    final result = await _run(
      tailscaleUpArgs(
        authKey: _config.authKey,
        hostname: hostname,
        loginServer: _config.loginServer,
      ),
      timeout: const Duration(seconds: 30),
    );
    if (result == null) {
      return _failConnect(MeshErrorKind.generic, 'Could not run Tailscale.');
    }
    if (result.exitCode != 0) {
      final stderr = '${result.stderr}\n${result.stdout}';
      final kind = classifyTailscaleError(stderr);
      _log('up failed (${result.exitCode}): ${stderr.trim()}');
      return _failConnect(kind, _friendlyError(kind));
    }

    _connected = true;
    _currentRoom = targetRoom;
    _connecting = false;
    _log('connected as $hostname');
    notifyListeners();
    await pollOnce();
    startPolling();
    return true;
  }

  /// Switch rooms live via `tailscale set --hostname` (no re-auth).
  Future<bool> joinRoom(String room) async {
    if (!_connected) return false;
    final target = _slugRoom(room);
    if (target == _currentRoom) return true;
    final hostname = buildAtlasHostname(target, _username);
    final result = await _run(
      tailscaleSetHostnameArgs(hostname),
      timeout: const Duration(seconds: 15),
    );
    if (result == null || result.exitCode != 0) {
      _log('join room "$target" failed');
      return false;
    }
    _currentRoom = target;
    _log('joined room $target');
    notifyListeners();
    await pollOnce();
    return true;
  }

  /// Leave the tailnet (`tailscale down`) and free the device slot.
  Future<void> disconnect() async {
    stopPolling();
    final result = await _run(
      tailscaleDownArgs,
      timeout: const Duration(seconds: 15),
    );
    _connected = false;
    _status = const MeshStatus(self: null, others: <MeshPeer>[]);
    _log(result == null ? 'disconnect may have failed' : 'disconnected');
    notifyListeners();
  }

  /// Poll `tailscale status --json` once and refresh the peer list.
  Future<void> pollOnce() async {
    if (!_connected) return;
    final result = await _run(
      tailscaleStatusArgs,
      timeout: const Duration(seconds: 8),
    );
    if (result == null || result.exitCode != 0) return;
    final parsed = parseTailscaleStatusJson(result.stdout as String);
    _status = parsed;
    if (parsed.self != null) _currentRoom = parsed.self!.room;
    notifyListeners();
  }

  /// Start periodic polling (only meaningful while the room menu is open).
  void startPolling() {
    if (_pollTimer != null || !_connected) return;
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(pollOnce()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // --- Internals -------------------------------------------------------------

  bool _failConnect(MeshErrorKind kind, String message) {
    _connecting = false;
    _connected = false;
    _errorKind = kind;
    _errorMessage = message;
    notifyListeners();
    return false;
  }

  String _slugRoom(String room) {
    final slug = slugify(room);
    return slug.isEmpty ? kDefaultRoom : slug;
  }

  String _friendlyError(MeshErrorKind kind) {
    switch (kind) {
      case MeshErrorKind.capacity:
        return 'ATLAS Network is full — too many players online right now. '
            'Try again in a bit.';
      case MeshErrorKind.expiredKey:
        return 'ATLAS network is temporarily unavailable — try again soon.';
      case MeshErrorKind.generic:
        return "Couldn't connect to the ATLAS Network. Please try again.";
    }
  }

  String? _resolveExe() {
    if (!_exeResolved) {
      _tailscaleExe = resolveTailscaleExe();
      _exeResolved = true;
    }
    return _tailscaleExe;
  }

  Future<ProcessResult?> _run(List<String> args, {Duration? timeout}) async {
    final exe = _resolveExe();
    if (exe == null) return null;
    try {
      final future = Process.run(exe, args, runInShell: false);
      return timeout == null ? await future : await future.timeout(timeout);
    } catch (error) {
      _log('command failed (${args.join(' ')}): $error');
      return null;
    }
  }

  void _log(String message) => logger?.call(message);

  @override
  void dispose() {
    stopPolling();
    // Best-effort release of the device slot on app exit.
    if (_connected && _tailscaleExe != null) {
      try {
        Process.runSync(_tailscaleExe!, tailscaleDownArgs);
      } catch (_) {
        // Ignore — process is shutting down anyway.
      }
    }
    super.dispose();
  }
}
