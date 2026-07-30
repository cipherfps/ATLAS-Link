import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ResilientJsonLoadStatus { primary, recovered, missing, invalid }

class ResilientJsonLoadResult {
  const ResilientJsonLoadResult({
    required this.status,
    this.data,
    this.recoveredFromPath,
    this.quarantinedPath,
    this.error,
  });

  final ResilientJsonLoadStatus status;
  final Map<String, dynamic>? data;
  final String? recoveredFromPath;
  final String? quarantinedPath;
  final Object? error;
}

/// Persists a JSON object without ever exposing a partially-written primary
/// file. The previous valid primary is retained as a last-known-good backup.
class ResilientJsonStore {
  ResilientJsonStore(this.file);

  final File file;

  File get backupFile => File('${file.path}.bak');
  File get tempFile => File('${file.path}.tmp');
  File get syncTempFile => File('${file.path}.sync.tmp');
  File get restoreTempFile => File('${file.path}.restore.tmp');

  Future<void> _writeChain = Future<void>.value();

  Future<ResilientJsonLoadResult> load() async {
    Object? primaryError;
    if (await file.exists()) {
      try {
        return ResilientJsonLoadResult(
          status: ResilientJsonLoadStatus.primary,
          data: await _readObject(file),
        );
      } catch (error) {
        primaryError = error;
      }
    }

    final recoveryCandidates = <_RecoveryCandidate>[];
    for (final candidate in <File>[
      tempFile,
      syncTempFile,
      restoreTempFile,
      backupFile,
    ]) {
      if (!await candidate.exists()) continue;
      try {
        recoveryCandidates.add(
          _RecoveryCandidate(
            file: candidate,
            data: await _readObject(candidate),
            modifiedAt: await candidate.lastModified(),
          ),
        );
      } catch (_) {
        // A failed temporary write is not a recovery candidate.
      }
    }

    if (recoveryCandidates.isNotEmpty) {
      recoveryCandidates.sort(
        (left, right) => right.modifiedAt.compareTo(left.modifiedAt),
      );
      final recovered = recoveryCandidates.first;
      await _restoreObject(recovered.data);
      await _deleteIfExists(tempFile);
      await _deleteIfExists(syncTempFile);
      await _deleteIfExists(restoreTempFile);
      return ResilientJsonLoadResult(
        status: ResilientJsonLoadStatus.recovered,
        data: recovered.data,
        recoveredFromPath: recovered.file.path,
        error: primaryError,
      );
    }

    if (primaryError == null) {
      return const ResilientJsonLoadResult(
        status: ResilientJsonLoadStatus.missing,
      );
    }

    final quarantinedPath = await _quarantineInvalidPrimary();
    return ResilientJsonLoadResult(
      status: ResilientJsonLoadStatus.invalid,
      quarantinedPath: quarantinedPath,
      error: primaryError,
    );
  }

  Future<void> writeObject(Map<String, dynamic> data) {
    final encoded = _encodeAndValidate(data);
    final operation = _writeChain.then((_) => _writeEncoded(encoded, tempFile));
    _writeChain = operation.catchError((Object _) {});
    return operation;
  }

  void writeObjectSync(Map<String, dynamic> data) {
    final encoded = _encodeAndValidate(data);
    _writeEncodedSync(encoded, syncTempFile);
  }

  Future<void> flush() => _writeChain;

  Future<void> deleteArtifacts() async {
    await flush();
    for (final artifact in <File>[
      file,
      backupFile,
      tempFile,
      syncTempFile,
      restoreTempFile,
    ]) {
      await _deleteIfExists(artifact);
    }
  }

  String _encodeAndValidate(Map<String, dynamic> data) {
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    _decodeObject(encoded);
    return encoded;
  }

  Future<Map<String, dynamic>> _readObject(File source) async {
    return _decodeObject(await source.readAsString());
  }

  Map<String, dynamic> _readObjectSync(File source) {
    return _decodeObject(source.readAsStringSync());
  }

  Map<String, dynamic> _decodeObject(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('Expected a JSON object.');
  }

  Future<void> _writeEncoded(String encoded, File temporary) async {
    await file.parent.create(recursive: true);
    await _deleteIfExists(temporary);
    await temporary.writeAsString(encoded, flush: true);
    await _readObject(temporary);

    var rotatedPrimary = false;
    try {
      if (await file.exists()) {
        if (await _isValidObject(file)) {
          await _deleteIfExists(backupFile);
          try {
            await file.rename(backupFile.path);
          } catch (_) {
            await file.copy(backupFile.path);
            await _readObject(backupFile);
            await file.delete();
          }
          rotatedPrimary = true;
        } else {
          await file.delete();
        }
      }

      await temporary.rename(file.path);
      await _readObject(file);
    } catch (_) {
      if (rotatedPrimary && !await _isValidObject(file)) {
        await backupFile.copy(file.path);
      }
      rethrow;
    } finally {
      await _deleteIfExists(temporary);
    }
  }

  void _writeEncodedSync(String encoded, File temporary) {
    file.parent.createSync(recursive: true);
    _deleteIfExistsSync(temporary);
    temporary.writeAsStringSync(encoded, flush: true);
    _readObjectSync(temporary);

    var rotatedPrimary = false;
    try {
      if (file.existsSync()) {
        if (_isValidObjectSync(file)) {
          _deleteIfExistsSync(backupFile);
          try {
            file.renameSync(backupFile.path);
          } catch (_) {
            file.copySync(backupFile.path);
            _readObjectSync(backupFile);
            file.deleteSync();
          }
          rotatedPrimary = true;
        } else {
          file.deleteSync();
        }
      }

      temporary.renameSync(file.path);
      _readObjectSync(file);
    } catch (_) {
      if (rotatedPrimary && !_isValidObjectSync(file)) {
        backupFile.copySync(file.path);
      }
      rethrow;
    } finally {
      _deleteIfExistsSync(temporary);
    }
  }

  Future<void> _restoreObject(Map<String, dynamic> data) async {
    final encoded = _encodeAndValidate(data);
    await file.parent.create(recursive: true);
    await _deleteIfExists(restoreTempFile);
    await restoreTempFile.writeAsString(encoded, flush: true);
    await _readObject(restoreTempFile);
    if (await file.exists()) await file.delete();
    await restoreTempFile.rename(file.path);
  }

  Future<String?> _quarantineInvalidPrimary() async {
    if (!await file.exists()) return null;
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final quarantine = File('${file.path}.corrupt-$timestamp');
    try {
      await file.rename(quarantine.path);
      return quarantine.path;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isValidObject(File candidate) async {
    if (!await candidate.exists()) return false;
    try {
      await _readObject(candidate);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isValidObjectSync(File candidate) {
    if (!candidate.existsSync()) return false;
    try {
      _readObjectSync(candidate);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteIfExists(File candidate) async {
    try {
      if (await candidate.exists()) await candidate.delete();
    } catch (_) {
      // Best-effort cleanup; the primary and backup remain authoritative.
    }
  }

  void _deleteIfExistsSync(File candidate) {
    try {
      if (candidate.existsSync()) candidate.deleteSync();
    } catch (_) {
      // Best-effort cleanup; the primary and backup remain authoritative.
    }
  }
}

class _RecoveryCandidate {
  const _RecoveryCandidate({
    required this.file,
    required this.data,
    required this.modifiedAt,
  });

  final File file;
  final Map<String, dynamic> data;
  final DateTime modifiedAt;
}
