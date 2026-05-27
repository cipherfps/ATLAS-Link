// Fortnite build import: unique Shipping exe, headless binary patch,
// and CrashReport metadata version.
// ignore_for_file: avoid_dynamic_calls

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart';

const String kShippingExeName = 'FortniteClient-Win64-Shipping.exe';
const String kCrashReportExeName = 'CrashReportClient.exe';

final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
final int Function(
  Pointer<Utf16> pszPath,
  Pointer<Void> pbc,
  int flags,
  Pointer<GUID> riid,
  Pointer<Pointer<COMObject>> ppv,
) _shGetPropertyStoreFromParsingName = _shell32.lookupFunction<
    Int32 Function(
      Pointer<Utf16> pszPath,
      Pointer<Void> pbc,
      Uint32 flags,
      Pointer<GUID> riid,
      Pointer<Pointer<COMObject>> ppv,
    ),
    int Function(
      Pointer<Utf16> pszPath,
      Pointer<Void> pbc,
      int flags,
      Pointer<GUID> riid,
      Pointer<Pointer<COMObject>> ppv,
    )>('SHGetPropertyStoreFromParsingName');

final Uint8List _originalHeadless = Uint8List.fromList([
  45, 0, 105, 0, 110, 0, 118, 0, 105, 0, 116, 0, 101, 0, 115, 0, 101, 0, 115, 0, 115, 0, 105, 0, 111, 0, 110, 0, 32, 0, 45, 0, 105, 0, 110, 0, 118, 0, 105, 0, 116, 0, 101, 0, 102, 0, 114, 0, 111, 0, 109, 0, 32, 0, 45, 0, 112, 0, 97, 0, 114, 0, 116, 0, 121, 0, 95, 0, 106, 0, 111, 0, 105, 0, 110, 0, 105, 0, 110, 0, 102, 0, 111, 0, 95, 0, 116, 0, 111, 0, 107, 0, 101, 0, 110, 0, 32, 0, 45, 0, 114, 0, 101, 0, 112, 0, 108, 0, 97, 0, 121, 0
]);

final Uint8List _patchedHeadless = Uint8List.fromList([
  45, 0, 108, 0, 111, 0, 103, 0, 32, 0, 45, 0, 110, 0, 111, 0, 115, 0, 112, 0, 108, 0, 97, 0, 115, 0, 104, 0, 32, 0, 45, 0, 110, 0, 111, 0, 115, 0, 111, 0, 117, 0, 110, 0, 100, 0, 32, 0, 45, 0, 110, 0, 117, 0, 108, 0, 108, 0, 114, 0, 104, 0, 105, 0, 32, 0, 45, 0, 117, 0, 115, 0, 101, 0, 111, 0, 108, 0, 100, 0, 105, 0, 116, 0, 101, 0, 109, 0, 99, 0, 97, 0, 114, 0, 100, 0, 115, 0, 32, 0, 32, 0, 32, 0, 32, 0, 32, 0, 32, 0, 32, 0
]);

/// Fortnite-style version token in a folder/file name (e.g. 32.11, 2.5, 1.8.0).
final RegExp _versionLabelPattern = RegExp(r'(\d+\.\d+(?:\.\d+)?)');

/// Closest path segment that looks like a Fortnite version label.
String inferVersionLabelFromDirectoryPath(String directoryPath) {
  final normalized = directoryPath.trim();
  final segments = path.split(normalized);
  for (var i = segments.length - 1; i >= 0; i--) {
    final segment = segments[i].trim();
    if (segment.isEmpty) continue;
    final match = _versionLabelPattern.firstMatch(segment);
    if (match != null) {
      return match.group(1)!;
    }
  }
  return path.basename(normalized);
}

/// Parsed from CrashReportClient `++Fortnite+Release-*` metadata.
class FortniteBuildMetadata {
  const FortniteBuildMetadata({
    required this.releaseLabel,
    this.engineChangelist,
  });

  /// e.g. `32.11`, `Cert`, or `Next`.
  final String releaseLabel;

  /// Unreal engine changelist from metadata prefix (e.g. `38202817`).
  final int? engineChangelist;
}

/// Result of reading a build folder at import time.
class BuildImportInfo {
  const BuildImportInfo({
    required this.gameVersion,
    this.engineChangelist,
  });

  final String gameVersion;
  final int? engineChangelist;
}

FortniteBuildMetadata? parseFortniteBuildMetadata(String value) {
  final headerIndex = value.indexOf('++Fortnite');
  if (headerIndex == -1) return null;

  final dashAfterHeader = value.indexOf('-', headerIndex);
  if (dashAfterHeader == -1) return null;

  final releaseLabel = value.substring(dashAfterHeader + 1);
  final engineVersion = value.substring(0, value.indexOf('+'));
  final engineParts = engineVersion.split('-');
  final engineChangelist = engineParts.length >= 2
      ? int.tryParse(engineParts[1])
      : null;

  return FortniteBuildMetadata(
    releaseLabel: releaseLabel,
    engineChangelist: engineChangelist,
  );
}

bool pathContainsVersionLabel(String directoryPath) {
  final segments = path.split(directoryPath.trim());
  for (var i = segments.length - 1; i >= 0; i--) {
    final segment = segments[i].trim();
    if (segment.isEmpty) continue;
    if (_versionLabelPattern.hasMatch(segment)) {
      return true;
    }
  }
  return false;
}

