import 'dart:io';
import 'dart:math';

enum BackendHealthAction { connect, connectionCheck, poll }

/// Launcher-neutral metadata attached to ATLAS backend health requests.
///
/// Identity headers accompany every final health request. Routine polls are
/// explicitly marked as such so a backend never mistakes them for legacy
/// first-contact traffic.
class BackendHealthProtocol {
  static const String actionHeader = 'X-Launcher-Action';
  static const String nameHeader = 'X-Launcher-Name';
  static const String versionHeader = 'X-Launcher-Version';
  static const String sessionHeader = 'X-Launcher-Session';
  static const String requestIdHeader = 'X-Launcher-Request-Id';

  static BackendHealthAction actionFor({
    required bool wasOnline,
    required bool explicitConnectionCheck,
  }) {
    if (explicitConnectionCheck) {
      return BackendHealthAction.connectionCheck;
    }
    return wasOnline ? BackendHealthAction.poll : BackendHealthAction.connect;
  }

  static Map<String, String> headersFor({
    required String launcherName,
    required String launcherVersion,
    required String sessionId,
    required BackendHealthAction action,
    String? requestId,
  }) {
    final headers = <String, String>{
      nameHeader: launcherName,
      versionHeader: launcherVersion,
      sessionHeader: sessionId,
    };

    switch (action) {
      case BackendHealthAction.connect:
        headers[actionHeader] = 'connect';
        break;
      case BackendHealthAction.connectionCheck:
        final normalizedRequestId = requestId?.trim() ?? '';
        if (normalizedRequestId.isEmpty) {
          throw ArgumentError.value(
            requestId,
            'requestId',
            'A connection check requires a request ID.',
          );
        }
        headers[actionHeader] = 'connection-check';
        headers[requestIdHeader] = normalizedRequestId;
        break;
      case BackendHealthAction.poll:
        headers[actionHeader] = 'poll';
        break;
    }

    return headers;
  }

  static String createIdentifier() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random.secure().nextInt(0x7fffffff).toRadixString(36);
    return '${pid.toRadixString(36)}-$timestamp-$entropy';
  }
}
