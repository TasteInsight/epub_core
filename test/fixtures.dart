import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Map<String, Object> epubFiles({String version = '3.0'}) => {
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '''<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles>
<rootfile full-path="OPS/package.opf" media-type="application/oebps-package+xml"/>
</rootfiles></container>''',
  'OPS/package.opf':
      '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="$version" unique-identifier="book-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
<dc:identifier id="book-id">urn:example:book</dc:identifier><dc:title>A small book</dc:title>
<dc:creator id="writer" opf:role="aut">Writer</dc:creator><dc:language>zh</dc:language><dc:language>en</dc:language>
<dc:subject>Fiction</dc:subject><dc:description>A &amp; B</dc:description>
<meta name="cover" content="cover"/><meta property="role" refines="#writer">aut</meta>
</metadata><manifest>
<item id="one" href="text/one.xhtml" media-type="application/xhtml+xml"/>
<item id="two" href="text/two.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="svg nav"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="cover" href="images/cover.png" media-type="image/png" properties="cover-image"/>
</manifest><spine toc="ncx" page-progression-direction="rtl">
<itemref idref="one"/><itemref idref="two" linear="no"/>
</spine></package>''',
  'OPS/text/one.xhtml':
      '<?xml version="1.0" encoding="UTF-8"?><html><body><h1 id="start">Hello 中文</h1><p>Text.</p></body></html>',
  'OPS/text/two.xhtml': '<html><body>Supplement.</body></html>',
  'OPS/images/cover.png': [1, 2, 3],
  if (!version.startsWith('2'))
    'OPS/nav.xhtml':
        '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>
<nav epub:type="landmarks"><ol><li><a href="text/one.xhtml">Start</a></li></ol></nav>
<nav epub:type="toc"><ol><li><span>Part one</span><ol><li><a href="text/one.xhtml#start">A &amp; B</a></li></ol></li></ol></nav>
</body></html>''',
  'OPS/toc.ncx': '''<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
<navPoint id="p" playOrder="1"><navLabel><text>Part one</text></navLabel><content src="text/one.xhtml"/>
<navPoint id="c" playOrder="2"><navLabel><text>A &amp; B</text></navLabel><content src="text/one.xhtml#start"/></navPoint>
</navPoint></navMap></ncx>''',
};

Uint8List epubBytes({String version = '3.0'}) =>
    zipFiles(epubFiles(version: version));

Uint8List zipFiles(Map<String, Object> files, {bool compress = true}) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = entry.value is String
        ? utf8.encode(entry.value as String)
        : entry.value as List<int>;
    archive.addFile(
      compress && entry.key != 'mimetype'
          ? ArchiveFile(entry.key, bytes.length, bytes)
          : ArchiveFile.noCompress(entry.key, bytes.length, bytes),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

List<int> utf16(String text, {required bool littleEndian}) => [
  if (littleEndian) ...[0xff, 0xfe] else ...[0xfe, 0xff],
  for (final unit in text.codeUnits)
    if (littleEndian) ...[
      unit & 255,
      unit >> 8,
    ] else ...[
      unit >> 8,
      unit & 255,
    ],
];

Uint8List corruptCompressedEntry(Uint8List bytes, String name) {
  final data = ByteData.sublistView(bytes);
  for (var offset = 0; offset < bytes.length - 46; offset++) {
    if (data.getUint32(offset, Endian.little) != 0x02014b50) continue;
    final nameSize = data.getUint16(offset + 28, Endian.little);
    if (utf8.decode(bytes.sublist(offset + 46, offset + 46 + nameSize)) !=
        name) {
      continue;
    }
    final local = data.getUint32(offset + 42, Endian.little);
    final payload =
        local +
        30 +
        data.getUint16(local + 26, Endian.little) +
        data.getUint16(local + 28, Endian.little);
    bytes[payload] = 0xff; // Invalid DEFLATE block type.
    return bytes;
  }
  throw StateError('Missing fixture entry: $name');
}

String encryption(String path, String algorithm) =>
    '''
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="$algorithm"/>
<CipherData><CipherReference URI="$path"/></CipherData></EncryptedData></encryption>''';
