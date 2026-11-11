/// 自检脚本：生成一个真实的 zip 文件，交给外部工具验证结构是否合法。
/// 用法：dart run tool/zip_selftest.dart
/// 单测只能验证字节布局自洽，这里产出真实文件，再用 Python 的 zipfile 解一遍，
/// 才能确认「别的软件打得开」。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clippings/zip.dart';

void main() {
  final now = DateTime(2026, 11, 11, 10, 30, 0);
  final md = [
    '# 我的剪藏',
    '',
    '> 导出于 2026-11-11 · 共 2 条',
    '',
    '### [如何用一张卡片整理零散灵感](https://sspai.com/post/84217)',
    '- 来源：少数派 · sspai.com · 2026-11-11 10:00',
    '- 原文：https://sspai.com/post/84217',
    '',
    '![周末在颐和路拍到的光](images/img_1.jpg)',
    '',
  ].join('\n');

  final entries = <ZipEntry>[
    ZipEntry('clips-2026-11-11.md', utf8.encode(md), modified: now),
    ZipEntry(
      'images/img_1.jpg',
      Uint8List.fromList(List<int>.generate(4096, (i) => (i * 37) % 256)),
      modified: now,
    ),
  ];

  final bytes = buildZipArchive(entries);
  final out = File('build/zip_selftest.zip');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);

  stdout.writeln('path=${out.absolute.path}');
  stdout.writeln('bytes=${bytes.length}');
  stdout.writeln('crc_of_table_check=${crc32(utf8.encode('123456789'))}');
}
