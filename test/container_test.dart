import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';
import 'fixtures.dart';

TypeMatcher<EpubException> code(EpubErrorCode value) =>
    isA<EpubException>().having((e) => e.code, 'code', value);

void main() {
  test('all rootfiles, container links and META-INF documents remain accessible', () {
    final files = epubFiles();
    files['OPS/alternate.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst('A small book', 'Alternate');
    files['META-INF/container.xml'] = (files['META-INF/container.xml']! as String)
        .replaceFirst(
          '</rootfiles>',
          '<rootfile full-path="OPS/alternate.opf" media-type="application/oebps-package+xml" rendition:language="fr" xmlns:rendition="http://www.idpf.org/2013/rendition"/></rootfiles>',
        )
        .replaceFirst(
          '</container>',
          '<links><link href="rendition-map.xhtml" rel="mapping"/></links></container>',
        );
    for (final name in ['metadata', 'rights', 'signatures', 'manifest']) {
      files['META-INF/$name.xml'] =
          '<$name xmlns="urn:custom"><data>Original $name</data></$name>';
    }
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.container.rootfiles, hasLength(2));
    expect(book.container.links.single.href, 'rendition-map.xhtml');
    expect(book.container.documents, hasLength(5));
    expect(book.openRendition('OPS/alternate.opf').metadata.title, 'Alternate');
    expect(
      EpubBook.fromBytes(
        zipFiles(files),
        packagePath: 'OPS/alternate.opf',
      ).metadata.title,
      'Alternate',
    );
    expect(
      book.readXmlDocument('META-INF/rights.xml')!.rootElement.innerText,
      'Original rights',
    );
    expect(
      () => book.openRendition('OPS/absent.opf'),
      throwsA(code(EpubErrorCode.invalidPackage)),
    );
  });

  test('foreign namespaces cannot replace container or DC elements', () {
    final files = epubFiles();
    files['META-INF/container.xml'] =
        (files['META-INF/container.xml']! as String).replaceFirst(
          '<rootfiles>',
          '<x:rootfile xmlns:x="urn:extension" full-path="wrong.opf" media-type="application/oebps-package+xml"/><rootfiles>',
        );
    files['OPS/package.opf'] = (files['OPS/package.opf']! as String)
        .replaceFirst(
          '<dc:title>',
          '<x:title xmlns:x="urn:extension">Unrelated</x:title><dc:title>',
        );
    expect(EpubBook.fromBytes(zipFiles(files)).metadata.title, 'A small book');
  });

  test(
    'OCF references resolve against a container root, including excess parent segments',
    () {
      expect(
        EpubPath.resolve('OPS/text/one.xhtml', '../../../../images/p.png'),
        'images/p.png',
      );
      expect(
        EpubPath.resolve('OPS/text/one.xhtml', '/images/p.png'),
        'images/p.png',
      );
      expect(
        EpubPath.resolve('https://example.org/a/b.xhtml', '../c.png'),
        'https://example.org/c.png',
      );
      final files = epubFiles()..['images/p.png'] = [7, 8, 9];
      final book = EpubBook.fromBytes(zipFiles(files));
      expect(book.readBytes('/images/p.png'), [7, 8, 9]);
    },
  );

  test('empty namespace extensions cannot shadow a namespaced container', () {
    final files = epubFiles();
    files['META-INF/container.xml'] =
        (files['META-INF/container.xml']! as String).replaceFirst(
          '<rootfiles>',
          '<rootfiles xmlns=""><rootfile full-path="evil.opf"/></rootfiles><rootfiles>',
        );
    expect(EpubBook.fromBytes(zipFiles(files)).metadata.title, 'A small book');
  });
  test('encryption declarations require an identifiable protected resource', () {
    for (final payload in [
      '',
      '<CipherData/>',
      '<CipherData><CipherReference/></CipherData>',
      '<CipherData><CipherReference URI=""/></CipherData>',
      '<CipherData><CipherReference URI=" "/></CipherData>',
    ]) {
      final files = epubFiles()
        ..['META-INF/encryption.xml'] =
            '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="urn:custom"/>'
            '$payload</EncryptedData></encryption>';
      expect(
        () => EpubBook.fromBytes(zipFiles(files)),
        throwsA(
          isA<EpubException>().having(
            (e) => e.path,
            'path',
            'META-INF/encryption.xml',
          ),
        ),
      );
    }
  });
  test('known protected resource with unspecified algorithm stays protected', () {
    final files = epubFiles()
      ..['META-INF/encryption.xml'] =
          '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">'
          '<CipherData><CipherReference URI="OPS/images/cover.png"/></CipherData>'
          '</EncryptedData></encryption>';
    final book = EpubBook.fromBytes(zipFiles(files));
    expect(book.container.encryption.single.href, 'OPS/images/cover.png');
    expect(book.readRawBytes('OPS/images/cover.png'), [1, 2, 3]);
    expect(
      () => book.readBytes('OPS/images/cover.png'),
      throwsA(code(EpubErrorCode.encryptedResource)),
    );
    expect(book.readString('OPS/text/one.xhtml'), contains('Hello'));
  });
  test('standard encryption compression metadata remains available', () {
    final files = epubFiles()
      ..['META-INF/encryption.xml'] =
          '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="urn:custom"/>'
          '<CipherData><CipherReference URI="OPS/images/cover.png"/></CipherData>'
          '<EncryptionProperties><EncryptionProperty>'
          '<Compression xmlns="http://www.idpf.org/2016/encryption#compression" Method="8" OriginalLength="3500000"/>'
          '</EncryptionProperty></EncryptionProperties></EncryptedData></encryption>';
    final declaration = EpubBook.fromBytes(
      zipFiles(files),
    ).container.encryption.single;
    expect(declaration.compressionMethod, 8);
    expect(declaration.originalLength, 3500000);
  });
  test('encryption targets require a resolved resource path', () {
    for (final uri in ['/', '../', '#fragment', '?query']) {
      final files = epubFiles()
        ..['META-INF/encryption.xml'] = encryption(uri, 'urn:custom');
      expect(
        () => EpubBook.fromBytes(zipFiles(files)),
        throwsA(code(EpubErrorCode.invalidPackage)),
      );
    }
    final files = epubFiles()
      ..['META-INF/encryption.xml'] = encryption(
        'OPS/absent.bin',
        'urn:custom',
      );
    expect(
      EpubBook.fromBytes(zipFiles(files)).container.encryption.single.href,
      'OPS/absent.bin',
    );
  });
}
