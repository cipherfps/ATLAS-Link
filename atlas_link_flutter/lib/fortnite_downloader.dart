// Native Fortnite build downloader — no Epic account required.
//
// Fortnite build chunks are served openly from Epic's CDN (legendary's own
// workers fetch them with no Authorization header). The only thing legendary
// needed a login for was resolving which manifest to use, which we already
// override with the fn-releases manifest. So this reimplements the download
// directly: parse the UE binary manifest, compute each chunk's public URL,
// download in parallel, zlib-inflate, and reassemble the files — entirely in a
// background isolate. Format ported from legendary 0.20.34
// (legendary/models/manifest.py + chunk.py).

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

const int _kManifestHeaderMagic = 0x44BEC00C;
const int _kChunkHeaderMagic = 0xB1FE3AA2;

/// Formats a 64-bit value as 16 uppercase hex chars, treating it as unsigned
/// (Dart ints are signed, so a high-bit-set uint64 would otherwise print a
/// leading '-').
String _u64Hex16(int value) {
  final hi = (value >> 32) & 0xFFFFFFFF;
  final lo = value & 0xFFFFFFFF;
  return hi.toRadixString(16).toUpperCase().padLeft(8, '0') +
      lo.toRadixString(16).toUpperCase().padLeft(8, '0');
}

/// Sequential little-endian reader over an in-memory buffer.
class _ByteReader {
  _ByteReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  int get position => _pos;
  void seek(int absolute) => _pos = absolute;
  void skip(int count) => _pos += count;

  int readUint8() => _bytes[_pos++];

  int readUint32() {
    final value = _data.getUint32(_pos, Endian.little);
    _pos += 4;
    return value;
  }

  int readInt32() {
    final value = _data.getInt32(_pos, Endian.little);
    _pos += 4;
    return value;
  }

  int readUint64() {
    final value = _data.getUint64(_pos, Endian.little);
    _pos += 8;
    return value;
  }

  int readInt64() {
    final value = _data.getInt64(_pos, Endian.little);
    _pos += 8;
    return value;
  }

  Uint8List readBytes(int count) {
    final view = Uint8List.sublistView(_bytes, _pos, _pos + count);
    _pos += count;
    return view;
  }

  /// UE "FString": int32 length prefix; negative length = UTF-16LE, positive =
  /// ASCII, both null-terminated (terminator included in the count).
  String readFString() {
    final length = readInt32();
    if (length < 0) {
      final byteLength = (-length) * 2;
      final chars = readBytes(byteLength - 2);
      skip(2); // UTF-16 null terminator
      final units = Uint16List(chars.length ~/ 2);
      for (var i = 0; i < units.length; i++) {
        units[i] = chars[i * 2] | (chars[i * 2 + 1] << 8);
      }
      return String.fromCharCodes(units);
    } else if (length > 0) {
      final chars = readBytes(length - 1);
      skip(1); // ASCII null terminator
      return String.fromCharCodes(chars);
    }
    return '';
  }
}

/// One downloadable chunk (an ~1 MiB compressed blob on the CDN).
class ManifestChunk {
  ManifestChunk({
    required this.guidKey,
    required this.hash,
    required this.groupNum,
    required this.windowSize,
    required this.fileSize,
  });

  /// 32-hex-char GUID (matches the on-CDN filename), also the map key.
  final String guidKey;
  final int hash;
  final int groupNum;
  final int windowSize; // uncompressed size
  final int fileSize; // compressed download size

  /// Public CDN path, e.g. `ChunksV4/04/88B4CF30..._8F7F6E99....chunk`.
  String pathFor(String chunkDir) {
    final group = groupNum.toString().padLeft(2, '0');
    return '$chunkDir/$group/${_u64Hex16(hash)}_$guidKey.chunk';
  }
}

/// A slice of a chunk's uncompressed data placed into an output file.
class ChunkPart {
  ChunkPart({
    required this.guidKey,
    required this.offset,
    required this.size,
    required this.fileOffset,
  });

  final String guidKey;
  final int offset; // offset within the chunk's uncompressed data
  final int size;
  final int fileOffset; // offset within the output file
}

