import 'dart:convert';
import 'dart:io';

/// Pure, dependency-light logic for the ATLAS "Network" feature.
///
/// The launcher drives the official Tailscale CLI: it joins one shared ATLAS
/// tailnet with a reusable/ephemeral pre-auth key, encodes the current room
/// into the device hostname, and reads `tailscale status --json` to render the
/// room. Everything here is deliberately free of Flutter so it can be unit
/// tested; the `State` class in `main.dart` owns the actual `Process` calls,
/// polling timer, and UI.

/// Remote config served from `config/mesh.json` in the repo. The auth key is
/// stored base64-encoded so Tailscale's GitHub secret-scanning partnership does
/// not auto-revoke it when the public file is committed.
class MeshConfig {
  const MeshConfig({
    required this.authKey,
    required this.loginServer,
    required this.enabled,
    required this.maxRoomSize,
    required this.onlineCap,
    this.gateUrl = '',
  });

  /// Decoded `tskey-auth-...` value (empty when not configured yet).
  ///
  /// Legacy: a single shared reusable key. The Discord-gated build leaves this
  /// empty and obtains a per-user single-use key from [gateUrl] instead.
  final String authKey;

  /// Empty for Tailscale cloud; a `https://...` URL when self-hosting Headscale.
  final String loginServer;

  /// Base URL of the ATLAS Network Gate (the Cloudflare Worker). When set, the
  /// launcher shows "Connect with Discord" and joins with a key minted there,
  /// rather than the shared [authKey]. Empty disables the Discord flow.
  final String gateUrl;

  /// Remote kill switch for the whole feature.
  final bool enabled;

  /// Soft, client-side per-room cap (lobby feel). Not a security boundary.
  final int maxRoomSize;

  /// Free-tier device ceiling used for the near-cap warning.
  final int onlineCap;

  static const MeshConfig disabled = MeshConfig(
    authKey: '',
    loginServer: '',
    enabled: false,
    maxRoomSize: 16,
    onlineCap: 100,
    gateUrl: '',
  );

  /// True when the legacy shared-key path can connect.
  bool get isUsable => enabled && authKey.isNotEmpty;

  /// True when the Discord login gate is configured and should be offered.
  bool get gateEnabled => enabled && gateUrl.isNotEmpty;

  factory MeshConfig.fromJson(Map<String, dynamic> json) {
    final encoded = (json['authKeyB64'] as String?)?.trim() ?? '';
    var key = '';
    if (encoded.isNotEmpty) {
      try {
        key = utf8.decode(base64.decode(base64.normalize(encoded))).trim();
      } catch (_) {
        key = '';
      }
    }
    return MeshConfig(
      authKey: key,
      loginServer: (json['loginServer'] as String?)?.trim() ?? '',
      enabled: json['enabled'] as bool? ?? false,
      maxRoomSize: _asPositiveInt(json['maxRoomSize'], 16),
      onlineCap: _asPositiveInt(json['onlineCap'], 100),
      gateUrl: _trimTrailingSlash((json['gateUrl'] as String?)?.trim() ?? ''),
    );
  }
}

/// Drop a single trailing slash so `gateUrl` joins cleanly with `/login`.
String _trimTrailingSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;

int _asPositiveInt(Object? value, int fallback) {
  if (value is num && value > 0) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return fallback;
}

/// A single device on the ATLAS tailnet, parsed from its hostname.
class MeshPeer {
  const MeshPeer({
    required this.name,
    required this.tailscaleIp,
    required this.online,
    required this.isSelf,
    required this.os,
  });

  /// User slug parsed from the hostname (display name for the row).
  final String name;

  /// The `100.x` address other peers connect to.
  final String tailscaleIp;
  final bool online;
  final bool isSelf;
  final String os;
}

/// Result of parsing `tailscale status --json`, restricted to ATLAS devices.
class MeshStatus {
  const MeshStatus({
    required this.self,
    required this.others,
    this.backendState = '',
    this.selfTailscaleIps = const <String>[],
    this.parseOk = true,
    this.selfNodePresent = false,
  });

