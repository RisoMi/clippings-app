import 'dart:convert';
import 'dart:typed_data';

import 'package:clippings/backup.dart';
import 'package:clippings/models.dart';
import 'package:clippings/zip.dart';
import 'package:flutter_test/flutter_test.dart';

Clip _clip(String id, {String? image, DateTime? at}) => Clip(
      id: id,
      type: image == null ? ClipType.link : ClipType.image,
      title: '标题 $id',
      summary: '摘要',
      source: '来源',
      url: 'https://example.com/$id',
      domain: 'example.com',
      tags: const ['效率工具'],
      createdAt: at ?? DateTime(2026, 11, 12, 10),
      imageFileName: image,
    );

void main() {
  group('ZIP 读写', () {
    test('打包再解包，文本与二进制都一致', () {
      final now = DateTime(2026, 11, 12, 10);
      final binary = Uint8List.fromList(List.generate(1024, (i) => (i * 7) % 256));
      final archive = buildZipArchive([
        ZipEntry('a.md', utf8.encode('# 标题\n正文'), modified: now),
        ZipEntry('images/图片 1.jpg', binary, modified: now),
      ]);

      final files = unzipArchive(archive);
      expect(files.length, 2);
      expect(utf8.decode(files[0].bytes), '# 标题\n正文');
      expect(files[1].name, 'images/图片 1.jpg');
      expect(files[1].bytes, binary);
    });

    test('空压缩包解出 0 项', () {
      expect(unzipArchive(buildZipArchive([])), isEmpty);
    });

    test('垃圾数据抛 ZipFormatException', () {
      expect(
        () => unzipArchive(Uint8List.fromList(List.filled(64, 0))),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('拒绝 .. 路径穿越', () {
      final archive = buildZipArchive([
        ZipEntry('../evil.txt', utf8.encode('x'), modified: DateTime(2026, 11, 12)),
      ]);
      expect(() => unzipArchive(archive), throwsA(isA<ZipFormatException>()));
    });

    test('拒绝绝对路径', () {
      final archive = buildZipArchive([
        ZipEntry('/etc/evil', utf8.encode('x'), modified: DateTime(2026, 11, 12)),
      ]);
      expect(() => unzipArchive(archive), throwsA(isA<ZipFormatException>()));
    });

    test('数据被篡改时 CRC 校验能拦住', () {
      final archive = buildZipArchive([
        ZipEntry('a.txt', utf8.encode('hello'), modified: DateTime(2026, 11, 12)),
      ]);
      // 本地头 30 字节 + 文件名 'a.txt' 5 字节 = 35，从这里开始是数据区
      archive[35] = archive[35] ^ 0xFF;
      expect(() => unzipArchive(archive), throwsA(isA<ZipFormatException>()));
    });
  });

  group('备份包', () {
    test('打包再解析，收藏 / 标签 / 图片都对得上', () {
      final now = DateTime(2026, 11, 12, 10);
      final clips = [_clip('a'), _clip('b', image: 'pic.jpg')];
      const tags = [AppTag(name: '效率工具', color: 0xFF2F6A54)];
      final images = {'pic.jpg': utf8.encode('fake-image-bytes')};

      final content = parseBackup(
        unzipArchive(
          buildZipArchive(buildBackupEntries(clips: clips, tags: tags, images: images, now: now)),
        ),
      );

      expect(content.clips.length, 2);
      expect(content.clips.map((c) => c.id), containsAll(['a', 'b']));
      expect(content.tags.single.name, '效率工具');
      expect(utf8.decode(content.images['pic.jpg']!), 'fake-image-bytes');
      expect(content.manifest.schema, 1);
      expect(content.manifest.exportedAt.year, 2026);
    });

    test('不是本应用的备份时给出明确错误', () {
      final now = DateTime(2026, 11, 12);
      final archive = buildZipArchive([
        ZipEntry(
          'manifest.json',
          utf8.encode(jsonEncode({'app': 'other.app', 'schema': 1})),
          modified: now,
        ),
      ]);
      expect(() => parseBackup(unzipArchive(archive)), throwsA(isA<BackupException>()));
    });

    test('缺少 manifest 时报错', () {
      final archive = buildZipArchive([
        ZipEntry('clips.json', utf8.encode('[]'), modified: DateTime(2026, 11, 12)),
      ]);
      expect(() => parseBackup(unzipArchive(archive)), throwsA(isA<BackupException>()));
    });

    test('备份来自更高 schema 时提示先升级', () {
      final now = DateTime(2026, 11, 12);
      final archive = buildZipArchive([
        ZipEntry(
          'manifest.json',
          utf8.encode(jsonEncode({'app': backupAppId, 'schema': 99})),
          modified: now,
        ),
        ZipEntry('clips.json', utf8.encode('[]'), modified: now),
      ]);
      expect(() => parseBackup(unzipArchive(archive)), throwsA(isA<BackupException>()));
    });
  });

  group('导入判定', () {
    test('只有示例数据（或为空）→ 可直接覆盖', () {
      expect(onlySampleData([]), isTrue);
      expect(onlySampleData([_clip('seed-link-1')]), isTrue);
      expect(onlySampleData([_clip('seed-link-1'), _clip('c_abc')]), isFalse);
    });

    test('合并按 id 去重，同 id 以备份为准', () {
      final local = [_clip('a', at: DateTime(2026, 11, 10))];
      final incoming = [
        Clip(
          id: 'a',
          type: ClipType.text,
          title: '备份版本',
          summary: '',
          source: '',
          url: '',
          domain: '',
          tags: const [],
          createdAt: DateTime(2026, 11, 12),
        ),
        _clip('b', at: DateTime(2026, 11, 11)),
      ];

      final merged = mergeClips(local, incoming);
      expect(merged.length, 2);
      expect(merged.firstWhere((c) => c.id == 'a').title, '备份版本');
      expect(merged.first.id, 'a', reason: '结果按时间倒序');
    });

    test('合并标签保留本地配色', () {
      const local = [AppTag(name: '甲', color: 0xFF111111)];
      const incoming = [AppTag(name: '甲', color: 0xFF999999), AppTag(name: '乙')];

      final merged = mergeTags(local, incoming);
      expect(merged.length, 2);
      expect(merged.firstWhere((t) => t.name == '甲').color, 0xFF111111);
    });

    test('备份文件名带日期且补零', () {
      expect(buildBackupFileName(DateTime(2026, 11, 12)), 'clippings-backup-2026-11-12.zip');
      expect(buildBackupFileName(DateTime(2026, 1, 5)), 'clippings-backup-2026-01-05.zip');
    });
  });
}
