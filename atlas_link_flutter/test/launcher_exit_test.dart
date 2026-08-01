import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:atlas_link_flutter/main.dart';
import 'package:atlas_link_flutter/mesh_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExitTestCli {
  final List<List<String>> calls = <List<String>>[];

  int countOf(String command) =>
      calls.where((args) => args.join(' ') == command).length;

  Future<ProcessResult?> call(List<String> args, Duration? timeout) async {
    calls.add(args);
    if (args.isNotEmpty && args.first == 'status') {
      return ProcessResult(0, 0, _runningStatus(), '');
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
  'Peer': <String, dynamic>{},
});

Future<(MeshController, _ExitTestCli)> _connectedController() async {
  final cli = _ExitTestCli();
  final controller = MeshController(processRunner: cli.call);
  final connected = await controller.connectWithAuthKey(
    'tskey-auth-test',
    username: 'cipher',
  );
  expect(connected, isTrue);
  return (controller, cli);
}

Future<void> _pumpLauncher(
  WidgetTester tester,
  MeshController controller,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(home: LauncherScreen(meshController: controller)),
  );
  await tester.pump();
}

Future<void> _disposeLauncher(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  const title = 'Are you sure you want to close the launcher?';
  const description =
      'You are currently connected to the ATLAS Network. Closing the launcher '
      'will remove your connection. Do you want to continue?';

  testWidgets(
    'connected close request can be cancelled without disconnecting',
    (tester) async {
      final (controller, cli) = await _connectedController();
      await _pumpLauncher(tester, controller);

      final responseFuture = tester.binding.handleRequestAppExit();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      expect(find.text(title), findsOneWidget);
      expect(find.text(description), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Close and Disconnect'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Cancel')).dx,
        lessThan(tester.getCenter(find.text('Close and Disconnect')).dx),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(await responseFuture, AppExitResponse.cancel);
      expect(controller.connected, isTrue);
      expect(cli.countOf('down'), 0);

      await _disposeLauncher(tester);
    },
  );

  testWidgets('confirmed repeated close requests disconnect exactly once', (
    tester,
  ) async {
    final (controller, cli) = await _connectedController();
    await _pumpLauncher(tester, controller);

    final firstResponse = tester.binding.handleRequestAppExit();
    final secondResponse = tester.binding.handleRequestAppExit();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text(title), findsOneWidget);
    await tester.tap(find.text('Close and Disconnect'));
    await tester.pump();

    expect(await firstResponse, AppExitResponse.exit);
    expect(await secondResponse, AppExitResponse.exit);
    expect(controller.connected, isFalse);
    expect(cli.countOf('down'), 1);

    await _disposeLauncher(tester);
  });

  testWidgets('disconnected close request exits without prompting', (
    tester,
  ) async {
    final cli = _ExitTestCli();
    final controller = MeshController(processRunner: cli.call);
    await _pumpLauncher(tester, controller);

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(find.text(title), findsNothing);
    expect(cli.countOf('down'), 0);

    await _disposeLauncher(tester);
  });
}