  final MeshPeer? self;
  final List<MeshPeer> others;

  /// False when `tailscale status --json` produced something we could not read
  /// at all (not JSON, or not an object). Such a payload is not evidence of
  /// anything — see [MeshPollOutcome.unknown].
  final bool parseOk;

  /// Whether the payload carried a `Self` block at all, regardless of whether
  /// its hostname is ATLAS-shaped. A status with no `Self` is unreadable rather
  /// than a removal, so it must not be confused with one whose `Self` lost its
  /// address.
  final bool selfNodePresent;

  /// Top-level `BackendState` from `tailscale status --json` — one of
  /// `ipn.State`'s names (`NoState`, `InUseOtherUser`, `NeedsLogin`,
  /// `NeedsMachineAuth`, `Stopped`, `Starting`, `Running`). Empty when the
  /// payload was missing or malformed. See [backendStateIsSignedOut].
  final String backendState;

  /// Raw `Self.TailscaleIPs`, kept unfiltered (i.e. regardless of whether the
  /// hostname is ATLAS-shaped) so removal detection asks "is this node still
  /// registered?" rather than "is it wearing an ATLAS hostname?".
  final List<String> selfTailscaleIps;

  /// True while this node still holds a `100.x` tailnet address. A device that
  /// was deleted server-side loses it, so this going false is the second half
  /// of the removal signal (the first being [backendStateIsSignedOut]).
  bool get hasTailnetAddress =>
      selfTailscaleIps.any((ip) => ip.startsWith('100.'));

  /// Everyone (self first).
  List<MeshPeer> get all => <MeshPeer>[?self, ...others];

  int onlineCount() => all.where((p) => p.online).length;
}

/// `BackendState` values that mean tailscaled is no longer logged in to the
/// tailnet — which is where the daemon lands after the device is deleted
/// server-side (kicked/banned). Verified against `ipn.State` in
/// tailscale/tailscale `ipn/backend.go`, whose `String()` values are exactly
/// `NoState`, `InUseOtherUser`, `NeedsLogin`, `NeedsMachineAuth`, `Stopped`,
/// `Starting` and `Running`.
///
/// `Starting` and `Running` are healthy. `InUseOtherUser` is deliberately NOT
/// here: it means another OS user owns the daemon, not that we were removed.
const Set<String> kSignedOutBackendStates = <String>{
  'NeedsLogin',
  'NeedsMachineAuth',
  'Stopped',
  'NoState',
};

/// Fail-safe classification of a `BackendState`: anything we don't recognise
/// (including an empty string from a malformed payload) is treated as healthy,
/// so an unexpected value can never disconnect a player who is fine.
bool backendStateIsSignedOut(String state) =>
    kSignedOutBackendStates.contains(state.trim());

/// Convenience wrapper over [backendStateIsSignedOut] for a parsed status.
bool meshStatusLooksSignedOut(MeshStatus status) =>
    backendStateIsSignedOut(status.backendState);

/// How one `tailscale status --json` poll classifies.
///
/// The three-way split is the entire safety story. "The CLI didn't answer" and
/// "the CLI said we are signed out" are completely different facts, and only
/// the second one is evidence: see [classifyPoll].
enum MeshPollOutcome {
  /// Status parsed, backend state fine, `Self` still holds its `100.x` address.
  /// Resets everything.
  healthy,

  /// The command SUCCEEDED and positively reported a signed-out `BackendState`,
  /// or reported a live one while `Self` has lost its tailnet address. This is
  /// real evidence that the node is off the tailnet.
  signedOut,

  /// The command failed, timed out, or its output could not be read. This is
  /// NOT evidence of removal and can never, on its own, disconnect anyone.
  unknown,
}

/// One classified poll: the outcome plus the `BackendState` behind it.
///
/// The constructor is private on purpose — a sample can only come out of
/// [classifyPoll], which is the single place that decides what counts as
/// evidence.
class MeshPollSample {
  const MeshPollSample._(this.outcome, this.backendState);

  final MeshPollOutcome outcome;

