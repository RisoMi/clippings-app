import 'package:clippings/core.dart';
import 'package:clippings/metadata.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只测纯解析部分（不发网络请求）。
/// 样例 HTML 取自实测抓取的页面结构，尤其是 X 的那段。
void main() {
  group('普通站点', () {
    const html = '''
<html><head>
<title>如何用一张卡片整理零散灵感 - 少数派</title>
<meta property="og:title" content="如何用一张卡片整理零散灵感" />
<meta property="og:description" content="把刷到的好内容先存下来。" />
<meta property="og:image" content="https://cdn.sspai.com/cover.jpg" />
</head><body></body></html>
''';

    test('优先用 og:title，摘要与封面一起拿到', () {
      final meta = parseHtmlMetadata(html, finalUrl: 'https://sspai.com/post/1');
      expect(meta.title, '如何用一张卡片整理零散灵感');
      expect(meta.description, '把刷到的好内容先存下来。');
      expect(meta.imageUrl, 'https://cdn.sspai.com/cover.jpg');
      expect(meta.finalUrl, 'https://sspai.com/post/1');
      expect(meta.hasContent, isTrue);
    });

    test('属性顺序颠倒也能解析（content 在 property 前）', () {
      const reversed = '''
<meta content="倒序也能读" property="og:title" />
''';
      expect(parseHtmlMetadata(reversed).title, '倒序也能读');
    });

    test('HTML 实体解码', () {
      const escaped = '''
<meta property="og:title" content="A &amp; B &#39;quoted&#39; &quot;x&quot;" />
''';
      expect(parseHtmlMetadata(escaped).title, 'A & B \'quoted\' "x"');
    });
  });

  group('X 的页面（实测结构）', () {
    // 这段来自真实推文页：og:title 只有账号名，正文在 <title> 里
    const xhtml = '''
<html><head>
<meta property="og:title" content="Elon Musk (@elonmusk) on X"/>
<meta name="twitter:title" content="Elon Musk (@elonmusk) on X"/>
<meta property="og:description" content="Tesla Megapacks are designed to ensure grid stability" />
<meta property="og:image" content="https://pbs.twimg.com/profile_images/2103567689515954176/aR-Kjpp4_400x400.jpg" />
<title>Elon Musk on X: &quot;Tesla Megapacks are designed to ensure grid stability&quot; / X</title>
</head></html>
''';

    test('英文环境：放弃「账号 on X」，取 <title> 里的正文', () {
      final meta = parseHtmlMetadata(xhtml, finalUrl: 'https://x.com/elonmusk/status/1');
      expect(meta.title, 'Tesla Megapacks are designed to ensure grid stability');
      expect(meta.description, 'Tesla Megapacks are designed to ensure grid stability');
    });

    test('中文环境：X 会把标题本地化成「X 上的某人：“正文”」', () {
      // 实测 zh-CN 下拿到的结构
      const zh = '''
<html><head>
<meta property="og:title" content="X 上的 Elon Musk (@elonmusk)"/>
<meta property="og:description" content="Tesla Megapacks are designed to ensure grid stability" />
<title>X 上的 Elon Musk：“Tesla Megapacks are designed to ensure grid stability” / X</title>
</head></html>
''';
      final meta = parseHtmlMetadata(zh, finalUrl: 'https://x.com/elonmusk/status/1');
      expect(meta.title, 'Tesla Megapacks are designed to ensure grid stability');
    });

    test('账号主页没有正文时用简介兜底', () {
      const profile = '''
<html><head>
<meta property="og:title" content="X 上的 Elon Musk (@elonmusk)"/>
<meta property="og:description" content="Tesla、SpaceX 等公司负责人" />
<title>X 上的 Elon Musk (@elonmusk)</title>
</head></html>
''';
      final meta = parseHtmlMetadata(profile, finalUrl: 'https://x.com/elonmusk');
      expect(meta.title, 'Tesla、SpaceX 等公司负责人');
    });

    test('账号名式的标题会被识别出来', () {
      expect(isSocialAccountTitle('Elon Musk (@elonmusk) on X'), isTrue);
      expect(isSocialAccountTitle('某某 on Twitter'), isTrue);
      expect(isSocialAccountTitle('X 上的内容'), isFalse);
      expect(isSocialAccountTitle('如何整理零散灵感'), isFalse);
    });

    test('社交域名判断', () {
      expect(isSocialHost('x.com'), isTrue);
      expect(isSocialHost('twitter.com'), isTrue);
      expect(isSocialHost('mobile.twitter.com'), isTrue);
      expect(isSocialHost('sspai.com'), isFalse);
      expect(isSocialHost(null), isFalse);
    });
  });

  group('标题选择', () {
    test('没有 OG 时退回 <title>', () {
      expect(pickTitle(htmlTitle: '某篇文章标题'), '某篇文章标题');
    });

    test('X 式 title 取正文并去掉引号与站点尾巴', () {
      expect(
        pickTitle(htmlTitle: '张三 on X: “今天试了个新东西” / X', host: 'x.com'),
        '今天试了个新东西',
      );
    });

    test('普通站点的标题带冒号时不能被截断', () {
      // 只在社交域名上才把冒号后面的部分当正文，否则「React: 深入理解」会被砍成「深入理解」
      expect(
        pickTitle(ogTitle: 'React: 深入理解原理', host: 'juejin.cn'),
        'React: 深入理解原理',
      );
      expect(
        pickTitle(htmlTitle: '读书笔记：第三部分', host: 'sspai.com'),
        '读书笔记：第三部分',
      );
    });

    test('只有摘要时用摘要兜底', () {
      expect(pickTitle(ogDescription: '只有一段描述'), '只有一段描述');
    });

    test('全空返回 null', () {
      expect(pickTitle(), isNull);
    });
  });

  group('其它', () {
    test('meta refresh 能取出跳转目标（t.co 在部分客户端的跳法）', () {
      const html =
          '<html><head><meta http-equiv="refresh" content="0;URL=https://example.com/a?b=1"></head></html>';
      expect(metaRefreshTarget(html), 'https://example.com/a?b=1');
    });

    test('没有 meta refresh 返回 null', () {
      expect(metaRefreshTarget('<html><head></head></html>'), isNull);
    });

    test('describeSource 拼出站点名与域名', () {
      expect(describeSource('https://sspai.com/post/1'), '少数派 · sspai.com');
      expect(describeSource('https://unknown.site/x'), 'unknown.site · unknown.site');
      expect(describeSource('not a url'), '剪藏库');
    });

    test('页面没有标题信息时 hasContent 为假', () {
      final meta = parseHtmlMetadata('<html><head></head><body>hi</body></html>');
      expect(meta.hasContent, isFalse);
    });
  });
}
