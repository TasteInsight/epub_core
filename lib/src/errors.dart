/// Text against which a parser error position is measured.
enum EpubLocationSource { resource, expandedXml, entityReplacement }

/// Error codes returned by EPUB parsing and resource reads.
enum EpubErrorCode {
  invalidArchive,
  invalidUri,
  ambiguousReference,
  resourceLimit,
  missingResource,
  invalidXml,
  invalidPackage,
  unsupportedVersion,
  encryptedResource,
  invalidText,
  invalidMediaOverlay,
}

/// A malformed or unsupported publication, optionally tied to a resource.
final class EpubException extends FormatException {
  const EpubException(
    this.code,
    String message, {
    this.path,
    int? offset,
    this.line,
    this.column,
    this.locationSource = EpubLocationSource.resource,
    this.entityName,
  }) : super(message, null, offset);

  /// One-based coordinates; offset is zero-based in [locationSource].
  final int? line;
  final int? column;

  final EpubLocationSource locationSource;

  /// Entity whose replacement text contains the failure, when applicable.
  final String? entityName;

  EpubDiagnostic toDiagnostic() => EpubDiagnostic(
    code.name,
    message,
    path: path,
    offset: offset,
    line: line,
    column: column,
    locationSource: locationSource,
    entityName: entityName,
  );

  final EpubErrorCode code;
  final String? path;

  @override
  String toString() =>
      'EpubException(${code.name}${path == null ? '' : ', $path'}${line == null ? '' : ':$line:$column'}): $message';
}

/// A recoverable parsing issue with an error code and resource path.
final class EpubDiagnostic {
  const EpubDiagnostic(
    this.code,
    this.message, {
    this.path,
    this.offset,
    this.line,
    this.column,
    this.locationSource = EpubLocationSource.resource,
    this.entityName,
  });
  final int? offset;
  final int? line;
  final int? column;
  final EpubLocationSource locationSource;
  final String? entityName;
  final String code;
  final String message;
  final String? path;
  @override
  String toString() =>
      '$code${path == null ? '' : ' ($path)'}${line == null ? '' : ' at $line:$column'}: $message';
}