class ManifestFile {
  ManifestFile({
    required this.filename,
    required this.sha1,
    required this.chunkParts,
    required this.fileSize,
    required this.isExecutable,
  });

  final String filename;

  /// SHA-1 of the fully reassembled file (from the manifest).
  final Uint8List sha1;
  final List<ChunkPart> chunkParts;
  final int fileSize;
  final bool isExecutable;
}

/// Parsed manifest: everything needed to fetch and reassemble a build.
class FortniteManifest {
  FortniteManifest({
    required this.featureLevel,
    required this.buildVersion,
    required this.buildId,
    required this.chunks,
    required this.files,
  });

  final int featureLevel;
  final String buildVersion;
  final String buildId;
  final Map<String, ManifestChunk> chunks;
  final List<ManifestFile> files;

  /// CDN chunk sub-directory changed across manifest feature levels.
  String get chunkDir {
    if (featureLevel >= 15) return 'ChunksV4';
    if (featureLevel >= 6) return 'ChunksV3';
    if (featureLevel >= 3) return 'ChunksV2';
    return 'Chunks';
  }

  /// Total compressed bytes to download (unique chunks referenced by files).
  int get downloadSizeBytes {
    final referenced = <String>{};
    for (final file in files) {
      for (final part in file.chunkParts) {
        referenced.add(part.guidKey);
      }
    }
    var total = 0;
    for (final key in referenced) {
      final chunk = chunks[key];
      if (chunk != null) total += chunk.fileSize;
    }
    return total;
  }

  /// Total bytes written to disk once installed.
  int get installSizeBytes {
    var total = 0;
    for (final file in files) {
      total += file.fileSize;
    }
    return total;
  }

  static String _guidKey(_ByteReader reader) {
    // 4x uint32 little-endian, rendered as the CDN's 8-hex-per-word form.
    final buffer = StringBuffer();
    for (var i = 0; i < 4; i++) {
      buffer.write(
        reader.readUint32().toRadixString(16).toUpperCase().padLeft(8, '0'),
      );
    }
    return buffer.toString();
  }

  static FortniteManifest parse(Uint8List raw) {
    final header = _ByteReader(raw);
    if (header.readUint32() != _kManifestHeaderMagic) {
      throw const FormatException('Not a UE manifest (bad header magic)');
    }
    final headerSize = header.readUint32();
    header.readUint32(); // size uncompressed
    header.readUint32(); // size compressed
    header.skip(20); // sha1
    final storedAs = header.readUint8();
    header.readUint32(); // version
    header.seek(headerSize);

    final body = Uint8List.sublistView(raw, headerSize);
    final Uint8List data = (storedAs & 0x1) != 0
        ? Uint8List.fromList(zlib.decode(body))
        : body;

    final reader = _ByteReader(data);
    final meta = _parseMeta(reader);
    final chunks = _parseChunks(reader, meta.featureLevel);
    final files = _parseFiles(reader);
    // custom fields follow but are unused here.

    return FortniteManifest(
      featureLevel: meta.featureLevel,
      buildVersion: meta.buildVersion,
      buildId: meta.buildId,
      chunks: chunks,
      files: files,
    );
  }

  static _ManifestMeta _parseMeta(_ByteReader reader) {
    final start = reader.position;
    final metaSize = reader.readUint32();
    final dataVersion = reader.readUint8();
    final featureLevel = reader.readUint32();
    reader.readUint8(); // is_file_data
    reader.readUint32(); // app_id
    reader.readFString(); // app_name
    final buildVersion = reader.readFString();
    reader.readFString(); // launch_exe
    reader.readFString(); // launch_command
    final prereqCount = reader.readUint32();
    for (var i = 0; i < prereqCount; i++) {
      reader.readFString();
    }
    reader.readFString(); // prereq_name
    reader.readFString(); // prereq_path
    reader.readFString(); // prereq_args
    var buildId = '';
    if (dataVersion >= 1) {
      buildId = reader.readFString();
    }
    if (dataVersion >= 2) {
      reader.readFString(); // uninstall action path
      reader.readFString(); // uninstall action args
    }
    reader.seek(start + metaSize);
    return _ManifestMeta(
      featureLevel: featureLevel,
      buildVersion: buildVersion,
      buildId: buildId,
    );
  }

