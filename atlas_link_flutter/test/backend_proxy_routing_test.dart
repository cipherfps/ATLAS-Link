import 'package:atlas_link_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackendProxyRouting.proxyRequired', () {
    test('uses local default backend directly', () {
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.local,
          host: '127.0.0.1',
          port: 3551,
        ),
        isFalse,
      );
    });

    test('proxies local custom ports through the default redirect port', () {
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.local,
          host: '127.0.0.1',
          port: 5595,
        ),
        isTrue,
      );
    });

    test('proxies embedded custom ports through the default redirect port', () {
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.embedded,
          host: '127.0.0.1',
          port: 5595,
        ),
        isTrue,
      );
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.embedded,
          host: '127.0.0.1',
          port: 3551,
        ),
        isFalse,
      );
    });

    test('proxies remote external hosts on default and custom ports', () {
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.remote,
          host: '10.0.0.25',
          port: 3551,
        ),
        isTrue,
      );
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.remote,
          host: '10.0.0.25',
          port: 5595,
        ),
        isTrue,
      );
    });

    test('proxies remote loopback custom ports', () {
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.remote,
          host: 'localhost',
          port: 5595,
        ),
        isTrue,
      );
      expect(
        BackendProxyRouting.proxyRequired(
          connectionType: BackendConnectionType.remote,
          host: 'http://127.0.0.1',
          port: 5595,
        ),
        isTrue,
      );
    });

    test('does not self-proxy remote loopback on the default port', () {
      for (final host in <String>[
        'localhost',
        '127.0.0.1',
        '127.10.20.30',
        'http://localhost',
        '[::1]',
      ]) {
        expect(
          BackendProxyRouting.proxyRequired(
            connectionType: BackendConnectionType.remote,
            host: host,
            port: 3551,
          ),
          isFalse,
          reason: host,
        );
      }
    });
  });

  group('BackendProxyRouting.isLocalHost', () {
    test('recognizes loopback aliases', () {
      expect(BackendProxyRouting.isLocalHost('localhost'), isTrue);
      expect(BackendProxyRouting.isLocalHost('http://localhost'), isTrue);
      expect(BackendProxyRouting.isLocalHost('127.0.0.1'), isTrue);
      expect(BackendProxyRouting.isLocalHost('127.0.0.1:3551'), isTrue);
      expect(BackendProxyRouting.isLocalHost('0.0.0.0'), isTrue);
      expect(BackendProxyRouting.isLocalHost('[::1]'), isTrue);
      expect(BackendProxyRouting.isLocalHost('10.0.0.25'), isFalse);
    });
  });
}
