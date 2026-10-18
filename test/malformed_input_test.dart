import 'dart:math';
import 'dart:typed_data';

import 'package:epub_core/epub_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test(
    'mutated archives either parse or report the public format error type',
    () {
      final random = Random(42);
      final original = epubBytes();
      for (var sample = 0; sample < 500; sample++) {
        final bytes = Uint8List.fromList(original);
        for (var index = 0; index < 1 + sample % 4; index++) {
          bytes[random.nextInt(bytes.length)] = random.nextInt(256);
        }
        try {
          final book = EpubBook.fromBytes(bytes);
          for (final resource in book.resources) {
            book.readRawBytes(resource.href);
          }
        } on EpubException {
          // Corruption is a normal input outcome; implementation errors propagate.
        }
      }
      for (final xml in [
        '',
        ' ',
        '<?xml version="1.0"?>',
        '<!DOCTYPE package>',
        '<a/><b/>',
        'plain text',
      ]) {
        expect(
          () => EpubBook.fromBytes(
            zipFiles(epubFiles()..['OPS/package.opf'] = xml),
          ),
          throwsA(isA<EpubException>()),
        );
      }
    },
  );
}