  static Map<String, ManifestChunk> _parseChunks(
    _ByteReader reader,
    int featureLevel,
  ) {
    final start = reader.position;
    final size = reader.readUint32();
    reader.readUint8(); // version
    final count = reader.readUint32();

    final guids = List<String>.generate(count, (_) => _guidKey(reader));
    final hashes = List<int>.generate(count, (_) => reader.readUint64());
    for (var i = 0; i < count; i++) {
      reader.skip(20); // sha1
    }
    final groups = List<int>.generate(count, (_) => reader.readUint8());
    final windowSizes = List<int>.generate(count, (_) => reader.readUint32());
    final fileSizes = List<int>.generate(count, (_) => reader.readInt64());

    final chunks = <String, ManifestChunk>{};
    for (var i = 0; i < count; i++) {
      chunks[guids[i]] = ManifestChunk(
        guidKey: guids[i],
        hash: hashes[i],
        groupNum: groups[i],
        windowSize: windowSizes[i],
        fileSize: fileSizes[i],
      );
    }
    reader.seek(start + size);
    return chunks;
  }

  static List<ManifestFile> _parseFiles(_ByteReader reader) {
    final start = reader.position;
    final size = reader.readUint32();
    final version = reader.readUint8();
    final count = reader.readUint32();

    final filenames = List<String>.generate(
      count,
      (_) => reader.readFString(),
    );
    for (var i = 0; i < count; i++) {
      reader.readFString(); // symlink target
    }
    final hashes = List<Uint8List>.generate(
      count,
      (_) => Uint8List.fromList(reader.readBytes(20)), // file sha1
    );
    final flags = List<int>.generate(count, (_) => reader.readUint8());
    for (var i = 0; i < count; i++) {
      final tagCount = reader.readUint32();
      for (var t = 0; t < tagCount; t++) {
        reader.readFString();
      }
    }

    final partsPerFile = <List<ChunkPart>>[];
    for (var i = 0; i < count; i++) {
      final partCount = reader.readUint32();
      final parts = <ChunkPart>[];
      var fileOffset = 0;
      for (var p = 0; p < partCount; p++) {
        final partStart = reader.position;
        final partSize = reader.readUint32();
        final guidKey = _guidKey(reader);
        final offset = reader.readUint32();
        final partLength = reader.readUint32();
        parts.add(
          ChunkPart(
            guidKey: guidKey,
            offset: offset,
            size: partLength,
            fileOffset: fileOffset,
          ),
        );
        fileOffset += partLength;
        reader.seek(partStart + partSize);
      }
      partsPerFile.add(parts);
    }

    if (version >= 1) {
      for (var i = 0; i < count; i++) {
        final hasMd5 = reader.readUint32();
        if (hasMd5 != 0) reader.skip(16);
      }
      for (var i = 0; i < count; i++) {
        reader.readFString(); // mime type
      }
    }
    if (version >= 2) {
      for (var i = 0; i < count; i++) {
        reader.skip(32); // sha256
      }
    }

    final files = <ManifestFile>[];
    for (var i = 0; i < count; i++) {
      final parts = partsPerFile[i];
      var fileSize = 0;
      for (final part in parts) {
        fileSize += part.size;
      }
      files.add(
        ManifestFile(
          filename: filenames[i],
          sha1: hashes[i],
          chunkParts: parts,
          fileSize: fileSize,
          isExecutable: (flags[i] & 0x4) != 0,
        ),
      );
    }
    reader.seek(start + size);
    return files;
  }
}

class _ManifestMeta {
  _ManifestMeta({
    required this.featureLevel,
    required this.buildVersion,
    required this.buildId,
  });
  final int featureLevel;
  final String buildVersion;
  final String buildId;
}