  /// The `BackendState` the CLI reported, or '' when none could be read. Only
  /// meaningful when [outcome] is [MeshPollOutcome.signedOut], where it decides
  /// the wording (see [removalKindForBackendState]).
  final String backendState;

  bool get isHealthy => outcome == MeshPollOutcome.healthy;
  bool get isSignedOut => outcome == MeshPollOutcome.signedOut;
  bool get isUnknown => outcome == MeshPollOutcome.unknown;

  @override
  String toString() => 'MeshPollSample(${outcome.name}, "$backendState")';
}

/// Classify a single `tailscale status --json` poll.
///
/// [commandOk] is whether the CLI ran at all and exited 0. Note that
/// `tailscale status --json` exits 0 even when the node is signed out — the
/// JSON path in `cmd/tailscale/cli/status.go` returns before the state checks
/// that make the human-readable mode exit 1 — so `BackendState`, not the exit
/// code, is the authoritative signal.
///
/// Everything we could not positively read lands in [MeshPollOutcome.unknown]:
/// a failed or timed-out command, output that is not JSON, output with no
/// `BackendState`, and output with no `Self` block. None of those say the
/// tailnet removed us; they say we could not ask.
///
/// A single signed-out poll must still never disconnect anyone — feed every
/// sample through [RemovalDetector].
MeshPollSample classifyPoll({required bool commandOk, MeshStatus? status}) {
  const unknown = MeshPollSample._(MeshPollOutcome.unknown, '');
  if (!commandOk || status == null || !status.parseOk) return unknown;
  final state = status.backendState.trim();
  // A real status always carries both. Missing either means we are reading
  // something we don't understand, not that the node was deleted.
  if (state.isEmpty || !status.selfNodePresent) return unknown;
  if (backendStateIsSignedOut(state)) {
    return MeshPollSample._(MeshPollOutcome.signedOut, state);
  }
  if (!status.hasTailnetAddress) {
    // Backend claims to be up, but the node no longer holds a tailnet address —
    // what a server-side delete looks like before the daemon notices.
    return MeshPollSample._(MeshPollOutcome.signedOut, state);
  }
  return MeshPollSample._(MeshPollOutcome.healthy, state);
}

/// Proof that a removal has been confirmed, carrying the `BackendState` of the
/// poll that confirmed it.
///
/// Its constructor is private to this library and is reached from exactly one
/// place: the [MeshPollOutcome.signedOut] branch of [RemovalDetector.record].
/// A caller that requires one of these to tear the connection down therefore
/// *cannot* be reached by an `unknown` poll — that is a property of the types,
/// not of anybody remembering to check an enum.
class ConfirmedRemoval {
  const ConfirmedRemoval._(this.backendState);

  /// The `BackendState` that confirmed it, e.g. `NeedsLogin` or `Stopped`.
  final String backendState;

  @override
  String toString() => 'ConfirmedRemoval("$backendState")';
}

