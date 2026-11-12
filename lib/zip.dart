/// 极简 ZIP 写入器：只用 store（不压缩）方式，够导出用。
/// 目的：把 Markdown 与图片打进一个压缩包，不引入 archive 之类三方包。
///
/// 结构遵循 PKWARE APPNOTE：每条记录 = 本地文件头 + 数据，
/// 结尾是中央目录与 EOCD。文件名按 UTF-8 编码并置通用标志位第 11 位。
library;

import 'dart:convert';
import 'dart:io' show ZLibDecoder;
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

/* ------------------------------- 解包 ------------------------------- */

/// 解出来的一项
class UnzippedFile {
  final String name;
  final Uint8List bytes;

  const UnzippedFile(this.name, this.bytes);
}

class ZipFormatException implements Exception {
  final String message;

  const ZipFormatException(this.message);

  @override
  String toString() => 'ZIP 解析失败：$message';
}

int _u16At(Uint8List d, int o) => d[o] | (d[o + 1] << 8);

int _u32At(Uint8List d, int o) =>
    d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);

/// 拒绝绝对路径与 `..` 跳出，防止恶意包写到目标目录之外
void _assertSafeName(String name) {
  final normalized = name.replaceAll('\\', '/');
  if (normalized.startsWith('/')) throw ZipFormatException('非法的文件路径：$name');
  if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
    throw ZipFormatException('非法的文件路径：$name');
  }
  for (final segment in normalized.split('/')) {
    if (segment == '..') throw ZipFormatException('非法的文件路径：$name');
  }
}

/// 解压一个 zip。
///
/// 只支持 store（0）与 deflate（8）两种压缩方式：本应用生成的是 store，
/// 支持 deflate 是为了兼容「在电脑上被重新压缩过」的备份包。
///
/// 几条限制不是摆设——备份包来自外部文件，一旦解析出错或包是恶意构造的，
/// 最坏情况是手机内存被吃光或者文件被写到别处，所以都挡在前面。
List<UnzippedFile> unzipArchive(
  Uint8List archive, {
  int maxEntries = 2000,
  int maxTotalBytes = 512 * 1024 * 1024,
  int maxSingleFileBytes = 64 * 1024 * 1024,
}) {
  if (archive.length < 22) throw const ZipFormatException('文件太小，不是有效的压缩包');

  // 1) 从尾部回退找 EOCD（注释最长 64KB）
  final floor = archive.length - 22 - 65535;
  final start = floor < 0 ? 0 : floor;
  var eocd = -1;
  for (var i = archive.length - 22; i >= start; i--) {
    if (_u32At(archive, i) == _sigEnd) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const ZipFormatException('找不到压缩包结尾标记');

  final entryCount = _u16At(archive, eocd + 10);
  final cdOffset = _u32At(archive, eocd + 16);
  if (entryCount > maxEntries) throw ZipFormatException('压缩包内条目过多（$entryCount 个）');
  // 条目为 0 时中央目录偏移本来就是 0，不能按越界处理
  if (entryCount > 0 && (cdOffset <= 0 || cdOffset >= archive.length)) {
    throw const ZipFormatException('压缩包目录偏移异常');
  }

  final files = <UnzippedFile>[];
  var totalBytes = 0;
  var p = cdOffset;

  // 2) 遍历中央目录
  for (var i = 0; i < entryCount; i++) {
    if (p + 46 > archive.length) throw const ZipFormatException('压缩包目录被截断');
    if (_u32At(archive, p) != _sigCentral) {
      throw const ZipFormatException('压缩包目录格式异常');
    }

    final method = _u16At(archive, p + 10);
    final checksum = _u32At(archive, p + 16);
    final compressedSize = _u32At(archive, p + 20);
    final nameLen = _u16At(archive, p + 28);
    final extraLen = _u16At(archive, p + 30);
    final commentLen = _u16At(archive, p + 32);
    final localOffset = _u32At(archive, p + 42);
    if (p + 46 + nameLen > archive.length) {
      throw const ZipFormatException('压缩包文件名被截断');
    }
    final name = utf8.decode(
      archive.sublist(p + 46, p + 46 + nameLen),
      allowMalformed: true,
    );
    p += 46 + nameLen + extraLen + commentLen;

    if (name.endsWith('/')) continue; // 目录项，跳过
    _assertSafeName(name);
    if (compressedSize > maxSingleFileBytes) {
      throw ZipFormatException('「$name」过大，超出单个文件限制');
    }

    // 3) 定位到本地头，算出真实数据区间（本地头的 extra 长度可能与中央目录不同）
    if (localOffset + 30 > archive.length) {
      throw const ZipFormatException('本地文件头越界');
    }
    if (_u32At(archive, localOffset) != _sigLocal) {
      throw const ZipFormatException('本地文件头格式异常');
    }
    final localNameLen = _u16At(archive, localOffset + 26);
    final localExtraLen = _u16At(archive, localOffset + 28);
    final dataStart = localOffset + 30 + localNameLen + localExtraLen;
    final dataEnd = dataStart + compressedSize;
    if (dataEnd > archive.length) throw const ZipFormatException('压缩数据被截断');

    final raw = archive.sublist(dataStart, dataEnd);
    Uint8List bytes;
    if (method == 0) {
      bytes = Uint8List.fromList(raw);
    } else if (method == 8) {
      try {
        bytes = Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
      } catch (error) {
        throw ZipFormatException('「$name」解压失败：$error');
      }
    } else {
      throw ZipFormatException('不支持的压缩方式（$method），请用本应用生成的备份包');
    }

    if (crc32(bytes) != checksum) {
      throw ZipFormatException('「$name」校验失败，文件可能已损坏');
    }

    totalBytes += bytes.length;
    if (totalBytes > maxTotalBytes) {
      throw const ZipFormatException('备份包解压后过大，已中止');
    }
    files.add(UnzippedFile(name, bytes));
  }

  return files;
}
