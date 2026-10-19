import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test(
    'XML/MathML/SVG/CSS resources and remote manifest declarations remain accessible',
    () {
      final files = epubFiles();
      addManifest(
        files,
        '<item id="css" href="styles/main.css" media-type="text/css"/>'
        '<item id="remote" href="https://example.org/audio.mp3" media-type="audio/mpeg"/>',
      );
      files['OPS/styles/main.css'] =
          '@font-face { font-family: Book; src: url(../font.otf); } p { color: red; }';
      files['OPS/text/one.xhtml'] =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math><svg xmlns="http://www.w3.org/2000/svg"><circle r="2"/></svg></body></html>';
      final book = EpubBook.fromBytes(zipFiles(files));
      expect(
        book
            .readXmlDocument('OPS/text/one.xhtml')!
            .descendantElements
            .where((node) => node.name.local == 'math')
            .single
            .name
            .namespaceUri,
        'http://www.w3.org/1998/Math/MathML',
      );
      expect(book.readCssDocument('OPS/styles/main.css')!.errors, isEmpty);
      expect(book.itemByHref('https://example.org/audio.mp3')!.id, 'remote');
      expect(book.readBytes('https://example.org/audio.mp3'), isNull);
      expect(
        book.resources.map((resource) => resource.path),
        contains('OPS/styles/main.css'),
      );
    },
  );

  for (final adobe in [false, true]) {
    test(
      '${adobe ? 'Adobe' : 'IDPF'} font deobfuscation preserves original tail and raw payload',
      () {
        final files = epubFiles();
        final identifier = adobe
            ? 'urn:uuid:00112233-4455-6677-8899-aabbccddeeff'
            : 'urn:uuid:00000000-0000-4000-8000-000000000001';
        files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
            .replaceAll('urn:example:book', identifier);
        addManifest(
          files,
          '<item id="font" href="font.otf" media-type="font/otf"/>',
        );
        final algorithm = adobe
            ? 'http://ns.adobe.com/pdf/enc#RC'
            : 'http://www.idpf.org/2008/embedding';
        final hex = adobe
            ? '00112233445566778899aabbccddeeff'
            : '62f2ff8a6e1cd08b5ee1657bd31fae18cca09cd2';
        final key = [
          for (var i = 0; i < hex.length; i += 2)
            int.parse(hex.substring(i, i + 2), radix: 16),
        ];
        final plain = List.generate(1300, (i) => i % 251);
        final encoded = [
          for (var i = 0; i < plain.length; i++)
            i < (adobe ? 1024 : 1040)
                ? plain[i] ^ key[i % key.length]
                : plain[i],
        ];
        files['OPS/font.otf'] = encoded;
        files['META-INF/encryption.xml'] = encryption(
          'OPS/font.otf',
          algorithm,
        );
        final book = EpubBook.fromBytes(zipFiles(files));
        expect(book.readRawBytes('OPS/font.otf'), encoded);
        expect(book.readBytes('OPS/font.otf'), plain);
        expect(book.container.encryption.single.algorithm, algorithm);
      },
    );
  }

  test(
    'internal entities expand in metadata, URI attributes and nested markup',
    () {
      final files = epubFiles();
      files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
          .replaceFirst(
            '<package ',
            '<!DOCTYPE package [<!ENTITY book "Entity &amp; Book"><!ENTITY chapter "text/one.xhtml"><!ENTITY rich "<em>Rich</em>">]><package ',
          )
          .replaceFirst('A small book', '&book;')
          .replaceFirst('href="text/one.xhtml"', 'href="&chapter;"');
      addMetadata(files, '<dc:description>&rich;</dc:description>');
      final book = EpubBook.fromBytes(zipFiles(files));
      expect(book.metadata.title, 'Entity & Book');
      expect(book.spine.first.item.href, 'OPS/text/one.xhtml');
      expect(book.metadata.values('description').last, 'Rich');
      expect(
        book
            .readXmlDocument(book.packagePath)!
            .rootElement
            .descendantElements
            .where((node) => node.name.local == 'em')
            .single
            .innerText,
        'Rich',
      );
      expect(book.packageXml, contains('&book;'));
    },
  );

  test('internal entity expansion excludes comments and CDATA', () {
    final files = epubFiles();
    files['OPS/text/one.xhtml'] =
        '<!DOCTYPE html [<!ENTITY text "expanded">]><html><body><!-- &text; --><p>&text;</p><![CDATA[&text;]]></body></html>';
    final document = EpubBook.fromBytes(
      zipFiles(files),
    ).readXmlDocument('OPS/text/one.xhtml')!;
    expect(
      document.descendants.whereType<XmlComment>().single.value,
      ' &text; ',
    );
    expect(document.descendants.whereType<XmlCDATA>().single.value, '&text;');
    expect(
      document.descendantElements
          .where((node) => node.name.local == 'p')
          .single
          .innerText,
      'expanded',
    );
  });

  test('parameter entities can declare bounded internal general entities', () {
    final files = epubFiles();
    files['OPS/text/one.xhtml'] =
        '<!DOCTYPE html [<!ENTITY % declaration "<!ENTITY text \'expanded\'>">%declaration;]><html><body>&text;</body></html>';
    expect(
      EpubBook.fromBytes(
        zipFiles(files),
      ).readXmlDocument('OPS/text/one.xhtml')!.rootElement.innerText,
      'expanded',
    );
  });

  test('XML depth and entity expansion budgets produce typed errors', () {
    final files = epubFiles();
    files['OPS/text/one.xhtml'] =
        '<html>${'<div>' * 300}text${'</div>' * 300}</html>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(
      () => book.readXmlDocument('OPS/text/one.xhtml'),
      throwsA(code(EpubErrorCode.resourceLimit)),
    );
    files['OPS/text/one.xhtml'] =
        '<!DOCTYPE html [<!ENTITY a "1234567890"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;">]><html>&b;&b;&b;&b;</html>';
    final limited = EpubBook.fromBytes(
      zipFiles(files),
      limits: const EpubLimits(maxEntityExpansionBytes: 128),
    );
    expect(
      () => limited.readXmlDocument('OPS/text/one.xhtml'),
      throwsA(code(EpubErrorCode.resourceLimit)),
    );
    files['OPS/text/one.xhtml'] =
        '<!DOCTYPE html [<!ENTITY a "&a;">]><html>&a;</html>';
    expect(
      () => EpubBook.fromBytes(
        zipFiles(files),
      ).readXmlDocument('OPS/text/one.xhtml'),
      throwsA(code(EpubErrorCode.invalidXml)),
    );
  });

  test(
    'external entity declarations never read filesystem or network content',
    () {
      final files = epubFiles();
      files['OPS/text/one.xhtml'] =
          '<!DOCTYPE html [<!ENTITY secret SYSTEM "file:///private/secret">]><html>&secret;</html>';
      expect(
        () => EpubBook.fromBytes(
          zipFiles(files),
        ).readXmlDocument('OPS/text/one.xhtml'),
        throwsA(code(EpubErrorCode.invalidXml)),
      );
    },
  );

  test('DTD default attributes and tokenized values have XML semantics', () {
    final files = epubFiles();
    files['OPS/text/one.xhtml'] =
        '<!DOCTYPE html [<!ENTITY lang "en"><!ATTLIST html xml:lang CDATA "&lang;" tags NMTOKENS #IMPLIED>]><html tags="  one   two  "/>';
    final doc = EpubBook.fromBytes(
      zipFiles(files),
    ).readXmlDocument('OPS/text/one.xhtml')!;
    expect(doc.rootElement.getAttribute('xml:lang'), 'en');
    expect(doc.rootElement.getAttribute('tags'), 'one two');
  });

  test('entities inside replacement CDATA and comments stay literal', () {
    final files = epubFiles();
    files['OPS/text/one.xhtml'] =
        '<!DOCTYPE html [<!ENTITY a "<![CDATA[&b;]]><!--&b;--><p>&b;</p>"><!ENTITY b "expanded">]><html>&a;</html>';
    final doc = EpubBook.fromBytes(
      zipFiles(files),
    ).readXmlDocument('OPS/text/one.xhtml')!;
    expect(doc.descendants.whereType<XmlCDATA>().single.value, '&b;');
    expect(doc.descendants.whereType<XmlComment>().single.value, '&b;');
    expect(
      doc.descendantElements
          .where((node) => node.name.local == 'p')
          .single
          .innerText,
      'expanded',
    );
  });

  test(
    'XHTML standard entities resolve offline and internal declarations take priority',
    () {
      final files = epubFiles();
      files['OPS/text/one.xhtml'] =
          '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd" [<!ENTITY copy "custom">]><html xmlns="http://www.w3.org/1999/xhtml"><body>&nbsp; &copy; &eacute;</body></html>';
      expect(
        EpubBook.fromBytes(
          zipFiles(files),
        ).readXmlDocument('OPS/text/one.xhtml')!.rootElement.innerText,
        '\u00a0 custom é',
      );
    },
  );
  test('entity replacement failures identify the actual coordinate source', () {
    final files = epubFiles()
      ..['OPS/text/one.xhtml'] =
          '<!DOCTYPE root [<!ENTITY e "<bad">]>\n<root>&e;</root>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(
      () => book.readXmlDocument('OPS/text/one.xhtml'),
      throwsA(
        isA<EpubException>()
            .having(
              (e) => e.locationSource,
              'source',
              EpubLocationSource.entityReplacement,
            )
            .having((e) => e.entityName, 'entity', 'e')
            .having((e) => e.offset, 'offset', 4),
      ),
    );
  });
  test(
    'tag mismatches after entity expansion use expanded document coordinates',
    () {
      final files = epubFiles()
        ..['OPS/text/one.xhtml'] =
            '<!DOCTYPE root [<!ENTITY e "<a>">]>\n<root>&e;</b></root>';
      final book = EpubBook.fromBytes(zipFiles(files));
      expect(
        () => book.readXmlDocument('OPS/text/one.xhtml'),
        throwsA(
          isA<EpubException>().having(
            (e) => e.locationSource,
            'source',
            EpubLocationSource.expandedXml,
          ),
        ),
      );
    },
  );
  test('DTD attribute application work stays within the document budget', () {
    for (final defaultValue in ['"v"', '#IMPLIED']) {
      final declarations = List.generate(
        250,
        (i) => 'a$i CDATA $defaultValue',
      ).join(' ');
      final files = epubFiles()
        ..['OPS/text/one.xhtml'] =
            '<!DOCTYPE root [<!ATTLIST p $declarations>]><root>${'<p/>' * 250}</root>';
      final book = EpubBook.fromBytes(
        zipFiles(files),
        limits: const EpubLimits(maxParseItems: 300),
      );
      expect(
        () => book.readXmlDocument('OPS/text/one.xhtml'),
        throwsA(code(EpubErrorCode.resourceLimit)),
      );
    }
  });
  test('DTD generated default text consumes the expansion budget', () {
    final files = epubFiles()
      ..['OPS/text/one.xhtml'] =
          '<!DOCTYPE root [<!ATTLIST p label CDATA "${'abcdefgh' * 16}">]><root><p/><p/></root>';
    final book = EpubBook.fromBytes(
      zipFiles(files),
      limits: const EpubLimits(maxEntityExpansionBytes: 64),
    );
    expect(
      () => book.readXmlDocument('OPS/text/one.xhtml'),
      throwsA(code(EpubErrorCode.resourceLimit)),
    );
  });
}