/// Debounces the removal signal so a transient blip — a slow `tailscale
/// status`, a daemon restart, a momentarily empty payload — never disconnects a
/// healthy player.
///
/// A removal is believed only when BOTH hold:
/// * [threshold] signed-out polls in the run, and
/// * [confirmWindow] of *credited* elapsed time has accumulated across it.
///
/// The elapsed half is what makes the tolerance cadence-independent. A poll
/// count alone means wildly different things at different cadences (three polls
/// is ~3s of grace at the dialog's 1.5s cadence — less than a routine Windows
/// Tailscale service restart — but 20-30s on the background watch), and a
/// single stalled CLI call can manufacture several "polls" out of one hang.
///
/// How each outcome is treated:
/// * [MeshPollOutcome.healthy] — resets everything.
/// * [MeshPollOutcome.signedOut] — extends the run.
/// * [MeshPollOutcome.unknown] — neutral. It neither confirms nor clears a run,
///   and the time it spans earns no credit, so a stretch of unknowns can never
///   silently satisfy the window.
///
/// Time is only ever credited for the gap between two *consecutive* signed-out
/// polls (nothing unknown in between), and even then only up to
/// [creditCapFor] the cadence that was actually armed when the sample was
/// taken. Two separate bounds do two separate jobs:
///
/// * The **per-gap credit cap** keeps the window accumulating in plausibly
///   sized steps. A gap much bigger than the armed cadence is not one poll's
///   worth of observation, whatever produced it — a brief suspend, a lid closed
///   for a minute, a stalled CLI, a GC pause, a machine thrashing. The excess
///   is discarded, so "12s of window" means 12s genuinely watched in small
///   steps rather than one large jump.
/// * [maxPollGap] is the outer re-anchor: past it the two polls are not one
///   observation at all (the machine suspended, the process was frozen, the
///   daemon was gone for minutes), so the run restarts from scratch.
///
/// Together with the monotonic [elapsed] source this is the belt and braces
/// against a sleep/resume producing a free confirmation. Credit is never more
/// than the time genuinely observed, so the window can never be satisfied by
/// less than [confirmWindow] of real, continuous, watched time.
///
/// [elapsed] is the injectable, **monotonic** time source (a running
/// [Stopwatch] by default), so NTP corrections and DST cannot inflate the
/// window and so every timing case is testable with no real delay.
class RemovalDetector {
  RemovalDetector({
    this.threshold = 3,
    this.confirmWindow = const Duration(seconds: 12),
    this.maxPollGap = const Duration(seconds: 60),
    this.unreachableAfter = const Duration(seconds: 90),
    this.gapCreditFactor = 2,
    Duration Function()? elapsed,
  }) : assert(threshold > 0),
       assert(gapCreditFactor > 0),
       _elapsed = elapsed ?? _monotonic();

  /// A free-running monotonic source. Unaffected by wall-clock corrections; on
  /// platforms where it also stops during suspend, [maxPollGap] covers us, and
  /// on platforms where it keeps running, [maxPollGap] covers us too.
  static Duration Function() _monotonic() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Signed-out polls required before a removal can be believed.
  final int threshold;

  /// Credited elapsed time that must accumulate across the run before the
  /// removal is allowed to fire.
  final Duration confirmWindow;

  /// Largest gap between two consecutive signed-out polls that still counts as
  /// one continuous observation. Anything longer re-anchors the run.
  final Duration maxPollGap;

  /// How long an uninterrupted run of [MeshPollOutcome.unknown] polls has to
  /// last before [tailscaleUnreachable] flips. Purely informational — it never
  /// disconnects anyone.
  final Duration unreachableAfter;

  /// How many normal poll intervals a single gap may be worth. A gap longer
  /// than `pollInterval * gapCreditFactor` is credited only up to that cap, so
  /// one stall cannot bank the whole [confirmWindow] in a single step.
  final int gapCreditFactor;

  final Duration Function() _elapsed;

  int _signedOut = 0;
  Duration _credit = Duration.zero;
  Duration? _lastSignedOutAt;
  bool _unknownSinceSignedOut = false;
  bool _fired = false;

  int _unknown = 0;
  Duration? _firstUnknownAt;
  Duration _unknownFor = Duration.zero;

  /// Signed-out polls in the current run (0 when the last poll was healthy).
  int get signedOutPollCount => _signedOut;

  /// Length of the current uninterrupted run of unknown polls.
  int get unknownPollCount => _unknown;

  /// Credited elapsed time banked so far for the current run.
  Duration get windowCredit => _credit;

  /// How long the current run of unknown polls has spanned (first to latest).
  Duration get unknownFor => _unknownFor;

  /// True once unknown polls have persisted for [unreachableAfter]. The cue for
  /// a NON-destructive "can't reach Tailscale" state — never a disconnect.
  bool get tailscaleUnreachable => _unknownFor >= unreachableAfter;

  /// True while a run of signed-out polls is open but unconfirmed — the cue for
  /// the caller to poll faster so the [confirmWindow] is walked promptly.
  bool get inSignedOutRun => _signedOut > 0;

  void reset() {
    _signedOut = 0;
    _credit = Duration.zero;
    _lastSignedOutAt = null;
    _unknownSinceSignedOut = false;
    _fired = false;
    _resetUnknownRun();
  }

