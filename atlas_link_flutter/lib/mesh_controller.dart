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
/// Tailscale CLI: everyone shares one ATLAS lobby; peers are read from
/// `tailscale status --json`.
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
  String _username = kDefaultUser;

  // True while a hostname change (initial connect or a name update) hasn't yet
  // been reported back by `tailscale status`. Drives the "Connecting…"
  // indicator.
  bool _joiningRoom = false;
  String? _pendingUserSlug;
  Timer? _joinTimeoutTimer;

  Timer? _pollTimer;

  // --- Read-only surface for the UI -----------------------------------------

  MeshConfig get config => _config;
  bool get loadingConfig => _loadingConfig;
  bool get connecting => _connecting;
  bool get joiningRoom => _joiningRoom;

  /// The name we publish for ourselves (slugified ATLAS profile name). Updates
  /// optimistically so the self row reflects a name change immediately.
  String get selfDisplayName => slugify(_username);
  bool get connected => _connected;
  bool get isUsable => _config.isUsable;

  /// Whether the Discord login gate is configured (offer "Connect with Discord").
  bool get gateEnabled => _config.gateEnabled;
  String get gateUrl => _config.gateUrl;
  bool get tailscaleInstalled => _resolveExe() != null;
  MeshErrorKind? get errorKind => _errorKind;
  String get errorMessage => _errorMessage;
  MeshStatus get status => _status;
  MeshPeer? get self => _status.self;
  String? get selfIp => _status.self?.tailscaleIp;
  List<MeshPeer> get peers => _status.others;
  int get onlineCount => _status.onlineCount();
  int get onlineCap => _config.onlineCap;
  bool get nearOnlineCap => onlineCount >= (onlineCap - 10);

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

  /// Join the ATLAS lobby with the legacy shared key from `mesh.json`.
  Future<bool> connect({required String username}) {
    if (!_config.isUsable) {
      _failConnect(MeshErrorKind.generic, 'ATLAS Network is unavailable right now.');
      return Future.value(false);
    }
    return _connectWithKey(authKey: _config.authKey, username: username);
  }

  /// Join the ATLAS lobby with a per-user key minted by the Discord gate.
  Future<bool> connectWithAuthKey(String authKey, {required String username}) {
    if (authKey.trim().isEmpty) {
      _failConnect(MeshErrorKind.generic, "Couldn't get a network key. Try again.");
      return Future.value(false);
    }
    return _connectWithKey(authKey: authKey.trim(), username: username);
  }

  /// Shared `tailscale up` + verification path for both connect entry points.
  Future<bool> _connectWithKey({
    required String authKey,
    required String username,
  }) async {
    if (_connecting) return false;
    _username = username.trim().isEmpty ? kDefaultUser : username.trim();
    _connecting = true;
    _errorKind = null;
    _errorMessage = '';
    notifyListeners();

    final exe = _resolveExe();
    if (exe == null) {
      return _failConnect(MeshErrorKind.generic, 'Tailscale is not installed.');
    }

    final hostname = buildAtlasHostname(_username);
    final result = await _run(
      tailscaleUpArgs(
        authKey: authKey,
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

    // `up` reported success, but confirm the node is actually up on the tailnet
    // (BackendState Running + a 100.x address) before showing a connected list.
    final live = await _verifyUp();
    if (!live) {
      unawaited(_run(tailscaleDownArgs, timeout: const Duration(seconds: 6)));
      _log('up succeeded but node never came online');
      return _failConnect(
        MeshErrorKind.generic,
        "Tailscale started but isn't responding. Make sure Tailscale is "
        'running, then try again.',
      );
    }

    _connected = true;
    _connecting = false;
    // Surface the Tailscale tray icon now that we're connected, so users have a
    // way to see/close Tailscale themselves. The device is already authenticated
    // here, so the GUI shows "connected" rather than a setup/login window.
    _launchTrayApp();
    // Hold the optimistic name and show "Connecting…" until status reports it.
    _startPendingName();
    _log('connected as $hostname');
    notifyListeners();
    await pollOnce();
    startPolling();
    return true;
  }

  /// Re-publish our identity if the ATLAS profile name changed while connected,
  /// so the new name propagates to everyone. Cheap no-op when unchanged.
  Future<void> syncIdentity(String username) async {
    if (!_connected || _joiningRoom) return;
    final newUser = username.trim().isEmpty ? kDefaultUser : username.trim();
    if (slugify(newUser) == slugify(_username)) return;

    final prevUser = _username;
    _username = newUser;
    _startPendingName();
    notifyListeners();

    final result = await _run(
      tailscaleSetHostnameArgs(buildAtlasHostname(newUser)),
      timeout: const Duration(seconds: 15),
    );
    if (result == null || result.exitCode != 0) {
      _username = prevUser;
      _joiningRoom = false;
      _pendingUserSlug = null;
      _joinTimeoutTimer?.cancel();
      _log('name update failed');
      notifyListeners();
      return;
    }
    _log('publishing name=$newUser');
    notifyListeners();
    await pollOnce();
  }

  /// Begin the "Connecting…" hold until `tailscale status` reports our name.
  void _startPendingName() {
    _joiningRoom = true;
    _pendingUserSlug = slugify(_username);
    _joinTimeoutTimer?.cancel();
    _joinTimeoutTimer = Timer(const Duration(seconds: 12), () {
      _joiningRoom = false;
      _pendingUserSlug = null;
      notifyListeners();
    });
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
    _joiningRoom = false;
    _pendingUserSlug = null;
    _joinTimeoutTimer?.cancel();
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
    final self = parsed.self;
    if (self != null &&
        _pendingUserSlug != null &&
        self.name == _pendingUserSlug) {
      _joiningRoom = false;
      _pendingUserSlug = null;
      _joinTimeoutTimer?.cancel();
    }
    notifyListeners();
  }

  /// Start periodic polling (only meaningful while the room menu is open).
  void startPolling() {
    if (_pollTimer != null || !_connected) return;
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => unawaited(pollOnce()),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Fast, fire-and-forget disconnect for app-exit / lifecycle paths so a closed
  /// launcher never leaves the user sitting in a room. Idempotent.
  void downNowSync() {
    stopPolling();
    _joinTimeoutTimer?.cancel();
    if (_connected && _tailscaleExe != null) {
      try {
        Process.runSync(_tailscaleExe!, tailscaleDownArgs);
      } catch (_) {
        // Best effort — the process is closing anyway.
      }
      _connected = false;
    }
  }

  /// Awaitable disconnect for the graceful exit-request hook.
  Future<void> shutdown() async {
    stopPolling();
    _joinTimeoutTimer?.cancel();
    if (_connected) {
      await _run(tailscaleDownArgs, timeout: const Duration(seconds: 6));
      _connected = false;
    }
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

  String _friendlyError(MeshErrorKind kind) {
    switch (kind) {
      case MeshErrorKind.capacity:
        return 'ATLAS Network is full, too many players online right now. '
            'Try again in a bit.';
      case MeshErrorKind.expiredKey:
        return 'ATLAS Network is temporarily unavailable, try again soon.';
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

  /// Best-effort launch of the Tailscale tray app (`tailscale-ipn.exe`, next to
  /// `tailscale.exe`) so a connected user has a way to see/close Tailscale. It's
  /// single-instance, so calling it when already running just no-ops.
  void _launchTrayApp() {
    final exe = _tailscaleExe;
    if (exe == null) return;
    final gui = File(
      '${File(exe).parent.path}${Platform.pathSeparator}tailscale-ipn.exe',
    );
    if (!gui.existsSync()) return;
    try {
      Process.start(gui.path, const <String>[], mode: ProcessStartMode.detached);
    } catch (_) {
      // Non-fatal — the connection works without the tray.
    }
  }

  /// Poll status briefly until the node reports it is actually up on the
  /// tailnet (BackendState Running + a 100.x address). False if it never does,
  /// which means Tailscale isn't really working even though `up` returned 0.
  Future<bool> _verifyUp() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final result = await _run(
        tailscaleStatusArgs,
        timeout: const Duration(seconds: 8),
      );
      if (result != null && result.exitCode == 0) {
        try {
          final decoded = jsonDecode(result.stdout as String);
          if (decoded is Map) {
            final backend = decoded['BackendState']?.toString() ?? '';
            final self = decoded['Self'];
            if (backend == 'Running' && self is Map) {
              final ips =
                  (self['TailscaleIPs'] as List?)?.map((e) => e.toString()) ??
                  const <String>[];
              if (ips.any((s) => s.startsWith('100.'))) {
                _status = parseTailscaleStatusJson(result.stdout as String);
                return true;
              }
            }
          }
        } catch (_) {
          // Malformed output — fall through and retry.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
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
    downNowSync();
    super.dispose();
  }
}
