/// 极简 ZIP 写入器：只用 store（不压缩）方式，够导出用。
/// 目的：把 Markdown 与图片打进一个压缩包，不引入 archive 之类三方包。
///
/// 结构遵循 PKWARE APPNOTE：每条记录 = 本地文件头 + 数据，
/// 结尾是中央目录与 EOCD。文件名按 UTF-8 编码并置通用标志位第 11 位。
library;

import 'dart:convert';
import 'dart:typed_data';

class ZipEntry {
  /// 包内路径，用 `/` 分隔，例如 `images/img_1.jpg`
  final String name;
  final List<int> bytes;
  final DateTime modified;

  const ZipEntry(this.name, this.bytes, {required this.modified});
}

const int _sigLocal = 0x04034b50;
const int _sigCentral = 0x02014b50;
const int _sigEnd = 0x06054b50;

/// UTF-8 文件名标志位
const int _flagUtf8 = 0x0800;

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) & 0xFFFFFFFF : (c >> 1) & 0xFFFFFFFF;
  }
  return c;
}, growable: false);

int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = (_crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8)) & 0xFFFFFFFF;
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _u16(int value) => Uint8List.fromList([value & 0xFF, (value >> 8) & 0xFF]);

Uint8List _u32(int value) => Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);

/// DOS 时间格式：日期与时间各 16 位，秒精度为 2 秒
(int, int) _dosDateTime(DateTime t) {
  final year = t.year < 1980 ? 1980 : t.year;
  final date = ((year - 1980) << 9) | (t.month << 5) | t.day;
  final time = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
  return (time & 0xFFFF, date & 0xFFFF);
}

/// 把若干条目打成一个 ZIP 字节流
Uint8List buildZipArchive(List<ZipEntry> entries) {
  final output = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;

  for (final entry in entries) {
    final nameBytes = utf8.encode(entry.name);
    final data = entry.bytes;
    final checksum = crc32(data);
    final (dosTime, dosDate) = _dosDateTime(entry.modified);

    final local = BytesBuilder(copy: false)
      ..add(_u32(_sigLocal))
      ..add(_u16(20)) // 需要的解压版本 2.0
      ..add(_u16(_flagUtf8))
      ..add(_u16(0)) // 压缩方法 0 = store
      ..add(_u16(dosTime))
      ..add(_u16(dosDate))
      ..add(_u32(checksum))
      ..add(_u32(data.length)) // 压缩后大小
      ..add(_u32(data.length)) // 原始大小
      ..add(_u16(nameBytes.length))
      ..add(_u16(0)) // 扩展字段长度
      ..add(nameBytes);

    final localBytes = local.takeBytes();
    output
      ..add(localBytes)
      ..add(data);

    central
      ..add(_u32(_sigCentral))
      ..add(_u16(20)) // 制作版本
      ..add(_u16(20)) // 需要的解压版本
      ..add(_u16(_flagUtf8))
      ..add(_u16(0))
      ..add(_u16(dosTime))
      ..add(_u16(dosDate))
      ..add(_u32(checksum))
      ..add(_u32(data.length))
      ..add(_u32(data.length))
      ..add(_u16(nameBytes.length))
      ..add(_u16(0)) // 扩展字段
      ..add(_u16(0)) // 注释
      ..add(_u16(0)) // 起始磁盘号
      ..add(_u16(0)) // 内部属性
      ..add(_u32(0)) // 外部属性
      ..add(_u32(offset)) // 本地头偏移
      ..add(nameBytes);

    offset += localBytes.length + data.length;
  }

  final centralBytes = central.takeBytes();
  output
    ..add(centralBytes)
    ..add(_u32(_sigEnd))
    ..add(_u16(0)) // 当前磁盘号
    ..add(_u16(0)) // 中央目录起始磁盘号
    ..add(_u16(entries.length)) // 本盘条目数
    ..add(_u16(entries.length)) // 总条目数
    ..add(_u32(centralBytes.length))
    ..add(_u32(offset))
    ..add(_u16(0)); // 注释长度

  return output.takeBytes();
}
