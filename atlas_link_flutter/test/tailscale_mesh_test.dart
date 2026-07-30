import 'dart:convert';

import 'package:atlas_link_flutter/tailscale_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hand-wound clock, so the elapsed-time half of the removal debounce can be
/// exercised at any speed without a single real delay in the suite.
///
/// Deliberately carries TWO sources: the monotonic one the detector actually
/// consumes, and a wall clock that a test can move on its own — which is
/// exactly what an NTP correction or a DST change does to a machine.
class _FakeClock {
  Duration _monotonic = Duration.zero;
  DateTime _wall = DateTime.utc(2026, 1, 1, 12);

  /// The injected seam: monotonic elapsed time.
  Duration call() => _monotonic;

  Duration get elapsed => _monotonic;
  DateTime get wallClock => _wall;

  /// Ordinary time passing: both sources move together.
  void advance(Duration by) {
    _monotonic += by;
    _wall = _wall.add(by);
  }

  /// An NTP/DST correction: the wall clock jumps (either way), monotonic time
  /// carries on regardless.
  void jumpWallClock(Duration by) => _wall = _wall.add(by);
}

// Poll samples for the detector. They go through [classifyPoll] on real-shaped
// payloads because that is the ONLY way to obtain one — a test cannot hand the
// detector a signed-out sample the classifier would never have produced.

/// Running, registered, holding its 100.x address.
MeshPollSample _healthy() => classifyPoll(
  commandOk: true,
  status: parseTailscaleStatusJson(
    jsonEncode({
      'BackendState': 'Running',
      'Self': {
        'HostName': 'atlas-lobby--cipher',
        'TailscaleIPs': ['100.81.186.59'],
        'Online': true,
      },
    }),
  ),
);

/// The command succeeded and positively reported a signed-out backend state.
MeshPollSample _signedOut([String state = 'NeedsLogin']) => classifyPoll(
  commandOk: true,
  status: parseTailscaleStatusJson(
    jsonEncode({
      'BackendState': state,
      'Self': {
        'HostName': 'atlas-lobby--cipher',
        'TailscaleIPs': null,
        'Online': false,
      },
    }),
  ),
);

