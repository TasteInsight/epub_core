import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test('metadata retains repeats, refinements, vocabulary aliases and extensions', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String).replaceFirst(
      '<package ',
      '<package prefix="r: http://www.idpf.org/vocab/rendition/# ex: urn:custom:" xml:lang="zh" ',
    );
    addMetadata(
      files,
      '<dc:title id="main">中文主标题</dc:title><meta refines="#main" property="title-type">main</meta>'
      '<meta refines="#main" property="alternate-script" xml:lang="en">English Title</meta>'
      '<meta property="r:layout">pre-paginated</meta><meta property="ex:future">future value</meta>'
      '<dc:source>Original</dc:source><dc:relation>Related</dc:relation><dc:coverage>Global</dc:coverage>'
      '<custom:opaque xmlns:custom="urn:extension" value="one"><custom:child>Preserved</custom:child></custom:opaque>'
      '<link id="record" rel="record" href="records/book.xml" media-type="application/marc+xml"/>',
    );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.metadata.title, '中文主标题');
    expect(book.metadata.values('title'), ['A small book', '中文主标题']);
    expect(book.metadata.refinementsFor('main'), hasLength(2));
    expect(
      book.metadata.properties('urn:custom:future').single.value,
      'future value',
    );
    expect(
      book.metadata.entries
          .where((entry) => entry.name == 'opaque')
          .single
          .sourceXml,
      contains('custom:child'),
    );
    expect(book.metadata.links.single.href, 'OPS/records/book.xml');
    expect(book.metadata.creators.single.language, 'zh');
    expect(book.renditionSettings.layout, 'pre-paginated');
    expect(book.packageXml, files['OPS/package.opf']);
  });

  test('foreign metadata properties cannot override rendition settings', () {
    final files = epubFiles();
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String).replaceFirst(
      '</metadata>',
      '<ext:meta xmlns:ext="urn:extension" property="rendition:layout">pre-paginated</ext:meta></metadata>',
    );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.renditionSettings.layout, 'reflowable');
    expect(
      book.metadata.entries.any(
        (entry) => entry.namespaceUri == 'urn:extension',
      ),
      isTrue,
    );
  });

  test('EPUB2 legacy metadata wrappers retain DC fields', () {
    final files = epubFiles(version: '2.0');
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst('<dc:identifier', '<dc-metadata><dc:identifier')
        .replaceFirst(
          '<meta name="cover"',
          '</dc-metadata><x-metadata><meta name="cover"',
        )
        .replaceFirst('</metadata>', '</x-metadata></metadata>');
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.metadata.title, 'A small book');
    expect(book.metadata.creators.single.name, 'Writer');
  });
  test('large metadata retains ordered creators and indexed refinements', () {
    final files = epubFiles();
    const count = 4000;
    final additions = List.generate(
      count,
      (i) =>
          '<dc:creator id="a$i">Author $i</dc:creator>'
          '<meta property="role" refines="#a$i">aut</meta>',
    ).join();
    files['OPS/package.opf'] = (files['OPS/package.opf'] as String)
        .replaceFirst('</metadata>', '$additions</metadata>');
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.metadata.creators.length, count + 1);
    expect(book.metadata.creators.last.name, 'Author 3999');
    expect(
      book.metadata.creators.every((person) => person.role == 'aut'),
      isTrue,
    );
    for (var i = 0; i < count; i++) {
      expect(book.metadata.refinementsFor('a$i').single.value, 'aut');
    }
    expect(
      () => book.metadata.refinementsFor('a1').clear(),
      throwsUnsupportedError,
    );
  });
}
