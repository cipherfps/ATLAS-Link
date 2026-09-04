import 'dart:io';

import 'package:atlas_link_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtlasBackendInstallSupport.selectInstallerUrl', () {
    test('prefers the versioned ATLAS setup exe over other assets', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS-Backend-1.5.5.msi',
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
          'name': 'ATLAS.Backend.Setup-1.6.8.exe',
          'browser_download_url': 'https://example.com/backend-setup.exe',
        },
      ]);

      expect(selected, 'https://example.com/backend-setup.exe');
    });

    test('prefers installer exes over plain backend executables', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS Backend.exe',
          'browser_download_url': 'https://example.com/backend-app.exe',
        },
        {
          'name': 'ATLAS.Backend.Setup-1.6.8.exe',
          'browser_download_url': 'https://example.com/backend-setup.exe',
        },
      ]);

      expect(selected, 'https://example.com/backend-setup.exe');
    });

    test('falls back to msi when that is the only installer asset', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS-Backend-1.5.5.msi',
          'browser_download_url': 'https://example.com/backend-legacy.msi',
        },
      ]);

      expect(selected, 'https://example.com/backend-legacy.msi');
    });
  });

  group('ATLAS Backend release endpoints', () {
    test('all point to the original backend repository', () {
      expect(
        AtlasBackendInstallSupport.latestReleaseApi,
        'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases/latest',
      );
      expect(
        AtlasBackendInstallSupport.recentReleasesApi,
        'https://api.github.com/repos/cipherfps/ATLAS-Backend/releases?per_page=12',
      );
      expect(
        AtlasBackendInstallSupport.latestReleasePage,
        'https://github.com/cipherfps/ATLAS-Backend/releases/latest',
      );
      expect(
        AtlasBackendInstallSupport.installerAppId,
        '{8C7FECAB-4CE9-43A5-9BB4-3BCE5AF7FB7F}_is1',
      );
    });
  });

  group('AtlasBackendInstallSupport.executableCandidatesForRoot', () {
    test('includes the staged Inno payload for a repo root', () {
      final root = ['C:', 'repo', 'ATLAS-Backend'].join(Platform.pathSeparator);
      final candidates = AtlasBackendInstallSupport.executableCandidatesForRoot(
        root,
      ).toList();

      expect(
        candidates,
        contains(
          [
            root,
            'dist',
            'ATLAS-Backend',
            'ATLAS Backend.exe',
          ].join(Platform.pathSeparator),
        ),
      );
    });

    test('includes original and transitional Windows install roots', () {
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
            'ATLAS Backend',
          ].join(Platform.pathSeparator),
        ),
      );
      expect(
        roots,
        isNot(
          contains(
            [
              'C:',
              'Program Files',
              'ATLAS Backend V2',
            ].join(Platform.pathSeparator),
          ),
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
      tempDir = Directory.systemTemp.createTempSync('atlas-backend-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    File createPayloadExecutable(String name) {
      File(
        [tempDir.path, 'package.json'].join(Platform.pathSeparator),
      ).writeAsStringSync('{}');
      final entrypoint = File(
        [tempDir.path, 'src', 'index.ts'].join(Platform.pathSeparator),
      );
      entrypoint.parent.createSync(recursive: true);
      entrypoint.writeAsStringSync('');
      final bun = File(
        [tempDir.path, 'tools', 'bun', 'bun.exe'].join(Platform.pathSeparator),
      );
      bun.parent.createSync(recursive: true);
      bun.writeAsBytesSync(const <int>[0]);
      return File([tempDir.path, name].join(Platform.pathSeparator))
        ..writeAsBytesSync(const <int>[0]);
    }

    test('accepts the original executable only with its payload markers', () {
      final executable = createPayloadExecutable('ATLAS Backend.exe');

      expect(
        AtlasBackendInstallSupport.isCurrentBackendExecutable(executable.path),
        isTrue,
      );

      File(
        [tempDir.path, 'package.json'].join(Platform.pathSeparator),
      ).deleteSync();
      expect(
        AtlasBackendInstallSupport.isCurrentBackendExecutable(executable.path),
        isFalse,
      );
    });

    test('accepts the legacy MSI executable name with the old payload', () {
      final executable = createPayloadExecutable('ATLAS.exe');

      expect(
        AtlasBackendInstallSupport.isCurrentBackendExecutable(executable.path),
        isTrue,
      );
    });

    test('rejects installers, uninstallers, and ATLAS Link', () {
      for (final name in const <String>[
        'atlas-backend-installer.exe',
        'ATLAS.Backend.Setup-1.6.8.exe',
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

    test('does not mistake a V2 payload for the original backend', () {
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
      final executable = File(
        [tempDir.path, 'ATLAS Backend.exe'].join(Platform.pathSeparator),
      )..writeAsBytesSync(const <int>[0]);

      expect(
        AtlasBackendInstallSupport.isCurrentBackendExecutable(executable.path),
        isFalse,
      );
      expect(
        AtlasBackendInstallSupport.isIncompleteBackendInstallationRoot(
          tempDir.path,
        ),
        isFalse,
      );
    });

    test(
      'recognizes an incomplete payload after its executable is removed',
      () {
        final executable = createPayloadExecutable('ATLAS Backend.exe');

        expect(
          AtlasBackendInstallSupport.isIncompleteBackendInstallationRoot(
            tempDir.path,
          ),
          isFalse,
        );

        executable.deleteSync();
        expect(
          AtlasBackendInstallSupport.isIncompleteBackendInstallationRoot(
            tempDir.path,
          ),
          isTrue,
        );
      },
    );
  });

  group('ATLAS Backend registry values', () {
    test('matches backend products without matching ATLAS Link', () {
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct('ATLAS Backend'),
        isTrue,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct('ATLAS'),
        isTrue,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct('ATLAS Backend V2'),
        isFalse,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct(
          'ATLAS Backend 2.0.2',
        ),
        isFalse,
      );
      expect(
        AtlasBackendInstallSupport.isBackendRegistryProduct(
          'ATLAS Backend 1.6.8',
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
          r'"C:\Program Files\ATLAS Backend\ATLAS Backend.exe",0',
        ),
        r'C:\Program Files\ATLAS Backend\ATLAS Backend.exe',
      );
    });
  });
}
