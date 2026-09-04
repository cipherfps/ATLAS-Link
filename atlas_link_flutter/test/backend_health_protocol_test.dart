import 'package:atlas_link_flutter/backend_health_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackendHealthProtocol.actionFor', () {
    test('marks the first automatic transition from offline as connect', () {
      expect(
        BackendHealthProtocol.actionFor(
          wasOnline: false,
          explicitConnectionCheck: false,
        ),
        BackendHealthAction.connect,
      );
    });

    test('marks routine online requests as silent polls', () {
      expect(
        BackendHealthProtocol.actionFor(
          wasOnline: true,
          explicitConnectionCheck: false,
        ),
        BackendHealthAction.poll,
      );
    });

    test('manual checks take precedence over current connection state', () {
      for (final wasOnline in <bool>[false, true]) {
        expect(
          BackendHealthProtocol.actionFor(
            wasOnline: wasOnline,
            explicitConnectionCheck: true,
          ),
          BackendHealthAction.connectionCheck,
          reason: 'wasOnline=$wasOnline',
        );
      }
    });
  });

  group('BackendHealthProtocol.headersFor', () {
    test('routine polls identify the launcher and their silent intent', () {
      final headers = BackendHealthProtocol.headersFor(
        launcherName: 'ATLAS Link',
        launcherVersion: '2.0.5',
        sessionId: 'session-1',
        action: BackendHealthAction.poll,
      );

      expect(headers[BackendHealthProtocol.nameHeader], 'ATLAS Link');
      expect(headers[BackendHealthProtocol.versionHeader], '2.0.5');
      expect(headers[BackendHealthProtocol.sessionHeader], 'session-1');
      expect(headers[BackendHealthProtocol.actionHeader], 'poll');
      expect(headers, isNot(contains(BackendHealthProtocol.requestIdHeader)));
    });

    test('connect and manual check use their canonical wire values', () {
      final connectHeaders = BackendHealthProtocol.headersFor(
        launcherName: 'Launcher A',
        launcherVersion: '1.0.0',
        sessionId: 'session-a',
        action: BackendHealthAction.connect,
      );
      final checkHeaders = BackendHealthProtocol.headersFor(
        launcherName: 'Launcher B',
        launcherVersion: '2.0.0',
        sessionId: 'session-b',
        action: BackendHealthAction.connectionCheck,
        requestId: 'request-b',
      );

      expect(connectHeaders[BackendHealthProtocol.actionHeader], 'connect');
      expect(
        connectHeaders,
        isNot(contains(BackendHealthProtocol.requestIdHeader)),
      );
      expect(
        checkHeaders[BackendHealthProtocol.actionHeader],
        'connection-check',
      );
      expect(checkHeaders[BackendHealthProtocol.requestIdHeader], 'request-b');
    });

    test('manual checks require a request ID', () {
      expect(
        () => BackendHealthProtocol.headersFor(
          launcherName: 'ATLAS Link',
          launcherVersion: '2.0.5',
          sessionId: 'session-1',
          action: BackendHealthAction.connectionCheck,
        ),
        throwsArgumentError,
      );
    });

    test('generated identifiers are non-empty and unique per call', () {
      final first = BackendHealthProtocol.createIdentifier();
      final second = BackendHealthProtocol.createIdentifier();

      expect(first, isNotEmpty);
      expect(second, isNotEmpty);
      expect(second, isNot(first));
    });
  });
}