/// Inflates a downloaded `.chunk` blob to its raw window data.
Uint8List decodeChunk(Uint8List raw) {
  final reader = _ByteReader(raw);
  if (reader.readUint32() != _kChunkHeaderMagic) {
    throw const FormatException('Bad chunk magic');
  }
  final headerVersion = reader.readUint32();
  final headerSize = reader.readUint32();
  reader.readUint32(); // compressed size
  reader.skip(16); // guid
  reader.readUint64(); // hash
  final storedAs = reader.readUint8();
  if (headerVersion >= 2) {
    reader.skip(20); // sha1
    reader.readUint8(); // hash type
  }
  if (headerVersion >= 3) {
    reader.readUint32(); // uncompressed size
  }
  final body = Uint8List.sublistView(raw, headerSize);
  if ((storedAs & 0x1) != 0) {
    return Uint8List.fromList(zlib.decode(body));
  }
  return body;
}

/// Free bytes on the volume containing [dirPath] (Windows), or null if it
/// can't be determined.
int? freeSpaceBytes(String dirPath) {
  if (!Platform.isWindows) return null;
  final freePtr = calloc<Uint64>();
  final pathPtr = dirPath.toNativeUtf16();
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getDiskFreeSpaceEx = kernel32.lookupFunction<
        Int32 Function(
          Pointer<Utf16> lpDirectoryName,
          Pointer<Uint64> lpFreeBytesAvailableToCaller,
          Pointer<Uint64> lpTotalNumberOfBytes,
          Pointer<Uint64> lpTotalNumberOfFreeBytes,
        ),
        int Function(
          Pointer<Utf16> lpDirectoryName,
          Pointer<Uint64> lpFreeBytesAvailableToCaller,
          Pointer<Uint64> lpTotalNumberOfBytes,
          Pointer<Uint64> lpTotalNumberOfFreeBytes,
        )>('GetDiskFreeSpaceExW');
    final ok = getDiskFreeSpaceEx(pathPtr, freePtr, nullptr, nullptr);
    if (ok == 0) return null;
    return freePtr.value;
  } catch (_) {
    return null;
  } finally {
    calloc.free(freePtr);
    calloc.free(pathPtr);
  }
}

// ===== Isolate protocol =====

class DownloadRequest {
  DownloadRequest({
    required this.manifestBytes,
    required this.baseUrl,
    required this.gameFolderPath,
    required this.workers,
    required this.buildId,
    required this.sendPort,
  });

  final Uint8List manifestBytes;
  final String baseUrl;
  final String gameFolderPath;
  final int workers;
  final String buildId;
  final SendPort sendPort;
}

/// Progress/lifecycle messages sent from the isolate as plain maps:
/// {type: 'sizes'|'progress'|'done'|'error'|'log', ...}.
class DownloadProgress {
  const DownloadProgress({
    required this.downloadedBytes,
    required this.writtenBytes,
    required this.installSizeBytes,
    required this.downloadSizeBytes,
    required this.completedFiles,
    required this.totalFiles,
  });

  final int downloadedBytes;
  final int writtenBytes;
  final int installSizeBytes;
  final int downloadSizeBytes;
  final int completedFiles;
  final int totalFiles;
}

const String _kResumeFileName = '.atlas_download.json';

/// Isolate entrypoint. Downloads and assembles the whole build, streaming
/// progress back through [request.sendPort].
Future<void> downloadIsolateEntry(DownloadRequest request) async {
  final port = request.sendPort;
  void log(String message) => port.send({'type': 'log', 'message': message});

  try {
    final manifest = FortniteManifest.parse(request.manifestBytes);
    final installSize = manifest.installSizeBytes;
    final downloadSize = manifest.downloadSizeBytes;

    final gameDir = Directory(request.gameFolderPath);
    await gameDir.create(recursive: true);

    // Disk-space guard (best effort).
    final free = freeSpaceBytes(request.gameFolderPath);
    if (free != null && free < installSize) {
      port.send({
        'type': 'error',
        'message':
            'Not enough free disk space. This build needs '
            '${_gib(installSize)} but only ${_gib(free)} is free on that '
            'drive.',
      });
      return;
    }

    port.send({
      'type': 'sizes',
      'installSizeBytes': installSize,
      'downloadSizeBytes': downloadSize,
      'totalFiles': manifest.files.length,
    });

    final resumeFile = File(
      path.join(request.gameFolderPath, _kResumeFileName),
    );
    final completed = _loadResume(resumeFile, request.buildId);

    final downloader = _IsolateDownloader(
      manifest: manifest,
      baseUrl: request.baseUrl,
      gameFolderPath: request.gameFolderPath,
      workers: request.workers,
      buildId: request.buildId,
      resumeFile: resumeFile,
      completed: completed,
      installSizeBytes: installSize,
      downloadSizeBytes: downloadSize,
      port: port,
      log: log,
    );
    await downloader.run();
    port.send({'type': 'done'});
  } catch (error, stack) {
    port.send({
      'type': 'error',
      'message': '$error',
      'detail': '$stack',
    });
  }
}

