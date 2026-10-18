import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test(
    'spine keeps original foreign resource, fallback chain and layout overrides',
    () {
      final files = epubFiles();
      addMetadata(
        files,
        '<meta property="rendition:layout">pre-paginated</meta><meta property="rendition:orientation">landscape</meta>',
      );
      addManifest(
        files,
        '<item id="foreign" href="foreign.xml" media-type="application/custom+xml" fallback="one"/>',
      );
      files['OPS/package.opf'] = (files['OPS/package.opf']! as String).replaceFirst(
        '<itemref idref="one"/>',
        '<itemref id="entry" idref="foreign" properties="rendition:layout-reflowable page-spread-left"/>',
      );
      final book = EpubBook.fromBytes(zipFiles(files));
      final entry = book.spine.first;
      expect(entry.sourceItem.id, 'foreign');
      expect(entry.item.id, 'one');
      expect(entry.fallbackChain.map((item) => item.id), ['foreign', 'one']);
      expect(entry.renditionSettings.layout, 'reflowable');
      expect(entry.renditionSettings.orientation, 'landscape');
      expect(entry.renditionSettings.pageSpread, 'left');
      expect(entry.attributes['id'], 'entry');
    },
  );

  test('guide, bindings and nested collections retain associations', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String).replaceFirst(
      '</package>',
      '<guide><reference type="text" title="Start" href="text/one.xhtml#start"/></guide>'
          '<bindings><mediaType media-type="application/custom" handler="one"/></bindings>'
          '<collection role="index" xml:lang="en"><metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Index</dc:title></metadata>'
          '<link rel="record" href="index.xhtml"/><collection role="index-group"><link href="group.xhtml"/></collection></collection></package>',
    );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.guide.single.href, 'OPS/text/one.xhtml#start');
    expect(book.bindings.single.handler, 'one');
    expect(book.collections.single.roles, {'index'});
    expect(book.collections.single.metadata.title, 'Index');
    expect(
      book.collections.single.children.single.links.single.href,
      'OPS/group.xhtml',
    );
  });

  test('unrecognized numeric versions retain data with a diagnostic', () {
    final book = EpubBook.fromBytes(epubBytes(version: '0'));
    expect(book.metadata.title, 'A small book');
    expect(book.version, '0');
    expect(
      book.diagnostics.any((item) => item.code == 'unrecognizedVersion'),
      isTrue,
    );
  });

  test('foreign spine content without a renderer stays accessible', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst(
          'href="text/one.xhtml" media-type="application/xhtml+xml"',
          'href="text/one.xhtml" media-type="application/custom+xml"',
        );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.spine.first.sourceItem, book.spine.first.item);
    expect(book.spine.first.item.mediaType, 'application/custom+xml');
    expect(book.readString(book.spine.first.item.href), contains('Hello'));
    expect(
      book.diagnostics.any((item) => item.code == 'unsupportedSpineContent'),
      isTrue,
    );
  });

  test('EPUB2 DTBook spine resources remain readable', () {
    final files = epubFiles(version: '2.0');
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst(
          'href="text/one.xhtml" media-type="application/xhtml+xml"',
          'href="text/one.xhtml" media-type="application/x-dtbook+xml"',
        );
    expect(
      EpubBook.fromBytes(zipFiles(files)).spine.first.item.mediaType,
      'application/x-dtbook+xml',
    );
  });

  test(
    'a foreign namespace bound to the epub prefix is not a TOC declaration',
    () {
      final files = epubFiles()..remove('OPS/toc.ncx');
      files['OPS/nav.xhtml'] =
          '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="urn:extension"><body><nav epub:type="toc"><ol><li><a href="text/one.xhtml">Wrong</a></li></ol></nav></body></html>';
      expect(EpubBook.fromBytes(zipFiles(files)).navigation, isEmpty);
    },
  );
}
