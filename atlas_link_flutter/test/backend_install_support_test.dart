import 'dart:io';

import 'package:atlas_link_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtlasBackendInstallSupport.selectInstallerUrl', () {
    test('prefers the Inno setup exe over legacy msi assets', () {
      final selected = AtlasBackendInstallSupport.selectInstallerUrl([
        {
          'name': 'ATLAS Backend Installer-1.5.5.msi',
          'browser_download_url': 'https://example.com/backend-legacy.msi',
        },
        {
          'name': 'ATLAS Backend Setup-1.5.6.exe',
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

  group('AtlasBackendInstallSupport.executableCandidatesForRoot', () {
    test('includes the staged Inno dist executable for a repo root', () {
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
}
