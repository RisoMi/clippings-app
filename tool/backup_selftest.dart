/// 备份包自检：
///   1) 用真实数据打一个备份包，供外部工具（Python zipfile）验证能否正常打开；
///   2) 反向读取外部工具生成的压缩包，验证解包器兼容 deflate。
///
/// 用法：
///   dart run tool/backup_selftest.dart            生成 build/backup_selftest.zip
///   dart run tool/backup_selftest.dart <zip 路径> 读取并解析该压缩包
library;

import 'dart:convert';
import 'dart:io';

import 'package:clippings/backup.dart';
import 'package:clippings/models.dart';
import 'package:clippings/zip.dart';

void main(List<String> args) {
  if (args.isNotEmpty) {
    _read(args.first);
    return;
  }
  _build();
}

void _build() {
  final now = DateTime(2026, 11, 12, 10, 30);
  final clips = [
    Clip(
      id: 'c_1',
      type: ClipType.link,
      title: '如何用一张卡片整理零散灵感',
      summary: '把刷到的好内容先存下来。',
      source: '少数派 · sspai.com',
      url: 'https://sspai.com/post/84217',
      domain: 'sspai.com',
      tags: const ['效率工具'],
      createdAt: now,
    ),
    Clip(
      id: 'c_2',
      type: ClipType.image,
      title: '周末在颐和路拍到的光',
      summary: '梧桐叶上的下午。',
      source: '小红书 · 09:24',
      url: '',
      domain: '',
      tags: const ['摄影'],
      createdAt: now.subtract(const Duration(hours: 3)),
      imageFileName: 'pic_1.jpg',
    ),
  ];
  const tags = [
    AppTag(name: '效率工具', color: 0xFF2F6A54),
    AppTag(name: '摄影', color: 0xFFC1A47C),
  ];
  final images = <String, List<int>>{
    'pic_1.jpg': List<int>.generate(2048, (i) => (i * 11) % 256),
  };

  final archive = buildZipArchive(
    buildBackupEntries(clips: clips, tags: tags, images: images, now: now),
  );
  final out = File('build/backup_selftest.zip');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(archive);

  // 立刻用自家解包器回读一遍，确认打包与解析自洽
  final back = parseBackup(unzipArchive(archive));
  stdout.writeln('path=${out.absolute.path}');
  stdout.writeln('bytes=${archive.length}');
  stdout.writeln('self_roundtrip_clips=${back.clipCount} tags=${back.tags.length} images=${back.imageCount}');
}

void _read(String path) {
  final bytes = File(path).readAsBytesSync();
  final content = parseBackup(unzipArchive(bytes));
  stdout.writeln('解析成功：');
  stdout.writeln('  clips=${content.clipCount}');
  stdout.writeln('  tags=${content.tagCount}');
  stdout.writeln('  images=${content.imageCount}');
  stdout.writeln('  schema=${content.manifest.schema}');
  stdout.writeln('  first_title=${content.clips.isEmpty ? '(空)' : content.clips.first.title}');
  stdout.writeln('  image_keys=${content.images.keys.join(",")}');
  // 顺带确认中文没被 UTF-8 解码破坏
  if (content.tags.isNotEmpty) {
    stdout.writeln('  tag_names=${content.tags.map((t) => t.name).join(",")}');
  }
  if (content.tags.isNotEmpty && utf8.encode(content.tags.first.name).isEmpty) {
    stderr.writeln('警告：标签名解码异常');
    exitCode = 1;
  }
}