  void _resetUnknownRun() {
    _unknown = 0;
    _firstUnknownAt = null;
    _unknownFor = Duration.zero;
  }

  /// Record one poll outcome.
  ///
  /// Returns non-null exactly once per run — on the first signed-out poll that
  /// satisfies both the count and the window — so the caller can act a single
  /// time per removal. Every other path, and in particular every
  /// [MeshPollOutcome.unknown] path, returns null.
  /// [pollInterval] is the cadence actually armed when this sample was taken.
  /// It caps how much of a gap can be credited: the window must be walked in
  /// plausibly-sized steps, so one long stall cannot bank it in a single jump.
  ConfirmedRemoval? record(MeshPollSample sample, {Duration? pollInterval}) {
    final at = _elapsed();
    switch (sample.outcome) {
      case MeshPollOutcome.healthy:
        reset();
        return null;
      case MeshPollOutcome.unknown:
        // Neutral: does not advance the run, does not clear it, and earns the
        // run no time. All it can do is raise [tailscaleUnreachable].
        _unknown++;
        final start = _firstUnknownAt ??= at;
        _unknownFor = at >= start ? at - start : Duration.zero;
        _unknownSinceSignedOut = true;
        return null;
      case MeshPollOutcome.signedOut:
        _resetUnknownRun();
        final last = _lastSignedOutAt;
        _lastSignedOutAt = at;
        final continuous = !_unknownSinceSignedOut;
        _unknownSinceSignedOut = false;
        if (last == null) {
          _signedOut = 1;
          _credit = Duration.zero;
          break;
        }
        final gap = at - last;
        if (gap < Duration.zero || gap > maxPollGap) {
          // Suspend/resume, a frozen process, or a daemon that was gone for
          // minutes: the two polls are not one observation. Re-anchoring can
          // only ever delay a disconnect, never rush one.
          _signedOut = 1;
          _credit = Duration.zero;
          break;
        }
        _signedOut++;
        // Time spanned by an unknown poll is time we were not watching, so it
        // buys the run nothing.
        //
        // A gap is also only worth what a NORMAL gap at the armed cadence is
        // worth. Without this cap a single sub-maxPollGap stall — a 55s wedge, a
        // brief suspend, a loaded machine — would bank the whole confirmWindow
        // in one step and disconnect a healthy player. Capping means "12s of
        // window" is 12s actually observed, in poll-sized pieces.
        if (continuous) {
          final cap = pollInterval == null
              ? maxPollGap
              : pollInterval * gapCreditFactor;
          _credit += gap <= cap ? gap : cap;
        }
    }
    if (_fired || _signedOut < threshold || _credit < confirmWindow) return null;
    _fired = true;
    return ConfirmedRemoval._(sample.backendState);
  }
}

/// Which flavour of "this node is off the tailnet" a [ConfirmedRemoval]
/// represents, from the `BackendState` that triggered it.
///
/// `Stopped` is the one signed-out state the user causes themselves — hitting
/// Disconnect in their own Tailscale tray — so it must not be reported as an
/// ATLAS removal. `NeedsLogin`/`NeedsMachineAuth`/`NoState` mean the node lost
/// its authorisation, which is what a kick or ban looks like. A CLI that
/// stopped answering never gets this far: it classifies as
/// [MeshPollOutcome.unknown], which cannot produce a [ConfirmedRemoval] at all.
MeshErrorKind removalKindForBackendState(String backendState) =>
    backendState.trim() == 'Stopped'
    ? MeshErrorKind.localDisconnect
    : MeshErrorKind.removed;

/// Hostname prefix that marks a device as belonging to ATLAS.
const String kAtlasHostPrefix = 'atlas-';

/// Separator between the lobby marker and the user slug inside the hostname.
const String kAtlasRoomUserSep = '--';

/// Constant lobby segment in the hostname — everyone shares one lobby.
const String kDefaultRoom = 'lobby';
const String kDefaultUser = 'player';

