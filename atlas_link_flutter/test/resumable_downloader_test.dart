import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:atlas_link_flutter/resumable_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory testDirectory;
  HttpServer? server;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'atlas-resumable-download-',
    );
  });

  tearDown(() async {
    await server?.close(force: true);
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  ResumableDownloader downloader({int chunkSize = 8}) => ResumableDownloader(
    rangeChunkBytes: chunkSize,
    maxConsecutiveFailures: 3,
    connectionTimeout: const Duration(seconds: 2),
    idleTimeout: const Duration(seconds: 2),
    initialRetryDelay: Duration.zero,
    maximumRetryDelay: Duration.zero,
  );

  Future<Uri> listen(
    FutureOr<void> Function(HttpRequest request) handler,
  ) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      try {
        await handler(request);
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
    return Uri.parse('http://127.0.0.1:${server!.port}/payload.bin');
  }

  test('downloads and assembles bounded byte ranges', () async {
    final payload = List<int>.generate(37, (index) => (index * 17) & 0xff);
    final requestedRanges = <String>[];
    final uri = await listen((request) async {
      final header = request.headers.value(HttpHeaders.rangeHeader)!;
      requestedRanges.add(header);
      final range = _parseRange(header, payload.length);
      await _sendRange(request.response, payload, range.$1, range.$2);
    });
    final destination = File('${testDirectory.path}/bounded.bin');
    int? finalReceived;
    int? finalTotal;

    await downloader().download(
      uri,
      destination,
      onProgress: (received, total) {
        finalReceived = received;
        finalTotal = total;
      },
    );

    expect(await destination.readAsBytes(), orderedEquals(payload));
    expect(requestedRanges, <String>[
      'bytes=0-7',
      'bytes=8-15',
      'bytes=16-23',
      'bytes=24-31',
      'bytes=32-36',
    ]);
    expect(finalReceived, payload.length);
    expect(finalTotal, payload.length);
    expect(
      await ResumableDownloader.partFileFor(destination).exists(),
      isFalse,
    );
    expect(
      await ResumableDownloader.metadataFileFor(destination).exists(),
      isFalse,
    );
  });

  test(
    'resumes at the exact saved offset after a response disconnects',
    () async {
      final payload = List<int>.generate(73, (index) => (index * 29) & 0xff);
      final requestedStarts = <int>[];
      var disconnectFirstResponse = true;
      var retryCount = 0;
      const disconnectedPrefixLength = 5;
      final uri = await listen((request) async {
        final range = _parseRange(
          request.headers.value(HttpHeaders.rangeHeader)!,
          payload.length,
        );
        requestedStarts.add(range.$1);
        if (disconnectFirstResponse) {
          disconnectFirstResponse = false;
          final response = request.response;
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes ${range.$1}-${range.$2}/${payload.length}',
          );
          response.contentLength = range.$2 - range.$1 + 1;
          final socket = await response.detachSocket(writeHeaders: true);
          socket.add(
            payload.sublist(range.$1, range.$1 + disconnectedPrefixLength),
          );
          await socket.flush();
          await socket.close();
          return;
        }
        await _sendRange(request.response, payload, range.$1, range.$2);
      });
      final destination = File('${testDirectory.path}/disconnected.bin');

      await downloader(chunkSize: 24).download(
        uri,
        destination,
        keepPartialOnFailure: true,
        onRetry: (_, _, _) => retryCount++,
      );

      expect(await destination.readAsBytes(), orderedEquals(payload));
      expect(requestedStarts.first, 0);
      expect(requestedStarts[1], disconnectedPrefixLength);
      expect(retryCount, greaterThanOrEqualTo(1));
    },
  );

  test('truncates a partial when the origin ignores Range', () async {
    final payload = List<int>.generate(41, (index) => 255 - index);
    late Uri uri;
    String? requestedRange;
    var requests = 0;
    uri = await listen((request) async {
      requests++;
      requestedRange = request.headers.value(HttpHeaders.rangeHeader);
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
    });
    final destination = File('${testDirectory.path}/ignored-range.bin');
    final partFile = ResumableDownloader.partFileFor(destination);
    await partFile.writeAsBytes(payload.sublist(0, 7), flush: true);
    await ResumableDownloader.metadataFileFor(destination).writeAsString(
      jsonEncode({
        'url': uri.toString(),
        'totalBytes': payload.length,
        'lastModified': 'Sat, 01 Aug 2026 12:00:00 GMT',
      }),
      flush: true,
    );

    await downloader().download(uri, destination);

    expect(requestedRange, 'bytes=7-14');
    expect(requests, 1);
    expect(await destination.readAsBytes(), orderedEquals(payload));
  });

  test('keeps a failed partial and resumes it on a later invocation', () async {
    final payload = List<int>.generate(51, (index) => (index * 13) & 0xff);
    final requestedStarts = <int>[];
    var disconnected = false;
    var originRecovered = false;
    const savedPrefixLength = 6;
    final uri = await listen((request) async {
      final range = _parseRange(
        request.headers.value(HttpHeaders.rangeHeader)!,
        payload.length,
      );
      requestedStarts.add(range.$1);
      if (!originRecovered && !disconnected) {
        disconnected = true;
        final response = request.response;
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.$1}-${range.$2}/${payload.length}',
        );
        response.contentLength = range.$2 - range.$1 + 1;
        final socket = await response.detachSocket(writeHeaders: true);
        socket.add(payload.sublist(0, savedPrefixLength));
        await socket.flush();
        await socket.close();
        return;
      }
      if (!originRecovered) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      await _sendRange(request.response, payload, range.$1, range.$2);
    });
    final destination = File('${testDirectory.path}/resume-later.bin');

    await expectLater(
      downloader(
        chunkSize: 20,
      ).download(uri, destination, keepPartialOnFailure: true),
      throwsA(anything),
    );
    final partFile = ResumableDownloader.partFileFor(destination);
    expect(await partFile.length(), savedPrefixLength);
    expect(await ResumableDownloader.isResumablePart(partFile), isTrue);

    originRecovered = true;
    final requestsBeforeResume = requestedStarts.length;
    await downloader(
      chunkSize: 20,
    ).download(uri, destination, keepPartialOnFailure: true);

    expect(requestedStarts[requestsBeforeResume], savedPrefixLength);
    expect(await destination.readAsBytes(), orderedEquals(payload));
  });

  test(
    'cancellation deletes resume files and preserves the destination',
    () async {
      final payload = List<int>.generate(32, (index) => index);
      var cancelled = false;
      final uri = await listen((request) async {
        final range = _parseRange(
          request.headers.value(HttpHeaders.rangeHeader)!,
          payload.length,
        );
        final response = request.response;
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.$1}-${range.$2}/${payload.length}',
        );
        response.contentLength = range.$2 - range.$1 + 1;
        final socket = await response.detachSocket(writeHeaders: true);
        socket.add(payload.sublist(range.$1, range.$1 + 4));
        await socket.flush();
        cancelled = true;
        try {
          socket.add(payload.sublist(range.$1 + 4, range.$2 + 1));
          await socket.flush();
          await socket.close();
        } catch (_) {}
      });
      final destination = File('${testDirectory.path}/cancelled.bin');
      await destination.writeAsBytes(<int>[99, 98, 97], flush: true);

      await expectLater(
        downloader(chunkSize: payload.length).download(
          uri,
          destination,
          keepPartialOnFailure: true,
          isCancelled: () => cancelled,
        ),
        throwsA(isA<ResumableDownloadCancelled>()),
      );

      expect(await destination.readAsBytes(), <int>[99, 98, 97]);
      expect(
        await ResumableDownloader.partFileFor(destination).exists(),
        isFalse,
      );
      expect(
        await ResumableDownloader.metadataFileFor(destination).exists(),
        isFalse,
      );
    },
  );

  test('promotes a complete partial after a 416 size confirmation', () async {
    final payload = List<int>.generate(19, (index) => index + 1);
    late Uri uri;
    uri = await listen((request) async {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */${payload.length}',
      );
      await request.response.close();
    });
    final destination = File('${testDirectory.path}/already-complete.bin');
    await ResumableDownloader.partFileFor(
      destination,
    ).writeAsBytes(payload, flush: true);
    await ResumableDownloader.metadataFileFor(
      destination,
    ).writeAsString(jsonEncode({'url': uri.toString()}), flush: true);

    await downloader().download(uri, destination);

    expect(await destination.readAsBytes(), orderedEquals(payload));
    expect(
      await ResumableDownloader.partFileFor(destination).exists(),
      isFalse,
    );
  });
}

(int, int) _parseRange(String header, int totalLength) {
  final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(header);
  if (match == null) throw FormatException('Unexpected Range: $header');
  final start = int.parse(match.group(1)!);
  final requestedEnd = int.parse(match.group(2)!);
  return (start, math.min(requestedEnd, totalLength - 1));
}

Future<void> _sendRange(
  HttpResponse response,
  List<int> payload,
  int start,
  int end,
) async {
  response.statusCode = HttpStatus.partialContent;
  response.headers.set(
    HttpHeaders.contentRangeHeader,
    'bytes $start-$end/${payload.length}',
  );
  response.headers.set(HttpHeaders.etagHeader, '"atlas-test-payload"');
  response.contentLength = end - start + 1;
  response.add(payload.sublist(start, end + 1));
  await response.close();
}
