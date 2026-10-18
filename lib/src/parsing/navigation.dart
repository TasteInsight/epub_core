import 'package:html/dom.dart' as dom;
import 'package:xml/xml.dart';

import '../archive/resource_archive.dart';
import '../document/html_document.dart';
import '../document/xml_document.dart';
import '../epub_path.dart';
import '../errors.dart';
import '../model/navigation.dart';
import '../model/package.dart';
import '../model/xml_source.dart';
import '../vocabulary.dart';

EpubNavigation readNavigation(
  ResourceArchive archive,
  List<EpubManifestItem> manifest,
  EpubManifestItem? spineNcx,
  List<EpubDiagnostic> diagnostics,
) {
  final candidates = {
    ...manifest.where((item) => item.properties.contains('nav')),
    ?spineNcx,
    ...manifest.where((item) => item.mediaType == 'application/x-dtbncx+xml'),
  };
  final sections = <EpubNavigationSection>[];
  final documents = <String, String>{};
  for (final item in candidates) {
    try {
      final source = archive.readText(item.href);
      if (source == null) {
        throw EpubException(
          EpubErrorCode.missingResource,
          'Navigation resource is missing.',
          path: item.href,
        );
      }
      documents[item.href] = source;
      List<EpubNavigationSection> parsed;
      if (item.mediaType == 'application/x-dtbncx+xml') {
        final root = parseEpubXml(
          source,
          item.href,
          archive.limits,
        ).rootElement;
        parsed = [
          for (final list in root.childElements)
            if (xmlIs(list, 'navMap', ncxNamespace) ||
                xmlIs(list, 'pageList', ncxNamespace) ||
                xmlIs(list, 'navList', ncxNamespace))
              EpubNavigationSection(
                types: {
                  switch (list.name.local) {
                    'navMap' => 'toc',
                    'pageList' => 'page-list',
                    _ => 'nav-list',
                  },
                },
                title: _ncxLabel(list),
                href: item.href,
                sourceXml: xmlFragment(list).text,
                isNcx: true,
                items: _ncxNodes(list, item.href, switch (list.name.local) {
                  'navMap' => 'navPoint',
                  'pageList' => 'pageTarget',
                  _ => 'navTarget',
                }),
              ),
        ];
      } else {
        try {
          final doc = parseEpubXml(source, item.href, archive.limits);
          parsed = _xhtmlNavigation(doc, item.href);
        } on EpubException catch (error) {
          if (error.code != EpubErrorCode.invalidXml) rethrow;
          diagnostics.add(
            EpubDiagnostic(
              'htmlNavigationRecovery',
              error.message,
              path: item.href,
            ),
          );
          parsed = _htmlNavigation(
            parseEpubHtml(
              source,
              item.href,
              archive.limits,
              generateSpans: true,
            ),
            item.href,
            source,
          );
        }
      }
      sections.addAll(parsed);
      if (!parsed.any(
        (section) => section.types.contains('toc') && section.items.isNotEmpty,
      )) {
        diagnostics.add(
          EpubDiagnostic(
            'missingToc',
            'Navigation has no table of contents.',
            path: item.href,
          ),
        );
      }
    } on EpubException catch (error) {
      diagnostics.add(error.toDiagnostic());
    }
  }
  return EpubNavigation(sections: sections, documents: documents);
}

String _ncxLabel(XmlElement node) =>
    xmlChild(
      xmlChild(node, 'navLabel', ncxNamespace) ?? node,
      'text',
      ncxNamespace,
    )?.innerText.trim() ??
    '';
List<EpubNavItem> _ncxNodes(XmlElement parent, String href, String tag) => [
  for (final node in xmlChildren(parent, tag, ncxNamespace))
    EpubNavItem(
      title: _ncxLabel(node),
      href: _navigationHref(
        elementBase(node, href),
        xmlChild(node, 'content', ncxNamespace)?.getAttribute('src'),
      ),
      children: _ncxNodes(node, href, tag),
      attributes: xmlAttributes(node),
      xmlFragment: xmlFragment(node),
      types: tokens(node.getAttribute('class')),
    ),
];

List<EpubNavigationSection> _xhtmlNavigation(XmlDocument doc, String href) {
  final baseElement = doc.descendantElements
      .where((node) => xmlIs(node, 'base', xhtmlNamespace))
      .firstOrNull;
  final base = baseElement?.getAttribute('href');
  final documentHref = base == null
      ? href
      : EpubPath.resolve(elementBase(baseElement!, href), base);
  return [
    for (final nav in doc.descendantElements.where(
      (node) => xmlIs(node, 'nav', xhtmlNamespace),
    ))
      EpubNavigationSection(
        types: _navTypes(nav),
        title:
            nav.childElements
                .where(
                  (node) => const {
                    'h1',
                    'h2',
                    'h3',
                    'h4',
                    'h5',
                    'h6',
                  }.contains(node.name.local),
                )
                .map(_xmlLabel)
                .firstOrNull ??
            '',
        href: href,
        items: [
          for (final list in xmlChildren(nav, 'ol', xhtmlNamespace))
            ..._xmlNavList(list, documentHref),
        ],
        sourceXml: xmlFragment(nav).text,
      ),
  ];
}

