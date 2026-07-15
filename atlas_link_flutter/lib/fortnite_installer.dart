// Fortnite version installer: polynite/fn-releases catalog + a native manifest
// downloader (see fortnite_downloader.dart). No Epic account is required the
// build chunks are served openly from Epic's CDN.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'fortnite_downloader.dart';

const String kFnReleasesReadmeUrl =
    'https://raw.githubusercontent.com/polynite/fn-releases/master/README.md';
const String kFnReleasesTreeUrl =
    'https://api.github.com/repos/polynite/fn-releases/git/trees/master?recursive=1';
const String kFnReleasesManifestBaseUrl =
    'https://raw.githubusercontent.com/polynite/fn-releases/master/manifests';

/// Epic's public build CDN. Chunk data is served here with no authentication
/// (the same host the community install flow used).
const String kFortniteCloudDirBaseUrl =
    'https://epicgames-download1.akamaized.net/Builds/Fortnite/CloudDir';

Future<String> _httpGetString(
  Uri uri, {
  Duration timeout = const Duration(seconds: 40),
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'ATLAS-Link';
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().catchError((_) {});
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

/// One installable (or at least documented) build from the fn-releases table.
class FortniteRelease {
  const FortniteRelease({
    required this.season,
    required this.buildVersion,
    required this.displayVersion,
    required this.engineVersion,
    required this.netCl,
    required this.buildDate,
    required this.manifestId,
    required this.notes,
    required this.manifestArchived,
  });

  final int season;

  /// Raw table value, e.g. `7.30-CL-4841819` or `Release-Cert-CL-3681159`.
  final String buildVersion;

  /// Short label for UI + folder names, e.g. `7.30`.
  final String displayVersion;
  final String engineVersion;
  final String netCl;
  final String buildDate;

  /// Basename of the manifest file in fn-releases (empty = not available).
  final String manifestId;
  final String notes;

  /// Whether the manifest file actually exists in the repo's manifests/ tree.
  final bool manifestArchived;

  bool get installable => manifestId.isNotEmpty && manifestArchived;

  String get manifestUrl => '$kFnReleasesManifestBaseUrl/$manifestId.manifest';

  Map<String, Object?> toJson() => {
        'season': season,
        'buildVersion': buildVersion,
        'displayVersion': displayVersion,
        'engineVersion': engineVersion,
        'netCl': netCl,
        'buildDate': buildDate,
        'manifestId': manifestId,
        'notes': notes,
        'manifestArchived': manifestArchived,
      };

  static FortniteRelease? fromJson(Object? value) {
    if (value is! Map) return null;
    final buildVersion = (value['buildVersion'] as String?)?.trim() ?? '';
    if (buildVersion.isEmpty) return null;
    return FortniteRelease(
      season: (value['season'] as num?)?.toInt() ?? 0,
      buildVersion: buildVersion,
      displayVersion:
          (value['displayVersion'] as String?)?.trim() ?? buildVersion,
      engineVersion: (value['engineVersion'] as String?)?.trim() ?? '',
      netCl: (value['netCl'] as String?)?.trim() ?? '',
      buildDate: (value['buildDate'] as String?)?.trim() ?? '',
      manifestId: (value['manifestId'] as String?)?.trim() ?? '',
      notes: (value['notes'] as String?)?.trim() ?? '',
      manifestArchived: value['manifestArchived'] == true,
    );
  }

  /// `7.30-CL-4841819` -> `7.30`; falls back to a `Patch x.y` note or the raw
  /// build string for the early `Release-Cert-CL-…` era entries.
  static String deriveDisplayVersion(String buildVersion, String notes) {
    final raw = buildVersion.trim();
    final versionMatch = RegExp(r'^(\d[^\s]*?)-CL-\d+$').firstMatch(raw);
    if (versionMatch != null) return versionMatch.group(1)!;
    final patchMatch = RegExp(
      r'Patch\s+([0-9][0-9.]*)',
      caseSensitive: false,
    ).firstMatch(notes);
    if (patchMatch != null) return patchMatch.group(1)!;
    return raw;
  }
}

class FortniteReleaseCatalog {
  const FortniteReleaseCatalog({required this.releases, required this.fetchedAt});

  final List<FortniteRelease> releases;
  final DateTime fetchedAt;

  List<FortniteRelease> get installable =>
      releases.where((release) => release.installable).toList();

  Map<String, Object?> toJson() => {
        'fetchedAt': fetchedAt.toIso8601String(),
        'releases': [for (final release in releases) release.toJson()],
      };

  static FortniteReleaseCatalog? fromJson(Object? value) {
    if (value is! Map) return null;
    final fetchedAt = DateTime.tryParse(value['fetchedAt'] as String? ?? '');
    final rawReleases = value['releases'];
    if (fetchedAt == null || rawReleases is! List) return null;
    final releases = <FortniteRelease>[];
    for (final entry in rawReleases) {
      final release = FortniteRelease.fromJson(entry);
      if (release != null) releases.add(release);
    }
    if (releases.isEmpty) return null;
    return FortniteReleaseCatalog(releases: releases, fetchedAt: fetchedAt);
  }
}

/// Fetches + caches the fn-releases version catalog.
class FortniteReleaseCatalogService {
  FortniteReleaseCatalogService({required this.dataDirPath, this.log});

  final String dataDirPath;
  final void Function(String message)? log;

  static const Duration _cacheMaxAge = Duration(hours: 12);

  FortniteReleaseCatalog? _memoryCache;

  String get _cacheFilePath =>
      path.join(dataDirPath, 'fortnite_release_catalog.json');

  Future<FortniteReleaseCatalog> load({bool forceRefresh = false}) async {
    final cached = _memoryCache ?? _readCacheFile();
    _memoryCache = cached;
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheMaxAge) {
      return cached;
    }

    try {
      final readme = await _httpGetString(Uri.parse(kFnReleasesReadmeUrl));
      final releases = parseFnReleasesReadme(readme);
      if (releases.isEmpty) {
        throw const FormatException('No releases parsed from fn-releases');
      }

      // Cross-check against the repo tree so rows whose manifest was never
      // archived are not offered as installable. Best-effort: GitHub API rate
      // limits (60/h unauthenticated) must not take the whole catalog down.
      Set<String>? archivedIds;
      try {
        final tree = await _httpGetString(
          Uri.parse(kFnReleasesTreeUrl),
          headers: const {'Accept': 'application/vnd.github+json'},
        );
        archivedIds = parseManifestIdsFromTree(tree);
      } catch (error) {
        log?.call('fn-releases tree fetch failed, assuming all manifests '
            'exist: $error');
      }

      final resolved = <FortniteRelease>[
        for (final release in releases)
          FortniteRelease(
            season: release.season,
            buildVersion: release.buildVersion,
            displayVersion: release.displayVersion,
            engineVersion: release.engineVersion,
            netCl: release.netCl,
            buildDate: release.buildDate,
            manifestId: release.manifestId,
            notes: release.notes,
            manifestArchived: release.manifestId.isNotEmpty &&
                (archivedIds == null ||
                    archivedIds.contains(release.manifestId)),
          ),
      ];

      final catalog = FortniteReleaseCatalog(
        releases: resolved,
        fetchedAt: DateTime.now(),
      );
      _memoryCache = catalog;
      _writeCacheFile(catalog);
      return catalog;
    } catch (error) {
      log?.call('fn-releases catalog refresh failed: $error');
      if (cached != null) return cached;
      rethrow;
    }
  }

  FortniteReleaseCatalog? _readCacheFile() {
    try {
      final file = File(_cacheFilePath);
      if (!file.existsSync()) return null;
      return FortniteReleaseCatalog.fromJson(
        jsonDecode(file.readAsStringSync()),
      );
    } catch (_) {
      return null;
    }
  }

  void _writeCacheFile(FortniteReleaseCatalog catalog) {
    try {
      File(_cacheFilePath).writeAsStringSync(jsonEncode(catalog.toJson()));
    } catch (error) {
      log?.call('Failed to write fn-releases cache: $error');
    }
  }

  /// Parses the per-season markdown tables. Column order varies between
  /// seasons (newer tables drop "Notes"), so indexes come from the header row.
  static List<FortniteRelease> parseFnReleasesReadme(String markdown) {
    final releases = <FortniteRelease>[];
    var season = -1;
    List<String>? headerCells;

    int columnIndex(List<String> header, String name) {
      for (var i = 0; i < header.length; i++) {
        if (header[i].toLowerCase().contains(name)) return i;
      }
      return -1;
    }

    String cellAt(List<String> cells, int index) =>
        index >= 0 && index < cells.length ? cells[index].trim() : '';

    for (final rawLine in const LineSplitter().convert(markdown)) {
      final line = rawLine.trim();
      if (line.startsWith('#')) {
        final match = RegExp(
          r'^#+\s*Season\s+(\d+)',
          caseSensitive: false,
        ).firstMatch(line);
        season = match != null ? int.parse(match.group(1)!) : -1;
        headerCells = null;
        continue;
      }
      if (season < 0 || !line.startsWith('|')) continue;

      final cells = line
          .split('|')
          .map((cell) => cell.trim())
          .toList();
      // Leading/trailing pipes produce empty first/last entries.
      if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
      if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
      if (cells.isEmpty) continue;

      final isSeparator = cells.every(
        (cell) => RegExp(r'^[-: ]*$').hasMatch(cell),
      );
      if (headerCells == null) {
        if (!isSeparator) headerCells = cells;
        continue;
      }
      if (isSeparator) continue;

      final buildVersion = cellAt(cells, columnIndex(headerCells, 'build version'));
      if (buildVersion.isEmpty) continue;
      final notes = cellAt(cells, columnIndex(headerCells, 'note'));

      releases.add(
        FortniteRelease(
          season: season,
          buildVersion: buildVersion,
          displayVersion:
              FortniteRelease.deriveDisplayVersion(buildVersion, notes),
          engineVersion: cellAt(cells, columnIndex(headerCells, 'engine')),
          netCl: cellAt(cells, columnIndex(headerCells, 'net cl')),
          buildDate: cellAt(cells, columnIndex(headerCells, 'date')),
          manifestId: cellAt(cells, columnIndex(headerCells, 'manifest')),
          notes: notes,
          manifestArchived: true,
        ),
      );
    }
    return releases;
  }

  static Set<String> parseManifestIdsFromTree(String jsonBody) {
    final ids = <String>{};
    final decoded = jsonDecode(jsonBody);
    if (decoded is! Map) return ids;
    final tree = decoded['tree'];
    if (tree is! List) return ids;
    for (final entry in tree) {
      if (entry is! Map) continue;
      final entryPath = entry['path'];
      if (entryPath is! String) continue;
      if (!entryPath.startsWith('manifests/') ||
          !entryPath.endsWith('.manifest')) {
        continue;
      }
      ids.add(path.basenameWithoutExtension(entryPath));
    }
    return ids;
  }
}

enum FortniteInstallPhase {
  preparing,
  downloadingManifest,
  analyzing,
  downloading,
  completed,
  failed,
  cancelled,
}

/// Starts and tracks native (no-login) Fortnite build installs.
class FortniteInstallService {
  FortniteInstallService({required this.dataDirPath, this.log});

  final String dataDirPath;
  final void Function(String message)? log;

  FortniteInstallJob? _activeJob;

  FortniteInstallJob? get activeJob =>
      (_activeJob?.isFinished ?? true) ? null : _activeJob;

  String get prefsFilePath =>
      path.join(dataDirPath, 'fortnite_installer_prefs.json');

  Map<String, Object?> readPrefs() {
    try {
      final decoded = jsonDecode(File(prefsFilePath).readAsStringSync());
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {}
    return <String, Object?>{};
  }

  void writePrefs(Map<String, Object?> updates) {
    try {
      final prefs = readPrefs()..addAll(updates);
      File(prefsFilePath).writeAsStringSync(jsonEncode(prefs));
    } catch (error) {
      log?.call('Failed to save installer prefs: $error');
    }
  }

  FortniteInstallJob startInstall({
    required FortniteRelease release,
    required String gameFolderPath,
    required int maxWorkers,
  }) {
    if (activeJob != null) {
      throw StateError('An install is already running');
    }
    final job = FortniteInstallJob._(
      service: this,
      release: release,
      gameFolderPath: gameFolderPath,
      maxWorkers: maxWorkers,
    );
    _activeJob = job;
    unawaited(job._run());
    return job;
  }
}

/// A single build install driven by the native downloader isolate. Progress
/// fields update from isolate messages; listen via [addListener].
class FortniteInstallJob extends ChangeNotifier {
  FortniteInstallJob._({
    required this.service,
    required this.release,
    required this.gameFolderPath,
    required this.maxWorkers,
  });

  final FortniteInstallService service;
  final FortniteRelease release;
  final String gameFolderPath;
  final int maxWorkers;

  FortniteInstallPhase phase = FortniteInstallPhase.preparing;
  String statusMessage = 'Preparing…';

  /// 0–100 while downloading, null when unknown.
  double? percent;
  String etaText = '';
  String elapsedText = '';
  double downloadedMiB = 0;
  double writtenMiB = 0;
  double rawSpeedMiBps = 0;
  double? downloadSizeMiB;
  double? installSizeMiB;
  String? failureReason;
  final DateTime startedAt = DateTime.now();

  /// True once the build has been auto-imported (guards double-import).
  bool importHandled = false;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  Completer<void>? _runCompleter;
  bool _cancelRequested = false;
  bool _deleteFilesOnCancel = true;
  bool _done = false;

  // Speed tracking from cumulative byte counters.
  int _lastDownloadedBytes = 0;
  int? _lastSampleMicros;

  bool get isFinished =>
      phase == FortniteInstallPhase.completed ||
      phase == FortniteInstallPhase.failed ||
      phase == FortniteInstallPhase.cancelled;

  bool get isCancelRequested => _cancelRequested;

  /// Whether this job removed (or will remove) its partial download when
  /// cancelled — false for interruptions that keep resume data.
  bool get deletedFilesOnCancel => _cancelRequested && _deleteFilesOnCancel;

  /// Stops the install. With [deleteFiles] (the Cancel button's behavior) the
  /// partial download is removed, freeing the disk. Pass false for
  /// interruptions (app closing) so the next install of this same version
  /// continues where it stopped.
  Future<void> cancel({bool deleteFiles = true}) async {
    if (isFinished || _cancelRequested) return;
    _cancelRequested = true;
    _deleteFilesOnCancel = deleteFiles;
    statusMessage = 'Cancelling…';
    notifyListeners();
    _teardownIsolate();
    final completer = _runCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    await _finalizeCancelled();
  }

  void _teardownIsolate() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
  }

  Future<void> _run() async {
    try {
      _update(
        phase: FortniteInstallPhase.downloadingManifest,
        status: 'Downloading manifest for ${release.displayVersion}…',
      );
      final manifestBytes = await _downloadManifestBytes();
      if (_cancelRequested) return;

      _update(
        phase: FortniteInstallPhase.analyzing,
        status: 'Preparing download…',
      );

      // Builds from roughly Season 15 and earlier use Epic's old JSON
      // manifest format. Parsing it wouldn't help: Epic has deleted the
      // actual file data for those builds from its CDN, so they cannot be
      // downloaded from Epic by any tool.
      if (manifestBytes.isNotEmpty && manifestBytes.first == 0x7B /* '{' */ ) {
        _update(
          phase: FortniteInstallPhase.failed,
          status: 'Install failed.',
          failure:
              'This build is too old to download from Epic and its files are '
              'no longer hosted on their servers. Use "Install manually" to '
              'get it from a community build archive.',
        );
        return;
      }

      final FortniteManifest manifest;
      final String buildId;
      try {
        manifest = FortniteManifest.parse(manifestBytes);
        buildId = manifest.buildId.isNotEmpty
            ? manifest.buildId
            : release.manifestId;
      } catch (error) {
        _update(
          phase: FortniteInstallPhase.failed,
          status: 'Install failed.',
          failure: 'This build\'s manifest could not be read ($error). Try '
              '"Install manually" for this version.',
        );
        return;
      }
      service.writePrefs({'lastManifestId': release.manifestId});

      final receivePort = ReceivePort();
      _receivePort = receivePort;
      final completer = Completer<void>();
      _runCompleter = completer;

      receivePort.listen((message) {
        if (message is Map) {
          _handleIsolateMessage(message, completer);
          return;
        }
        // Non-Map: isolate onExit (null) or onError ([error, stack]). If the
        // isolate died without a terminal 'done'/'error' message, treat it as
        // a failure (unless we're already finishing or cancelling).
        if (_done || _cancelRequested || isFinished) return;
        final detail = message is List && message.isNotEmpty
            ? '${message.first}'
            : 'the download process stopped unexpectedly';
        _isolate = null;
        _update(
          phase: FortniteInstallPhase.failed,
          status: 'Install failed.',
          failure: 'Download stopped unexpectedly ($detail). Re-run the '
              'install to resume where it stopped.',
        );
        if (!completer.isCompleted) completer.complete();
      });

      _isolate = await Isolate.spawn(
        downloadIsolateEntry,
        DownloadRequest(
          manifestBytes: manifestBytes,
          baseUrl: kFortniteCloudDirBaseUrl,
          gameFolderPath: gameFolderPath,
          workers: maxWorkers,
          buildId: buildId,
          sendPort: receivePort.sendPort,
        ),
        onError: receivePort.sendPort,
        onExit: receivePort.sendPort,
      );

      _update(
        phase: FortniteInstallPhase.downloading,
        status: 'Downloading ${release.displayVersion}…',
      );

      await completer.future;
    } catch (error) {
      if (_cancelRequested) {
        await _finalizeCancelled();
      } else {
        _update(
          phase: FortniteInstallPhase.failed,
          status: 'Install failed.',
          failure: '$error',
        );
      }
    }
  }

  void _handleIsolateMessage(Map message, Completer<void> completer) {
    switch (message['type']) {
      case 'sizes':
        installSizeMiB = _toMiB(message['installSizeBytes']);
        downloadSizeMiB = _toMiB(message['downloadSizeBytes']);
        notifyListeners();
      case 'progress':
        _applyProgress(message);
      case 'log':
        service.log?.call('${message['message']}');
      case 'done':
        _done = true;
        _receivePort?.close();
        _receivePort = null;
        _isolate = null;
        percent = 100;
        etaText = '';
        _update(
          phase: FortniteInstallPhase.completed,
          status: 'Download complete.',
        );
        if (!completer.isCompleted) completer.complete();
      case 'error':
        _done = true;
        _receivePort?.close();
        _receivePort = null;
        _isolate = null;
        if (_cancelRequested) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        _update(
          phase: FortniteInstallPhase.failed,
          status: 'Install failed.',
          failure: '${message['message']}',
        );
        if (!completer.isCompleted) completer.complete();
    }
  }

  void _applyProgress(Map message) {
    final downloadedBytes = (message['downloadedBytes'] as num?)?.toInt() ?? 0;
    final writtenBytes = (message['writtenBytes'] as num?)?.toInt() ?? 0;
    final installBytes = (message['installSizeBytes'] as num?)?.toInt() ?? 0;
    downloadedMiB = downloadedBytes / (1024 * 1024);
    writtenMiB = writtenBytes / (1024 * 1024);
    if (installBytes > 0) {
      installSizeMiB = installBytes / (1024 * 1024);
      percent = (writtenBytes / installBytes * 100).clamp(0.0, 100.0);
    }

    // Speed from delta of downloaded (network) bytes over wall time.
    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    if (_lastSampleMicros != null) {
      final dt = (nowMicros - _lastSampleMicros!) / 1e6;
      if (dt > 0) {
        final dBytes = downloadedBytes - _lastDownloadedBytes;
        final instMiBps = (dBytes / (1024 * 1024)) / dt;
        // Light smoothing so the readout isn't jumpy.
        rawSpeedMiBps = rawSpeedMiBps <= 0
            ? instMiBps
            : rawSpeedMiBps * 0.6 + instMiBps * 0.4;
      }
    }
    _lastSampleMicros = nowMicros;
    _lastDownloadedBytes = downloadedBytes;

    // ETA from remaining install bytes at the current write rate.
    final elapsed = DateTime.now().difference(startedAt);
    elapsedText = _formatDuration(elapsed);
    if (installBytes > 0 && writtenBytes > 0 && elapsed.inSeconds > 0) {
      final writeRate = writtenBytes / elapsed.inSeconds; // bytes/sec
      if (writeRate > 0) {
        final remaining = (installBytes - writtenBytes) / writeRate;
        etaText = _formatDuration(Duration(seconds: remaining.round()));
      }
    }

    if (phase != FortniteInstallPhase.downloading && !isFinished) {
      phase = FortniteInstallPhase.downloading;
      statusMessage = 'Downloading ${release.displayVersion}…';
    }
    notifyListeners();
  }

  Future<void> _finalizeCancelled() async {
    if (_done) return;
    _done = true;
    if (_deleteFilesOnCancel) {
      _update(status: 'Removing downloaded files…');
      await _deletePartialDownload();
      _update(
        phase: FortniteInstallPhase.cancelled,
        status: 'Install cancelled and the downloaded files were removed.',
      );
      return;
    }
    _update(phase: FortniteInstallPhase.cancelled, status: 'Install stopped.');
  }

  /// Best-effort removal of the partial game folder. The just-killed isolate
  /// can hold a file handle for a moment, so retry a few times.
  Future<void> _deletePartialDownload() async {
    final dir = Directory(gameFolderPath);
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(
        Duration(milliseconds: attempt == 0 ? 300 : 1200),
      );
      try {
        if (!dir.existsSync()) return;
        await dir.delete(recursive: true);
        return;
      } catch (error) {
        service.log?.call(
          'Cancel cleanup attempt ${attempt + 1} for $gameFolderPath '
          'failed: $error',
        );
      }
    }
    if (dir.existsSync()) {
      service.log?.call(
        'Could not fully remove $gameFolderPath after cancel; leftover files '
        'can be deleted manually.',
      );
    }
  }

  Future<Uint8List> _downloadManifestBytes() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'ATLAS-Link';
    try {
      final request = await client.getUrl(Uri.parse(release.manifestUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().catchError((_) {});
        throw HttpException(
          response.statusCode == HttpStatus.notFound
              ? 'Manifest for ${release.displayVersion} is missing from the '
                  'fn-releases archive (HTTP 404).'
              : 'Manifest download failed (HTTP ${response.statusCode}).',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final part in response) {
        builder.add(part);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  void _update({
    FortniteInstallPhase? phase,
    String? status,
    String? failure,
  }) {
    if (phase != null) this.phase = phase;
    if (status != null) statusMessage = status;
    if (failure != null) failureReason = failure;
    notifyListeners();
  }

  static double? _toMiB(Object? bytes) {
    final value = (bytes as num?)?.toInt();
    if (value == null) return null;
    return value / (1024 * 1024);
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (hours > 0) return '${two(hours)}:${two(minutes)}:${two(seconds)}';
    return '${two(minutes)}:${two(seconds)}';
  }
}
