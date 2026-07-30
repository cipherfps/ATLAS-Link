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
  MeshController({
    this.configUrl = kMeshConfigUrl,
    this.logger,
    @visibleForTesting this.processRunner,
    @visibleForTesting Duration Function()? elapsed,
  }) : _removalDetector = RemovalDetector(
         threshold: kRemovalSignedOutPolls,
         confirmWindow: kRemovalConfirmWindow,
         maxPollGap: kMaxPlausiblePollGap,
         unreachableAfter: kUnreachableAfter,
         elapsed: elapsed,
       );

  final String configUrl;
  final void Function(String message)? logger;

  /// Test seam: when set, every Tailscale CLI invocation goes here instead of
  /// spawning a process, and CLI discovery is stubbed out. Null in production.
  @visibleForTesting
  final Future<ProcessResult?> Function(List<String> args, Duration? timeout)?
  processRunner;

  /// Poll cadence while the Network dialog is open — the live peer list.
  static const Duration kFastPollInterval = Duration(milliseconds: 1500);

  /// Poll cadence with no menu open: the cheap background removal watch. This
  /// only bounds how long a kick can go unnoticed *before* the first bad poll;
  /// once one lands we drop to [kConfirmPollInterval], so the confirmation cost
  /// is the same from either cadence.
  static const Duration kWatchPollInterval = Duration(seconds: 10);

  /// Cadence used from the first signed-out poll until the run clears or is
  /// confirmed. Short enough to walk [kRemovalConfirmWindow] in small steps
  /// from either starting cadence, so the CONFIRM phase costs the same either
  /// way. Total detection latency is not cadence-independent: it still includes
  /// the wait for the first signed-out poll, which is up to one interval of
  /// whichever cadence was running (see [kWatchPollInterval]).
  static const Duration kConfirmPollInterval = Duration(seconds: 2);

  /// Signed-out polls required before we believe we were removed. Polls we
  /// could not read do not count — see [MeshPollOutcome].
  static const int kRemovalSignedOutPolls = 3;

  /// Elapsed time that must also be credited across the run before the
  /// disconnect. Guards against a burst of signed-out polls that is really one
  /// event: a stalled CLI call, or a Tailscale service restart/auto-update,
  /// both of which resolve well inside this window on a healthy machine.
  static const Duration kRemovalConfirmWindow = Duration(seconds: 12);

  /// Largest gap between two consecutive signed-out polls that still counts as
  /// one continuous observation: `max(60s, 4 x the slowest cadence)`. A
  /// suspend/resume, a frozen process or a daemon that vanished for minutes
  /// produce a bigger gap than this, and re-anchor the run instead of banking
  /// the time.
  static final Duration kMaxPlausiblePollGap =
      kWatchPollInterval * 4 > const Duration(seconds: 60)
      ? kWatchPollInterval * 4
      : const Duration(seconds: 60);

  /// How long polls we cannot read may persist before the UI is told we can't
  /// reach Tailscale. Informational only: nothing is disconnected.
  static const Duration kUnreachableAfter = Duration(seconds: 90);

  /// Stand-in for `tailscale.exe` when [processRunner] is injected.
  static const String _stubExe = 'tailscale';

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

  /// The cadence the UI actually wants: true while the Network dialog is open.
  /// Tracked separately from what is armed so a good poll can restore it after
  /// the confirm cadence.
  bool _pollFast = false;

  /// True while a run of bad polls is being confirmed on [kConfirmPollInterval].
  bool _confirming = false;

  /// Interval currently armed on [_pollTimer], so re-targeting can no-op when
  /// nothing changed instead of restarting the period every call.
  Duration? _armedInterval;

  /// True while a [pollOnce] is in flight. Ticks that land during one are
  /// dropped: a single stalled `tailscale status` must not be able to
  /// manufacture a run of bad polls out of one hang.
  bool _polling = false;

  /// True from the start of a `down` teardown until it finishes, so a late
  /// `resumeWatch()` can't arm a timer that outlives the connection.
  bool _tearingDown = false;

  /// Bumped by every path that tears the connection down — [disconnect],
  /// [shutdown], [downNowSync] and [_handleRemoved]. A connect captures it
  /// before its first await and bails if it has moved, so a teardown landing
  /// mid-connect can never be overwritten by a connect that finishes after it
  /// and leaves an orphaned node polling on the mesh.
  int _teardownGeneration = 0;

  bool _disposed = false;

  /// Debounces signed-out status polls (count + credited elapsed time) so a
  /// blip never disconnects anyone.
  final RemovalDetector _removalDetector;

  int _removedTick = 0;

  /// Fired exactly once per removal, right after the state has flipped to
  /// disconnected, so the launcher can toast the player a single time. The UI
  /// owns this field; clear it in `dispose`.
  void Function()? onRemoved;

  // --- Read-only surface for the UI -----------------------------------------

  /// Bumped once per removal — an alternative latch for anything that renders
  /// from state rather than callbacks.
  int get removedTick => _removedTick;

  /// Whether a poll timer is currently armed. Also the leak check in tests.
  @visibleForTesting
  bool get pollingActive => _pollTimer != null;

  /// The cadence currently armed on the poll timer, or null when idle.
  @visibleForTesting
  Duration? get armedPollInterval => _pollTimer == null ? null : _armedInterval;

  /// Length of the current run of signed-out polls (0 when the last poll was
  /// healthy). Polls we could not read never appear here.
  @visibleForTesting
  int get signedOutPollCount => _removalDetector.signedOutPollCount;

  /// Length of the current run of unreadable polls.
  @visibleForTesting
  int get unknownPollCount => _removalDetector.unknownPollCount;

  /// True while Tailscale itself is unreachable — the CLI has stopped answering
  /// for [kUnreachableAfter]. Deliberately non-destructive: we stay connected,
  /// keep polling, and claim nothing about having been removed.
  bool get tailscaleUnreachable =>
      _errorKind == MeshErrorKind.tailscaleUnreachable;

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
  Future<bool> connectWithAuthKey(
    String authKey, {
    required String username,
  }) {
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
    // Anything that tears the connection down while we are mid-connect moves
    // this; see [_teardownGeneration].
    final generation = _teardownGeneration;
    _removalDetector.reset();
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
    // The launcher can be closed — or the user can hit Disconnect / the app can
    // be asked to exit — while `up` is still running. Anything past here would
    // touch a dead or deliberately torn-down controller (notifyListeners,
    // timers, the tray app), so bail; and if `up` did land, leave the tailnet
    // again so we don't strand a node nobody is watching.
    if (_disposed || _teardownGeneration != generation) {
      // Compensate unless `up` DEFINITELY failed. A timeout (result == null)
      // does not kill the child process, so `tailscale up` can still succeed
      // after we have given up on it — and then nobody is left to take the node
      // down. An unnecessary `down` on a node that never came up is harmless;
      // a node stranded on the mesh after the player left is not.
      if (result == null || result.exitCode == 0) {
        unawaited(_run(tailscaleDownArgs, timeout: const Duration(seconds: 6)));
      }
      return _abandonConnect();
    }
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
    if (_disposed || _teardownGeneration != generation) {
      // Closed, disconnected or removed while verifying. Don't flip any state —
      // but do leave the tailnet so a shut (or departed) launcher never leaves
      // the player lingering in the lobby ([dispose]'s own `down` already ran,
      // before we were up).
      unawaited(_run(tailscaleDownArgs, timeout: const Duration(seconds: 6)));
      return _abandonConnect();
    }
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

    final generation = _teardownGeneration;
    final prevUser = _username;
    _username = newUser;
    _startPendingName();
    notifyListeners();

    final result = await _run(
      tailscaleSetHostnameArgs(buildAtlasHostname(newUser)),
      timeout: const Duration(seconds: 15),
    );
    // A teardown during the rename owns the state now; touching it here would
    // resurrect a connection the user already left.
    if (_disposed || _teardownGeneration != generation) return;
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
    // Never arm the timeout on a controller that is already gone.
    if (_disposed) return;
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
  ///
  /// State is torn down BEFORE the `down` call, not after: `down` can take
  /// seconds, and anything landing during it (a dialog closing into
  /// [resumeWatch], say) must see a disconnected controller rather than arm a
  /// timer that outlives the connection.
  Future<void> disconnect() async {
    _teardownGeneration++;
    _tearingDown = true;
    _connected = false;
    stopPolling();
    _status = const MeshStatus(self: null, others: <MeshPeer>[]);
    _joiningRoom = false;
    _pendingUserSlug = null;
    _joinTimeoutTimer?.cancel();
    ProcessResult? result;
    try {
      result = await _run(
        tailscaleDownArgs,
        timeout: const Duration(seconds: 15),
      );
    } finally {
      _tearingDown = false;
      stopPolling();
    }
    if (_disposed) return;
    _log(result == null ? 'disconnect may have failed' : 'disconnected');
    notifyListeners();
  }

  /// Poll `tailscale status --json` once: refresh the peer list, and watch for
  /// this device having been deleted from the tailnet (kicked or banned).
  ///
  /// `tailscale status --json` still exits 0 once the node is signed out, so a
  /// non-zero exit is not the removal signal — `BackendState` is. Each poll is
  /// classified three ways by [classifyPoll]; only [MeshPollOutcome.signedOut]
  /// is evidence. A poll we could not read is [MeshPollOutcome.unknown] and
  /// cannot disconnect anyone: the worst it can do, once it has persisted for
  /// [kUnreachableAfter], is raise [MeshErrorKind.tailscaleUnreachable].
  ///
  /// Re-entrant calls return immediately and are recorded as no sample at all:
  /// the CLI call can hang for its full 8s timeout, which is several ticks at
  /// any of our cadences, and one hang must count as one sample.
  Future<void> pollOnce() async {
    if (_disposed || !_connected || _polling) return;
    _polling = true;
    try {
      final result = await _run(
        tailscaleStatusArgs,
        timeout: const Duration(seconds: 8),
      );
      if (_disposed || !_connected) return;

      final commandOk = result != null && result.exitCode == 0;
      final parsed = commandOk
          ? parseTailscaleStatusJson(result.stdout as String)
          : null;
      final sample = classifyPoll(commandOk: commandOk, status: parsed);
      // The only way to reach [_handleRemoved] is with one of these, and the
      // only way to get one is a signed-out sample. An unknown poll literally
      // cannot produce the argument.
      // The armed cadence tells the detector how big a normal gap is, so one
      // stall cannot be mistaken for the confirm window quietly elapsing.
      final confirmed = _removalDetector.record(
        sample,
        pollInterval: _armedInterval,
      );
      if (confirmed != null) {
        _handleRemoved(confirmed);
        return;
      }
      // Speed up while a signed-out run is open so the confirm window is walked
      // promptly, and drop back to the cadence the UI wants once it clears.
      // Confirm faster only while a signed-out run is genuinely open AND the
      // CLI is still answering. Unknown polls never clear the run, so without
      // the second clause a single signed-out poll followed by a dead CLI would
      // latch the 2s cadence forever — spawning tailscale.exe every 2s on a
      // machine that is already unhealthy. Once we have given up enough to tell
      // the user (tailscaleUnreachable), drop back to the normal cadence; the
      // next signed-out poll re-arms confirmation.
      _setConfirming(
        _removalDetector.inSignedOutRun && !_removalDetector.tailscaleUnreachable,
      );

      switch (sample.outcome) {
        case MeshPollOutcome.unknown:
          // Tells us nothing. Hold the last known-good list, stay connected,
          // and only say so out loud once it has gone on long enough to be
          // worth mentioning.
          _log(
            'status poll unreadable '
            '(${_removalDetector.unknownPollCount} in a row, '
            '${_removalDetector.unknownFor.inSeconds}s)',
          );
          _setUnreachable(_removalDetector.tailscaleUnreachable);
          return;
        case MeshPollOutcome.signedOut:
          // Not confident yet — hold the last known-good list rather than
          // blanking the room on one slow or empty poll.
          _setUnreachable(false);
          _log(
            'status poll looks signed out '
            '(${_removalDetector.signedOutPollCount}/$kRemovalSignedOutPolls, '
            '${_removalDetector.windowCredit.inSeconds}s of '
            '${kRemovalConfirmWindow.inSeconds}s): '
            'backendState=${sample.backendState}',
          );
          return;
        case MeshPollOutcome.healthy:
          break;
      }

      _setUnreachable(false);
      _status = parsed!;
      final self = parsed.self;
      if (self != null &&
          _pendingUserSlug != null &&
          self.name == _pendingUserSlug) {
        _joiningRoom = false;
        _pendingUserSlug = null;
        _joinTimeoutTimer?.cancel();
      }
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  /// Raise or clear the non-destructive "can't reach Tailscale" state. Never
  /// touches [_connected] — we do not know that anything is wrong with the
  /// connection, only that we cannot see it.
  void _setUnreachable(bool value) {
    final showing = _errorKind == MeshErrorKind.tailscaleUnreachable;
    if (value == showing) return;
    if (value) {
      _errorKind = MeshErrorKind.tailscaleUnreachable;
      _errorMessage = _friendlyError(MeshErrorKind.tailscaleUnreachable);
      _log('tailscale CLI has not answered for '
          '${_removalDetector.unknownFor.inSeconds}s (still connected)');
    } else {
      _errorKind = null;
      _errorMessage = '';
    }
    notifyListeners();
  }

  /// Start (or re-target) periodic polling. Runs for as long as we believe we
  /// are connected — not just while the room menu is open — because that is the
  /// only way a player who is mid-game finds out they were kicked.
  ///
  /// [fast] is the [kFastPollInterval] cadence the Network dialog uses for its
  /// live peer list; the default is the cheap [kWatchPollInterval] removal
  /// watch. Switching cadence re-arms the timer; asking for the cadence that is
  /// already running is a no-op. While a run of bad polls is being confirmed
  /// [kConfirmPollInterval] wins, and [fast] is remembered so the good poll that
  /// clears the run restores the cadence the UI actually wants.
  void startPolling({bool fast = false}) {
    if (_disposed || !_connected || _tearingDown) return;
    _pollFast = fast;
    _armPollTimer();
  }

  /// Drop back to the background removal watch — what the Network dialog calls
  /// when it closes, instead of stopping outright.
  void resumeWatch() => startPolling();

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _armedInterval = null;
    _pollFast = false;
    _confirming = false;
    _removalDetector.reset();
  }

  /// The cadence that should be running right now.
  Duration get _desiredInterval => _confirming
      ? kConfirmPollInterval
      : (_pollFast ? kFastPollInterval : kWatchPollInterval);

  /// (Re-)arm the poll timer at [_desiredInterval], leaving it alone when that
  /// is already what is running so repeat calls can't starve polling by
  /// restarting the period.
  void _armPollTimer() {
    if (_disposed || !_connected || _tearingDown) return;
    final interval = _desiredInterval;
    if (_pollTimer != null && _armedInterval == interval) return;
    _pollTimer?.cancel();
    _armedInterval = interval;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(pollOnce()));
  }

  /// Enter/leave the short confirm cadence. Only re-targets a timer that is
  /// already armed — a manual [pollOnce] never starts polling by itself.
  void _setConfirming(bool value) {
    if (_confirming == value) return;
    _confirming = value;
    if (_pollTimer != null) _armPollTimer();
  }

  /// This node is off the tailnet for good. Stop watching, clear local
  /// Tailscale state so a later reconnect starts clean, flip to disconnected,
  /// and fire the one-shot [onRemoved] signal.
  ///
  /// Takes a [ConfirmedRemoval] rather than a flag or a string precisely so it
  /// is unreachable without one: the only source of that type is the
  /// signed-out branch of [RemovalDetector.record]. Its `backendState` decides
  /// whether the player is told they were removed or that they turned Tailscale
  /// off themselves. See [removalKindForBackendState].
  void _handleRemoved(ConfirmedRemoval evidence) {
    if (_disposed) return;
    _teardownGeneration++;
    stopPolling();
    _joinTimeoutTimer?.cancel();
    _joiningRoom = false;
    _pendingUserSlug = null;
    _connecting = false;
    _connected = false;
    _status = const MeshStatus(self: null, others: <MeshPeer>[]);
    final kind = removalKindForBackendState(evidence.backendState);
    _errorKind = kind;
    _errorMessage = _friendlyError(kind);
    _removedTick++;
    _log(
      kind == MeshErrorKind.localDisconnect
          ? 'tailscale was stopped on this PC, cleaning up local state'
          : 'removed from the tailnet server-side, cleaning up local state',
    );
    // Fire-and-forget: `tailscale up` on a stale logged-out node is flaky, so
    // put the daemon in a known state without blocking the UI flip.
    unawaited(_run(tailscaleDownArgs, timeout: const Duration(seconds: 10)));
    notifyListeners();
    onRemoved?.call();
  }

  /// Record a terminal gate rejection (a ban) so the Network dialog can show it
  /// as a dead end rather than inviting an immediate, pointless retry.
  void noteGateBan(String message) {
    _connecting = false;
    _errorKind = MeshErrorKind.banned;
    _errorMessage = message;
    notifyListeners();
  }

  /// Fast, fire-and-forget disconnect for app-exit / lifecycle paths so a closed
  /// launcher never leaves the user sitting in a room. Idempotent.
  void downNowSync() {
    _teardownGeneration++;
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

  /// Awaitable disconnect for the graceful exit-request hook. Tears state down
  /// before the `down` call for the same reason [disconnect] does.
  Future<void> shutdown() async {
    _teardownGeneration++;
    _tearingDown = true;
    final wasConnected = _connected;
    _connected = false;
    stopPolling();
    _joinTimeoutTimer?.cancel();
    try {
      if (wasConnected) {
        await _run(tailscaleDownArgs, timeout: const Duration(seconds: 6));
      }
    } finally {
      _tearingDown = false;
      stopPolling();
    }
  }

  // --- Internals -------------------------------------------------------------

  /// Give up on a connect that a teardown (or a dispose) overtook. Only the
  /// in-flight latch is cleared: the teardown owns everything else, and on a
  /// disposed controller nothing may be touched at all. Without this a
  /// disconnect landing mid-connect would leave [_connecting] latched forever
  /// and the player unable to rejoin.
  bool _abandonConnect() {
    if (_disposed) return false;
    _connecting = false;
    notifyListeners();
    return false;
  }

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
      case MeshErrorKind.removed:
        return 'You were removed from the ATLAS Network.';
      case MeshErrorKind.localDisconnect:
        return 'Tailscale was disconnected on this PC.';
      case MeshErrorKind.banned:
        return 'You are banned from the ATLAS Network.';
      case MeshErrorKind.tailscaleUnreachable:
        // Deliberately says nothing about having been removed: we don't know.
        return "Can't reach Tailscale on this PC. Make sure it's still "
            'running.';
      case MeshErrorKind.generic:
        return "Couldn't connect to the ATLAS Network. Please try again.";
    }
  }

  String? _resolveExe() {
    // Tests drive the CLI through [processRunner]; there is nothing to find.
    if (processRunner != null) return _stubExe;
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
    if (processRunner != null) return;
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
              // Deliberately does NOT publish _status: this is a yes/no check,
              // and the connect path polls immediately afterwards. A verifier
              // that also mutates observed state makes the connect sequence's
              // side effects much harder to reason about.
              if (ips.any((s) => s.startsWith('100.'))) return true;
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
    final runner = processRunner;
    if (runner != null) return runner(args, timeout);
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
    // Set first so an in-flight `pollOnce` that resolves after this can't call
    // notifyListeners (or fire a removal) on a dead controller.
    _disposed = true;
    onRemoved = null;
    downNowSync();
    super.dispose();
  }
}
