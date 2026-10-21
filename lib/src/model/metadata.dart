import '../vocabulary.dart';

/// An ordered metadata element, including extension elements and refinements.
final class EpubMetadataEntry {
  /// Creates an ordered metadata entry retaining its source declaration.
  EpubMetadataEntry({
    required this.name,
    required this.namespaceUri,
    required this.value,
    required Map<String, String> attributes,
    required this.sourceXml,
    this.propertyIri,
    this.language,
    this.direction,
    this.legacyRole,
    this.legacyFileAs,
  }) : attributes = Map.unmodifiable(attributes);

  /// Local XML element name, such as title, creator, or meta.
  final String name;

  /// Resolved XML namespace of the element.
  final String namespaceUri;

  /// Text content of the metadata element.
  final String value;

  /// Parsed attributes keyed by qualified XML name, including DTD defaults.
  final Map<String, String> attributes;

  /// Metadata element markup after XML preprocessing.
  final String sourceXml;

  /// Property name expanded through the package vocabulary prefixes.
  final String? propertyIri;

  /// Effective xml:lang language tag, when declared.
  final String? language;

  /// Effective text direction, when declared.
  final String? direction;

  /// Namespace-resolved EPUB 2 creator attributes.
  final String? legacyRole;

  /// Namespace-resolved EPUB 2 sorting key.
  final String? legacyFileAs;

  /// Element identifier used as a refinement target.
  String? get id => attributes['id'];

  /// Literal property attribute before vocabulary expansion.
  String? get property => attributes['property'];

  /// URI reference to the metadata element being refined.
  String? get refines => attributes['refines'];

  /// Vocabulary or encoding scheme declared for this value.
  String? get scheme => attributes['scheme'];
}

/// A package, collection, or container link with its XML declaration.
final class EpubLink {
  /// Creates a metadata or container link and its relationship tokens.
  EpubLink({
    required this.href,
    required this.sourceXml,
    required Map<String, String> attributes,
    required Set<String> rel,
  }) : attributes = Map.unmodifiable(attributes),
       rel = Set.unmodifiable(rel);

  /// Link target URI resolved relative to the archive root.
  final String href;

  /// Declared link relationship tokens.
  final Set<String> rel;

  /// Parsed link attributes keyed by qualified XML name.
  final Map<String, String> attributes;

  /// Link element markup after XML preprocessing.
  final String sourceXml;

  /// Identifier of the link declaration.
  String? get id => attributes['id'];

  /// Declared MIME type of the linked resource.
  String? get mediaType => attributes['media-type'];

  /// URI reference to the metadata element being refined.
  String? get refines => attributes['refines'];

  /// Literal properties attribute from the link declaration.
  String? get properties => attributes['properties'];
}

/// A creator or contributor and optional EPUB role/sort key.
final class EpubPerson {
  /// Creates a creator or contributor with optional role and sorting metadata.
  const EpubPerson(
    this.name, {
    this.role,
    this.fileAs,
    this.id,
    this.language,
    this.direction,
  });

  /// Display name from the creator or contributor element.
  final String name;

  /// Refined EPUB 3 role or legacy EPUB 2 role.
  final String? role;

  /// Refined or legacy sorting key for the person.
  final String? fileAs;

  /// Identifier of the source metadata element.
  final String? id;

  /// Effective language tag of the name.
  final String? language;

  /// Effective text direction of the name.
  final String? direction;
}

/// Title, creators and other Dublin Core fields,
/// with metadata entries in document order.
final class EpubMetadata {
  /// Creates metadata with explicitly supplied convenience fields.
  EpubMetadata({
    required this.title,
    required this.identifier,
    required List<String> identifiers,
    required List<EpubPerson> creators,
    required List<EpubPerson> contributors,
    required List<String> languages,
    required List<String> subjects,
    this.description,
    this.publisher,
    this.rights,
    this.date,
    List<EpubMetadataEntry> entries = const [],
    List<EpubLink> links = const [],
  }) : entries = List.unmodifiable(entries),
       links = List.unmodifiable(links),
       identifiers = List.unmodifiable(identifiers),
       creators = List.unmodifiable(creators),
       contributors = List.unmodifiable(contributors),
       languages = List.unmodifiable(languages),
       subjects = List.unmodifiable(subjects);

