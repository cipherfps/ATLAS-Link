import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class LauncherDiscordActivity {
  const LauncherDiscordActivity({
    required this.details,
    required this.state,
    required this.startTimestampSeconds,
    this.largeImageKey,
    this.largeImageText,
    this.smallImageKey,
    this.smallImageText,
    this.buttons = const <LauncherDiscordButton>[],
  });

  final String details;
  final String state;
  final int startTimestampSeconds;
  final String? largeImageKey;
  final String? largeImageText;
  final String? smallImageKey;
  final String? smallImageText;
  final List<LauncherDiscordButton> buttons;

  String get signature => '$details|$state';

  Map<String, dynamic> toJson() {
    final activity = <String, dynamic>{
      'details': details,
      'timestamps': <String, dynamic>{'start': startTimestampSeconds},
    };
    if (_hasText(state)) {
      activity['state'] = state;
    }

    final assets = <String, String>{};
    if (_hasText(largeImageKey)) {
      assets['large_image'] = largeImageKey!.trim();
    }
    if (_hasText(largeImageText)) {
      assets['large_text'] = largeImageText!.trim();
    }
    if (_hasText(smallImageKey)) {
      assets['small_image'] = smallImageKey!.trim();
    }
    if (_hasText(smallImageText)) {
      assets['small_text'] = smallImageText!.trim();
    }
    if (assets.isNotEmpty) {
      activity['assets'] = assets;
    }

    final resolvedButtons = buttons
        .where((button) => _hasText(button.label) && _hasText(button.url))
        .take(2)
        .map((button) => button.toJson())
        .toList(growable: false);
    if (resolvedButtons.isNotEmpty) {
      activity['buttons'] = resolvedButtons;
    }

    return activity;
  }
}

class LauncherDiscordButton {
  const LauncherDiscordButton({required this.label, required this.url});

  final String label;
  final String url;

  Map<String, String> toJson() {
    return <String, String>{'label': label.trim(), 'url': url.trim()};
  }
}

class LauncherDiscordRpcClient {
  LauncherDiscordRpcClient({
    required this.applicationId,
    int? sessionStartTimestampSeconds,
  }) : sessionStartTimestampSeconds =
           sessionStartTimestampSeconds ??
           DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final String applicationId;
  final int sessionStartTimestampSeconds;

  int _pipeHandle = INVALID_HANDLE_VALUE;
  String _connectedApplicationId = '';
  int _nonceCounter = 0;

  bool setActivity(LauncherDiscordActivity activity) {
    if (!Platform.isWindows || !_hasText(applicationId)) return false;
    if (!_ensureConnected()) return false;

    final payload = jsonEncode(<String, dynamic>{
      'cmd': 'SET_ACTIVITY',
      'args': <String, dynamic>{'pid': pid, 'activity': activity.toJson()},
      'nonce': _nextNonce(),
    });

    if (!_writeFrame(1, payload)) {
      _close();
      return false;
    }
    _drainIncomingMessages();
    return true;
  }

  bool clearActivity() {
    if (!Platform.isWindows || !_hasText(applicationId)) return false;
    if (!_ensureConnected()) return false;

    final payload = jsonEncode(<String, dynamic>{
      'cmd': 'SET_ACTIVITY',
      'args': <String, dynamic>{'pid': pid, 'activity': null},
      'nonce': _nextNonce(),
    });

    if (!_writeFrame(1, payload)) {
      _close();
      return false;
    }
    _drainIncomingMessages();
    return true;
  }

  void dispose() {
    _close();
  }

  bool _ensureConnected() {
    if (_pipeHandle != INVALID_HANDLE_VALUE &&
        _connectedApplicationId == applicationId) {
      return true;
    }

    _close();
    if (!_connect()) return false;

    _connectedApplicationId = applicationId;
    if (_sendHandshake()) return true;

    _close();
    return false;
  }

  bool _connect() {
    for (var index = 0; index <= 9; index++) {
      final path = '\\\\.\\pipe\\discord-ipc-$index'.toNativeUtf16();
      try {
        final handle = CreateFile(
          path,
          GENERIC_READ | GENERIC_WRITE,
          0,
          ffi.nullptr,
          OPEN_EXISTING,
          0,
          NULL,
        );
        if (handle != INVALID_HANDLE_VALUE) {
          _pipeHandle = handle;
          return true;
        }
      } finally {
        calloc.free(path);
      }
    }

    return false;
  }

  bool _sendHandshake() {
    final payload = jsonEncode(<String, dynamic>{
      'v': 1,
      'client_id': applicationId,
    });
    if (!_writeFrame(0, payload)) return false;
    _drainIncomingMessages();
    return true;
  }

  bool _writeFrame(int opcode, String payload) {
    if (_pipeHandle == INVALID_HANDLE_VALUE) return false;

    final payloadBytes = Uint8List.fromList(utf8.encode(payload));
    final header = ByteData(8)
      ..setInt32(0, opcode, Endian.little)
      ..setInt32(4, payloadBytes.length, Endian.little);

    if (!_writeAll(header.buffer.asUint8List())) return false;
    if (payloadBytes.isEmpty) return true;
    return _writeAll(payloadBytes);
  }

  bool _writeAll(Uint8List bytes) {
    if (_pipeHandle == INVALID_HANDLE_VALUE) return false;
    if (bytes.isEmpty) return true;

    final buffer = calloc<ffi.Uint8>(bytes.length);
    final bytesWritten = calloc<ffi.Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final ok = WriteFile(
        _pipeHandle,
        buffer,
        bytes.length,
        bytesWritten,
        ffi.nullptr.cast(),
      );
      return ok != 0 && bytesWritten.value == bytes.length;
    } finally {
      calloc.free(bytesWritten);
      calloc.free(buffer);
    }
  }

  void _drainIncomingMessages() {
    if (_pipeHandle == INVALID_HANDLE_VALUE) return;

    final available = calloc<ffi.Uint32>();
    final read = calloc<ffi.Uint32>();
    final buffer = calloc<ffi.Uint8>(4096);
    try {
      while (PeekNamedPipe(
                _pipeHandle,
                ffi.nullptr,
                0,
                ffi.nullptr.cast(),
                available,
                ffi.nullptr.cast(),
              ) !=
              0 &&
          available.value > 0) {
        final chunk = available.value > 4096 ? 4096 : available.value;
        final ok = ReadFile(
          _pipeHandle,
          buffer,
          chunk,
          read,
          ffi.nullptr.cast(),
        );
        if (ok == 0 || read.value == 0) {
          break;
        }
      }
    } finally {
      calloc.free(buffer);
      calloc.free(read);
      calloc.free(available);
    }
  }

  void _close() {
    if (_pipeHandle != INVALID_HANDLE_VALUE) {
      CloseHandle(_pipeHandle);
      _pipeHandle = INVALID_HANDLE_VALUE;
    }
    _connectedApplicationId = '';
  }

  String _nextNonce() {
    _nonceCounter += 1;
    return 'atlas-launcher-$_nonceCounter';
  }
}

bool _hasText(String? value) {
  return value != null && value.trim().isNotEmpty;
}
