/// 链接元数据抓取：分享进来往往只有一个 URL（X 甚至只给 t.co 短链）。
/// 标题和摘要不是「分享时传过来的」，而是接收方自己去网页 head 里读的 ——
/// 微信就是这么做的，这里做同一件事。
///
/// 只用 dart:io 的 HttpClient，零三方依赖。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String _userAgent =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/120.0.0.0 Mobile Safari/537.36';

class LinkMetadata {
  /// 跟完重定向后的真实地址（t.co 会解析成目标页）
  final String finalUrl;
  final String? title;
  final String? description;
  final String? imageUrl;

  const LinkMetadata({
    required this.finalUrl,
    this.title,
    this.description,
    this.imageUrl,
  });

  bool get hasContent => (title?.isNotEmpty ?? false) || (description?.isNotEmpty ?? false);
}

class MetadataResult {
  final LinkMetadata? data;
  final String? error;

  const MetadataResult.ok(this.data) : error = null;

  const MetadataResult.failed(this.error) : data = null;

  bool get ok => data != null;
}

/// 抓取一个链接的标题 / 摘要 / 封面地址。
///
/// 只读网页前 160KB：og 标签都在 head 里，不需要整页。
/// 短链（t.co）会跟重定向；若对方用 meta refresh 跳转，再补一次请求。
Future<MetadataResult> fetchLinkMetadata(
  String rawUrl, {
  Duration timeout = const Duration(seconds: 10),
  int maxBytes = 160 * 1024,
}) async {
  final url = rawUrl.trim();
  if (url.isEmpty) return const MetadataResult.failed('没有链接');
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return const MetadataResult.failed('不是可访问的网页链接');
  }

  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = _userAgent
    ..autoUncompress = true;

  try {
    var target = url;
    for (var hop = 0; hop < 3; hop++) {
      final page = await _fetch(client, target, timeout, maxBytes);
      if (page == null) return const MetadataResult.failed('网页打不开');

      // t.co 之类有时不用 3xx，而是在 body 里写 meta refresh
      final refreshed = metaRefreshTarget(page.body);
      if (refreshed != null) {
        final next = Uri.tryParse(page.finalUrl)?.resolve(refreshed).toString() ?? refreshed;
        if (next != target) {
          target = next;
          continue;
        }
      }

      final meta = parseHtmlMetadata(page.body, finalUrl: page.finalUrl);
      if (meta.hasContent) return MetadataResult.ok(meta);
      return const MetadataResult.failed('页面里没有标题信息');
    }
    return const MetadataResult.failed('跳转次数过多');
  } on TimeoutException {
    return const MetadataResult.failed('请求超时');
  } on SocketException {
    return const MetadataResult.failed('网络不可用');
  } on HandshakeException {
    return const MetadataResult.failed('证书校验失败');
  } catch (error) {
    return MetadataResult.failed('抓取失败：$error');
  } finally {
    client.close(force: true);
  }
}

class _Page {
  final String finalUrl;
  final String body;

  const _Page(this.finalUrl, this.body);
}

Future<_Page?> _fetch(
  HttpClient client,
  String url,
  Duration timeout,
  int maxBytes,
) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;

  final request = await client.getUrl(uri).timeout(timeout);
  // 重定向参数是 request 级的，不是 client 级的
  request.followRedirects = true;
  request.maxRedirects = 6;
  request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,*/*;q=0.8');
  request.headers.set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9,en;q=0.8');

  final response = await request.close().timeout(timeout);
  if (response.statusCode < 200 || response.statusCode >= 400) return null;

  final builder = BytesBuilder(copy: false);
  try {
    await for (final chunk in response.timeout(timeout)) {
      builder.add(chunk);
      if (builder.length >= maxBytes) break;
    }
  } catch (_) {
    // 读够就断流，或连接提前结束，都按已读到的部分处理
  }

  final bytes = builder.takeBytes();
  if (bytes.isEmpty) return null;

  // 中文站点偶有 gbk，dart:convert 没有对应解码器，用容错 utf8 兜底
  final body = utf8.decode(bytes, allowMalformed: true);

  var finalUrl = url;
  if (response.redirects.isNotEmpty) {
    final last = response.redirects.last.location;
    finalUrl = last.hasScheme ? last.toString() : uri.resolveUri(last).toString();
  }

  return _Page(finalUrl, body);
}

/* --------------------------- 纯解析部分（可单测） --------------------------- */

/// 从 HTML 里提取标题 / 摘要 / 封面
LinkMetadata parseHtmlMetadata(String html, {String finalUrl = ''}) {
  final metas = <String, String>{};
  for (final match in RegExp(r'<meta\s[^>]*>', caseSensitive: false).allMatches(html)) {
    final tag = match.group(0)!;
    for (final key in const [
      'og:title',
      'og:description',
      'og:image',
      'twitter:title',
      'twitter:description',
      'twitter:image',
      'description',
    ]) {
      final value = _metaContent(tag, key);
      if (value != null && value.isNotEmpty) {
        metas.putIfAbsent(key, () => value);
      }
    }
  }

  final ogTitle = _clean(metas['og:title'] ?? metas['twitter:title']);
  final htmlTitle = _clean(_htmlTitle(html));
  final ogDesc = _clean(
    metas['og:description'] ?? metas['twitter:description'] ?? metas['description'],
  );
  final image = _clean(metas['og:image'] ?? metas['twitter:image']);

  return LinkMetadata(
    finalUrl: finalUrl,
    title: pickTitle(
      ogTitle: ogTitle,
      htmlTitle: htmlTitle,
      ogDescription: ogDesc,
      host: hostOf(finalUrl),
    ),
    description: ogDesc == null ? null : _limit(ogDesc, 200),
    imageUrl: image,
  );
}

