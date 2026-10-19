import 'package:path/path.dart' as path;

import 'errors.dart';

/// URI resolution shared by manifest, navigation and document resources.
abstract final class EpubPath {
  /// Parses a URI; malformed input throws [EpubException] with invalidUri.
  static Uri parse(String value) {
    try {
      if (RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value)) {
        throw const FormatException('Invalid percent escape.');
      }
      return Uri.parse(value);
    } on FormatException catch (error) {
      throw EpubException(
        EpubErrorCode.invalidUri,
        error.message,
        path: value,
        offset: error.offset,
      );
    }
  }

  /// Resolves [reference] against a root-relative document URI.
  static String resolve(String documentHref, String reference) {
    try {
      final base = parse(documentHref);
      final target = parse(reference.trim());
      if (base.hasScheme ||
          base.hasAuthority ||
          target.hasScheme ||
          target.hasAuthority) {
        return base.resolveUri(target).toString();
      }
      // Resolve against a container root so parent segments stop at that root.
      final root = Uri.parse('epub://container/');
      final resolved = root.resolveUri(base).resolveUri(target).toString();
      return resolved.substring('epub://container/'.length);
    } on EpubException {
      rethrow;
    } on FormatException catch (error) {
      throw EpubException(
        EpubErrorCode.invalidUri,
        error.message,
        path: reference,
        offset: error.offset,
      );
    }
  }

  /// Whether a reference points outside the publication.
  static bool isExternal(String href) {
    final uri = parse(href);
    return uri.hasScheme || uri.hasAuthority;
  }

  /// The encoded fragment, for a consumer to decode exactly once.
  static String? fragment(String href) {
    final uri = parse(href);
    return uri.hasFragment ? uri.fragment : null;
  }

  /// Converts a resource URI to a decoded ZIP name, excluding query/fragment.
  /// Returns null for external or empty paths; malformed URIs throw invalidUri.
  static String? archivePath(String href) {
    if (isExternal(href)) return null;
    try {
      return normalizeArchivePath(
        Uri.decodeComponent(parse(resolve('', href)).path),
      );
    } on EpubException {
      rethrow;
    } on FormatException catch (error) {
      throw EpubException(EpubErrorCode.invalidUri, error.message, path: href);
    } on ArgumentError {
      throw EpubException(
        EpubErrorCode.invalidUri,
        'Invalid URI path encoding.',
        path: href,
      );
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
