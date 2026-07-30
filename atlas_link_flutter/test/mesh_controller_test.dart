import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atlas_link_flutter/mesh_controller.dart';
import 'package:atlas_link_flutter/tailscale_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hand-wound clock. Every timing assertion below is made against this, so the
/// suite exercises the elapsed-time debounce without a single real delay.
///
/// It carries two sources on purpose: the monotonic one the controller's
/// detector consumes, and a wall clock a test can move on its own — which is
/// what an NTP correction or a DST change does to a real machine, and which
/// must therefore be incapable of confirming a removal.
class _FakeClock {
  Duration _monotonic = Duration.zero;
  DateTime _wall = DateTime.utc(2026, 1, 1, 12);

  /// The injected seam.
  Duration call() => _monotonic;

  Duration get elapsed => _monotonic;
  DateTime get wallClock => _wall;

  /// Ordinary time passing: both sources move together.
  void advance(Duration by) {
    _monotonic += by;
    _wall = _wall.add(by);
  }

  /// An NTP/DST correction: only the wall clock moves.
  void jumpWallClock(Duration by) => _wall = _wall.add(by);

  Duration since(Duration start) => _monotonic - start;
}

/// Drives [MeshController] without spawning a real Tailscale CLI: records every
/// invocation and answers `status` from whatever payload the test has staged.
class _FakeCli {
  _FakeCli({required String statusJson, this.clock}) : _statusJson = statusJson;

  String _statusJson;
  final List<List<String>> calls = <List<String>>[];

  /// When set, every call burns [latency] of fake time before answering, so a
  /// test can model a CLI that is slow rather than absent.
  final _FakeClock? clock;
  Duration latency = Duration.zero;

  /// When true, every invocation fails the way a missing/wedged daemon does.
  bool broken = false;

  /// When true, `status` exits 0 but answers with something unreadable.
  bool garbage = false;

  /// When set, `status` hangs on this instead of answering — a wedged CLI that
  /// eventually times out. Complete it with null to model the timeout.
  Completer<ProcessResult?>? statusGate;

  /// When set, `up` / `down` hang on these, so a test can land other calls
  /// while a connect or a teardown is mid-flight.
  Completer<void>? upGate;
  Completer<void>? downGate;

  /// Swap what the next `tailscale status --json` reports (e.g. to simulate the
  /// device being deleted from the tailnet mid-session).
  set statusJson(String value) => _statusJson = value;

  List<String> get commands => calls.map((c) => c.join(' ')).toList();

  int countOf(String command) => commands.where((c) => c == command).length;

  Future<ProcessResult?> call(List<String> args, Duration? timeout) async {
    calls.add(args);
    final verb = args.isEmpty ? '' : args.first;
    if (verb == 'up' && upGate != null) await upGate!.future;
    if (verb == 'down' && downGate != null) await downGate!.future;
    if (verb == 'status') {
      final gate = statusGate;
      if (gate != null) return gate.future;
      if (latency > Duration.zero) clock?.advance(latency);
    }
    if (broken) {
      return ProcessResult(0, 1, '', 'failed to connect to local backend');
    }
    if (verb == 'status') {
      return ProcessResult(0, 0, garbage ? '<html>502</html>' : _statusJson, '');
    }
    return ProcessResult(0, 0, '', '');
  }
}

String _runningStatus() => jsonEncode({
  'BackendState': 'Running',
  'Self': {
    'HostName': 'atlas-lobby--cipher',
    'TailscaleIPs': ['100.81.186.59'],
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
  },
});

/// What the daemon reports after the device is deleted server-side.
String _needsLoginStatus() => jsonEncode({
  'BackendState': 'NeedsLogin',
  'Self': {
    'HostName': 'atlas-lobby--cipher',
    'TailscaleIPs': null,
    'Online': false,
  },
  'Peer': null,
});

/// What the daemon reports after the user hits Disconnect in their own tray:
/// still registered (the address is intact), just switched off locally.
String _stoppedStatus() => jsonEncode({
  'BackendState': 'Stopped',
  'Self': {
    'HostName': 'atlas-lobby--cipher',
    'TailscaleIPs': ['100.81.186.59'],
    'Online': false,
    'OS': 'windows',
  },
  'Peer': null,
});

Future<MeshController> _connected(_FakeCli cli, {_FakeClock? clock}) async {
  final controller = MeshController(
    processRunner: cli.call,
    elapsed: clock?.call,
  );
  final ok = await controller.connectWithAuthKey(
    'tskey-auth-test',
    username: 'cipher',
  );
  expect(ok, isTrue, reason: 'fake CLI should have connected cleanly');
  expect(controller.connected, isTrue);
  return controller;
}

