/// Text against which a parser error position is measured.
enum EpubLocationSource {
  /// Original text decoded from the publication resource.
  resource,

  /// XML text after entity expansion and preprocessing.
  expandedXml,

  /// Replacement text of the entity identified by entityName.
  entityReplacement,
}

/// Error codes returned by EPUB parsing and resource reads.
enum EpubErrorCode {
  /// The ZIP archive has a structure or feature compatibility error.
  invalidArchive,

  /// A resource reference contains a malformed URI or path encoding.
  invalidUri,

  /// A configured archive, resource, or document limit was exceeded.
  resourceLimit,

  /// A required publication resource is absent from the archive.
  missingResource,

  /// An XML document is malformed or violates XML parsing constraints.
  invalidXml,

  /// An OPF or container declaration has an invalid structure or reference.
  invalidPackage,

  /// The package declares an EPUB version outside the supported range.
  unsupportedVersion,

  /// The resource requires an external decoder or a valid deobfuscation key.
  encryptedResource,

  /// The resource encoding or byte sequence causes a text decoding error.
  invalidText,

  /// A SMIL declaration or clock value is invalid.
  invalidMediaOverlay,
}

/// A publication parsing or resource-access failure with optional source context.
final class EpubException extends FormatException {
  /// Creates a parsing failure with optional resource and source coordinates.
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

  /// One-based column within the text identified by [locationSource].
  final int? column;

  /// Text against which offset, [line], and [column] are measured.
  final EpubLocationSource locationSource;

  /// Entity whose replacement text contains the failure, when applicable.
  final String? entityName;

  /// Converts this failure into a recoverable diagnostic with its coordinates.
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

  /// Machine-readable category of the parsing failure.
  final EpubErrorCode code;

  /// Resource path or URI associated with the failure, when available.
  final String? path;

  @override
  String toString() =>
      'EpubException(${code.name}${path == null ? '' : ', $path'}${line == null ? '' : ':$line:$column'}): $message';
}

/// A recoverable parsing issue with an error code and resource path.
final class EpubDiagnostic {
  /// Creates a recoverable issue with optional resource and source coordinates.
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

  /// Zero-based Dart string offset within [locationSource].
  final int? offset;

  /// One-based source line, when supplied by the parser.
  final int? line;

  /// One-based source column, when supplied by the parser.
  final int? column;

  /// Text against which the stored source coordinates are measured.
  final EpubLocationSource locationSource;

  /// Entity whose replacement text contains this issue, when applicable.
  final String? entityName;

  /// Machine-readable issue category.
  final String code;

  /// Human-readable description of the issue.
  final String message;

  /// Resource path or URI associated with the issue, when available.
  final String? path;
  @override
  String toString() =>
      '$code${path == null ? '' : ' ($path)'}${line == null ? '' : ' at $line:$column'}: $message';
}
