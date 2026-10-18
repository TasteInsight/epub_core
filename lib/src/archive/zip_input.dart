import 'dart:typed_data';

import '../errors.dart';
import '../limits.dart';

/// Locates a complete EOCD record before archive builds its index. archive 4.5.2
/// accepts the last signature even inside a comment; removing only the verified
/// comment keeps ZIP parsing/decompression in archive and fixes that ambiguity.
Uint8List prepareZipInput(List<int> input, EpubLimits limits) {
  final bytes = Uint8List.fromList(input);
  final data = ByteData.sublistView(bytes);
  final lower = bytes.length - 22 - 65535;
  for (
    var offset = bytes.length - 22;
    offset >= 0 && offset >= lower;
    offset--
  ) {
    if (data.getUint32(offset, Endian.little) != 0x06054b50) continue;
    final commentLength = data.getUint16(offset + 20, Endian.little);
    if (offset + 22 + commentLength != bytes.length) continue;
    if (data.getUint16(offset + 4, Endian.little) != 0 ||
        data.getUint16(offset + 6, Endian.little) != 0) {
      continue;
    }
    var count = data.getUint16(offset + 10, Endian.little);
    var size = data.getUint32(offset + 12, Endian.little);
    var start = data.getUint32(offset + 16, Endian.little);
    if (count == 0xffff || size == 0xffffffff || start == 0xffffffff) {
      final locator = offset - 20;
      if (locator < 0 || data.getUint32(locator, Endian.little) != 0x07064b50) {
        continue;
      }
      final record = data.getUint64(locator + 8, Endian.little);
      if (record < 0 ||
          record > locator - 56 ||
          data.getUint32(record, Endian.little) != 0x06064b50) {
        continue;
      }
      count = data.getUint64(record + 32, Endian.little);
      size = data.getUint64(record + 40, Endian.little);
      start = data.getUint64(record + 48, Endian.little);
    }
    if (count == 0 ||
        start < 0 ||
        size < count * 46 ||
        start + size > offset ||
        start > bytes.length - 4 ||
        data.getUint32(start, Endian.little) != 0x02014b50) {
      continue;
    }
    if (count > limits.maxEntries) {
      throw const EpubException(
        EpubErrorCode.resourceLimit,
        'Archive exceeds maxEntries.',
      );
    }
    var cursor = start;
    var actualCount = 0;
    final directoryEnd = start + size;
    while (cursor < directoryEnd) {
      if (cursor > directoryEnd - 4) break;
      final signature = data.getUint32(cursor, Endian.little);
      if (signature == 0x05054b50 &&
          cursor <= directoryEnd - 6 &&
          cursor + 6 + data.getUint16(cursor + 4, Endian.little) ==
              directoryEnd) {
        cursor = directoryEnd;
        break;
      }
      if (signature != 0x02014b50 || cursor > directoryEnd - 46) break;
      if (++actualCount > limits.maxEntries) {
        throw const EpubException(
          EpubErrorCode.resourceLimit,
          'Actual ZIP entries exceed maxEntries.',
        );
      }
      cursor +=
          46 +
          data.getUint16(cursor + 28, Endian.little) +
          data.getUint16(cursor + 30, Endian.little) +
          data.getUint16(cursor + 32, Endian.little);
    }
    if (cursor != directoryEnd || actualCount != count) {
      throw const EpubException(
        EpubErrorCode.invalidArchive,
        'ZIP directory records disagree with their declared bounds.',
      );
    }
    if (commentLength == 0) return bytes;
    final result = bytes.sublist(0, offset + 22);
    ByteData.sublistView(result).setUint16(offset + 20, 0, Endian.little);
    return result;
  }
  throw const EpubException(
    EpubErrorCode.invalidArchive,
    'No complete ZIP directory record.',
  );
}
