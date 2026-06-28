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
  const MeshStatus({required this.self, required this.others});

  final MeshPeer? self;
  final List<MeshPeer> others;

  /// Everyone (self first).
  List<MeshPeer> get all => <MeshPeer>[?self, ...others];

  int onlineCount() => all.where((p) => p.online).length;
}

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
  final body = host.substring(kAtlasHostPrefix.length);
  final parts = body.split(kAtlasRoomUserSep);
  if (parts.length != 2) return null;
  final user = parts[1];
  if (user.isEmpty) return null;
  return user;
}

/// Classification of a failed `tailscale up` so the UI can show friendly copy.
enum MeshErrorKind { capacity, expiredKey, generic }

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
    return const MeshStatus(self: null, others: <MeshPeer>[]);
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
  return MeshStatus(self: self, others: others);
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
