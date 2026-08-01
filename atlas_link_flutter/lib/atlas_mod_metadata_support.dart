class AtlasModMetadataSupport {
  const AtlasModMetadataSupport._();

  static String filesBaseUrl(Map<String, dynamic> metadata) {
    for (final key in const <String>['filesBaseUrl', 'files_base_url']) {
      final value = metadata[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Resolves a relative mod-file reference against [filesBaseUrl].
  ///
  /// Absolute references always win, while an absent or invalid base preserves
  /// the caller's legacy [fallbackUrl]. A base without a trailing slash is
  /// still treated as a directory.
  static String resolveFileUrl({
    required String reference,
    required String fallbackUrl,
    String filesBaseUrl = '',
  }) {
    final trimmed = reference.trim();
    if (trimmed.isEmpty) return fallbackUrl;
    if (_isAbsoluteReference(trimmed)) return trimmed;

    final baseUri = Uri.tryParse(filesBaseUrl.trim());
    if (baseUri == null ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
        baseUri.host.isEmpty) {
      return fallbackUrl;
    }

    final normalized = trimmed
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    final segments = <String>[];
    for (final rawSegment in normalized.split('/')) {
      if (rawSegment.isEmpty) continue;
      String segment;
      try {
        segment = Uri.decodeComponent(rawSegment);
      } on FormatException {
        segment = rawSegment;
      }
      if (segment == '.' || segment == '..') return fallbackUrl;
      segments.add(segment);
    }
    if (segments.isEmpty) return fallbackUrl;

    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path
        : '${baseUri.path}/';
    final directoryUri = baseUri.replace(path: basePath, fragment: '');
    return directoryUri.resolveUri(Uri(pathSegments: segments)).toString();
  }

  static bool _isAbsoluteReference(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('file://')) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) ||
        value.startsWith(r'\\');
  }
}