/// Lowercase a value into a DNS-label-safe slug (`[a-z0-9-]`, no leading/
/// trailing or doubled hyphens) so it survives Tailscale hostname handling and
/// never collides with the room/user separator.
String slugify(String input, {int maxLen = 24}) {
  final lowered = input.toLowerCase();
  final buffer = StringBuffer();
  var lastWasHyphen = false;
  for (final rune in lowered.runes) {
    final char = String.fromCharCode(rune);
    final isAlnum =
        (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7a);
    if (isAlnum) {
      buffer.write(char);
      lastWasHyphen = false;
    } else if (!lastWasHyphen) {
      buffer.write('-');
      lastWasHyphen = true;
    }
  }
  var slug = buffer.toString();
  if (slug.length > maxLen) slug = slug.substring(0, maxLen);
  // Trim hyphens that may now sit at the edges (incl. after truncation).
  slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
  return slug;
}

/// Build the Tailscale device hostname `atlas-lobby--<userSlug>`. Everyone
/// shares one lobby, so the middle segment is constant.
String buildAtlasHostname(String user) {
  final userSlug = slugify(user);
  return '$kAtlasHostPrefix$kDefaultRoom$kAtlasRoomUserSep'
      '${userSlug.isEmpty ? kDefaultUser : userSlug}';
}

/// Decode an ATLAS hostname back into the user slug, or null if it is not an
/// ATLAS device. Tailscale's `-N` dedup suffix on the user is kept as-is so
/// colliding users stay distinguishable.
String? parseAtlasHostname(String? hostname) {
  if (hostname == null) return null;
  var host = hostname.trim().toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  // MagicDNS names arrive as `<host>.<tailnet>.ts.net`; keep only the label.
  final dot = host.indexOf('.');
  if (dot != -1) host = host.substring(0, dot);
  if (!host.startsWith(kAtlasHostPrefix)) return null;
  final parts = host.substring(kAtlasHostPrefix.length).split(kAtlasRoomUserSep);
  if (parts.length != 2) return null;
  final user = parts[1];
  if (user.isEmpty) return null;
  return user;
}

/// Classification of a failed `tailscale up` — plus the states that arrive
/// after a successful connect: [removed] (deleted from the tailnet while we
/// were on it), [localDisconnect] (the user turned Tailscale off themselves,
/// which is not our doing and must not read like a ban), [banned] (the Discord
/// gate refused to mint a key at all) and [tailscaleUnreachable].
///
/// [tailscaleUnreachable] is the deliberately NON-destructive one: the CLI has
/// stopped answering, so we do not know anything. Nothing is disconnected, no
/// `tailscale down` is run, and the player is not told they were removed —
/// because as far as we can tell, they weren't.
enum MeshErrorKind {
  capacity,
  expiredKey,
  removed,
  localDisconnect,
  banned,
  tailscaleUnreachable,
  generic,
}

MeshErrorKind classifyTailscaleError(String stderr) {
  final text = stderr.toLowerCase();
  const capacity = [
    'limit',
    'maximum',
    'too many',
    'quota',
    'device cap',
    'exceeded',
  ];
  const expired = [
    'expired',
    'invalid key',
    'invalid auth',
    'unauthorized',
    'not valid',
    'key is invalid',
  ];
  if (expired.any(text.contains)) return MeshErrorKind.expiredKey;
  if (capacity.any(text.contains)) return MeshErrorKind.capacity;
  return MeshErrorKind.generic;
}

/// Arguments for `tailscale up`. Ephemerality comes from the key itself, so no
/// `--ephemeral` flag here. `--unattended` keeps Tailscale connected without the
/// tray/GUI app running (Windows) — without it, a closed GUI leaves the node not
/// "Running" and connect fails verification. `--reset` keeps flags consistent
/// across reconnects; `--accept-dns=false` avoids hijacking the user's DNS.
List<String> tailscaleUpArgs({
  required String authKey,
  required String hostname,
  String loginServer = '',
}) {
  return <String>[
    'up',
    '--auth-key=$authKey',
    '--hostname=$hostname',
    '--unattended',
    '--accept-dns=false',
    '--reset',
    if (loginServer.trim().isNotEmpty) '--login-server=${loginServer.trim()}',
  ];
}