  /// Extracts the title, creators and other fields from metadata entries.
  factory EpubMetadata.fromEntries({
    required List<EpubMetadataEntry> entries,
    List<EpubLink> links = const [],
    String? identifierId,
  }) {
    final dc = _group(
      entries.where((e) => e.namespaceUri == dcNamespace),
      (e) => e.name,
    );
    final refinements = _group(
      entries.where(_isMeta).where((e) => e.refines != null),
      (e) => e.refines!,
    );
    String? refinement(EpubMetadataEntry entry, String property) =>
        entry.id == null
        ? null
        : (refinements['#${entry.id}'] ?? const <EpubMetadataEntry>[])
              .where((e) => e.propertyIri == '$metadataVocabulary$property')
              .firstOrNull
              ?.value;
    List<String> values(String name) =>
        (dc[name] ?? const <EpubMetadataEntry>[])
            .map((e) => e.value)
            .where((value) => value.isNotEmpty)
            .toList();
    List<EpubPerson> people(String name) => [
      for (final entry in dc[name] ?? const <EpubMetadataEntry>[])
        if (entry.value.isNotEmpty)
          EpubPerson(
            entry.value,
            id: entry.id,
            role: refinement(entry, 'role') ?? entry.legacyRole,
            fileAs: refinement(entry, 'file-as') ?? entry.legacyFileAs,
            language: entry.language,
            direction: entry.direction,
          ),
    ];
    final titles = dc['title'] ?? const <EpubMetadataEntry>[];
    final title =
        titles
            .where((e) => refinement(e, 'title-type') == 'main')
            .firstOrNull ??
        titles.firstOrNull;
    final ids = dc['identifier'] ?? const <EpubMetadataEntry>[];
    return EpubMetadata(
      title: title?.value ?? '',
      identifier:
          ids
              .where((e) => identifierId != null && e.id == identifierId)
              .firstOrNull
              ?.value ??
          values('identifier').firstOrNull,
      identifiers: values('identifier'),
      creators: people('creator'),
      contributors: people('contributor'),
      languages: values('language'),
      subjects: values('subject'),
      description: values('description').firstOrNull,
      publisher: values('publisher').firstOrNull,
      rights: values('rights').firstOrNull,
      date: values('date').firstOrNull,
      entries: entries,
      links: links,
    );
  }

  /// All metadata elements in document order, including extensions.
  final List<EpubMetadataEntry> entries;

  /// Links declared alongside the metadata entries.
  final List<EpubLink> links;
  late final Map<String, List<EpubMetadataEntry>> _dc = _group(
    entries.where((entry) => entry.namespaceUri == dcNamespace),
    (entry) => entry.name,
  );
  late final Map<String, List<EpubMetadataEntry>> _refinements = _group(
    entries.where(_isMeta).where((entry) => entry.refines != null),
    (entry) => entry.refines!,
  );
  late final Map<String, List<EpubMetadataEntry>> _properties = () {
    final grouped = <String, List<EpubMetadataEntry>>{};
    for (final entry in entries.where(_isMeta)) {
      for (final key in {entry.property, entry.propertyIri}.nonNulls) {
        grouped.putIfAbsent(key, () => []).add(entry);
      }
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List<EpubMetadataEntry>.unmodifiable(entry.value),
    };
  }();

  /// All Dublin Core values, in document order, including empty declarations.
  List<String> values(String localName) => List.unmodifiable(
    (_dc[localName] ?? const []).map((entry) => entry.value),
  );

  /// Metadata refinements targeting the element with the supplied [id].
  List<EpubMetadataEntry> refinementsFor(String id) =>
      _refinements['#$id'] ?? const [];

  /// Meta entries matching a literal property name or expanded IRI.
  List<EpubMetadataEntry> properties(String propertyOrIri) =>
      _properties[propertyOrIri] ?? const [];

  /// Main title selected from the Dublin Core title entries.
  final String title;

  /// Publication identifier selected by unique-identifier, when available.
  final String? identifier;

  /// Dublin Core identifier values in document order.
  final List<String> identifiers;

  /// Creators in document order with resolved roles and sorting keys.
  final List<EpubPerson> creators;

  /// Contributors in document order with resolved role metadata.
  final List<EpubPerson> contributors;

  /// Dublin Core language values in document order.
  final List<String> languages;

  /// Dublin Core subject values in document order.
  final List<String> subjects;

  /// First nonempty Dublin Core description, when available.
  final String? description;

  /// First nonempty Dublin Core publisher, when available.
  final String? publisher;

  /// First nonempty Dublin Core rights statement, when available.
  final String? rights;

  /// First nonempty Dublin Core date value, retained as text.
  final String? date;
}

bool _isMeta(EpubMetadataEntry entry) =>
    entry.name == 'meta' && entry.namespaceUri == opfNamespace;
Map<String, List<EpubMetadataEntry>> _group(
  Iterable<EpubMetadataEntry> entries,
  String Function(EpubMetadataEntry) key,
) {
  final result = <String, List<EpubMetadataEntry>>{};
  for (final entry in entries) {
    result.putIfAbsent(key(entry), () => []).add(entry);
  }
  return {
    for (final entry in result.entries)
      entry.key: List<EpubMetadataEntry>.unmodifiable(entry.value),
  };
}
