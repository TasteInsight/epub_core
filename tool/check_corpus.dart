import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epub_core/epub_core.dart';
import 'package:path/path.dart' as p;

/// Runs structural/resource ingestion against an external unpacked EPUB corpus.
/// This does not evaluate rendering, playback, scripts, or reading-system tests.
void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/check_corpus.dart CORPUS_DIRECTORY [REPORT.json]',
    );
    exitCode = 64;
    return;
  }
  final root = Directory(arguments.first).absolute;
  final directories =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where(
            (file) =>
                p.basename(file.path) == 'container.xml' &&
                p.basename(p.dirname(file.path)) == 'META-INF',
          )
          .map((file) => p.dirname(p.dirname(file.path)))
          .toSet()
          .toList()
        ..sort();
  final results = <Map<String, Object?>>[];
  for (final directory in directories) {
    final name = p.relative(directory, from: root.path);
    try {
      final files =
          Directory(directory)
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final archive = Archive();
      final mime = File(p.join(directory, 'mimetype'));
      if (mime.existsSync()) {
        final bytes = mime.readAsBytesSync();
        archive.addFile(
          ArchiveFile.noCompress('mimetype', bytes.length, bytes),
        );
      }
      for (final file in files) {
        final path = p
            .relative(file.path, from: directory)
            .split(p.separator)
            .join('/');
        if (path == 'mimetype' || path.endsWith('.epub')) continue;
        final bytes = file.readAsBytesSync();
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }
      final book = EpubBook.fromBytes(ZipEncoder().encodeBytes(archive));
      var resourceBytes = 0;
      for (final resource in book.resources) {
        resourceBytes += book.readRawBytes(resource.href)!.length;
      }
      var renditions = 0;
      var overlays = 0;
      for (final rootfile in book.container.rootfiles.where(
        (root) => root.mediaType == 'application/oebps-package+xml',
      )) {
        final rendition = book.openRendition(rootfile.fullPath);
        renditions++;
        overlays += rendition.mediaOverlays.length;
      }
      results.add({
        'name': name,
        'parsed': true,
        'renditions': renditions,
        'overlays': overlays,
        'resources': book.resources.length,
        'resourceBytes': resourceBytes,
        'diagnostics': book.warnings,
      });
    } catch (error) {
      results.add({'name': name, 'parsed': false, 'error': error.toString()});
      stderr.writeln('$name: $error');
    }
  }
  final failures = results.where((result) => result['parsed'] == false).length;
  final report = {
    'scope':
        'Structural and resource ingestion only; not reading-system conformance.',
    'total': results.length,
    'parsed': results.length - failures,
    'failed': failures,
    'results': results,
  };
  if (arguments.length == 2) {
    File(
      arguments[1],
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  }
  stdout.writeln(
    '${results.length - failures}/${results.length} publications parsed; $failures failures.',
  );
  if (failures > 0 || results.isEmpty) exitCode = 1;
}