String resolveGameVersionLabel({
  required FortniteBuildMetadata metadata,
  required String directoryPath,
}) {
  final releaseLabel = metadata.releaseLabel;
  if (releaseLabel != 'Cert' && releaseLabel != 'Next') {
    return releaseLabel;
  }

  if (pathContainsVersionLabel(directoryPath)) {
    return inferVersionLabelFromDirectoryPath(directoryPath);
  }

  final changelist = metadata.engineChangelist;
  if (changelist != null) {
    return changelist.toString();
  }

  return inferVersionLabelFromDirectoryPath(directoryPath);
}

Future<List<File>> findFiles(Directory directory, String name) =>
    Isolate.run(() => directory
        .list(recursive: true, followLinks: true)
        .handleError((_) {})
        .where(
          (event) => event is File && path.basename(event.path) == name,
        )
        .map((event) => event as File)
        .toList());

/// All `FortniteClient-Win64-Shipping.exe` paths under [rootPath] (recursive).
Future<List<String>> findShippingExecutables(String rootPath) async {
  final dir = Directory(rootPath.trim());
  if (!dir.existsSync()) return const [];
  final files = await findFiles(dir, kShippingExeName);
  return files.map((f) => f.path).toList();
}

Future<bool> patchHeadless(File file) async =>
    _patch(file, _originalHeadless, _patchedHeadless);

Future<bool> _patch(File file, Uint8List original, Uint8List patched) async =>
    Isolate.run(() async {
      try {
        if (original.length != patched.length) {
          throw Exception('Cannot mutate length of binary file');
        }

        final source = await file.readAsBytes();
        var readOffset = 0;
        var patchOffset = -1;
        var patchCount = 0;
        while (readOffset < source.length) {
          if (source[readOffset] == original[patchCount]) {
            if (patchOffset == -1) {
              patchOffset = readOffset;
            }

            if (readOffset - patchOffset + 1 == original.length) {
              break;
            }

            patchCount++;
          } else {
            patchOffset = -1;
            patchCount = 0;
          }

          readOffset++;
        }

        if (patchOffset == -1) {
          return false;
        }

        for (var i = 0; i < patched.length; i++) {
          source[patchOffset + i] = patched[i];
        }

        await file.writeAsBytes(source, flush: true);
        return true;
      } catch (_) {
        return false;
      }
    });

/// Version + engine CL from CrashReportClient metadata (Windows) when available.
Future<BuildImportInfo> extractBuildImportInfo(String directoryPath) async {
  if (!Platform.isWindows) {
    return BuildImportInfo(
      gameVersion: inferVersionLabelFromDirectoryPath(directoryPath),
    );
  }
  return Isolate.run(() async {
    final directory = Directory(directoryPath.trim());
    final defaultGameVersion =
        inferVersionLabelFromDirectoryPath(directory.path);
    final crashReportClients = await findFiles(directory, kCrashReportExeName);
    if (crashReportClients.isEmpty) {
      return BuildImportInfo(gameVersion: defaultGameVersion);
    }

    final filePathPtr = crashReportClients.last.path.toNativeUtf16();
    final pPropertyStore = calloc<COMObject>();
    final iidPropertyStore = GUIDFromString(IID_IPropertyStore);
    final ret = _shGetPropertyStoreFromParsingName(
      filePathPtr,
      nullptr,
      GPS_DEFAULT,
      iidPropertyStore,
      pPropertyStore.cast(),
    );

    calloc.free(filePathPtr);
    calloc.free(iidPropertyStore);

    if (FAILED(ret)) {
      calloc.free(pPropertyStore);
      return BuildImportInfo(gameVersion: defaultGameVersion);
    }

    final propertyStore = IPropertyStore(pPropertyStore);

    final countPtr = calloc<Uint32>();
    final hrCount = propertyStore.getCount(countPtr);
    final count = countPtr.value;
    calloc.free(countPtr);
    if (FAILED(hrCount)) {
      return BuildImportInfo(gameVersion: defaultGameVersion);
    }

    for (var i = 0; i < count; i++) {
      final pKey = calloc<PROPERTYKEY>();
      final hrKey = propertyStore.getAt(i, pKey);
      if (FAILED(hrKey)) {
        calloc.free(pKey);
        continue;
      }

      final pv = calloc<PROPVARIANT>();
      final hrValue = propertyStore.getValue(pKey, pv);
      if (!FAILED(hrValue)) {
        if (pv.ref.vt == VT_LPWSTR) {
          final valueStr = pv.ref.pwszVal.toDartString();
          final metadata = parseFortniteBuildMetadata(valueStr);
          if (metadata != null) {
            return BuildImportInfo(
              gameVersion: resolveGameVersionLabel(
                metadata: metadata,
                directoryPath: directory.path,
              ),
              engineChangelist: metadata.engineChangelist,
            );
          }
        }
      }
      calloc.free(pKey);
      calloc.free(pv);
    }

    return BuildImportInfo(gameVersion: defaultGameVersion);
  });
}

/// Version label only — prefer [extractBuildImportInfo] when CL is needed.
Future<String> extractGameVersionFromBuildDirectory(String directoryPath) async {
  final info = await extractBuildImportInfo(directoryPath);
  return info.gameVersion;
}
