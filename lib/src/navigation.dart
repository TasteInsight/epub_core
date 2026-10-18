part of 'epub_book.dart';

List<EpubNavItem> _readNavigation(
  ResourceArchive archive,
  List<EpubManifestItem> manifest,
  EpubManifestItem? spineNcx,
  List<String> warnings,
) {
  final candidates = {
    ...manifest.where((item) => item.properties.contains('nav')),
    ?spineNcx,
    ...manifest.where((item) => item.mediaType == 'application/x-dtbncx+xml'),
  };
  for (final item in candidates) {
    try {
      final List<EpubNavItem> toc;
      if (item.mediaType == 'application/x-dtbncx+xml') {
        final root = _xml(archive, item.href).rootElement;
        final map = _child(root, 'navMap');
        toc = map == null ? [] : _readNcxNodes(map, item.href);
      } else {
        final source = archive.readText(item.href);
        if (source == null) {
          throw EpubException(
            EpubErrorCode.missingResource,
            'Navigation resource is missing.',
            path: item.href,
          );
        }
        final document = html.parse(source);
        final base = document.querySelector('base[href]')?.attributes['href'];
        final documentHref = base == null
            ? item.href
            : EpubPath.resolve(item.href, base);
        final nav = document.querySelectorAll('nav').where((node) {
          final type =
              node.attributes['epub:type'] ??
              node.attributes[const dom.AttributeName(
                'epub',
                'type',
                'http://www.idpf.org/2007/ops',
              )];
          return _tokens(type).contains('toc') ||
              _tokens(node.attributes['role']).contains('doc-toc');
        }).firstOrNull;
        final list = nav?.children
            .where((child) => child.localName == 'ol')
            .firstOrNull;
        toc = list == null ? [] : _readNavList(list, documentHref);
      }
      if (toc.isNotEmpty) return toc;
      warnings.add('Navigation has no table of contents: ${item.href}');
    } on EpubException catch (error) {
      warnings.add(error.toString());
    }
  }
  return [];
}

List<EpubNavItem> _readNcxNodes(XmlElement parent, String href) => [
  for (final point in _children(parent, 'navPoint'))
    EpubNavItem(
      title:
          _child(
            _child(point, 'navLabel') ?? point,
            'text',
          )?.innerText.trim() ??
          '',
      href: _navigationHref(
        href,
        _child(point, 'content')?.getAttribute('src'),
      ),
      children: _readNcxNodes(point, href),
    ),
];

List<EpubNavItem> _readNavList(dom.Element list, String href) => [
  for (final item in list.children.where((child) => child.localName == 'li'))
    _readNavItem(item, href),
];

EpubNavItem _readNavItem(dom.Element item, String href) {
  final label = item.children
      .where((child) => child.localName == 'a' || child.localName == 'span')
      .firstOrNull;
  return EpubNavItem(
    title: _navigationLabel(label),
    href: _navigationHref(href, label?.attributes['href']),
    children: [
      for (final list in item.children.where(
        (child) => child.localName == 'ol',
      ))
        ..._readNavList(list, href),
    ],
  );
}

String? _navigationHref(String documentHref, String? reference) =>
    reference == null ? null : EpubPath.resolve(documentHref, reference);

String _navigationLabel(dom.Element? label) {
  if (label == null) return '';
  final copy = label.clone(true);
  for (final image in copy.querySelectorAll('img')) {
    image.replaceWith(
      dom.Text(image.attributes['alt'] ?? image.attributes['title'] ?? ''),
    );
  }
  return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
