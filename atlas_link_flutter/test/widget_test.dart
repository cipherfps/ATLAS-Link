import 'package:atlas_link_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ATLAS shell boot screen renders', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const AtlasLauncherApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LauncherScreen), findsOneWidget);
  });
}
