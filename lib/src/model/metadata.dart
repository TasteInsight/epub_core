import '../vocabulary.dart';

/// An ordered metadata element, including extension elements and refinements.
final class EpubMetadataEntry {
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
  final String name;
  final String namespaceUri;
  final String value;
  final Map<String, String> attributes;
  final String sourceXml;
  final String? propertyIri;
  final String? language;
  final String? direction;

  /// Namespace-resolved EPUB 2 creator attributes.
  final String? legacyRole;
  final String? legacyFileAs;
  String? get id => attributes['id'];
  String? get property => attributes['property'];
  String? get refines => attributes['refines'];
  String? get scheme => attributes['scheme'];
}

/// A package, collection, or container link with its XML declaration.
final class EpubLink {
  EpubLink({
    required this.href,
    required this.sourceXml,
    required Map<String, String> attributes,
    required Set<String> rel,
  }) : attributes = Map.unmodifiable(attributes),
       rel = Set.unmodifiable(rel);
  final String href;
  final Set<String> rel;
  final Map<String, String> attributes;
  final String sourceXml;
  String? get id => attributes['id'];
  String? get mediaType => attributes['media-type'];
  String? get refines => attributes['refines'];
  String? get properties => attributes['properties'];
}

/// A creator or contributor and optional EPUB role/sort key.
final class EpubPerson {
  const EpubPerson(
    this.name, {
    this.role,
    this.fileAs,
    this.id,
    this.language,
    this.direction,
  });
  final String name;
  final String? role;
  final String? fileAs;
  final String? id;
  final String? language;
  final String? direction;
}

/// Title, creators and other Dublin Core fields,
/// with metadata entries in document order.
final class EpubMetadata {
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

  final List<EpubMetadataEntry> entries;
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
  List<EpubMetadataEntry> refinementsFor(String id) =>
      _refinements['#$id'] ?? const [];
  List<EpubMetadataEntry> properties(String propertyOrIri) =>
      _properties[propertyOrIri] ?? const [];
  final String title;
  final String? identifier;
  final List<String> identifiers;
  final List<EpubPerson> creators;
  final List<EpubPerson> contributors;
  final List<String> languages;
  final List<String> subjects;
  final String? description;
  final String? publisher;
  final String? rights;
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
