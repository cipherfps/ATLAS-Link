import 'package:atlas_link_flutter/atlas_mod_metadata_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtlasModMetadataSupport.filesBaseUrl', () {
    test('reads camel-case and snake-case metadata keys', () {
      expect(
        AtlasModMetadataSupport.filesBaseUrl({
          'filesBaseUrl': 'https://cdn.example/mod/',
        }),
        'https://cdn.example/mod/',
      );
      expect(
        AtlasModMetadataSupport.filesBaseUrl({
          'files_base_url': 'https://cdn.example/legacy/',
        }),
        'https://cdn.example/legacy/',
      );
    });
  });

  group('AtlasModMetadataSupport.resolveFileUrl', () {
    const fallback = 'https://raw.example/legacy.pak';

    test('joins a filename to a base URL with a trailing slash', () {
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: 'pakchunk2003-WindowsClient_P.pak',
          filesBaseUrl: 'https://atlas.fmod.dev/paks/retrac/14.40/',
          fallbackUrl: fallback,
        ),
        'https://atlas.fmod.dev/paks/retrac/14.40/'
        'pakchunk2003-WindowsClient_P.pak',
      );
    });

    test('treats a base without a trailing slash as a directory', () {
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: 'pakchunk2009-WindowsClient_P.utoc',
          filesBaseUrl: 'https://atlas.fmod.dev/paks/retrac/14.60',
          fallbackUrl: fallback,
        ),
        'https://atlas.fmod.dev/paks/retrac/14.60/'
        'pakchunk2009-WindowsClient_P.utoc',
      );
    });

    test('normalizes nested paths and encodes path segments', () {
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: r'nested\Pak File.pak',
          filesBaseUrl: 'https://cdn.example/mod/',
          fallbackUrl: fallback,
        ),
        'https://cdn.example/mod/nested/Pak%20File.pak',
      );
    });

    test('keeps an explicit absolute file URL', () {
      const explicit = 'https://mirror.example/custom.pak';
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: explicit,
          filesBaseUrl: 'https://cdn.example/mod/',
          fallbackUrl: fallback,
        ),
        explicit,
      );
    });

    test('preserves legacy fallback without a valid base URL', () {
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: 'legacy.pak',
          fallbackUrl: fallback,
        ),
        fallback,
      );
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: 'legacy.pak',
          filesBaseUrl: 'not-a-url',
          fallbackUrl: fallback,
        ),
        fallback,
      );
    });

    test('rejects path traversal and preserves the fallback', () {
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: '../outside.pak',
          filesBaseUrl: 'https://cdn.example/mod/',
          fallbackUrl: fallback,
        ),
        fallback,
      );
      expect(
        AtlasModMetadataSupport.resolveFileUrl(
          reference: '%2e%2e/outside.pak',
          filesBaseUrl: 'https://cdn.example/mod/',
          fallbackUrl: fallback,
        ),
        fallback,
      );
    });
  });
}