Set<String> _navTypes(XmlElement node) {
  final types = tokens(
    xmlAttribute(node, 'type', epubNamespace) ??
        node.attributes
            .where(
              (attribute) =>
                  attribute.name.qualified == 'epub:type' &&
                  (attribute.name.namespaceUri == null ||
                      attribute.name.namespaceUri == ''),
            )
            .firstOrNull
            ?.value,
  );
  if (tokens(node.getAttribute('role')).contains('doc-toc')) types.add('toc');
  return types;
}

List<EpubNavItem> _xmlNavList(XmlElement list, String href) => [
  for (final node in xmlChildren(list, 'li', xhtmlNamespace))
    _xmlNavItem(node, href),
];
EpubNavItem _xmlNavItem(XmlElement node, String href) {
  final label = node.childElements
      .where(
        (child) =>
            xmlIs(child, 'a', xhtmlNamespace) ||
            xmlIs(child, 'span', xhtmlNamespace),
      )
      .firstOrNull;
  return EpubNavItem(
    title: label == null ? '' : _xmlLabel(label),
    href: label == null
        ? null
        : _navigationHref(elementBase(label, href), label.getAttribute('href')),
    children: [
      for (final list in xmlChildren(node, 'ol', xhtmlNamespace))
        ..._xmlNavList(list, href),
    ],
    types: label == null
        ? _navTypes(node)
        : {..._navTypes(node), ..._navTypes(label)},
    attributes: xmlAttributes(node),
    xmlFragment: xmlFragment(node),
  );
}

String _xmlLabel(XmlElement label) {
  String visit(XmlNode node) {
    if (node is XmlText || node is XmlCDATA) return node.value ?? '';
    if (node is! XmlElement) return '';
    if (node.name.local == 'img') {
      return node.getAttribute('alt') ?? node.getAttribute('title') ?? '';
    }
    if (node.name.local == 'math' && node.getAttribute('alttext') != null) {
      return node.getAttribute('alttext')!;
    }
    final text = node.children.map(visit).join();
    return text.isEmpty ? node.getAttribute('title') ?? '' : text;
  }

  return visit(label).replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<EpubNavigationSection> _htmlNavigation(
  dom.Document document,
  String href,
  String source,
) {
  final base = document.querySelector('base[href]')?.attributes['href'];
  final documentHref = base == null ? href : EpubPath.resolve(href, base);
  return [
    for (final nav in document.querySelectorAll('nav'))
      EpubNavigationSection(
        types: {
          ...tokens(nav.attributes['epub:type']),
          if (tokens(nav.attributes['role']).contains('doc-toc')) 'toc',
        },
        title: nav.querySelector('h1,h2,h3,h4,h5,h6')?.text.trim() ?? '',
        href: href,
        sourceXml: nav.outerHtml,
        items: [
          for (final list in nav.children.where(
            (child) => child.localName == 'ol',
          ))
            ..._htmlNavList(list, documentHref, source),
        ],
      ),
  ];
}

List<EpubNavItem> _htmlNavList(
  dom.Element list,
  String href,
  String source,
) => [
  for (final node in list.children.where((child) => child.localName == 'li'))
    _htmlNavItem(node, href, source),
];
EpubNavItem _htmlNavItem(dom.Element node, String href, String source) {
  final label = node.children
      .where((child) => child.localName == 'a' || child.localName == 'span')
      .firstOrNull;
  final copy = label?.clone(true);
  for (final image in copy?.querySelectorAll('img') ?? <dom.Element>[]) {
    image.replaceWith(
      dom.Text(image.attributes['alt'] ?? image.attributes['title'] ?? ''),
    );
  }
  return EpubNavItem(
    title: (copy?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
    href: _navigationHref(href, label?.attributes['href']),
    children: [
      for (final list in node.children.where(
        (child) => child.localName == 'ol',
      ))
        ..._htmlNavList(list, href, source),
    ],
    types: tokens(label?.attributes['epub:type']),
    xmlFragment: EpubXmlFragment(
      source,
      node.sourceSpan?.start.offset ?? 0,
      node.endSourceSpan?.end.offset ?? source.length,
    ),
    attributes: {
      for (final attribute in node.attributes.entries)
        attribute.key.toString(): attribute.value,
    },
  );
}

String? _navigationHref(String base, String? reference) =>
    reference == null ? null : EpubPath.resolve(base, reference);
