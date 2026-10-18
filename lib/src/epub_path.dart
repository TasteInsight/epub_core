import 'package:path/path.dart' as path;

import 'models.dart';

/// URI resolution shared by manifest, navigation and document resources.
abstract final class EpubPath {
  /// Resolves [reference] against a root-relative document URI.
  static String resolve(String documentHref, String reference) {
    try {
      return Uri.parse(documentHref).resolve(reference.trim()).toString();
    } on FormatException {
      throw EpubException(
        EpubErrorCode.invalidPackage,
        'Invalid resource URI.',
        path: reference,
      );
    }
  }

  /// Whether a reference points outside the publication.
  static bool isExternal(String href) {
    final uri = Uri.parse(href);
    return uri.hasScheme || uri.hasAuthority || uri.path.startsWith('/');
  }

  /// The encoded fragment, for a consumer to decode exactly once.
  static String? fragment(String href) {
    final uri = Uri.parse(href);
    return uri.hasFragment ? uri.fragment : null;
  }

  /// Converts a resource URI to a decoded ZIP name, excluding query/fragment.
  /// Returns null for external, malformed or escaping paths.
  static String? archivePath(String href) {
    try {
      if (isExternal(href)) return null;
      return normalizeArchivePath(Uri.decodeComponent(Uri.parse(href).path));
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Normalizes a literal ZIP entry name; percent characters remain literal.
  static String? normalizeArchivePath(String name) {
    if (name.contains('\\') ||
        name.contains('\u0000') ||
        name.startsWith('/')) {
      return null;
    }
    final normalized = path.posix.normalize(name);
    if (normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      return null;
    }
    return normalized;
  }
}
