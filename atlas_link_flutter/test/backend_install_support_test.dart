import 'dart:io';

import 'package:atlas_link_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtlasBackendInstallSupport.selectInstallerUrl', () {
    test('prefers the versioned V2 setup exe over other assets', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS Backend Installer-1.5.5.msi',
          'browser_download_url': 'https://example.com/backend-legacy.msi',
        },
        {
          'name': 'setup.exe',
          'browser_download_url': 'https://example.com/generic-setup.exe',
        },
        {
          'name': 'ATLAS Backend.exe',
          'browser_download_url': 'https://example.com/backend-app.exe',
        },
        {
          'name': 'ATLAS Backend Setup-2.0.0.exe',
          'browser_download_url': 'https://example.com/backend-v2-setup.exe',
        },
      ]);

      expect(selected, 'https://example.com/backend-v2-setup.exe');
    });

    test('prefers installer exes over plain backend executables', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS Backend.exe',
          'browser_download_url': 'https://example.com/backend-app.exe',
        },
        {
          'name': 'ATLAS Backend Setup-1.5.6.exe',
          'browser_download_url': 'https://example.com/backend-setup.exe',
        },
      ]);

      expect(selected, 'https://example.com/backend-setup.exe');
    });

    test('falls back to msi when that is the only installer asset', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS Backend Installer-1.5.5.msi',
          'browser_download_url': 'https://example.com/backend-legacy.msi',
        },
      ]);

      expect(selected, 'https://example.com/backend-legacy.msi');
    });
  });

  group('ATLAS Backend release endpoints', () {
    test('all point to the V2 repository', () {
      expect(
        AtlasBackendInstallSupport.latestReleaseApi,
        'https://api.github.com/repos/cipherfps/ATLAS-Backend-V2/releases/latest',
      );
      expect(
        AtlasBackendInstallSupport.recentReleasesApi,
        'https://api.github.com/repos/cipherfps/ATLAS-Backend-V2/releases?per_page=12',
      );
      expect(
        AtlasBackendInstallSupport.latestReleasePage,
        'https://github.com/cipherfps/ATLAS-Backend-V2/releases/latest',
      );
    });
  });

  group('AtlasBackendInstallSupport.executableCandidatesForRoot', () {
    test('includes the staged installer payload for a repo root', () {
      final root = [
        'C:',
        'repo',
        'ATLAS-Backend-V2',
      ].join(Platform.pathSeparator);
      final candidates = AtlasBackendInstallSupport.executableCandidatesForRoot(
        root,
      ).toList();

      expect(
        candidates,
        contains(
          [
            root,
            'installer',
            'stage',
            'ATLAS Backend.exe',
          ].join(Platform.pathSeparator),
        ),
      );
    });

    test('includes current and transitional Windows install roots', () {
      final roots = AtlasBackendInstallSupport.installationRootCandidates({
        'LOCALAPPDATA': [
          'C:',
          'Users',
          'atlas',
          'AppData',
          'Local',
        ].join(Platform.pathSeparator),
        'ProgramFiles': ['C:', 'Program Files'].join(Platform.pathSeparator),
        'ProgramFiles(x86)': [
          'C:',
          'Program Files (x86)',
        ].join(Platform.pathSeparator),
      }).toList();

      expect(
        roots,
        contains(
          [
            'C:',
            'Program Files',
            'ATLAS Backend V2',
          ].join(Platform.pathSeparator),
        ),
      );
      expect(
        roots,
        contains(
          ['C:', 'Program Files', 'ATLAS Backend'].join(Platform.pathSeparator),
        ),
      );
      expect(
        roots,
        contains(
          [
            'C:',
            'Users',
            'atlas',
            'AppData',
            'Local',
            'Programs',
            'ATLAS Backend V2',
          ].join(Platform.pathSeparator),
        ),
      );
    });

    test('includes legacy Flutter runner executable names', () {
      final root = [
        'C:',
        'Program Files',
        'ATLAS Backend',
      ].join(Platform.pathSeparator);
      final candidates = AtlasBackendInstallSupport.executableCandidatesForRoot(
        root,
      ).toList();

      expect(
        candidates,
        contains([root, 'atlas_gui_flutter.exe'].join(Platform.pathSeparator)),
      );
    });

    test('identifies ATLAS backend paths without matching other backends', () {
      expect(
        AtlasBackendInstallSupport.looksLikeAtlasBackendPath(
          ['C:', 'Program Files', 'ATLAS Backend'].join(Platform.pathSeparator),
        ),
        isTrue,
      );
      expect(
        AtlasBackendInstallSupport.looksLikeAtlasBackendPath(
          [
            'C:',
            'Servers',
            'LawinServer',
            'Backend.exe',
          ].join(Platform.pathSeparator),
        ),
        isFalse,
      );
    });
  });

  group('AtlasBackendInstallSupport.isCurrentBackendExecutable', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('atlas-backend-v2-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File createPayloadExecutable(String name) {
      File(
        [tempDir.path, 'backend-content.json'].join(Platform.pathSeparator),
      ).writeAsStringSync('{}');
      File(
        [tempDir.path, 'app.js'].join(Platform.pathSeparator),
      ).writeAsStringSync('');
      final node = File(
        [
          tempDir.path,
          'tools',
          'node',
          'node.exe',
        ].join(Platform.pathSeparator),
      );
      node.parent.createSync(recursive: true);
      node.writeAsBytesSync(const <int>[0]);
      return File([tempDir.path, name].join(Platform.pathSeparator))
        ..writeAsBytesSync(const <int>[0]);
    }

    test('accepts the V2 executable only with its payload markers', () {
      final executable = createPayloadExecutable('ATLAS Backend.exe');

      expect(
        AtlasBackendInstallSupport.isCurrentBackendExecutable(executable.path),
        isTrue,
      );

      File(
        [tempDir.path, 'backend-content.json'].join(Platform.pathSeparator),
      ).deleteSync();
      expect(
        AtlasBackendInstallSupport.isCurrentBackendExecutable(executable.path),
        isFalse,
      );
    });

    test('rejects installers, uninstallers, and ATLAS Link', () {
      for (final name in const <String>[
        'atlas-backend-installer.exe',
        'ATLAS Backend Setup-2.0.0.exe',
        'unins000.exe',
        'ATLAS Link.exe',
      ]) {
        final executable = createPayloadExecutable(name);
        expect(
          AtlasBackendInstallSupport.isCurrentBackendExecutable(
            executable.path,
          ),
          isFalse,
          reason: '$name must not be treated as the installed backend',
        );
      }
    });
  });

  group('ATLAS Backend registry values', () {
    test('matches backend products without matching ATLAS Link', () {
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct('ATLAS Backend'),
        isTrue,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct('ATLAS Backend V2'),
        isTrue,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct(
          'ATLAS Backend 2.0.0',
        ),
        isTrue,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct('ATLAS Link'),
        isFalse,
      );
    });

    test('normalizes quoted DisplayIcon paths', () {
      expect(
        AtlasBackendInstallSupport.normalizeRegistryExecutablePath(
          r'"C:\Program Files\ATLAS Backend V2\ATLAS Backend.exe",0',
        ),
        r'C:\Program Files\ATLAS Backend V2\ATLAS Backend.exe',
      );
    });
  });
}
