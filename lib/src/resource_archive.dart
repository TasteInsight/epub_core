import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'epub_path.dart';
import 'models.dart';

/// In-memory ZIP index. Resources are decompressed on first read.
class ResourceArchive {
  ResourceArchive(List<int> bytes, EpubLimits limits) {
    if ([
      limits.maxArchiveBytes,
      limits.maxEntries,
      limits.maxEntryBytes,
      limits.maxUncompressedBytes,
    ].any((limit) => limit <= 0)) {
      throw ArgumentError('EPUB resource limits must be positive.');
    }
    if (bytes.length > limits.maxArchiveBytes) {
      _limit('Archive exceeds maxArchiveBytes.');
    }
    try {
      final directory = ZipDirectory()
        ..read(InputMemoryStream(Uint8List.fromList(bytes)));
      if (directory.filePosition < 0 ||
          directory.fileHeaders.length !=
              directory.totalCentralDirectoryEntries ||
          directory.numberOfThisDisk != 0) {
        throw const EpubException(
          EpubErrorCode.invalidArchive,
          'Invalid or incomplete ZIP directory.',
        );
      }
      if (directory.fileHeaders.length > limits.maxEntries) {
        _limit('Archive exceeds maxEntries.');
      }
      var total = 0;
      for (final header in directory.fileHeaders) {
        final file = header.file!;
        if (header.filename != file.filename ||
            header.uncompressedSize != file.uncompressedSize) {
          throw EpubException(
            EpubErrorCode.invalidArchive,
            'Conflicting ZIP entry headers.',
            path: header.filename,
          );
        }
        if (header.filename.endsWith('/')) continue;
        final name = EpubPath.normalizeArchivePath(header.filename);
        if (name == null || _entries.containsKey(name)) {
          throw EpubException(
            EpubErrorCode.invalidArchive,
            'Invalid or duplicate ZIP path.',
            path: header.filename,
          );
        }
        if (header.compressionMethod != 0 && header.compressionMethod != 8) {
          throw EpubException(
            EpubErrorCode.invalidArchive,
            'EPUB supports stored and deflated ZIP entries.',
            path: name,
          );
        }
        if (header.uncompressedSize > limits.maxEntryBytes) {
          _limit('Resource exceeds maxEntryBytes.', name);
        }
        total += header.uncompressedSize;
        if (total > limits.maxUncompressedBytes) {
          _limit('Archive exceeds maxUncompressedBytes.');
        }
        _entries[name] = header;
        final folded = name.toLowerCase();
        _caseIndex[folded] = _caseIndex.containsKey(folded) ? null : name;
      }
    } on ArchiveException catch (error) {
      throw EpubException(EpubErrorCode.invalidArchive, error.toString());
    } on RangeError {
      throw const EpubException(
        EpubErrorCode.invalidArchive,
        'Truncated ZIP data.',
      );
    }
  }

  final _entries = <String, ZipFileHeader>{};
  final _caseIndex = <String, String?>{};
  final _cache = <String, Uint8List>{};
  final encryptedPaths = <String>{};

  String? pathFor(String href) {
    final name = EpubPath.archivePath(href);
    if (name == null) return null;
    return _entries.containsKey(name) ? name : _caseIndex[name.toLowerCase()];
  }

  bool contains(String href) => pathFor(href) != null;

  void ensureReadable(String href) {
    final name = pathFor(href);
    if (name == null) {
      throw EpubException(
        EpubErrorCode.missingResource,
        'Resource is missing.',
        path: href,
      );
    }
    final entry = _entries[name]!;
    if (encryptedPaths.contains(name) ||
        (entry.generalPurposeBitFlag & 1) != 0) {
      throw EpubException(
        EpubErrorCode.encryptedResource,
        'Encrypted or obfuscated resources require a separate decoder.',
        path: name,
      );
    }
  }

  Uint8List? read(String href) {
    final name = pathFor(href);
    if (name == null) return null;
    ensureReadable(href);
    return _cache.putIfAbsent(name, () {
      try {
        final entry = _entries[name]!;
        // archive bounds decompression to the declared size, including forged
        // small sizes. Validate stored entries and CRC here as well.
        final bytes = entry.file!.getStream().toUint8List();
        if (bytes.length != entry.uncompressedSize ||
            getCrc32(bytes) != entry.crc32) {
          throw EpubException(
            EpubErrorCode.invalidArchive,
            'Resource size or CRC does not match its ZIP entry.',
            path: name,
          );
        }
        return bytes.asUnmodifiableView();
      } on EpubException {
        rethrow;
      } on FormatException catch (error) {
        throw EpubException(
          EpubErrorCode.invalidArchive,
          error.message,
          path: name,
        );
      } on RangeError {
        throw EpubException(
          EpubErrorCode.invalidArchive,
          'Truncated resource.',
          path: name,
        );
      }
    });
  }

  String? readText(String href) {
    final bytes = read(href);
    if (bytes == null) return null;
    try {
      final little = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe;
      final big = bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff;
      final inferredLittle =
          bytes.length >= 4 && bytes[0] == 60 && bytes[1] == 0 && bytes[3] == 0;
      final inferredBig =
          bytes.length >= 4 && bytes[0] == 0 && bytes[1] == 60 && bytes[2] == 0;
      if (little || big || inferredLittle || inferredBig) {
        final offset = little || big ? 2 : 0;
        if ((bytes.length - offset).isOdd) {
          throw const FormatException('Truncated UTF-16.');
        }
        final data = ByteData.sublistView(bytes);
        return String.fromCharCodes([
          for (var index = offset; index < bytes.length; index += 2)
            data.getUint16(
              index,
              little || inferredLittle ? Endian.little : Endian.big,
            ),
        ]);
      }
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw EpubException(EpubErrorCode.invalidText, error.message, path: href);
    }
  }
}

Never _limit(String message, [String? path]) =>
    throw EpubException(EpubErrorCode.resourceLimit, message, path: path);
