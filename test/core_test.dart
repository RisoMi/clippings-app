import 'dart:convert';
import 'dart:typed_data';

import 'package:clippings/core.dart';
import 'package:clippings/models.dart';
import 'package:clippings/zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('类型识别', () {
    test('链接 + 混排文字 → link，并解析站点名', () {
      final result = detectContent(
        text: '刷到好内容别急着读完，先存下来。 https://sspai.com/post/84217',
      );
      expect(result, isNotNull);
      expect(result!.type, ClipType.link);
      expect(result.url, 'https://sspai.com/post/84217');
      expect(result.domain, 'sspai.com');
      expect(result.source, contains('少数派'));
      expect(result.title, '刷到好内容别急着读完，先存下来');
    });

    test('显式标题优先于正文首句', () {
      final result = detectContent(
        title: '把灵感存进第二大脑',
        text: '这是一段正文 https://mp.weixin.qq.com/s/abc',
        url: 'https://mp.weixin.qq.com/s/abc',
      );
      expect(result!.title, '把灵感存进第二大脑');
      expect(result.domain, 'mp.weixin.qq.com');
      expect(result.source, contains('微信公众号'));
    });

    test('纯文本 → text，标题取首句并截断', () {
      final result = detectContent(
        text: '「信息的价值不在于收藏那一刻，而在于重新找到它的那一刻。」后面还有很多内容。',
      );
      expect(result!.type, ClipType.text);
      expect(result.url, isEmpty);
      expect(result.title.startsWith('「信息'), isTrue);
      expect(result.title.length, lessThanOrEqualTo(27));
    });

    test('空输入返回 null', () {
      expect(detectContent(), isNull);
      expect(detectContent(text: '   '), isNull);
    });

    test('parseDomain 去掉 www，非法输入返回空串', () {
      expect(parseDomain('https://www.sspai.com/post/1'), 'sspai.com');
      expect(parseDomain('not a url'), '');
    });

    test('分享参数组合解析', () {
      final result = detectFromShare(
        title: '周末在颐和路拍到的光',
        text: '那天下午的光刚好落在梧桐叶上',
        url: 'https://www.xiaohongshu.com/discovery/item/123',
      );
      expect(result!.type, ClipType.link);
      expect(result.domain, 'xiaohongshu.com');
      expect(result.title, '周末在颐和路拍到的光');
    });
  });

  group('检索与分组', () {
    final clips = [
      Clip(
        id: 'a',
        type: ClipType.link,
        title: '如何用一张卡片整理零散灵感',
        summary: '把刷到的好内容先存下来',
        source: '少数派 · sspai.com',
        url: 'https://sspai.com/post/84217',
        domain: 'sspai.com',
        tags: const ['效率工具'],
        createdAt: DateTime(2026, 11, 11, 10),
      ),
      Clip(
        id: 'b',
        type: ClipType.image,
        title: '周末在颐和路拍到的光',
        summary: '梧桐叶上的下午',
        source: '小红书 · xiaohongshu.com',
        url: '',
        domain: '',
        tags: const ['摄影'],
        createdAt: DateTime(2026, 11, 11, 9),
      ),
    ];

    test('命中标题、标签、来源域名', () {
      expect(searchClips(clips, keyword: '卡片').length, 1);
      expect(searchClips(clips, keyword: '摄影').length, 1);
      expect(searchClips(clips, keyword: 'xiaohongshu').length, 1);
      expect(searchClips(clips, keyword: '').length, 2);
    });

    test('类型筛选与关键词叠加', () {
      expect(searchClips(clips, keyword: '光', type: ClipType.image).length, 1);
      expect(searchClips(clips, keyword: '光', type: ClipType.link).length, 0);
    });

    test('按今天 / 昨天 / 更早分组', () {
      final now = DateTime(2026, 11, 11, 12);
      final groups = groupByDay([
        Clip(
          id: '1',
          type: ClipType.text,
          title: 't1',
          summary: '',
          source: '',
          url: '',
          domain: '',
          tags: const [],
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
        Clip(
          id: '2',
          type: ClipType.text,
          title: 't2',
          summary: '',
          source: '',
          url: '',
          domain: '',
          tags: const [],
          createdAt: now.subtract(const Duration(hours: 26)),
        ),
        Clip(
          id: '3',
          type: ClipType.text,
          title: 't3',
          summary: '',
          source: '',
          url: '',
          domain: '',
          tags: const [],
          createdAt: now.subtract(const Duration(days: 5)),
        ),
      ], now: now);

      expect(groups[0].label, '今天');
      expect(groups[1].label, '昨天');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(groups[2].label), isTrue);
    });
  });

  group('导出', () {
    final clip = Clip(
      id: 'a',
      type: ClipType.link,
      title: '如何用一张卡片整理零散灵感',
      summary: '把刷到的好内容先存下来',
      source: '少数派 · sspai.com',
      url: 'https://sspai.com/post/84217',
      domain: 'sspai.com',
      tags: const ['效率工具', '待读'],
      createdAt: DateTime(2026, 11, 11, 10),
    );

    test('Markdown 包含链接语法、标签与来源', () {
      final content = exportMarkdown([clip], groupByTime: false, now: DateTime(2026, 11, 11));
      expect(content.startsWith('# 我的剪藏'), isTrue);
      expect(content, contains('### [如何用一张卡片整理零散灵感](https://sspai.com/post/84217)'));
      expect(content, contains('标签：效率工具 / 待读'));
      expect(content, contains('来源：少数派 · sspai.com'));
      expect(content, contains('---'));
    });

    test('按时间分组时输出二级标题', () {
      final now = DateTime(2026, 11, 11, 12);
      final today = Clip(
        id: 'a',
        type: ClipType.link,
        title: '标题',
        summary: '',
        source: '',
        url: '',
        domain: '',
        tags: const [],
        createdAt: now.subtract(const Duration(hours: 1)),
      );
      expect(exportMarkdown([today], now: now), contains('## 今天'));
    });

    test('纯文本不含 Markdown 语法', () {
      final content = exportText([clip], groupByTime: false);
      expect(content, contains('· 如何用一张卡片整理零散灵感'));
      expect(content.contains('###'), isFalse);
    });

    test('空列表有兜底文案', () {
      expect(exportMarkdown([], now: DateTime(2026, 11, 11)), contains('暂无内容'));
    });

    test('文件名按日期与格式生成', () {
      final ts = DateTime(2026, 11, 11);
      expect(buildExportFileName('md', now: ts), 'clips-2026-11-11.md');
      expect(buildExportFileName('txt', now: ts), 'clips-2026-11-11.txt');
    });

    test('图片使用相对路径引用', () {
      final withImage = Clip(
        id: 'img',
        type: ClipType.image,
        title: '照片',
        summary: '',
        source: '',
        url: '',
        domain: '',
        tags: const [],
        createdAt: DateTime(2026, 11, 11),
        imageFileName: 'img_1.jpg',
      );
      final content = exportMarkdown([withImage], groupByTime: false, now: DateTime(2026, 11, 11));
      expect(content, contains('![照片](images/img_1.jpg)'));
    });
  });

  group('标签推荐', () {
    test('来源站点 + 类型组合，最多 3 个', () {
      final tags = suggestTags(
        const Detected(
          type: ClipType.link,
          title: '',
          summary: '',
          source: '',
          url: '',
          domain: 'sspai.com',
        ),
        const [
          TagCount(name: '效率工具', count: 9, color: 0xFF2F6A54),
          TagCount(name: '待读', count: 4, color: 0xFF2F6A54),
          TagCount(name: '旅行', count: 1, color: 0xFF2F6A54),
        ],
      );
      expect(tags, contains('效率工具'));
      expect(tags, contains('待读'));
      expect(tags.length, lessThanOrEqualTo(3));
    });

    test('纯文本归类到摘录', () {
      final tags = suggestTags(
        const Detected(
          type: ClipType.text,
          title: '',
          summary: '',
          source: '',
          url: '',
          domain: '',
        ),
        const [],
      );
      expect(tags, ['摘录']);
    });
  });

  group('导出链接与压缩包', () {
    final linkClip = Clip(
      id: 'a',
      type: ClipType.link,
      title: '标题',
      summary: '摘要',
      source: '少数派',
      url: 'https://sspai.com/post/84217',
      domain: 'sspai.com',
      tags: const [],
      createdAt: DateTime(2026, 11, 11, 10),
    );

    test('Markdown 与纯文本都单列原文链接', () {
      final md = exportMarkdown([linkClip], groupByTime: false, now: DateTime(2026, 11, 11));
      expect(md, contains('- 原文：https://sspai.com/post/84217'));
      final txt = exportText([linkClip], groupByTime: false, now: DateTime(2026, 11, 11));
      expect(txt, contains('  原文：https://sspai.com/post/84217'));
    });

    test('纯文本可带图片相对路径', () {
      final imgClip = Clip(
        id: 'i',
        type: ClipType.image,
        title: '照片',
        summary: '',
        source: '',
        url: '',
        domain: '',
        tags: const [],
        createdAt: DateTime(2026, 11, 11),
        imageFileName: 'img_1.jpg',
      );
      expect(exportText([imgClip], groupByTime: false), isNot(contains('图片：')));
      expect(
        exportText([imgClip], groupByTime: false, includeImages: true),
        contains('  图片：images/img_1.jpg'),
      );
    });

    test('压缩包与基础文件名', () {
      final ts = DateTime(2026, 11, 11);
      expect(buildExportBaseName(now: ts), 'clips-2026-11-11');
      expect(buildExportZipFileName(now: ts), 'clips-2026-11-11.zip');
    });

    test('crc32 命中标准校验向量', () {
      // 通用校验向量："123456789" → 0xCBF43926
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
      expect(crc32(const []), 0);
    });

    test('ZIP 结构：本地头 / 中央目录 / EOCD 数量与偏移自洽', () {
      final bytes = buildZipArchive([
        ZipEntry('a.md', utf8.encode('# hi'), modified: DateTime(2026, 11, 11, 10)),
        ZipEntry(
          'images/b.jpg',
          Uint8List.fromList(List.filled(10, 7)),
          modified: DateTime(2026, 11, 11, 10),
        ),
      ]);

      expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]); // PK\x03\x04
      final data = ByteData.sublistView(bytes);
      final eocd = bytes.length - 22;
      expect(data.getUint32(eocd, Endian.little), 0x06054b50);
      expect(data.getUint16(eocd + 8, Endian.little), 2); // 本盘条目数
      expect(data.getUint16(eocd + 10, Endian.little), 2); // 总条目数

      final cdSize = data.getUint32(eocd + 12, Endian.little);
      final cdOffset = data.getUint32(eocd + 16, Endian.little);
      expect(cdOffset + cdSize, eocd); // 中央目录之后紧接 EOCD
      expect(data.getUint32(cdOffset, Endian.little), 0x02014b50);
    });

    test('有图片且开关打开 → 走压缩包', () {
      final plan = planExport(
        [linkClip],
        format: 'md',
        includeImages: true,
        hasImages: true,
        now: DateTime(2026, 11, 11),
      );
      expect(plan.asZip, isTrue);
      expect(plan.fileName, 'clips-2026-11-11.zip');
      expect(plan.textFileName, 'clips-2026-11-11.md');
      expect(plan.mime, 'application/zip');
      expect(plan.content, contains('- 原文：https://sspai.com/post/84217'));
    });

    test('没有图片或关掉开关 → 单个文本文件', () {
      final noImage = planExport(
        [linkClip],
        format: 'md',
        includeImages: true,
        hasImages: false,
        now: DateTime(2026, 11, 11),
      );
      expect(noImage.asZip, isFalse);
      expect(noImage.fileName, 'clips-2026-11-11.md');
      expect(noImage.mime, 'text/markdown');

      final offSwitch = planExport(
        [linkClip],
        format: 'txt',
        includeImages: false,
        hasImages: true,
        now: DateTime(2026, 11, 11),
      );
      expect(offSwitch.asZip, isFalse);
      expect(offSwitch.fileName, 'clips-2026-11-11.txt');
      expect(offSwitch.mime, 'text/plain');
    });
  });
}
