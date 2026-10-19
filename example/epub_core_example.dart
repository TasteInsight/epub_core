import 'dart:io';

import 'package:epub_core/epub_core.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run example/epub_core_example.dart book.epub');
    exitCode = 64;
    return;
  }
  try {
    final bytes = await File(arguments.single).readAsBytes();
    final book = EpubBook.fromBytes(bytes);
    stdout.writeln(book.metadata.title);
    stdout.writeln(
      book.metadata.creators.map((person) => person.name).join(', '),
    );
    for (final entry in book.spine.where((entry) => entry.linear)) {
      stdout.writeln('${entry.item.href} (${entry.item.mediaType})');
    }
    for (final diagnostic in book.diagnostics) {
      stderr.writeln(diagnostic);
    }
  } on EpubException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 66;
  }
}