String _gib(int bytes) => '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';

Set<String> _loadResume(File resumeFile, String buildId) {
  try {
    if (!resumeFile.existsSync()) return <String>{};
    final decoded = jsonDecode(resumeFile.readAsStringSync());
    if (decoded is Map && decoded['buildId'] == buildId) {
      final files = decoded['completedFiles'];
      if (files is List) {
        return files.whereType<String>().toSet();
      }
    }
  } catch (_) {}
  return <String>{};
}

class _IsolateDownloader {
  _IsolateDownloader({
    required this.manifest,
    required this.baseUrl,
    required this.gameFolderPath,
    required this.workers,
    required this.buildId,
    required this.resumeFile,
    required this.completed,
    required this.installSizeBytes,
    required this.downloadSizeBytes,
    required this.port,
    required this.log,
  });

  final FortniteManifest manifest;
  final String baseUrl;
  final String gameFolderPath;
  final int workers;
  final String buildId;
  final File resumeFile;
  final Set<String> completed;
  final int installSizeBytes;
  final int downloadSizeBytes;
  final SendPort port;
  final void Function(String) log;

  late final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..maxConnectionsPerHost = workers
    ..userAgent =
        'EpicGamesLauncher/11.0.1-14907503+++Portal+Release-Live Windows/10.0';

  // Small cross-file cache so chunks shared across adjacent files aren't
  // re-downloaded. Bounded to keep memory in check.
  final LinkedHashMapCache _globalCache = LinkedHashMapCache(maxEntries: 96);

  int _downloadedBytes = 0;
  int _writtenBytes = 0;
  int _completedFiles = 0;
  final Stopwatch _throttle = Stopwatch()..start();

  Future<void> run() async {
    // Pre-count already-completed files toward progress.
    for (final file in manifest.files) {
      if (completed.contains(file.filename) && _outputLooksComplete(file)) {
        _writtenBytes += file.fileSize;
        _completedFiles++;
      }
    }
    _sendProgress(force: true);

    try {
      for (final file in manifest.files) {
        if (completed.contains(file.filename) && _outputLooksComplete(file)) {
          continue;
        }
        await _downloadFile(file);
        completed.add(file.filename);
        _completedFiles++;
        _persistResume();
        _sendProgress(force: true);
      }
    } finally {
      _client.close(force: true);
    }
  }

  bool _outputLooksComplete(ManifestFile file) {
    try {
      final f = File(path.join(gameFolderPath, file.filename));
      return f.existsSync() && f.lengthSync() == file.fileSize;
    } catch (_) {
      return false;
    }
  }