/// Live hostname change when switching rooms (no re-auth required).
List<String> tailscaleSetHostnameArgs(String hostname) =>
    <String>['set', '--hostname=$hostname'];

const List<String> tailscaleDownArgs = <String>['down'];
const List<String> tailscaleStatusArgs = <String>['status', '--json'];

/// Parse `tailscale status --json`, keeping only ATLAS devices.
MeshStatus parseTailscaleStatusJson(String jsonStr) {
  Map<String, dynamic> data;
  try {
    final decoded = jsonDecode(jsonStr);
    data = decoded is Map<String, dynamic>
        ? decoded
        : (decoded as Map).cast<String, dynamic>();
  } catch (_) {
    // Not JSON, or not an object. Flagged so callers can tell "unreadable" from
    // "read fine, and it says we're signed out" — see [classifyPoll].
    return const MeshStatus(
      self: null,
      others: <MeshPeer>[],
      parseOk: false,
    );
  }

  MeshPeer? toPeer(Object? node, bool isSelf) {
    if (node is! Map) return null;
    final map = node.cast<String, dynamic>();
    final parsed = parseAtlasHostname(map['HostName'] as String?) ??
        parseAtlasHostname(map['DNSName'] as String?);
    if (parsed == null) return null;
    final ips = (map['TailscaleIPs'] as List?) ?? const <dynamic>[];
    final ipStrings = ips.map((e) => e.toString()).toList();
    final ipv4 = ipStrings.firstWhere(
      (s) => s.contains('.'),
      orElse: () => ipStrings.isNotEmpty ? ipStrings.first : '',
    );
    final online = isSelf ? true : (map['Online'] as bool? ?? false);
    return MeshPeer(
      name: parsed,
      tailscaleIp: ipv4,
      online: online,
      isSelf: isSelf,
      os: map['OS'] as String? ?? '',
    );
  }

  final self = toPeer(data['Self'], true);
  // Read Self's addresses straight off the payload, not off [self]: a node that
  // was deleted server-side may still report a Self block, and one whose
  // hostname isn't ATLAS-shaped is not a removal.
  final selfNode = data['Self'];
  final selfIps = selfNode is Map
      ? ((selfNode['TailscaleIPs'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toList()
      : const <String>[];
  final others = <MeshPeer>[];
  final peerMap = data['Peer'];
  if (peerMap is Map) {
    for (final entry in peerMap.values) {
      final peer = toPeer(entry, false);
      if (peer != null) others.add(peer);
    }
  }
  others.sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return MeshStatus(
    self: self,
    others: others,
    backendState: data['BackendState']?.toString() ?? '',
    selfTailscaleIps: selfIps,
    selfNodePresent: selfNode is Map,
  );
}

/// Locate `tailscale.exe` (or `tailscale` off-Windows). Returns null if absent.
String? resolveTailscaleExe() {
  if (Platform.isWindows) {
    final env = Platform.environment;
    final candidates = <String>[];
    void add(String? base, List<String> parts) {
      if (base == null || base.trim().isEmpty) return;
      candidates.add(<String>[base, ...parts].join(Platform.pathSeparator));
    }

    add(env['ProgramFiles'], const ['Tailscale', 'tailscale.exe']);
    add(env['ProgramFiles(x86)'], const ['Tailscale', 'tailscale.exe']);
    add(env['ProgramW6432'], const ['Tailscale', 'tailscale.exe']);
    add(env['LOCALAPPDATA'], const ['Tailscale', 'tailscale.exe']);
    add(env['LOCALAPPDATA'], const ['Programs', 'Tailscale', 'tailscale.exe']);
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return _whichExecutable('tailscale');
}

String? _whichExecutable(String exe) {
  try {
    final result = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      <String>[exe],
      runInShell: true,
    );
    if (result.exitCode == 0) {
      final lines = (result.stdout as String)
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return lines.first.trim();
    }
  } catch (_) {
    // Ignore — treated as "not found".
  }
  return null;
}