/// 选标题。
///
/// 社交站点（X / Twitter）要特殊对待：`og:title` 只有「X 上的某人 (@handle)」，
/// 真正的正文藏在 `<title>` 里（`某人 on X: "正文" / X`，中文下是 `X 上的某人："正文" / X`）。
/// 这个判断只对社交域名生效——普通站点标题本身可能带冒号，不能一刀切。
String? pickTitle({
  String? ogTitle,
  String? htmlTitle,
  String? ogDescription,
  String? host,
}) {
  final og = _clean(ogTitle);
  final html = _clean(htmlTitle);
  final desc = _clean(ogDescription);

  if (isSocialHost(host)) {
    final body = _bodyFromSocialTitle(html);
    if (body != null) return _limit(body, 120);
    // 账号页没有正文，简介也比一串账号名有用
    if (desc != null) return _limit(desc, 120);
    if (og != null) return _limit(og, 120);
    return null;
  }

  // 常规站点：OG 标题一般最干净
  if (og != null && !isSocialAccountTitle(og)) return _limit(og, 120);

  // 退回 HTML 标题（去掉末尾「/ 站点名」）
  if (html != null) return _limit(_stripSiteSuffix(html), 120);

  if (og != null) return _limit(og, 120);
  return desc == null ? null : _limit(desc, 120);
}

/// X / Twitter 这类站点
bool isSocialHost(String? host) {
  if (host == null) return false;
  final h = host.toLowerCase();
  return h == 'x.com' ||
      h == 'twitter.com' ||
      h.endsWith('.x.com') ||
      h.endsWith('.twitter.com');
}

String? hostOf(String url) {
  if (url.isEmpty) return null;
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// 从社交站点的 `<title>` 里剥出正文，剥不出来返回 null
String? _bodyFromSocialTitle(String? htmlTitle) {
  if (htmlTitle == null) return null;
  final stripped = _stripSiteSuffix(htmlTitle);
  final match = RegExp(r'[:：]\s*([\s\S]+)$').firstMatch(stripped);
  if (match == null) return null;
  final body = _unwrapQuotes(match.group(1)!.trim());
  return body.isEmpty ? null : body;
}

/// 「某某 on X」「某某 on Twitter」这类只有账号名的标题
bool isSocialAccountTitle(String title) =>
    RegExp(r'\s+on\s+(?:X|Twitter)$', caseSensitive: false).hasMatch(title.trim());

/// 从 meta refresh 里取跳转目标（t.co 在部分客户端会这么跳）
String? metaRefreshTarget(String html) {
  final head = html.length > 4000 ? html.substring(0, 4000) : html;
  final tag = RegExp(
    r'<meta[^>]+http-equiv\s*=\s*["' "'" r']?refresh["' "'" r']?[^>]*>',
    caseSensitive: false,
  ).firstMatch(head);
  if (tag == null) return null;
  final target = RegExp(r'url\s*=\s*["' "'" r']?([^"'' >]+)', caseSensitive: false)
      .firstMatch(tag.group(0)!);
  return target?.group(1);
}

/* ------------------------------- 小工具 ------------------------------- */

String? _clean(String? value) {
  if (value == null) return null;
  final decoded = _decodeEntities(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  return decoded.isEmpty ? null : decoded;
}

String _limit(String text, int max) => text.length <= max ? text : '${text.substring(0, max).trim()}…';

String _stripSiteSuffix(String title) =>
    title.replaceAll(RegExp(r'\s*[/|·-]\s*(?:X|Twitter)\s*$', caseSensitive: false), '').trim();

String _unwrapQuotes(String text) {
  var out = text.trim();
  while (out.length >= 2) {
    final first = out[0];
    final last = out[out.length - 1];
    if ((first == '"' && last == '"') ||
        (first == '“' && last == '”') ||
        (first == '「' && last == '」')) {
      out = out.substring(1, out.length - 1).trim();
    } else {
      break;
    }
  }
  return out;
}

String? _htmlTitle(String html) {
  final match = RegExp(r'<title[^>]*>([\s\S]{0,300}?)</title>', caseSensitive: false)
      .firstMatch(html);
  return match?.group(1);
}

String? _metaContent(String tag, String key) {
  if (!tag.toLowerCase().contains(key.toLowerCase())) return null;
  final match = RegExp(r'''content\s*=\s*["']([^"']*)["']''', caseSensitive: false).firstMatch(tag);
  return match?.group(1);
}

String _decodeEntities(String input) {
  var out = input
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
  out = out.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 63),
  );
  return out.replaceAll('&amp;', '&');
}
