import 'dart:convert';

import 'package:atlas_link_flutter/tailscale_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slugify', () {
    test('lowercases and replaces unsafe characters with single hyphens', () {
      expect(slugify('Cipher FPS'), 'cipher-fps');
      expect(slugify('OG Zone  Wars!!'), 'og-zone-wars');
      expect(slugify('  weird__name  '), 'weird-name');
    });

    test('trims edge hyphens even after truncation', () {
      expect(slugify('a' * 30, maxLen: 5), 'aaaaa');
      // Truncation lands on a hyphen which must be trimmed away.
      expect(slugify('abcd efgh', maxLen: 5), 'abcd');
    });

    test('empty / symbol-only input collapses to empty', () {
      expect(slugify('***'), '');
      expect(slugify(''), '');
    });
  });

  group('hostname round-trip', () {
    test('builds the atlas-lobby--<user> shape', () {
      expect(buildAtlasHostname('cipher'), 'atlas-lobby--cipher');
      expect(buildAtlasHostname('Nata 123'), 'atlas-lobby--nata-123');
    });

    test('falls back to the default user for empty input', () {
      expect(buildAtlasHostname(''), 'atlas-lobby--player');
    });

    test('parses the user back out', () {
      expect(parseAtlasHostname('atlas-lobby--cipher'), 'cipher');
    });

    test('keeps tailscale dedup suffix and strips MagicDNS tails', () {
      expect(parseAtlasHostname('atlas-lobby--cipher-2'), 'cipher-2');
      expect(
        parseAtlasHostname('atlas-lobby--cipher.tailabc.ts.net.'),
        'cipher',
      );
    });

    test('rejects non-atlas hostnames', () {
      expect(parseAtlasHostname('cipher-pc'), isNull);
      expect(parseAtlasHostname('atlas-onlyuser'), isNull);
      expect(parseAtlasHostname(null), isNull);
    });

    test('round-trips through build then parse', () {
      expect(
        parseAtlasHostname(buildAtlasHostname('Nata 123')),
        slugify('Nata 123'),
      );
    });
  });

  group('MeshConfig.fromJson', () {
    test('base64-decodes the auth key', () {
      final json = {
        'authKeyB64': base64.encode(utf8.encode('tskey-auth-abc123')),
        'loginServer': '',
        'enabled': true,
        'maxRoomSize': 8,
      };
      final config = MeshConfig.fromJson(json);
      expect(config.authKey, 'tskey-auth-abc123');
      expect(config.enabled, isTrue);
      expect(config.maxRoomSize, 8);
      expect(config.onlineCap, 100); // default
      expect(config.isUsable, isTrue);
    });

    test('is unusable when disabled or keyless', () {
      expect(
        MeshConfig.fromJson({'enabled': false, 'authKeyB64': ''}).isUsable,
        isFalse,
      );
      expect(
        MeshConfig.fromJson({'enabled': true, 'authKeyB64': ''}).isUsable,
        isFalse,
      );
    });

    test('survives malformed base64', () {
      final config = MeshConfig.fromJson({
        'authKeyB64': 'not valid base64!!!',
        'enabled': true,
      });
      expect(config.authKey, '');
      expect(config.isUsable, isFalse);
    });
  });

  group('classifyTailscaleError', () {
    test('detects capacity failures', () {
      expect(
        classifyTailscaleError('device limit reached for this tailnet'),
        MeshErrorKind.capacity,
      );
      expect(
        classifyTailscaleError('too many devices'),
        MeshErrorKind.capacity,
      );
    });

    test('detects expired / invalid keys', () {
      expect(
        classifyTailscaleError('authkey is expired'),
        MeshErrorKind.expiredKey,
      );
      expect(
        classifyTailscaleError('invalid key: unauthorized'),
        MeshErrorKind.expiredKey,
      );
    });

    test('falls back to generic', () {
      expect(
        classifyTailscaleError('something else went wrong'),
        MeshErrorKind.generic,
      );
    });
  });

  group('tailscale arg builders', () {
    test('up args carry key + hostname, omit login-server when empty', () {
      final args = tailscaleUpArgs(
        authKey: 'tskey-auth-x',
        hostname: 'atlas-lobby--cipher',
      );
      expect(args.first, 'up');
      expect(args, contains('--auth-key=tskey-auth-x'));
      expect(args, contains('--hostname=atlas-lobby--cipher'));
      expect(args, contains('--unattended')); // stays up without the tray app
      expect(args.any((a) => a.startsWith('--login-server')), isFalse);
    });

    test('up args include login-server for headscale', () {
      final args = tailscaleUpArgs(
        authKey: 'k',
        hostname: 'h',
        loginServer: 'https://hs.example.com',
      );
      expect(args, contains('--login-server=https://hs.example.com'));
    });

    test('set-hostname args', () {
      expect(
        tailscaleSetHostnameArgs('atlas-x--y'),
        ['set', '--hostname=atlas-x--y'],
      );
    });
  });

  group('parseTailscaleStatusJson', () {
    final sample = jsonEncode({
      'Self': {
        'HostName': 'atlas-lobby--cipher',
        'TailscaleIPs': ['100.81.186.59', 'fd7a:115c::1'],
        'Online': true,
        'OS': 'windows',
      },
      'Peer': {
        'nodekeyA': {
          'HostName': 'atlas-lobby--nata',
          'TailscaleIPs': ['100.84.0.7'],
          'Online': true,
          'OS': 'windows',
        },
        'nodekeyB': {
          'HostName': 'atlas-lobby--ghost',
          'TailscaleIPs': ['100.84.0.9'],
          'Online': false,
          'OS': 'linux',
        },
        'nodekeyC': {
          // Non-ATLAS device must be ignored.
          'HostName': 'someones-laptop',
          'TailscaleIPs': ['100.84.0.20'],
          'Online': true,
          'OS': 'macOS',
        },
      },
    });

    test('extracts self and atlas peers only', () {
      final status = parseTailscaleStatusJson(sample);
      expect(status.self, isNotNull);
      expect(status.self!.name, 'cipher');
      expect(status.self!.tailscaleIp, '100.81.186.59');
      expect(status.others.length, 2); // laptop filtered out
    });

    test('counts online members across the network', () {
      final status = parseTailscaleStatusJson(sample);
      // self + nata online; ghost offline.
      expect(status.onlineCount(), 2);
      expect(status.all.length, 3);
    });

    test('returns empty status on malformed json', () {
      final status = parseTailscaleStatusJson('not json');
      expect(status.self, isNull);
      expect(status.others, isEmpty);
    });
  });
}
