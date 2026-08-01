import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

typedef DownloadProgressCallback =
    void Function(int receivedBytes, int? totalBytes);
typedef DownloadRetryCallback =
    void Function(int attempt, Duration delay, Object error);

/// Thrown when [ResumableDownloader.download] observes a cancellation request.
class ResumableDownloadCancelled implements Exception {
  const ResumableDownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}

/// Downloads HTTP files in bounded byte ranges and resumes interrupted ranges.
///
/// A validated `<destination>.part` plus metadata sidecar is retained when
/// [keepPartialOnFailure] is true. The destination itself is only replaced once
/// the complete response has been written.
class ResumableDownloader {
  const ResumableDownloader({
    this.rangeChunkBytes = 16 * 1024 * 1024,
    this.maxConsecutiveFailures = 8,
    this.connectionTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 60),
    this.initialRetryDelay = const Duration(milliseconds: 500),
    this.maximumRetryDelay = const Duration(seconds: 12),
  }) : assert(rangeChunkBytes > 0),
       assert(maxConsecutiveFailures > 0);

  final int rangeChunkBytes;
  final int maxConsecutiveFailures;
  final Duration connectionTimeout;
  final Duration idleTimeout;
  final Duration initialRetryDelay;
  final Duration maximumRetryDelay;

  static File partFileFor(File destination) => File('${destination.path}.part');

  static File metadataFileForPart(File partFile) =>
      File('${partFile.path}.meta');

  static File metadataFileFor(File destination) =>
      metadataFileForPart(partFileFor(destination));

  /// Returns true only for a partial file with parseable, matching metadata.
  static Future<bool> isResumablePart(File partFile) async {
    if (!await partFile.exists()) return false;
    final metadata = await _ResumeMetadata.read(metadataFileForPart(partFile));
    if (metadata == null || metadata.url.isEmpty) return false;
    final length = await partFile.length();
    return metadata.totalBytes == null || length <= metadata.totalBytes!;
  }

  static Future<void> discardPartial(File destination) =>
      _deleteResumeFiles(partFileFor(destination));

  Future<void> download(
    Uri uri,
    File destination, {
    DownloadProgressCallback? onProgress,
    DownloadRetryCallback? onRetry,
    bool Function()? isCancelled,
    bool rejectHtmlResponse = false,
    bool keepPartialOnFailure = false,
  }) async {
    await destination.parent.create(recursive: true);
    final partFile = partFileFor(destination);
    final metadataFile = metadataFileForPart(partFile);
    var metadata = await _ResumeMetadata.read(metadataFile);

    if (!await partFile.exists()) {
      await _deleteFile(metadataFile);
      metadata = null;
    } else if (metadata == null || metadata.url != uri.toString()) {
      await _deleteResumeFiles(partFile);
      metadata = null;
    } else {
      final partialLength = await partFile.length();
      if (metadata.totalBytes != null && partialLength > metadata.totalBytes!) {
        await _deleteResumeFiles(partFile);
        metadata = null;
      }
    }

    var consecutiveFailures = 0;
    var consecutiveRestarts = 0;
    try {
      while (true) {
        _throwIfCancelled(isCancelled);
        final offset = await partFile.exists() ? await partFile.length() : 0;
        final knownTotal = metadata?.totalBytes;
        if (knownTotal != null && offset == knownTotal) {
          await _promotePartial(partFile, metadataFile, destination);
          onProgress?.call(knownTotal, knownTotal);
          return;
        }
        if (knownTotal != null && offset > knownTotal) {
          await _deleteResumeFiles(partFile);
          metadata = null;
          consecutiveFailures = 0;
          continue;
        }

        try {
          final result = await _downloadNextRange(
            uri,
            partFile,
            metadata,
            onProgress: onProgress,
            isCancelled: isCancelled,
            rejectHtmlResponse: rejectHtmlResponse,
          );
          metadata = result.metadata;
          consecutiveRestarts = 0;
          if (result.complete) {
            await _promotePartial(partFile, metadataFile, destination);
            final completedLength = await destination.length();
            onProgress?.call(
              completedLength,
              metadata?.totalBytes ?? completedLength,
            );
            return;
          }
          consecutiveFailures = 0;
        } on _RestartDownload {
          await _deleteResumeFiles(partFile);
          metadata = null;
          consecutiveFailures = 0;
          consecutiveRestarts++;
          if (consecutiveRestarts >= 2) {
            throw FormatException(
              'The server repeatedly returned an invalid byte range for $uri.',
            );
          }
        } on ResumableDownloadCancelled {
          rethrow;
        } catch (error) {
          final currentLength = await partFile.exists()
              ? await partFile.length()
              : 0;
          final madeProgress = currentLength > offset;
          if (!_isRetryable(error)) {
            await _deleteResumeFiles(partFile);
            rethrow;
          }

          consecutiveFailures = madeProgress ? 0 : consecutiveFailures + 1;
          if (consecutiveFailures >= maxConsecutiveFailures) rethrow;

          final retryOrdinal = math.max(1, consecutiveFailures);
          final delay = _retryDelay(retryOrdinal);
          onRetry?.call(retryOrdinal, delay, error);
          await _cancellableDelay(delay, isCancelled);
          metadata = await _ResumeMetadata.read(metadataFile);
        }
      }
    } on ResumableDownloadCancelled {
      await _deleteResumeFiles(partFile);
      rethrow;
    } catch (_) {
      if (!keepPartialOnFailure) await _deleteResumeFiles(partFile);
      rethrow;
    }
  }

  Future<_RangeResult> _downloadNextRange(
    Uri uri,
    File partFile,
    _ResumeMetadata? metadata, {
    DownloadProgressCallback? onProgress,
    bool Function()? isCancelled,
    required bool rejectHtmlResponse,
  }) async {
    final offset = await partFile.exists() ? await partFile.length() : 0;
    final knownTotal = metadata?.totalBytes;
    final requestedEnd = knownTotal == null
        ? offset + rangeChunkBytes - 1
        : math.min(knownTotal - 1, offset + rangeChunkBytes - 1);

    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = connectionTimeout
      ..userAgent = 'ATLAS-Link';
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.persistentConnection = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=$offset-$requestedEnd',
      );
      final validator = metadata?.ifRangeValidator;
      if (offset > 0 && validator != null) {
        request.headers.set(HttpHeaders.ifRangeHeader, validator);
      }

      final response = await request.close();
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        final remoteTotal = _parseUnsatisfiedTotal(
          response.headers.value(HttpHeaders.contentRangeHeader),
        );
        if (remoteTotal != null && remoteTotal == offset) {
          final nextMetadata =
              (metadata ?? _ResumeMetadata(url: uri.toString())).copyWith(
                totalBytes: remoteTotal,
              );
          await nextMetadata.write(metadataFileForPart(partFile));
          return _RangeResult(metadata: nextMetadata, complete: true);
        }
        throw const _RestartDownload();
      }

      if (response.statusCode == HttpStatus.ok) {
        _rejectHtmlIfNeeded(response, rejectHtmlResponse, uri);
        // The origin ignored Range, or If-Range rejected a stale validator.
        // Start over and treat this as the complete response body.
        final total = response.contentLength > 0
            ? response.contentLength
            : null;
        final nextMetadata = _ResumeMetadata(
          url: uri.toString(),
          totalBytes: total,
          etag: _strongEtag(response),
          lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
        );
        await nextMetadata.write(metadataFileForPart(partFile));
        final received = await _writeResponse(
          response,
          partFile,
          append: false,
          baseOffset: 0,
          totalBytes: total,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        if (total != null && received != total) {
          throw HttpException(
            'Connection closed before the full response was received '
            '($received of $total bytes).',
            uri: uri,
          );
        }
        return _RangeResult(metadata: nextMetadata, complete: true);
      }

      if (response.statusCode != HttpStatus.partialContent) {
        throw _DownloadHttpException(
          response.statusCode,
          uri,
          retryable: _retryableStatusCodes.contains(response.statusCode),
        );
      }

      _rejectHtmlIfNeeded(response, rejectHtmlResponse, uri);
      final range = _ContentRange.parse(
        response.headers.value(HttpHeaders.contentRangeHeader),
      );
      if (range == null || range.start != offset) {
        throw const _RestartDownload();
      }
      if (metadata?.totalBytes != null &&
          range.total != null &&
          metadata!.totalBytes != range.total) {
        throw const _RestartDownload();
      }

      final nextMetadata = _ResumeMetadata(
        url: uri.toString(),
        totalBytes: range.total ?? metadata?.totalBytes,
        etag: _strongEtag(response) ?? metadata?.etag,
        lastModified:
            response.headers.value(HttpHeaders.lastModifiedHeader) ??
            metadata?.lastModified,
      );
      await nextMetadata.write(metadataFileForPart(partFile));
      onProgress?.call(offset, nextMetadata.totalBytes);
      final received = await _writeResponse(
        response,
        partFile,
        append: offset > 0,
        baseOffset: offset,
        totalBytes: nextMetadata.totalBytes,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      final expected = range.end - range.start + 1;
      if (received != expected) {
        throw HttpException(
          'Connection closed before the requested range was received '
          '($received of $expected bytes).',
          uri: uri,
        );
      }

      final currentLength = await partFile.length();
      if (range.total != null && currentLength > range.total!) {
        throw const _RestartDownload();
      }
      return _RangeResult(
        metadata: nextMetadata,
        complete: range.total != null && currentLength == range.total,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _writeResponse(
    HttpClientResponse response,
    File partFile, {
    required bool append,
    required int baseOffset,
    required int? totalBytes,
    DownloadProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sink = partFile.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    var received = 0;
    try {
      await for (final chunk in response.timeout(idleTimeout)) {
        _throwIfCancelled(isCancelled);
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(baseOffset + received, totalBytes);
      }
      await sink.flush();
      return received;
    } finally {
      await sink.close();
    }
  }

  static void _rejectHtmlIfNeeded(
    HttpClientResponse response,
    bool rejectHtmlResponse,
    Uri uri,
  ) {
    if (!rejectHtmlResponse) return;
    final mime = response.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (mime == 'text/html' || mime == 'application/xhtml+xml') {
      throw FormatException(
        'Download did not return a file (got an HTML page). Use a direct '
        'download link: $uri',
      );
    }
  }

  static String? _strongEtag(HttpClientResponse response) {
    final value = response.headers.value(HttpHeaders.etagHeader)?.trim();
    if (value == null || value.isEmpty || value.startsWith('W/')) return null;
    return value;
  }

  Duration _retryDelay(int failureCount) {
    if (initialRetryDelay == Duration.zero) return Duration.zero;
    final exponent = math.min(5, math.max(0, failureCount - 1));
    final milliseconds = initialRetryDelay.inMilliseconds * (1 << exponent);
    return Duration(
      milliseconds: math.min(milliseconds, maximumRetryDelay.inMilliseconds),
    );
  }

  static bool _isRetryable(Object error) {
    if (error is _DownloadHttpException) return error.retryable;
    if (error is FileSystemException || error is FormatException) return false;
    if (error is ResumableDownloadCancelled || error is _RestartDownload) {
      return false;
    }
    return error is IOException || error is TimeoutException;
  }

  static Future<void> _cancellableDelay(
    Duration duration,
    bool Function()? isCancelled,
  ) async {
    var remaining = duration;
    while (remaining > Duration.zero) {
      _throwIfCancelled(isCancelled);
      final slice = remaining > const Duration(milliseconds: 250)
          ? const Duration(milliseconds: 250)
          : remaining;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
    _throwIfCancelled(isCancelled);
  }

  static void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const ResumableDownloadCancelled();
    }
  }

  static Future<void> _promotePartial(
    File partFile,
    File metadataFile,
    File destination,
  ) async {
    if (await destination.exists()) await destination.delete();
    await partFile.rename(destination.path);
    await _deleteFile(metadataFile);
  }

  static Future<void> _deleteResumeFiles(File partFile) async {
    await _deleteFile(partFile);
    await _deleteFile(metadataFileForPart(partFile));
  }

  static Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static int? _parseUnsatisfiedTotal(String? value) {
    final match = RegExp(
      r'^bytes\s+\*/(\d+)$',
      caseSensitive: false,
    ).firstMatch(value?.trim() ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

class _RangeResult {
  const _RangeResult({required this.metadata, required this.complete});

  final _ResumeMetadata? metadata;
  final bool complete;
}

class _ContentRange {
  const _ContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int? total;

  static _ContentRange? parse(String? value) {
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$',
      caseSensitive: false,
    ).firstMatch(value?.trim() ?? '');
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final totalText = match.group(3)!;
    final total = totalText == '*' ? null : int.tryParse(totalText);
    if (start == null || end == null || end < start) return null;
    if (total != null && end >= total) return null;
    return _ContentRange(start: start, end: end, total: total);
  }
}

class _ResumeMetadata {
  const _ResumeMetadata({
    required this.url,
    this.totalBytes,
    this.etag,
    this.lastModified,
  });

  final String url;
  final int? totalBytes;
  final String? etag;
  final String? lastModified;

  String? get ifRangeValidator {
    final strongEtag = etag?.trim();
    if (strongEtag != null &&
        strongEtag.isNotEmpty &&
        !strongEtag.startsWith('W/')) {
      return strongEtag;
    }
    final modified = lastModified?.trim();
    return modified == null || modified.isEmpty ? null : modified;
  }

  _ResumeMetadata copyWith({int? totalBytes}) => _ResumeMetadata(
    url: url,
    totalBytes: totalBytes ?? this.totalBytes,
    etag: etag,
    lastModified: lastModified,
  );

  Future<void> write(File file) async {
    await file.writeAsString(
      jsonEncode({
        'url': url,
        if (totalBytes != null) 'totalBytes': totalBytes,
        if (etag != null && etag!.isNotEmpty) 'etag': etag,
        if (lastModified != null && lastModified!.isNotEmpty)
          'lastModified': lastModified,
      }),
      flush: true,
    );
  }

  static Future<_ResumeMetadata?> read(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final url = (map['url'] ?? '').toString().trim();
      if (url.isEmpty) return null;
      final totalRaw = map['totalBytes'];
      final total = totalRaw is num ? totalRaw.toInt() : null;
      if (total != null && total < 0) return null;
      return _ResumeMetadata(
        url: url,
        totalBytes: total,
        etag: map['etag']?.toString(),
        lastModified: map['lastModified']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class _DownloadHttpException implements Exception {
  const _DownloadHttpException(
    this.statusCode,
    this.uri, {
    required this.retryable,
  });

  final int statusCode;
  final Uri uri;
  final bool retryable;

  @override
  String toString() => 'Download failed (HTTP $statusCode): $uri';
}

class _RestartDownload implements Exception {
  const _RestartDownload();
}

const Set<int> _retryableStatusCodes = <int>{
  HttpStatus.requestTimeout,
  425, // Too Early
  HttpStatus.tooManyRequests,
  HttpStatus.internalServerError,
  HttpStatus.badGateway,
  HttpStatus.serviceUnavailable,
  HttpStatus.gatewayTimeout,
};
