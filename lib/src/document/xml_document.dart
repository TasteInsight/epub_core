import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../epub_path.dart';
import '../errors.dart';
import '../limits.dart';
import '../model/xml_source.dart';
import '../vocabulary.dart';
import 'xml_entities.dart';
import 'xml_error.dart';

XmlDocument parseEpubXml(String source, String path, EpubLimits limits) {
  final original = source;
  try {
    final prepared = expandInternalEntities(source, path, limits);
    source = prepared.source;
    var depth = 0;
    var count = 0;
    var htmlEntities = false;
    final spans = <(int, int)>[];
    final stack = <int>[];
    for (final event in parseEvents(
      source,
      validateNesting: true,
      withLocation: true,
    )) {
      if (++count > limits.maxXmlNodes) {
        throw EpubException(
          EpubErrorCode.resourceLimit,
          'XML exceeds maxXmlNodes.',
          path: path,
        );
      }
      if (event is XmlDoctypeEvent) {
        final publicId = event.externalId?.publicId ?? '';
        htmlEntities =
            publicId.startsWith('-//W3C//DTD XHTML ') &&
            publicId.endsWith('//EN');
      }
      if (event is XmlStartElementEvent) {
        if (++depth > limits.maxXmlDepth) {
          throw EpubException(
            EpubErrorCode.resourceLimit,
            'XML exceeds maxXmlDepth.',
            path: path,
          );
        }
        final index = spans.length;
        spans.add((event.start!, event.stop!));
        if (event.isSelfClosing) {
          depth--;
        } else {
          stack.add(index);
        }
      } else if (event is XmlEndElementEvent) {
        depth--;
        final index = stack.removeLast();
        spans[index] = (spans[index].$1, event.stop!);
      }
    }
    final mapping = htmlEntities
        ? const XmlDefaultEntityMapping.html()
        : const XmlDefaultEntityMapping.xml();
    final document = XmlDocument.parse(source, entityMapping: mapping);
    var index = 0;
    var expansionBytes = prepared.expansionBytes;
    for (final node in document.descendantElements) {
      final defaults =
          prepared.attributes[node.name.qualified] ?? <DtdAttribute>[];
      // DTD declarations also produce work and attributes during DOM construction.
      count += defaults.length;
      if (count > limits.maxXmlNodes) {
        throw EpubException(
          EpubErrorCode.resourceLimit,
          'DTD attribute applications exceed maxXmlNodes.',
          path: path,
        );
      }
      for (final attribute in defaults) {
        var value = node.getAttribute(attribute.name);
        if (value == null && attribute.value != null) {
          expansionBytes += attribute.value!.length * 2;
          if (expansionBytes > limits.maxEntityExpansionBytes) {
            throw EpubException(
              EpubErrorCode.resourceLimit,
              'DTD generated text exceeds maxEntityExpansionBytes.',
              path: path,
            );
          }
          value = mapping.decode(attribute.value!);
        }
        if (value == null) continue;
        if (!attribute.cdata) {
          value = value.replaceAll(RegExp(r'[ \t\r\n]+'), ' ').trim();
        }
        node.setAttribute(attribute.name, value);
      }

      final span = spans[index++];
      _xmlFragments[node] = EpubXmlFragment(source, span.$1, span.$2);
    }
    return document;
  } on XmlException catch (error) {
    throw xmlFailure(
      error,
      path,
      locationSource: source == original
          ? EpubLocationSource.resource
          : EpubLocationSource.expandedXml,
    );
  }
}

final _xmlFragments = Expando<EpubXmlFragment>();
EpubXmlFragment xmlFragment(XmlElement node) =>
    _xmlFragments[node] ??
    (() {
      final text = node.toXmlString();
      return EpubXmlFragment(text, 0, text.length);
    })();

bool xmlIs(XmlElement node, String name, String namespace) {
  if (node.name.local != name) return false;
  final uri = node.name.namespaceUri;
  if (uri == namespace) return true;
  if (uri != null && uri.isNotEmpty) return false;
  // Recovery for a wholly unnamespaced document does not make a nested
  // xmlns="" extension in a standards-namespaced document into a core element.
  final root = node.root;
  final element = root is XmlDocument
      ? root.rootElement
      : root is XmlElement
      ? root
      : null;
  final rootNamespace = element?.name.namespaceUri;
  return rootNamespace == null || rootNamespace.isEmpty;
}

Iterable<XmlElement> xmlChildren(
  XmlElement parent,
  String name,
  String namespace,
) => parent.childElements.where((node) => xmlIs(node, name, namespace));
XmlElement? xmlChild(XmlElement parent, String name, String namespace) =>
    xmlChildren(parent, name, namespace).firstOrNull;
String? xmlAttribute(XmlElement node, String name, String namespace) => node
    .attributes
    .where(
      (attr) => attr.name.local == name && attr.name.namespaceUri == namespace,
    )
    .firstOrNull
    ?.value;
Map<String, String> xmlAttributes(XmlElement node) => {
  for (final attr in node.attributes) attr.name.qualified: attr.value,
};
String? inheritedXmlAttribute(XmlElement node, String name, String namespace) {
  for (
    XmlNode? current = node;
    current is XmlElement;
    current = current.parent
  ) {
    final value = xmlAttribute(current, name, namespace);
    if (value != null) return value;
  }
  return null;
}

String? inheritedDirection(XmlElement node) {
  for (
    XmlNode? current = node;
    current is XmlElement;
    current = current.parent
  ) {
    final value = current.getAttribute('dir');
    if (value != null) return value;
  }
  return null;
}

String elementBase(XmlElement node, String documentHref) {
  final lineage = <XmlElement>[];
  for (
    XmlNode? current = node;
    current is XmlElement;
    current = current.parent
  ) {
    lineage.add(current);
  }
  var base = documentHref;
  for (final element in lineage.reversed) {
    final value = xmlAttribute(element, 'base', xmlNamespace);
    if (value != null) base = EpubPath.resolve(base, value);
  }
  return base;
}

Set<String> tokens(String? value) => (value ?? '')
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toSet();

Map<String, String> vocabularyPrefixes(XmlElement node) {
  final result = <String, String>{
    'dcterms': 'http://purl.org/dc/terms/',
    'media': 'http://www.idpf.org/epub/vocab/overlays/#',
    'rendition': renditionVocabulary,
    'schema': 'http://schema.org/',
    'marc': 'http://id.loc.gov/vocabulary/',
    'xsd': 'http://www.w3.org/2001/XMLSchema#',
    'onix': 'http://www.editeur.org/ONIX/book/codelists/current.html#',
    'a11y': 'http://www.idpf.org/epub/vocab/package/a11y/#',
  };
  final parents = <XmlElement>[];
  for (
    XmlNode? current = node;
    current is XmlElement;
    current = current.parent
  ) {
    parents.add(current);
  }
  for (final parent in parents.reversed) {
    final value =
        parent.getAttribute('prefix') ??
        xmlAttribute(parent, 'prefix', epubNamespace) ??
        '';
    for (final match in RegExp(r'([^\s:]+):\s+(\S+)').allMatches(value)) {
      result[match[1]!] = match[2]!;
    }
  }
  return Map.unmodifiable(result);
}

String expandProperty(
  String value,
  Map<String, String> prefixes, {
  String defaultVocabulary = metadataVocabulary,
}) {
  final colon = value.indexOf(':');
  if (colon < 0) return '$defaultVocabulary$value';
  final prefix = prefixes[value.substring(0, colon)];
  return prefix == null ? value : '$prefix${value.substring(colon + 1)}';
}