/// Walk the poll loop the way the timer would — at whatever cadence the
/// controller currently has armed — moving only the fake clock. Returns how
/// much time it took the controller to act, or null if it never did.
///
/// The wait for each tick is charged in full before the call, and the fake CLI
/// charges its own latency on top, which is exactly the worst-case spacing a
/// real `Timer.periodic` produces when a call outlives its tick.
Future<Duration?> _pollUntilDisconnected(
  MeshController controller,
  _FakeClock clock, {
  Duration giveUpAfter = const Duration(minutes: 5),
}) async {
  final start = clock.elapsed;
  while (controller.connected && clock.since(start) < giveUpAfter) {
    clock.advance(
      controller.armedPollInterval ?? MeshController.kConfirmPollInterval,
    );
    await controller.pollOnce();
  }
  return controller.connected ? null : clock.since(start);
}

void main() {
  group('removal watch', () {
    test('three back-to-back signed-out polls inside the window do NOT '
        'disconnect', () async {
      // The K1/K2 case: three "polls" that are really one 3s event (a Tailscale
      // service restart, or one stalled CLI call seen three times) must never
      // cost a healthy player their connection.
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      var removedSignals = 0;
      controller.onRemoved = () => removedSignals++;

      expect(controller.pollingActive, isTrue);
      expect(controller.peers.single.name, 'nata');

      cli.statusJson = _needsLoginStatus();
      for (var i = 0; i < 3; i++) {
        clock.advance(const Duration(seconds: 1));
        await controller.pollOnce();
      }
      expect(controller.connected, isTrue, reason: '3s of bad polls is a blip');
      expect(controller.signedOutPollCount, 3);
      expect(removedSignals, 0);
      // The room is held, not blanked, while we are unsure.
      expect(controller.peers.single.name, 'nata');

      // It really is gone: the confirm window elapses and we act.
      final took = await _pollUntilDisconnected(controller, clock);
      expect(took, isNotNull);
      expect(took!, lessThanOrEqualTo(MeshController.kRemovalConfirmWindow));

      expect(controller.connected, isFalse);
      expect(controller.errorKind, MeshErrorKind.removed);
      expect(controller.errorMessage, 'You were removed from the ATLAS Network.');
      expect(controller.status.self, isNull);
      expect(controller.peers, isEmpty);
      expect(controller.joiningRoom, isFalse);
      // No timer may outlive the connection.
      expect(controller.pollingActive, isFalse);
      // Signalled exactly once.
      expect(removedSignals, 1);
      expect(controller.removedTick, 1);
      // Local Tailscale state was cleaned up so a later reconnect is clean.
      expect(cli.commands, contains('down'));

      // Further polls are inert — no second signal, no re-entry.
      clock.advance(const Duration(minutes: 1));
      await controller.pollOnce();
      await controller.pollOnce();
      expect(removedSignals, 1);
      expect(controller.removedTick, 1);

      controller.dispose();
    });

    test('a real kick is confirmed promptly from either cadence', () async {
      for (final fast in <bool>[true, false]) {
        final reason = fast ? 'dialog open' : 'background watch';
        final clock = _FakeClock();
        final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
        final controller = await _connected(cli, clock: clock);
        controller.startPolling(fast: fast);
        expect(
          controller.armedPollInterval,
          fast
              ? MeshController.kFastPollInterval
              : MeshController.kWatchPollInterval,
          reason: reason,
        );

        // Kicked, right after a healthy poll — the worst moment for it.
        cli.statusJson = _needsLoginStatus();
        final took = await _pollUntilDisconnected(controller, clock);

        expect(controller.connected, isFalse, reason: reason);
        expect(controller.errorKind, MeshErrorKind.removed, reason: reason);
        // The CONFIRM phase costs the same from either cadence; the wait for
        // the FIRST signed-out poll does not, and adds one cadence interval.
        final cadence = fast
            ? MeshController.kFastPollInterval
            : MeshController.kWatchPollInterval;
        expect(
          took!,
          lessThanOrEqualTo(
            cadence +
                MeshController.kRemovalConfirmWindow +
                MeshController.kConfirmPollInterval,
          ),
          reason: reason,
        );
        // Everything after the first signed-out poll — the part that is meant
        // to be cadence-independent — fits in ~15s either way.
        expect(
          took - cadence,
          lessThanOrEqualTo(const Duration(seconds: 15)),
          reason: reason,
        );
        // Measured: 13.5s with the dialog open, 22.0s on the background watch.
        expect(took, fast
            ? const Duration(milliseconds: 13500)
            : const Duration(seconds: 22), reason: reason);
        controller.dispose();
      }
    });

    test('a kick is still confirmed when every status call rides its timeout',
        () async {
      // Same kick, but the daemon answers only at the 8s timeout boundary.
      // Slower, and that is the correct trade.
      for (final fast in <bool>[true, false]) {
        final reason = fast ? 'dialog open' : 'background watch';
        final clock = _FakeClock();
        final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
        final controller = await _connected(cli, clock: clock);
        cli.latency = const Duration(seconds: 8);
        controller.startPolling(fast: fast);

        cli.statusJson = _needsLoginStatus();
        final took = await _pollUntilDisconnected(controller, clock);

        expect(controller.connected, isFalse, reason: reason);
        expect(controller.errorKind, MeshErrorKind.removed, reason: reason);
        // Measured with the per-gap credit cap in place: 39.5s dialog-open,
        // 48.0s on the background watch. Slower than the uncapped numbers
        // (29.5s / 38.0s) precisely BECAUSE a wedged CLI no longer banks a
        // whole 8s stall as observed time — the window is walked in
        // poll-sized steps or not at all. Slower here is the point.
        expect(took, fast
            ? const Duration(milliseconds: 39500)
            : const Duration(seconds: 48), reason: reason);
        controller.dispose();
      }
    });

    test('a single 11s stall at the fast cadence is one unknown poll, not '
        'three bad ones', () async {
      // K1: `Timer.periodic` keeps firing while a `tailscale status` call is
      // wedged. Those ticks must be dropped, not counted — otherwise one hang
      // manufactures a whole run of bad polls and a false removal.
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.startPolling(fast: true);
      controller.onRemoved = () => fail('a stalled CLI disconnected a healthy '
          'player');

      final gate = Completer<ProcessResult?>();
      cli.statusGate = gate;
      final stalled = controller.pollOnce();

      // 11s of ticks at 1.5s land while that one call is in flight.
      var ticks = 0;
      for (var elapsed = Duration.zero;
          elapsed < const Duration(seconds: 11);
          elapsed += MeshController.kFastPollInterval) {
        clock.advance(MeshController.kFastPollInterval);
        await controller.pollOnce();
        ticks++;
      }
      expect(ticks, greaterThanOrEqualTo(7));
      expect(controller.unknownPollCount, 0, reason: 'nothing has resolved');

      // The wedged call finally gives up (what the 8s timeout looks like).
      cli.statusGate = null;
      gate.complete(null);
      await stalled;

      expect(controller.connected, isTrue);
      expect(controller.signedOutPollCount, 0, reason: 'a timeout is no proof');
      expect(controller.unknownPollCount, 1, reason: 'one hang, one sample');
      expect(controller.removedTick, 0);

      // And it recovers with no trace once the daemon answers again.
      clock.advance(MeshController.kConfirmPollInterval);
      await controller.pollOnce();
      expect(controller.unknownPollCount, 0);
      expect(controller.connected, isTrue);

      controller.dispose();
    });

    test('a skipped tick counts as no sample at all', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);

      cli.statusJson = _needsLoginStatus();
      clock.advance(const Duration(seconds: 2));
      await controller.pollOnce();
      clock.advance(const Duration(seconds: 2));
      await controller.pollOnce();
      expect(controller.signedOutPollCount, 2);

      // A poll stalls; the ticks that pile up behind it must not advance the
      // run (nor clear it).
      final gate = Completer<ProcessResult?>();
      cli.statusGate = gate;
      final stalled = controller.pollOnce();
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(seconds: 2));
        await controller.pollOnce();
      }
      expect(controller.signedOutPollCount, 2, reason: 'skipped ticks are not '
          'polls');
      expect(controller.connected, isTrue);

      // The stalled call comes back healthy: the whole run is absorbed.
      cli.statusGate = null;
      cli.statusJson = _runningStatus();
      gate.complete(ProcessResult(0, 0, _runningStatus(), ''));
      await stalled;
      expect(controller.signedOutPollCount, 0);
      expect(controller.connected, isTrue);

      controller.dispose();
    });

    test('a good poll mid-run resets the detector and restores the cadence',
        () async {
      for (final fast in <bool>[true, false]) {
        final wanted = fast
            ? MeshController.kFastPollInterval
            : MeshController.kWatchPollInterval;
        final clock = _FakeClock();
        final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
        final controller = await _connected(cli, clock: clock);
        controller.startPolling(fast: fast);
        expect(controller.armedPollInterval, wanted);

        cli.statusJson = _needsLoginStatus();
        clock.advance(wanted);
        await controller.pollOnce();
        expect(controller.signedOutPollCount, 1);
        expect(
          controller.armedPollInterval,
          MeshController.kConfirmPollInterval,
          reason: 'the first signed-out poll speeds us up to confirm',
        );

        cli.statusJson = _runningStatus();
        clock.advance(MeshController.kConfirmPollInterval);
        await controller.pollOnce();
        expect(controller.signedOutPollCount, 0);
        expect(controller.connected, isTrue);
        expect(
          controller.armedPollInterval,
          wanted,
          reason: 'a good poll restores the cadence the UI wants',
        );
        controller.dispose();
      }
    });

    test('the dialog opening mid-run still confirms, then goes fast', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);

      cli.statusJson = _needsLoginStatus();
      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.armedPollInterval, MeshController.kConfirmPollInterval);

      // Player opens the Network dialog while we are unsure: confirming wins,
      // but the fast cadence is remembered.
      controller.startPolling(fast: true);
      expect(controller.armedPollInterval, MeshController.kConfirmPollInterval);

      cli.statusJson = _runningStatus();
      clock.advance(MeshController.kConfirmPollInterval);
      await controller.pollOnce();
      expect(controller.armedPollInterval, MeshController.kFastPollInterval);

      controller.dispose();
    });

    test('a good poll in between absorbs the blips', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      var removedSignals = 0;
      controller.onRemoved = () => removedSignals++;

      cli.statusJson = _needsLoginStatus();
      for (var i = 0; i < 2; i++) {
        clock.advance(const Duration(seconds: 8));
        await controller.pollOnce();
      }

      cli.statusJson = _runningStatus();
      clock.advance(const Duration(seconds: 8));
      await controller.pollOnce();

      cli.statusJson = _needsLoginStatus();
      for (var i = 0; i < 2; i++) {
        clock.advance(const Duration(seconds: 8));
        await controller.pollOnce();
      }

      expect(controller.connected, isTrue);
      expect(controller.pollingActive, isTrue);
      expect(removedSignals, 0);

      controller.dispose();
    });

    test('a healthy stream never disconnects anyone', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('healthy player was disconnected');

      for (var i = 0; i < 25; i++) {
        clock.advance(MeshController.kWatchPollInterval);
        await controller.pollOnce();
      }
      expect(controller.connected, isTrue);
      expect(controller.errorKind, isNull);
      expect(controller.removedTick, 0);
      expect(controller.armedPollInterval, MeshController.kWatchPollInterval);

      controller.dispose();
    });
  });

  group('F1 — sleep, resume and clock jumps', () {
    test('a suspend/resume in the middle of a run does NOT disconnect',
        () async {
      // The reproduced case: one signed-out poll banked as the machine
      // suspends, an hour asleep, then two more 2s apart while tailscaled is
      // still coming back. Closing a laptop lid is not an edge case.
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('a laptop lid disconnected a healthy '
          'player');

      cli.statusJson = _needsLoginStatus();
      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.signedOutPollCount, 1);

      // Lid closed. Both the wall clock and (on some platforms) the monotonic
      // source run on through it.
      clock.advance(const Duration(hours: 1));
      await controller.pollOnce();
      clock.advance(const Duration(seconds: 2));
      await controller.pollOnce();

      expect(controller.connected, isTrue, reason: 'nobody touched this player');
      expect(controller.removedTick, 0);
      expect(controller.errorKind, isNull);
      expect(cli.commands, isNot(contains('down')));

      // Tailscaled finishes coming back: no trace of any of it.
      cli.statusJson = _runningStatus();
      clock.advance(const Duration(seconds: 2));
      await controller.pollOnce();
      expect(controller.connected, isTrue);
      expect(controller.signedOutPollCount, 0);
      expect(controller.peers.single.name, 'nata');

      controller.dispose();
    });

    test('an NTP-style forward wall-clock jump mid-run does NOT disconnect',
        () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('a clock correction disconnected a '
          'healthy player');

      cli.statusJson = _needsLoginStatus();
      for (var i = 0; i < 3; i++) {
        clock.advance(const Duration(seconds: 1));
        // The kind of correction Windows makes after a resume, or a DST flip.
        clock.jumpWallClock(const Duration(hours: 1));
        await controller.pollOnce();
      }
      expect(controller.connected, isTrue);
      expect(controller.signedOutPollCount, 3);
      expect(controller.removedTick, 0);
      expect(clock.wallClock.difference(DateTime.utc(2026, 1, 1, 12)),
          greaterThan(const Duration(hours: 2)));

      controller.dispose();
    });

    test('a resume with the daemon still down never disconnects, however long',
        () async {
      // Worst realistic shape: hours asleep, then a stretch of polls while
      // tailscaled comes back. No single gap is ever plausible enough to bank.
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('a resume disconnected a healthy '
          'player');

      cli.statusJson = _needsLoginStatus();
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(hours: 2));
        await controller.pollOnce();
        expect(controller.connected, isTrue, reason: 'suspend #$i');
        expect(controller.signedOutPollCount, 1, reason: 'always re-anchored');
      }
      expect(controller.removedTick, 0);

      controller.dispose();
    });
  });

  group('F2 — a CLI we cannot read is not evidence', () {
    test('a CLI that never answers never disconnects anyone', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('an unreadable CLI disconnected a '
          'healthy player');
      final downsAtStart = cli.countOf('down');

      cli.broken = true;
      final took = await _pollUntilDisconnected(
        controller,
        clock,
        giveUpAfter: const Duration(minutes: 30),
      );
      expect(took, isNull, reason: '30 minutes of failures, still connected');
      expect(controller.connected, isTrue);
      expect(controller.removedTick, 0);
      expect(controller.signedOutPollCount, 0);
      // No `tailscale down`, which is what made the old false alarm come true.
      expect(cli.countOf('down'), downsAtStart);
      // A non-destructive state instead, claiming nothing about removal.
      expect(controller.tailscaleUnreachable, isTrue);
      expect(controller.errorKind, MeshErrorKind.tailscaleUnreachable);
      expect(controller.errorMessage, isNot(contains('removed')));
      expect(
        controller.errorMessage,
        "Can't reach Tailscale on this PC. Make sure it's still running.",
      );

      controller.dispose();
    });

    test('output we cannot parse behaves the same as a dead CLI', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('garbage output disconnected a healthy '
          'player');

      cli.garbage = true;
      for (var i = 0; i < 60; i++) {
        clock.advance(MeshController.kWatchPollInterval);
        await controller.pollOnce();
      }
      expect(controller.connected, isTrue);
      expect(controller.removedTick, 0);
      expect(controller.tailscaleUnreachable, isTrue);

      controller.dispose();
    });

    test('the unreachable state appears only after ~90s, and clears cleanly',
        () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);

      cli.broken = true;
      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.tailscaleUnreachable, isFalse,
          reason: 'one failure is nothing');

      // Eight more at 10s: 80s of unreadable polls, still quiet.
      for (var i = 0; i < 8; i++) {
        clock.advance(MeshController.kWatchPollInterval);
        await controller.pollOnce();
      }
      expect(controller.tailscaleUnreachable, isFalse);
      expect(controller.errorKind, isNull);

      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.tailscaleUnreachable, isTrue);
      expect(controller.connected, isTrue, reason: 'we still believe we are on');

      // The daemon comes back: the warning clears, the room repopulates.
      cli.broken = false;
      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.tailscaleUnreachable, isFalse);
      expect(controller.errorKind, isNull);
      expect(controller.errorMessage, '');
      expect(controller.peers.single.name, 'nata');
      expect(controller.connected, isTrue);

      controller.dispose();
    });

    test('unknown polls interleaved into a signed-out run do not shortcut the '
        'window', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      var removedSignals = 0;
      controller.onRemoved = () => removedSignals++;

      // One real signed-out poll opens the run...
      cli.statusJson = _needsLoginStatus();
      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.signedOutPollCount, 1);

      // ...then the CLI stops answering for 40s. Under the old good/bad split
      // that was 20 more "bad polls" and 40s of window, i.e. a disconnect.
      cli.broken = true;
      for (var i = 0; i < 20; i++) {
        clock.advance(MeshController.kConfirmPollInterval);
        await controller.pollOnce();
      }
      expect(controller.connected, isTrue);
      expect(removedSignals, 0);
      expect(controller.signedOutPollCount, 1, reason: 'unknowns do not count');

      // Two more real ones: the count is now satisfied, the window is not.
      cli.broken = false;
      cli.statusJson = _needsLoginStatus();
      clock.advance(MeshController.kConfirmPollInterval);
      await controller.pollOnce();
      clock.advance(MeshController.kConfirmPollInterval);
      await controller.pollOnce();
      expect(controller.signedOutPollCount, 3);
      expect(controller.connected, isTrue, reason: 'only 2s was truly observed');
      expect(removedSignals, 0);

      // The kick is real, so it does confirm — on genuinely observed time.
      final took = await _pollUntilDisconnected(controller, clock);
      expect(took, isNotNull);
      expect(took!, greaterThanOrEqualTo(const Duration(seconds: 10)));
      expect(controller.errorKind, MeshErrorKind.removed);
      expect(removedSignals, 1);

      controller.dispose();
    });

    test('a run of unknowns cannot be capped off by a single signed-out poll',
        () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('one signed-out poll after a dead CLI '
          'disconnected a player');

      cli.broken = true;
      for (var i = 0; i < 30; i++) {
        clock.advance(MeshController.kWatchPollInterval);
        await controller.pollOnce();
      }
      expect(controller.tailscaleUnreachable, isTrue);

      // The daemon answers once, mid-restart, and says NeedsLogin.
      cli.broken = false;
      cli.statusJson = _needsLoginStatus();
      clock.advance(MeshController.kWatchPollInterval);
      await controller.pollOnce();
      expect(controller.connected, isTrue);
      expect(controller.signedOutPollCount, 1);
      expect(controller.tailscaleUnreachable, isFalse,
          reason: 'we reached it, so it is reachable');

      // ...and then comes back properly.
      cli.statusJson = _runningStatus();
      clock.advance(MeshController.kConfirmPollInterval);
      await controller.pollOnce();
      expect(controller.connected, isTrue);
      expect(controller.signedOutPollCount, 0);

      controller.dispose();
    });

    test('a genuine signed-out run still confirms and still removes', () async {
      // The no-regression half of F2: real evidence still works.
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      var removedSignals = 0;
      controller.onRemoved = () => removedSignals++;

      cli.statusJson = _needsLoginStatus();
      final took = await _pollUntilDisconnected(controller, clock);

      expect(took, isNotNull);
      expect(controller.connected, isFalse);
      expect(controller.errorKind, MeshErrorKind.removed);
      expect(controller.errorMessage, 'You were removed from the ATLAS Network.');
      expect(removedSignals, 1);
      expect(controller.pollingActive, isFalse);
      expect(cli.commands, contains('down'));

      controller.dispose();
    });
  });

  group('removal wording', () {
    test('a lost authorisation reads as a removal', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);

      cli.statusJson = _needsLoginStatus();
      await _pollUntilDisconnected(controller, clock);

      expect(controller.errorKind, MeshErrorKind.removed);
      expect(controller.errorMessage, 'You were removed from the ATLAS Network.');
      expect(controller.removedTick, 1);

      controller.dispose();
    });

    test('Stopped reads as a local disconnect, not a removal', () async {
      // The user hit Disconnect in their own Tailscale tray. Same teardown,
      // different story — telling them they were removed would be a lie.
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);

      cli.statusJson = _stoppedStatus();
      await _pollUntilDisconnected(controller, clock);

      expect(controller.connected, isFalse);
      expect(controller.errorKind, MeshErrorKind.localDisconnect);
      expect(controller.errorMessage, 'Tailscale was disconnected on this PC.');
      expect(controller.removedTick, 1);
      expect(controller.pollingActive, isFalse);

      controller.dispose();
    });
  });

  group('polling lifecycle', () {
    test('startPolling is a no-op while disconnected', () {
      final controller = MeshController(
        processRunner: _FakeCli(statusJson: _runningStatus()).call,
      );
      controller.startPolling();
      controller.startPolling(fast: true);
      expect(controller.pollingActive, isFalse);
      expect(controller.armedPollInterval, isNull);
      controller.dispose();
    });

    test('switching cadence keeps exactly one timer, and stop clears it',
        () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);

      expect(controller.pollingActive, isTrue); // watch cadence from connect
      expect(controller.armedPollInterval, MeshController.kWatchPollInterval);
      controller.startPolling(fast: true);
      expect(controller.armedPollInterval, MeshController.kFastPollInterval);
      controller.startPolling(fast: true); // idempotent
      expect(controller.armedPollInterval, MeshController.kFastPollInterval);
      controller.resumeWatch();
      expect(controller.armedPollInterval, MeshController.kWatchPollInterval);

      controller.stopPolling();
      expect(controller.pollingActive, isFalse);
      expect(controller.armedPollInterval, isNull);

      controller.dispose();
    });

    test('resumeWatch does not resurrect polling after a disconnect', () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);

      await controller.disconnect();
      expect(controller.connected, isFalse);
      expect(controller.pollingActive, isFalse);

      // What the Network dialog's `finally` does on close.
      controller.resumeWatch();
      expect(controller.pollingActive, isFalse);

      controller.dispose();
    });

    test('resumeWatch racing an in-flight disconnect arms nothing', () async {
      // K3: `down` can take seconds. A dialog closing during it used to see a
      // still-connected controller and arm a watch timer that outlived the
      // teardown.
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);
      final gate = Completer<void>();
      cli.downGate = gate;

      final pending = controller.disconnect();
      expect(controller.connected, isFalse, reason: 'state falls first');
      expect(controller.pollingActive, isFalse);

      controller.resumeWatch();
      controller.startPolling(fast: true);
      expect(controller.pollingActive, isFalse, reason: 'tearing down');

      cli.downGate = null;
      gate.complete();
      await pending;

      expect(controller.connected, isFalse);
      expect(controller.pollingActive, isFalse);
      controller.resumeWatch();
      expect(controller.pollingActive, isFalse);

      controller.dispose();
    });

    test('resumeWatch racing an in-flight shutdown arms nothing', () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);
      final gate = Completer<void>();
      cli.downGate = gate;

      final pending = controller.shutdown();
      expect(controller.connected, isFalse);

      controller.resumeWatch();
      controller.startPolling(fast: true);
      expect(controller.pollingActive, isFalse, reason: 'tearing down');

      cli.downGate = null;
      gate.complete();
      await pending;

      expect(controller.pollingActive, isFalse);
      controller.resumeWatch();
      expect(controller.pollingActive, isFalse);

      controller.dispose();
    });

    test('shutdown stops the watch', () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);
      expect(controller.pollingActive, isTrue);

      await controller.shutdown();
      expect(controller.connected, isFalse);
      expect(controller.pollingActive, isFalse);
      expect(cli.commands, contains('down'));

      controller.dispose();
    });

    test('downNowSync stops the watch', () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);
      expect(controller.pollingActive, isTrue);

      controller.downNowSync();
      expect(controller.pollingActive, isFalse);

      controller.dispose();
    });

    test('dispose leaves no timer and silences the removal signal', () async {
      final clock = _FakeClock();
      final cli = _FakeCli(statusJson: _runningStatus(), clock: clock);
      final controller = await _connected(cli, clock: clock);
      controller.onRemoved = () => fail('signalled after dispose');
      expect(controller.pollingActive, isTrue);

      controller.dispose();
      expect(controller.pollingActive, isFalse);

      // A poll that resolves after dispose must not touch the dead controller.
      cli.statusJson = _needsLoginStatus();
      for (var i = 0; i < 3; i++) {
        clock.advance(const Duration(seconds: 10));
        await controller.pollOnce();
      }
      expect(controller.removedTick, 0);
    });
  });

  group('F3 — a teardown landing mid-connect', () {
    /// Start a connect that is suspended inside `tailscale up`.
    Future<(MeshController, _FakeCli, Completer<void>, Future<bool>)>
    connectingController() async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = MeshController(processRunner: cli.call);
      final gate = Completer<void>();
      cli.upGate = gate;
      final connecting = controller.connectWithAuthKey(
        'tskey-auth-test',
        username: 'cipher',
      );
      await pumpEventQueue();
      expect(cli.calls.any((c) => c.first == 'up'), isTrue);
      return (controller, cli, gate, connecting);
    }

    test('shutdown completing mid-connect leaves nothing connected', () async {
      final (controller, cli, gate, connecting) = await connectingController();

      await controller.shutdown();
      cli.upGate = null;
      gate.complete();

      expect(await connecting, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.connecting, isFalse, reason: 'the latch must clear');
      expect(controller.pollingActive, isFalse);
      // The node came up after the user asked to leave: put it back down.
      expect(cli.commands, contains('down'));
      // It never got as far as believing it was connected.
      expect(cli.commands, isNot(contains('status --json')));

      controller.dispose();
    });

    test('disconnect completing mid-connect leaves nothing connected', () async {
      final (controller, cli, gate, connecting) = await connectingController();

      await controller.disconnect();
      cli.upGate = null;
      gate.complete();

      expect(await connecting, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.connecting, isFalse);
      expect(controller.pollingActive, isFalse);
      // One `down` from the disconnect, one from the connect abandoning ship.
      expect(cli.countOf('down'), 2);

      controller.dispose();
    });

    test('downNowSync mid-connect leaves nothing connected', () async {
      final (controller, cli, gate, connecting) = await connectingController();

      controller.downNowSync();
      cli.upGate = null;
      gate.complete();

      expect(await connecting, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.pollingActive, isFalse);
      expect(cli.commands, contains('down'));

      controller.dispose();
    });

    test('a teardown during verification still leaves the tailnet', () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = MeshController(processRunner: cli.call);
      final gate = Completer<ProcessResult?>();
      cli.statusGate = gate;

      final connecting = controller.connectWithAuthKey(
        'tskey-auth-test',
        username: 'cipher',
      );
      // Let `up` land so we are suspended inside _verifyUp's status call.
      await pumpEventQueue();
      expect(cli.commands, contains('status --json'));

      await controller.shutdown();
      cli.statusGate = null;
      gate.complete(ProcessResult(0, 0, _runningStatus(), ''));

      expect(await connecting, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.connecting, isFalse);
      expect(controller.pollingActive, isFalse);
      expect(cli.commands, contains('down'));

      controller.dispose();
    });

    test('an abandoned connect leaves the controller reusable', () async {
      // The latch that guards re-entrancy must not survive the teardown, or the
      // player can never rejoin after leaving mid-connect.
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = MeshController(processRunner: cli.call);
      final gate = Completer<void>();
      cli.upGate = gate;
      final connecting = controller.connectWithAuthKey(
        'tskey-auth-test',
        username: 'cipher',
      );
      await pumpEventQueue();

      // Whatever tore us down while `up` was in flight, the connect must not
      // resurrect the connection behind it.
      await controller.disconnect();
      cli.upGate = null;
      gate.complete();
      expect(await connecting, isFalse);

      // ...and the user can still try again afterwards.
      final ok = await controller.connectWithAuthKey(
        'tskey-auth-test',
        username: 'cipher',
      );
      expect(ok, isTrue);
      expect(controller.connected, isTrue);

      controller.dispose();
    });

    test('a rename racing a disconnect does not resurrect the connection',
        () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = await _connected(cli);
      final gate = Completer<void>();
      // `set --hostname` is not gated, so gate `down` and drive the order by
      // starting the rename first.
      cli.downGate = gate;

      final renaming = controller.syncIdentity('nata');
      final leaving = controller.disconnect();
      cli.downGate = null;
      gate.complete();
      await Future.wait(<Future<void>>[renaming, leaving]);

      expect(controller.connected, isFalse);
      expect(controller.pollingActive, isFalse);
      expect(controller.joiningRoom, isFalse);

      controller.dispose();
    });
  });

  group('connect racing dispose', () {
    test('a connect resolving after dispose sets nothing and arms nothing',
        () async {
      // K4: the launcher can be closed while `tailscale up` is still running.
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = MeshController(processRunner: cli.call);
      final gate = Completer<void>();
      cli.upGate = gate;

      final connecting = controller.connectWithAuthKey(
        'tskey-auth-test',
        username: 'cipher',
      );
      controller.dispose();
      cli.upGate = null;
      gate.complete();

      expect(await connecting, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.joiningRoom, isFalse);
      expect(controller.pollingActive, isFalse);
      expect(controller.removedTick, 0);
      // Never got as far as verifying, so it never came up.
      expect(cli.commands, isNot(contains('status --json')));
    });

    test('a connect that comes up after dispose leaves the tailnet again',
        () async {
      final cli = _FakeCli(statusJson: _runningStatus());
      final controller = MeshController(processRunner: cli.call);
      final gate = Completer<ProcessResult?>();
      cli.statusGate = gate;

      final connecting = controller.connectWithAuthKey(
        'tskey-auth-test',
        username: 'cipher',
      );
      // Let `up` land so we are suspended inside _verifyUp's status call.
      await pumpEventQueue();
      expect(cli.commands, contains('status --json'));
      // The window closes now.
      controller.dispose();
      cli.statusGate = null;
      gate.complete(ProcessResult(0, 0, _runningStatus(), ''));

      expect(await connecting, isFalse);
      expect(controller.connected, isFalse);
      expect(controller.joiningRoom, isFalse);
      expect(controller.pollingActive, isFalse);
      // Nobody is left lingering in the lobby.
      expect(cli.commands, contains('down'));
    });
  });

  group('gate ban', () {
    test('noteGateBan is a terminal, disconnected state', () {
      final controller = MeshController(
        processRunner: _FakeCli(statusJson: _runningStatus()).call,
      );
      var notified = 0;
      controller.addListener(() => notified++);

      controller.noteGateBan('You are banned from the ATLAS Network.');

      expect(controller.errorKind, MeshErrorKind.banned);
      expect(controller.errorMessage, 'You are banned from the ATLAS Network.');
      expect(controller.connected, isFalse);
      expect(controller.connecting, isFalse);
      expect(notified, 1);

      controller.dispose();
    });
  });
}