/// The CLI failed, timed out, or answered with something unreadable.
MeshPollSample _unknown() => classifyPoll(commandOk: false, status: null);

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

    test('gateEnabled requires enabled + a gateUrl', () {
      // The clean-cut shape: no shared key, gate drives connection.
      final gated = MeshConfig.fromJson({
        'enabled': true,
        'authKeyB64': '',
        'gateUrl': 'https://gate.example.workers.dev',
      });
      expect(gated.isUsable, isFalse); // no legacy shared key
      expect(gated.gateEnabled, isTrue);

      expect(
        MeshConfig.fromJson({'enabled': false, 'gateUrl': 'https://x'})
            .gateEnabled,
        isFalse,
      );
      expect(
        MeshConfig.fromJson({'enabled': true, 'gateUrl': ''}).gateEnabled,
        isFalse,
      );
    });

    test('gateUrl drops a single trailing slash', () {
      final config = MeshConfig.fromJson({
        'enabled': true,
        'gateUrl': 'https://gate.example.workers.dev/',
      });
      expect(config.gateUrl, 'https://gate.example.workers.dev');
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
      // Fail safe: an unparseable payload must not read as "signed out".
      expect(status.backendState, '');
      expect(meshStatusLooksSignedOut(status), isFalse);
    });

    test('carries BackendState and the raw self addresses', () {
      final status = parseTailscaleStatusJson(
        jsonEncode({
          'BackendState': 'Running',
          'Self': {
            'HostName': 'atlas-lobby--cipher',
            'TailscaleIPs': ['100.81.186.59', 'fd7a:115c::1'],
            'Online': true,
          },
        }),
      );
      expect(status.backendState, 'Running');
      expect(status.selfTailscaleIps, ['100.81.186.59', 'fd7a:115c::1']);
      expect(status.hasTailnetAddress, isTrue);
      expect(meshStatusLooksSignedOut(status), isFalse);
    });

    test('reads self addresses even when the hostname is not ATLAS-shaped', () {
      // Not a removal — just a device we don't render. `self` is filtered out,
      // but the node is plainly still registered.
      final status = parseTailscaleStatusJson(
        jsonEncode({
          'BackendState': 'Running',
          'Self': {
            'HostName': 'someones-laptop',
            'TailscaleIPs': ['100.84.0.20'],
          },
        }),
      );
      expect(status.self, isNull);
      expect(status.hasTailnetAddress, isTrue);
      expect(
        classifyPoll(commandOk: true, status: status).outcome,
        MeshPollOutcome.healthy,
      );
    });
  });

  group('backend state / removal detection', () {
    // Real shape of `tailscale status --json` once the device has been deleted
    // server-side: the daemon drops to NeedsLogin, Self keeps its identity but
    // loses its tailnet addresses, and Peer is empty. The command still exits
    // 0 — the JSON path in cmd/tailscale/cli/status.go returns before the
    // state checks that make the human-readable mode exit 1 — so BackendState
    // is the signal, not the exit code.
    final needsLogin = jsonEncode({
      'Version': '1.86.2-t7a0dd7c1e',
      'BackendState': 'NeedsLogin',
      'AuthURL': '',
      'TailscaleIPs': null,
      'Self': {
        'ID': '',
        'HostName': 'atlas-lobby--cipher',
        'DNSName': '',
        'OS': 'windows',
        'TailscaleIPs': null,
        'Online': false,
      },
      'Health': ['not logged in, last login error=...'],
      'MagicDNSSuffix': '',
      'Peer': null,
    });

    test('parses a real-shaped NeedsLogin payload as signed out', () {
      final status = parseTailscaleStatusJson(needsLogin);
      expect(status.backendState, 'NeedsLogin');
      expect(status.selfTailscaleIps, isEmpty);
      expect(status.hasTailnetAddress, isFalse);
      expect(meshStatusLooksSignedOut(status), isTrue);
      final sample = classifyPoll(commandOk: true, status: status);
      expect(sample.outcome, MeshPollOutcome.signedOut);
      expect(sample.backendState, 'NeedsLogin');
    });

    test('classifies every ipn.State name', () {
      // Signed out — the states tailscaled lands in after a server-side delete.
      for (final state in const [
        'NeedsLogin',
        'NeedsMachineAuth',
        'Stopped',
        'NoState',
      ]) {
        expect(backendStateIsSignedOut(state), isTrue, reason: state);
      }
      // Healthy. InUseOtherUser means another OS user owns the daemon, which is
      // not a removal.
      for (final state in const ['Running', 'Starting', 'InUseOtherUser']) {
        expect(backendStateIsSignedOut(state), isFalse, reason: state);
      }
    });

    test('unknown or empty states are never signed out (fail safe)', () {
      expect(backendStateIsSignedOut(''), isFalse);
      expect(backendStateIsSignedOut('SomeFutureState'), isFalse);
      expect(backendStateIsSignedOut('needslogin'), isFalse); // case-sensitive
      expect(backendStateIsSignedOut('  Running  '), isFalse);
    });

    test('a running node that lost its 100.x address counts as removed', () {
      final status = parseTailscaleStatusJson(
        jsonEncode({
          'BackendState': 'Running',
          'Self': {
            'HostName': 'atlas-lobby--cipher',
            'TailscaleIPs': ['fd7a:115c::1'],
          },
        }),
      );
      expect(meshStatusLooksSignedOut(status), isFalse);
      expect(status.hasTailnetAddress, isFalse);
      expect(
        classifyPoll(commandOk: true, status: status).outcome,
        MeshPollOutcome.signedOut,
      );
    });

    test('a failed command is unknown, not evidence of anything', () {
      expect(
        classifyPoll(commandOk: false, status: null).outcome,
        MeshPollOutcome.unknown,
      );
      // Even with a healthy-looking body, a non-zero exit is not trusted —
      // but it is not a removal either.
      expect(
        classifyPoll(
          commandOk: false,
          status: parseTailscaleStatusJson(
            jsonEncode({
              'BackendState': 'Running',
              'Self': {
                'HostName': 'atlas-lobby--cipher',
                'TailscaleIPs': ['100.1.1.1'],
              },
            }),
          ),
        ).outcome,
        MeshPollOutcome.unknown,
      );
    });

    test('output we cannot read is unknown, not a removal', () {
      for (final payload in const <String>['', 'not json', '[]', 'null']) {
        final status = parseTailscaleStatusJson(payload);
        expect(
          classifyPoll(commandOk: true, status: status).outcome,
          MeshPollOutcome.unknown,
          reason: 'payload: "$payload"',
        );
      }
    });

    test('a payload missing BackendState or Self is unknown', () {
      // No BackendState: we could not read the one field that decides this.
      expect(
        classifyPoll(
          commandOk: true,
          status: parseTailscaleStatusJson(
            jsonEncode({
              'Self': {'HostName': 'atlas-lobby--cipher', 'TailscaleIPs': null},
            }),
          ),
        ).outcome,
        MeshPollOutcome.unknown,
      );
      // No Self block at all: unreadable, NOT "Self lost its address".
      expect(
        classifyPoll(
          commandOk: true,
          status: parseTailscaleStatusJson(
            jsonEncode({'BackendState': 'Running', 'Peer': null}),
          ),
        ).outcome,
        MeshPollOutcome.unknown,
      );
    });

    test('a healthy sample carries its backend state', () {
      final sample = classifyPoll(
        commandOk: true,
        status: parseTailscaleStatusJson(
          jsonEncode({
            'BackendState': 'Running',
            'Self': {
              'HostName': 'atlas-lobby--cipher',
              'TailscaleIPs': ['100.1.1.1'],
            },
          }),
        ),
      );
      expect(sample.isHealthy, isTrue);
      expect(sample.isSignedOut, isFalse);
      expect(sample.isUnknown, isFalse);
      expect(sample.backendState, 'Running');
    });
  });

  group('RemovalDetector', () {
    const window = Duration(seconds: 12);

    RemovalDetector detectorOn(_FakeClock clock) =>
        RemovalDetector(confirmWindow: window, elapsed: clock.call);

    test('needs three signed-out polls AND the confirm window', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);

      expect(detector.record(_signedOut()), isNull);
      clock.advance(const Duration(seconds: 6));
      expect(detector.record(_signedOut()), isNull);
      clock.advance(const Duration(seconds: 5));
      // Count is satisfied (3) but only 11s have been credited — not enough.
      expect(detector.record(_signedOut()), isNull);
      clock.advance(const Duration(seconds: 1));
      expect(detector.record(_signedOut()), isNotNull);
      // Already acted — further signed-out polls must not re-fire.
      clock.advance(const Duration(seconds: 30));
      expect(detector.record(_signedOut()), isNull);
      expect(detector.record(_signedOut()), isNull);
    });

    // R1 regression. This bug class came back three times: a stall shorter than
    // maxPollGap used to be credited IN FULL, so one 55s wedge — a brief
    // suspend, a loaded machine, a slow daemon — banked the entire confirm
    // window in a single step and disconnected a healthy player. Earlier tests
    // only ever exercised hour-long gaps, which is exactly why it survived.
    // These pin the sizes that actually occur in the wild.
    group('a single stall cannot bank the confirm window', () {
      // The confirm cadence: gaps are worth at most 2 x 2s = 4s each.
      const armed = Duration(seconds: 2);

      for (final stall in const <Duration>[
        Duration(seconds: 20),
        Duration(seconds: 40),
        Duration(seconds: 55),
        Duration(seconds: 59),
      ]) {
        test('${stall.inSeconds}s gaps do not confirm on count alone', () {
          final clock = _FakeClock();
          final detector = detectorOn(clock);
          // Three signed-out polls satisfies the COUNT. Without the per-gap cap
          // the elapsed time would satisfy the window too, and this would fire.
          for (var i = 0; i < 3; i++) {
            expect(detector.record(_signedOut(), pollInterval: armed), isNull,
                reason: '${stall.inSeconds}s gap, poll ${i + 1}');
            clock.advance(stall);
          }
          // 2 gaps x 4s credited = 8s, short of the 12s window.
          expect(detector.windowCredit, const Duration(seconds: 8));
          expect(detector.signedOutPollCount, 3);
        });
      }

      test('a real kick still confirms when observed in normal steps', () {
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        ConfirmedRemoval? fired;
        // Polling steadily at the armed cadence: every gap is fully credited
        // because it is exactly what a normal gap looks like.
        for (var i = 0; i < 12 && fired == null; i++) {
          fired = detector.record(_signedOut(), pollInterval: armed);
          if (fired == null) clock.advance(armed);
        }
        expect(fired, isNotNull);
        // 12s of window at 2s per step — genuinely observed, not banked.
        expect(clock.elapsed, const Duration(seconds: 12));
      });
    });

    test('the confirmation carries the state that produced it', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      detector.record(_signedOut('Stopped'));
      clock.advance(window);
      detector.record(_signedOut('Stopped'));
      final confirmed = detector.record(_signedOut('Stopped'));
      expect(confirmed, isNotNull);
      expect(confirmed!.backendState, 'Stopped');
      // Which is what keeps a self-inflicted disconnect from reading as a ban.
      expect(
        removalKindForBackendState(confirmed.backendState),
        MeshErrorKind.localDisconnect,
      );
    });

    test('a burst of fast polls inside the window cannot fire', () {
      // This is the cadence-independence guarantee: at the dialog's 1.5s
      // cadence, a Tailscale service restart used to trip a removal in ~3s.
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      for (var i = 0; i < 7; i++) {
        if (i > 0) clock.advance(const Duration(milliseconds: 1500));
        expect(detector.record(_signedOut()), isNull);
      }
      expect(detector.signedOutPollCount, 7);
      // Seven signed-out polls spanning 9s, and still nobody was disconnected.
      expect(detector.windowCredit, const Duration(seconds: 9));
    });

    test('the window is measured across the whole run', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      detector.record(_signedOut());
      clock.advance(window);
      expect(detector.record(_signedOut()), isNull, reason: 'only two polls');
      expect(detector.record(_signedOut()), isNotNull);
    });

    test('a single healthy poll resets the run and restarts the window', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      detector.record(_signedOut());
      clock.advance(window);
      detector.record(_signedOut());
      expect(detector.signedOutPollCount, 2);
      expect(detector.record(_healthy()), isNull);
      expect(detector.signedOutPollCount, 0);
      expect(detector.windowCredit, Duration.zero);
      expect(detector.inSignedOutRun, isFalse);

      // Blip absorbed: the window starts over, so three more signed-out polls
      // at the same instant still aren't enough.
      expect(detector.record(_signedOut()), isNull);
      expect(detector.record(_signedOut()), isNull);
      expect(detector.record(_signedOut()), isNull);
      clock.advance(window);
      expect(detector.record(_signedOut()), isNotNull);
    });

    test('inSignedOutRun opens on the first signed-out poll', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      expect(detector.inSignedOutRun, isFalse);
      detector.record(_signedOut());
      expect(detector.inSignedOutRun, isTrue);
      detector.record(_healthy());
      expect(detector.inSignedOutRun, isFalse);
    });

    test('never fires on a healthy stream', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      for (var i = 0; i < 100; i++) {
        expect(detector.record(_healthy()), isNull);
        clock.advance(const Duration(seconds: 10));
      }
    });

    group('F1 — clock jumps and suspends', () {
      test('an NTP-style forward wall-clock jump mid-run changes nothing', () {
        // The detector reads a monotonic source, so a wall clock that leaps an
        // hour forward (NTP correction, DST) cannot buy the run any credit.
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        detector.record(_signedOut());
        clock.advance(const Duration(seconds: 6));
        detector.record(_signedOut());

        clock.jumpWallClock(const Duration(hours: 1));
        clock.advance(const Duration(seconds: 5));
        expect(
          detector.record(_signedOut()),
          isNull,
          reason: '11s of real time, whatever the wall clock says',
        );
        expect(detector.windowCredit, const Duration(seconds: 11));

        // A backwards correction is just as inert.
        clock.jumpWallClock(const Duration(hours: -3));
        clock.advance(const Duration(seconds: 1));
        expect(detector.record(_signedOut()), isNotNull);
      });

      test('a suspend/resume gap re-anchors the run instead of confirming it',
          () {
        // F1, the reproduced case: one signed-out poll banked as the machine
        // suspends (the in-flight `tailscale status` dies), an hour asleep,
        // then two more 2s apart while tailscaled is still coming back. On
        // platforms where the monotonic source keeps running through sleep the
        // window would otherwise be satisfied for free.
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        expect(detector.record(_signedOut()), isNull);

        clock.advance(const Duration(hours: 1)); // lid closed
        expect(detector.record(_signedOut()), isNull);
        expect(detector.signedOutPollCount, 1, reason: 're-anchored');
        expect(detector.windowCredit, Duration.zero);

        clock.advance(const Duration(seconds: 2));
        expect(detector.record(_signedOut()), isNull);
        clock.advance(const Duration(seconds: 2));
        expect(detector.record(_signedOut()), isNull);
        expect(detector.windowCredit, const Duration(seconds: 4));

        // And once real, contiguous time has passed it still works.
        for (var i = 0; i < 4; i++) {
          clock.advance(const Duration(seconds: 2));
          detector.record(_signedOut());
        }
        expect(detector.windowCredit, greaterThanOrEqualTo(window));
      });

      test('any gap beyond maxPollGap re-anchors, in either direction', () {
        final clock = _FakeClock();
        final detector = RemovalDetector(
          confirmWindow: window,
          maxPollGap: const Duration(seconds: 60),
          elapsed: clock.call,
        );
        detector.record(_signedOut());
        clock.advance(const Duration(seconds: 30));
        detector.record(_signedOut());
        expect(detector.windowCredit, const Duration(seconds: 30));

        clock.advance(const Duration(seconds: 61));
        expect(detector.record(_signedOut()), isNull);
        expect(detector.windowCredit, Duration.zero);
        expect(detector.signedOutPollCount, 1);

        // A monotonic source that somehow went backwards is just as implausible.
        clock.advance(const Duration(seconds: 30));
        detector.record(_signedOut());
        clock.advance(const Duration(seconds: -100));
        expect(detector.record(_signedOut()), isNull);
        expect(detector.signedOutPollCount, 1);
        expect(detector.windowCredit, Duration.zero);
      });

      test('a gap exactly at maxPollGap is still credited', () {
        final clock = _FakeClock();
        final detector = RemovalDetector(
          confirmWindow: window,
          maxPollGap: const Duration(seconds: 60),
          elapsed: clock.call,
        );
        detector.record(_signedOut());
        clock.advance(const Duration(seconds: 60));
        expect(detector.record(_signedOut()), isNull, reason: 'two polls');
        expect(detector.windowCredit, const Duration(seconds: 60));
        expect(detector.record(_signedOut()), isNotNull);
      });
    });

    group('F2 — unknown polls are not evidence', () {
      test('a run of unknown polls of any length never fires', () {
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        for (var i = 0; i < 500; i++) {
          expect(
            detector.record(_unknown()),
            isNull,
            reason: 'unknown poll #$i',
          );
          clock.advance(const Duration(seconds: 10));
        }
        expect(detector.signedOutPollCount, 0);
        expect(detector.inSignedOutRun, isFalse);
        expect(detector.unknownPollCount, 500);
      });

      test('sustained unknowns raise the unreachable flag, nothing else', () {
        final clock = _FakeClock();
        final detector = RemovalDetector(
          confirmWindow: window,
          unreachableAfter: const Duration(seconds: 90),
          elapsed: clock.call,
        );
        detector.record(_unknown());
        expect(detector.tailscaleUnreachable, isFalse);
        for (var i = 0; i < 8; i++) {
          clock.advance(const Duration(seconds: 10));
          detector.record(_unknown());
        }
        expect(detector.unknownFor, const Duration(seconds: 80));
        expect(detector.tailscaleUnreachable, isFalse);

        clock.advance(const Duration(seconds: 10));
        expect(detector.record(_unknown()), isNull);
        expect(detector.unknownFor, const Duration(seconds: 90));
        expect(detector.tailscaleUnreachable, isTrue);
        expect(detector.signedOutPollCount, 0, reason: 'still no evidence');

        // The daemon comes back: the flag clears with no side effects.
        detector.record(_healthy());
        expect(detector.tailscaleUnreachable, isFalse);
        expect(detector.unknownPollCount, 0);
      });

      test('a signed-out poll also clears the unreachable flag', () {
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        for (var i = 0; i < 20; i++) {
          detector.record(_unknown());
          clock.advance(const Duration(seconds: 10));
        }
        expect(detector.tailscaleUnreachable, isTrue);
        detector.record(_signedOut());
        expect(detector.tailscaleUnreachable, isFalse);
        expect(detector.unknownFor, Duration.zero);
      });

      test('unknowns interleaved into a run do not shortcut the window', () {
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        expect(detector.record(_signedOut()), isNull);

        // 30s of polls we could not read. Under the old good/bad split these
        // were "bad" and both counted and banked their time.
        for (var i = 0; i < 15; i++) {
          clock.advance(const Duration(seconds: 2));
          expect(detector.record(_unknown()), isNull);
        }
        expect(detector.signedOutPollCount, 1, reason: 'unknowns do not count');

        // The next real sample resumes the run, but the 30s buys nothing.
        expect(detector.record(_signedOut()), isNull);
        expect(detector.signedOutPollCount, 2);
        expect(detector.windowCredit, Duration.zero);

        clock.advance(const Duration(seconds: 2));
        expect(
          detector.record(_signedOut()),
          isNull,
          reason: 'count is 3 but only 2s of credited time',
        );
        expect(detector.windowCredit, const Duration(seconds: 2));

        // It confirms only once the time is genuinely observed.
        for (var i = 0; i < 4; i++) {
          clock.advance(const Duration(seconds: 2));
          detector.record(_signedOut());
        }
        expect(detector.windowCredit, const Duration(seconds: 10));
        clock.advance(const Duration(seconds: 2));
        expect(detector.record(_signedOut()), isNotNull);
      });

      test('an unknown neither confirms nor clears a run in progress', () {
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        detector.record(_signedOut());
        clock.advance(const Duration(seconds: 2));
        detector.record(_signedOut());
        expect(detector.signedOutPollCount, 2);

        clock.advance(const Duration(seconds: 2));
        expect(detector.record(_unknown()), isNull);
        expect(detector.signedOutPollCount, 2, reason: 'not cleared');
        expect(detector.inSignedOutRun, isTrue, reason: 'still confirming');
        expect(detector.windowCredit, const Duration(seconds: 2));
      });

      test('unknowns alternating with signed-out polls still cannot fire fast',
          () {
        // Pathological CLI: every other poll is unreadable. Nothing here is a
        // continuous observation, so the run crawls instead of confirming.
        final clock = _FakeClock();
        final detector = detectorOn(clock);
        for (var i = 0; i < 200; i++) {
          clock.advance(const Duration(seconds: 2));
          expect(detector.record(_signedOut()), isNull);
          clock.advance(const Duration(seconds: 2));
          expect(detector.record(_unknown()), isNull);
        }
        expect(detector.windowCredit, Duration.zero);
      });
    });

    test('reset clears the run', () {
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      detector.record(_signedOut());
      clock.advance(window);
      detector.record(_signedOut());
      detector.record(_unknown());
      detector.reset();
      expect(detector.signedOutPollCount, 0);
      expect(detector.unknownPollCount, 0);
      expect(detector.windowCredit, Duration.zero);
      expect(detector.record(_signedOut()), isNull);
    });

    test('defaults to a real monotonic source without waiting on it', () {
      // No injected source: three instant signed-out polls must not fire,
      // because no time has passed.
      final detector = RemovalDetector();
      expect(detector.record(_signedOut()), isNull);
      expect(detector.record(_signedOut()), isNull);
      expect(detector.record(_signedOut()), isNull);
      expect(detector.signedOutPollCount, 3);
      expect(detector.windowCredit, lessThan(const Duration(seconds: 1)));
    });

    test('no mixture of healthy and unknown polls can ever confirm', () {
      // The structural guarantee, exercised: only a signed-out sample can mint
      // a ConfirmedRemoval, so no amount of unreadable polls reaches teardown.
      final clock = _FakeClock();
      final detector = detectorOn(clock);
      final samples = <MeshPollSample>[_unknown(), _healthy()];
      for (var i = 0; i < 400; i++) {
        clock.advance(const Duration(seconds: 7));
        expect(detector.record(samples[i % samples.length]), isNull);
      }
    });
  });

  group('removalKindForBackendState', () {
    test('Stopped is the user disconnecting themselves', () {
      expect(
        removalKindForBackendState('Stopped'),
        MeshErrorKind.localDisconnect,
      );
      expect(
        removalKindForBackendState(' Stopped '),
        MeshErrorKind.localDisconnect,
      );
    });

    test('lost authorisation reads as a removal', () {
      for (final state in <String>[
        'NeedsLogin',
        'NeedsMachineAuth',
        'NoState',
      ]) {
        expect(
          removalKindForBackendState(state),
          MeshErrorKind.removed,
          reason: state,
        );
      }
    });

    test('an unknown or missing state falls back to removal', () {
      expect(removalKindForBackendState(''), MeshErrorKind.removed);
      expect(removalKindForBackendState('Whatever'), MeshErrorKind.removed);
    });
  });
}
