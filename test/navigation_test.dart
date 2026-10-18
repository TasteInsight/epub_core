import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test('all XHTML navigation types and image labels are preserved', () {
    final files = epubFiles();
    files['OPS/nav.xhtml'] =
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:e="http://www.idpf.org/2007/ops"><body>'
        '<nav e:type="toc"><h1>目录</h1><ol><li><a href="text/one.xhtml"><img alt="第一章"/></a></li></ol></nav>'
        '<nav e:type="page-list"><ol><li><a href="text/one.xhtml#p1">1</a></li></ol></nav>'
        '<nav e:type="landmarks"><ol><li><a e:type="bodymatter" href="text/one.xhtml">Start</a></li></ol></nav>'
        '<nav e:type="loi"><ol><li><a href="text/one.xhtml#image">Illustrations</a></li></ol></nav></body></html>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.navigation.single.title, '第一章');
    expect(book.readingNavigation.pageList.single.href, endsWith('#p1'));
    expect(book.readingNavigation.landmarks.single.types, {'bodymatter'});
    expect(
      book.readingNavigation.itemsFor('loi').single.title,
      'Illustrations',
    );
    expect(book.readingNavigation.sections.first.title, '目录');
    expect(
      book.readingNavigation.documents['OPS/nav.xhtml'],
      files['OPS/nav.xhtml'],
    );
  });

  test('NCX pageList and navList coexist with hierarchical TOC', () {
    final files = epubFiles(version: '2.0');
    files['OPS/toc.ncx'] = (files['OPS/toc.ncx']! as String).replaceFirst(
      '</ncx>',
      '<pageList><navLabel><text>Pages</text></navLabel><pageTarget id="p" value="1" type="normal"><navLabel><text>1</text></navLabel><content src="text/one.xhtml#p1"/></pageTarget></pageList>'
          '<navList class="figures"><navLabel><text>Figures</text></navLabel><navTarget><navLabel><text>Figure 1</text></navLabel><content src="text/one.xhtml#fig1"/></navTarget></navList></ncx>',
    );
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.navigation.single.children, hasLength(1));
    expect(book.readingNavigation.pageList.single.attributes['value'], '1');
    expect(
      book.readingNavigation.itemsFor('nav-list').single.title,
      'Figure 1',
    );
  });

  test(
    'deep optional navigation produces diagnostics and keeps readable spine',
    () {
      final files = epubFiles(version: '2.0');
      files['OPS/toc.ncx'] =
          '<ncx><navMap>${'<navPoint><navLabel><text>Level</text></navLabel>' * 1000}${'</navPoint>' * 1000}</navMap></ncx>';
      final book = EpubBook.fromBytes(zipFiles(files));
      expect(book.navigation, isEmpty);
      expect(
        book.diagnostics.any(
          (diagnostic) => diagnostic.code == 'resourceLimit',
        ),
        isTrue,
      );
      expect(book.readString(book.spine.first.item.href), contains('Hello'));
    },
  );

  test('XHTML and EPUB namespace prefixes may vary', () {
    final files = epubFiles()..remove('OPS/toc.ncx');
    files['OPS/nav.xhtml'] =
        '<h:html xmlns:h="http://www.w3.org/1999/xhtml" xmlns:ops="http://www.idpf.org/2007/ops">'
        '<h:body><h:nav ops:type="toc"><h:ol><h:li><h:a href="text/one.xhtml">Chapter</h:a></h:li></h:ol></h:nav></h:body></h:html>';
    expect(
      EpubBook.fromBytes(zipFiles(files)).navigation.single.title,
      'Chapter',
    );
  });

  test('nested navigation source fragments share a single document', () {
    final files = epubFiles();
    final label = 'x' * 200000;
    files['OPS/nav.xhtml'] =
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:e="http://www.idpf.org/2007/ops"><body><nav e:type="toc">'
        '${'<ol><li><span>Group</span>' * 110}<ol><li><a href="text/one.xhtml">$label</a></li></ol>${'</li></ol>' * 110}</nav></body></html>';
    final book = EpubBook.fromBytes(zipFiles(files));
    var node = book.navigation.single;
    final document = node.xmlFragment!.document;
    var count = 0;
    while (true) {
      count++;
      expect(identical(node.xmlFragment!.document, document), isTrue);
      expect(node.xmlFragment!.end, lessThanOrEqualTo(document.length));
      if (node.children.isEmpty) break;
      node = node.children.single;
    }
    expect(count, 111);
    expect(node.sourceXml, contains(label));
  });
}