  Future<void> _downloadFile(ManifestFile file) async {
    final outPath = path.join(gameFolderPath, file.filename);
    await Directory(path.dirname(outPath)).create(recursive: true);

    if (file.chunkParts.isEmpty) {
      await File(outPath).writeAsBytes(const <int>[], flush: true);
      return;
    }

    final parts = file.chunkParts;
    // first-need order of unique chunks in this file
    final order = <String>[];
    final seen = <String>{};
    final remaining = <String, int>{};
    for (final part in parts) {
      remaining[part.guidKey] = (remaining[part.guidKey] ?? 0) + 1;
      if (seen.add(part.guidKey)) order.add(part.guidKey);
    }

    final available = <String, Uint8List>{};
    final inFlight = <String, Future<void>>{};
    var nextLaunch = 0;
    final memCap = (workers * 4).clamp(32, 512);

    void launchMore() {
      while (nextLaunch < order.length &&
          inFlight.length < workers &&
          (available.length + inFlight.length) < memCap) {
        final key = order[nextLaunch++];
        if (available.containsKey(key) || inFlight.containsKey(key)) continue;
        final cached = _globalCache.take(key);
        if (cached != null) {
          available[key] = cached;
          continue;
        }
        inFlight[key] = _fetchChunk(key).then((data) {
          inFlight.remove(key);
          available[key] = data;
        });
      }
    }

    final raf = await File(outPath).open(mode: FileMode.write);
    try {
      for (final part in parts) {
        launchMore();
        while (!available.containsKey(part.guidKey)) {
          if (inFlight.isEmpty) {
            // Needed chunk not launched yet (memCap pressure) — force it.
            launchMore();
            if (inFlight.isEmpty) {
              available[part.guidKey] = await _fetchChunk(part.guidKey);
              break;
            }
          }
          await Future.any(inFlight.values);
          launchMore();
        }
        final data = available[part.guidKey]!;
        await raf.setPosition(part.fileOffset);
        await raf.writeFrom(data, part.offset, part.offset + part.size);
        _writtenBytes += part.size;

        remaining[part.guidKey] = remaining[part.guidKey]! - 1;
        if (remaining[part.guidKey] == 0) {
          final evicted = available.remove(part.guidKey);
          if (evicted != null) _globalCache.put(part.guidKey, evicted);
        }
        _sendProgress();
      }
    } finally {
      await raf.close();
    }
  }

  Future<Uint8List> _fetchChunk(String guidKey) async {
    final chunk = manifest.chunks[guidKey];
    if (chunk == null) {
      throw StateError('Manifest references missing chunk $guidKey');
    }
    final url = '$baseUrl/${chunk.pathFor(manifest.chunkDir)}';
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: 300 * (1 << (attempt - 1))),
        );
      }
      try {
        final request = await _client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>().catchError((_) {});
          // 404/403 means Epic purged this build's chunks — not retryable.
          if (response.statusCode == HttpStatus.notFound ||
              response.statusCode == HttpStatus.forbidden) {
            throw _ChunksUnavailableException(response.statusCode);
          }
          lastError = HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
          continue;
        }
        final builder = BytesBuilder(copy: false);
        await for (final part in response) {
          builder.add(part);
        }
        final raw = builder.takeBytes();
        _downloadedBytes += raw.length;
        return decodeChunk(raw);
      } on _ChunksUnavailableException {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('Chunk download failed: $url');
  }

  void _persistResume() {
    try {
      resumeFile.writeAsStringSync(
        jsonEncode({
          'buildId': buildId,
          'completedFiles': completed.toList(),
        }),
      );
    } catch (error) {
      log('Failed to write resume state: $error');
    }
  }

  void _sendProgress({bool force = false}) {
    if (!force && _throttle.elapsedMilliseconds < 400) return;
    _throttle.reset();
    port.send({
      'type': 'progress',
      'downloadedBytes': _downloadedBytes,
      'writtenBytes': _writtenBytes,
      'installSizeBytes': installSizeBytes,
      'downloadSizeBytes': downloadSizeBytes,
      'completedFiles': _completedFiles,
      'totalFiles': manifest.files.length,
    });
  }
}

/// Raised when the CDN no longer hosts a build's chunks (404/403).
class _ChunksUnavailableException implements Exception {
  _ChunksUnavailableException(this.statusCode);
  final int statusCode;
  @override
  String toString() =>
      'Epic no longer hosts the download data for this version '
      '(HTTP $statusCode). Use "Install manually" for a community archive.';
}

/// Tiny bounded LRU of decompressed chunks, keyed by GUID.
class LinkedHashMapCache {
  LinkedHashMapCache({required this.maxEntries});
  final int maxEntries;
  final Map<String, Uint8List> _map = <String, Uint8List>{};

  Uint8List? take(String key) => _map.remove(key);

  void put(String key, Uint8List value) {
    if (maxEntries <= 0) return;
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }
}
