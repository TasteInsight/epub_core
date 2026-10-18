import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../epub_path.dart';
import '../errors.dart';
import '../limits.dart';
import '../model/container.dart';
import 'zip_input.dart';

/// In-memory ZIP index. Resources are decompressed on first read.
class ResourceArchive {
  ResourceArchive(List<int> bytes, this.limits) {
    if ([
      limits.maxArchiveBytes,
      limits.maxEntries,
      limits.maxEntryBytes,
      limits.maxUncompressedBytes,
      limits.maxXmlDepth,
      limits.maxXmlNodes,
      limits.maxEntityExpansionBytes,
    ].any((limit) => limit <= 0)) {
      throw ArgumentError('EPUB resource limits must be positive.');
    }
    if (limits.maxCachedBytes < 0) {
      throw ArgumentError('maxCachedBytes must be non-negative.');
    }
    if (bytes.length > limits.maxArchiveBytes) {
      _limit('Archive exceeds maxArchiveBytes.');
    }
    try {
      final directory = ZipDirectory()
        ..read(InputMemoryStream(prepareZipInput(bytes, limits)));
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

  final EpubLimits limits;
  int _cachedBytes = 0;
  final _entries = <String, ZipFileHeader>{};
  final _caseIndex = <String, String?>{};
  final _cache = <String, Uint8List>{};
  List<EpubResourceInfo> get resources => List.unmodifiable(
    _entries.entries.map(
      (entry) => EpubResourceInfo(
        path: entry.key,
        href: Uri(path: entry.key).toString(),
        size: entry.value.uncompressedSize,
        compressedSize: entry.value.compressedSize,
      ),
    ),
  );
  void clearCache() {
    _cache.clear();
    _cachedBytes = 0;
  }

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
    if ((entry.generalPurposeBitFlag & 1) != 0) {
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
    final cached = _cache.remove(name);
    if (cached != null) {
      _cache[name] = cached;
      return cached;
    }
    final result = (() {
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
    })();
    if (result.length <= limits.maxCachedBytes) {
      while (_cachedBytes + result.length > limits.maxCachedBytes &&
          _cache.isNotEmpty) {
        _cachedBytes -= _cache.remove(_cache.keys.first)!.length;
      }
      _cache[name] = result;
      _cachedBytes += result.length;
    }
    return result;
  }

  String? readText(String href) {
    final bytes = read(href);
    return bytes == null ? null : decodeText(bytes, href);
  }

  static String decodeText(Uint8List bytes, String href) {
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
        final units = <int>[
          for (var index = offset; index < bytes.length; index += 2)
            data.getUint16(
              index,
              little || inferredLittle ? Endian.little : Endian.big,
            ),
        ];
        for (var i = 0; i < units.length; i++) {
          final unit = units[i];
          if (unit >= 0xd800 && unit <= 0xdbff) {
            if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
              throw const FormatException('Unpaired UTF-16 surrogate.');
            }
          } else if (unit >= 0xdc00 && unit <= 0xdfff) {
            throw const FormatException('Unpaired UTF-16 surrogate.');
          }
        }
        return String.fromCharCodes(units);
      }
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw EpubException(EpubErrorCode.invalidText, error.message, path: href);
    }
  }
}

Never _limit(String message, [String? path]) =>
    throw EpubException(EpubErrorCode.resourceLimit, message, path: path);
