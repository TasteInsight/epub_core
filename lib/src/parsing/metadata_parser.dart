import 'package:xml/xml.dart';

import '../document/xml_document.dart';
import '../epub_path.dart';
import '../model/metadata.dart';
import '../model/package.dart';
import '../vocabulary.dart';

List<XmlElement> metadataElements(XmlElement metadata) => [
  for (final node in metadata.childElements)
    if (xmlIs(node, 'dc-metadata', opfNamespace) ||
        xmlIs(node, 'x-metadata', opfNamespace))
      ...node.childElements
    else
      node,
];

EpubMetadataEntry _metadataEntry(XmlElement node) => EpubMetadataEntry(
  name: node.name.local,
  namespaceUri: node.name.namespaceUri ?? '',
  value: node.innerText.trim(),
  attributes: xmlAttributes(node),
  sourceXml: xmlFragment(node).text,
  propertyIri: node.getAttribute('property') == null
      ? null
      : expandProperty(
          node.getAttribute('property')!,
          vocabularyPrefixes(node),
        ),
  language: inheritedXmlAttribute(node, 'lang', xmlNamespace),
  direction: inheritedDirection(node),
  legacyRole: xmlAttribute(node, 'role', opfNamespace),
  legacyFileAs: xmlAttribute(node, 'file-as', opfNamespace),
);

EpubMetadata readMetadata(
  XmlElement metadata,
  String? identifierId,
  String packagePath,
) {
  final nodes = metadataElements(metadata);
  return EpubMetadata.fromEntries(
    entries: nodes.map(_metadataEntry).toList(),
    identifierId: identifierId,
    links: [
      for (final node in nodes.where(
        (node) => xmlIs(node, 'link', opfNamespace),
      ))
        _readLink(node, packagePath),
    ],
  );
}

EpubLink _readLink(XmlElement node, String base) => EpubLink(
  href: EpubPath.resolve(
    elementBase(node, base),
    node.getAttribute('href') ?? '',
  ),
  sourceXml: xmlFragment(node).text,
  attributes: xmlAttributes(node),
  rel: tokens(node.getAttribute('rel')),
);

EpubCollection readCollection(XmlElement node, String path) {
  final metadata = xmlChild(node, 'metadata', opfNamespace);
  return EpubCollection(
    roles: tokens(node.getAttribute('role')),
    metadata: readMetadata(
      metadata ?? XmlElement(XmlName.parts('metadata')),
      null,
      path,
    ),
    links: xmlChildren(
      node,
      'link',
      opfNamespace,
    ).map((link) => _readLink(link, path)).toList(),
    children: xmlChildren(
      node,
      'collection',
      opfNamespace,
    ).map((child) => readCollection(child, path)).toList(),
    xmlFragment: xmlFragment(node),
    attributes: xmlAttributes(node),
  );
}

EpubRenditionSettings readRenditionSettings(
  EpubMetadata metadata, {
  Set<String> properties = const {},
  Map<String, String> prefixes = const {},
}) {
  String setting(String name, String fallback) {
    final global =
        metadata
            .properties('$renditionVocabulary$name')
            .where((entry) => entry.refines == null)
            .firstOrNull
            ?.value ??
        fallback;
    for (final property in properties) {
      final iri = expandProperty(
        property,
        prefixes,
        defaultVocabulary: 'http://idpf.org/epub/vocab/package/itemref/#',
      );
      if (iri.startsWith('$renditionVocabulary$name-')) {
        return iri.substring('$renditionVocabulary$name-'.length);
      }
    }
    return global;
  }

  final spread = properties
      .where(
        (property) =>
            property.startsWith('page-spread-') ||
            expandProperty(
              property,
              prefixes,
            ).startsWith('${renditionVocabulary}page-spread-'),
      )
      .firstOrNull;
  return EpubRenditionSettings(
    layout: setting('layout', 'reflowable'),
    orientation: setting('orientation', 'auto'),
    spread: setting('spread', 'auto'),
    flow: setting('flow', 'auto'),
    pageSpread: spread?.substring(
      spread.indexOf('page-spread-') + 'page-spread-'.length,
    ),
  );
}
