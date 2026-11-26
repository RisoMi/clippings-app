/// 纯业务逻辑：类型识别、检索、时间分组、Markdown/纯文本导出、标签推荐。
/// 不依赖 Flutter 与 dart:io，可直接单元测试。
library;

import 'models.dart';

const _urlPattern = r'https?://[^\s<>"' r"'）】]+";

const _siteNames = <String, String>{
  'mp.weixin.qq.com': '微信公众号',
  'sspai.com': '少数派',
  'xiaohongshu.com': '小红书',
  'weibo.com': '微博',
  'zhihu.com': '知乎',
  'bilibili.com': '哔哩哔哩',
  'douyin.com': '抖音',
  'juejin.cn': '掘金',
  'github.com': 'GitHub',
  'youtube.com': 'YouTube',
  'medium.com': 'Medium',
};

const _siteTags = <String, String>{
  'sspai.com': '效率工具',
  'mp.weixin.qq.com': '摘录',
  'xiaohongshu.com': '摄影',
  'juejin.cn': '技术',
  'github.com': '技术',
};

const _typeTags = <ClipType, String>{
  ClipType.link: '待读',
  ClipType.text: '摘录',
  ClipType.image: '摄影',
};

/// 识别结果（尚未入库）
class Detected {
  final ClipType type;
  final String title;
  final String summary;
  final String source;
  final String url;
  final String domain;

  const Detected({
    required this.type,
    required this.title,
    required this.summary,
    required this.source,
    required this.url,
    required this.domain,
  });
}

String uid([String prefix = 'c']) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = DateTime.now().hashCode.toRadixString(36);
  return '${prefix}_$ts$rnd';
}

String parseDomain(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  } catch (_) {
    return '';
  }
}

String _firstSentence(String text, [int max = 32]) {
  final s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return '';
  final match = RegExp(r'^[^。！？.!?\n]{1,80}').firstMatch(s);
  final base = match?.group(0) ?? s;
  return base.length > max ? '${base.substring(0, max).trim()}…' : base;
}

/// 从剪贴板 / 分享内容识别类型。
Detected? detectContent({String text = '', String url = '', String title = ''}) {
  final raw = text.trim();
  final match = RegExp(_urlPattern, caseSensitive: false).firstMatch(raw);
  var candidate = url.trim();
  if (candidate.isEmpty && match != null) candidate = match.group(0) ?? '';

  if (candidate.isNotEmpty) {
    final cleanUrl = candidate.replaceAll(RegExp(r'[，。；、）】\s]+$'), '');
    final domain = parseDomain(cleanUrl);
    final siteName = _siteNames[domain] ?? (domain.isEmpty ? '网页' : domain);
    var rest = raw.replaceFirst(candidate, '').replaceFirst(cleanUrl, '').trim();
    final finalTitle = title.trim().isNotEmpty
        ? title.trim()
        : (rest.isNotEmpty ? _firstSentence(rest, 44) : '$siteName 上的内容');
    final summary = rest.isNotEmpty && rest != finalTitle
        ? (rest.length > 180 ? rest.substring(0, 180) : rest)
        : '来自 $siteName 的链接，点开可回溯原文。';
    return Detected(
      type: ClipType.link,
      title: finalTitle,
      summary: summary,
      source: domain.isEmpty ? siteName : '$siteName · $domain',
      url: cleanUrl,
      domain: domain,
    );
  }

  if (raw.isNotEmpty) {
    final finalTitle = title.trim().isNotEmpty ? title.trim() : _firstSentence(raw, 26);
    return Detected(
      type: ClipType.text,
      title: finalTitle,
      summary: raw.length > 400 ? raw.substring(0, 400) : raw,
      source: '剪贴板 · 文本',
      url: '',
      domain: '',
    );
  }

  return null;
}

/// 处理系统分享参数（Android Intent / 分享回调）
Detected? detectFromShare({String title = '', String text = '', String url = ''}) {
  final joined = [title, text].where((e) => e.trim().isNotEmpty).join(' ').trim();
  return detectContent(text: joined, url: url, title: title) ??
      detectContent(text: joined);
}

/// 标签推荐：来源站点 + 类型 + 高频已有标签，最多 3 个
List<String> suggestTags(Detected? detected, List<TagCount> known) {
  final picked = <String>{};
  final siteTag = _siteTags[detected?.domain ?? ''];
  if (siteTag != null) picked.add(siteTag);
  final typeTag = _typeTags[detected?.type];
  if (typeTag != null) picked.add(typeTag);
  final sorted = [...known]..sort((a, b) => b.count.compareTo(a.count));
  for (final tag in sorted.take(3)) {
    picked.add(tag.name);
  }
  return picked.take(3).toList();
}

List<Clip> searchClips(List<Clip> clips, {String keyword = '', ClipType? type}) {
  final kw = keyword.trim().toLowerCase();
  return clips.where((clip) {
    if (type != null && clip.type != type) return false;
    if (kw.isEmpty) return true;
    final haystack = [
      clip.title,
      clip.summary,
      clip.source,
      clip.url,
      clip.tags.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(kw);
  }).toList();
}

DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

String _pad2(int v) => v.toString().padLeft(2, '0');

String formatClock(DateTime t) => '${_pad2(t.hour)}:${_pad2(t.minute)}';

String formatDate(DateTime t) => '${t.year}-${_pad2(t.month)}-${_pad2(t.day)}';

String formatDateTime(DateTime t) => '${formatDate(t)} ${formatClock(t)}';

String formatRelative(DateTime t, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = _startOfDay(current);
  final yesterday = today.subtract(const Duration(days: 1));
  if (!t.isBefore(today)) {
    final diff = current.difference(t);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '今天 ${formatClock(t)}';
  }
  if (!t.isBefore(yesterday)) return '昨天 ${formatClock(t)}';
  return '${_pad2(t.month)}-${_pad2(t.day)}';
}

/// 某一天在列表里显示的标签：今天 / 昨天 / 具体日期。
String dayLabel(DateTime t, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = _startOfDay(current);
  final yesterday = today.subtract(const Duration(days: 1));
  if (!t.isBefore(today)) return '今天';
  if (!t.isBefore(yesterday)) return '昨天';
  return formatDate(t);
}

List<ClipGroup> groupByDay(List<Clip> clips, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final sorted = [...clips]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final groups = <ClipGroup>[];
  final index = <String, int>{};

  for (final clip in sorted) {
    final label = dayLabel(clip.createdAt, now: current);
    final existing = index[label];
    if (existing == null) {
      index[label] = groups.length;
      groups.add(ClipGroup(label: label, items: [clip]));
    } else {
      groups[existing].items.add(clip);
    }
  }
  return groups;
}

/// 导出页的一天：key 是稳定的 `YYYY-MM-DD`，label 是「今天 / 昨天 / 日期」。
/// 用 key 而不是 label 做选中态，避免「今天」隔天变成「昨天」后选中丢失。
class ExportDateGroup {
  final String key;
  final String label;
  final List<Clip> clips;

  const ExportDateGroup({
    required this.key,
    required this.label,
    required this.clips,
  });

  int get count => clips.length;
}

/// 只列出「有数据」的日期，按日期从新到旧排序；同一天内按时间从新到旧。
List<ExportDateGroup> groupByExportDate(List<Clip> clips, {DateTime? now}) {
  final buckets = <String, List<Clip>>{};
  for (final clip in clips) {
    (buckets[formatDate(clip.createdAt)] ??= []).add(clip);
  }
  final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  final current = now ?? DateTime.now();
  return [
    for (final key in keys)
      ExportDateGroup(
        key: key,
        label: dayLabel(buckets[key]!.first.createdAt, now: current),
        clips: [...buckets[key]!]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      ),
  ];
}

/// 默认选中的日期：有今天的数据就选今天，否则退到最近有数据的那天。
String? defaultExportDateKey(List<ExportDateGroup> groups, {DateTime? now}) {
  if (groups.isEmpty) return null;
  final todayKey = formatDate(now ?? DateTime.now());
  for (final group in groups) {
    if (group.key == todayKey) return group.key;
  }
  return groups.first.key;
}

String _tagSuffix(Clip clip) =>
    clip.tags.isEmpty ? '' : '\n- 标签：${clip.tags.join(' / ')}';

String exportMarkdown(
  List<Clip> clips, {
  bool groupByTime = true,
  bool includeImages = true,
  DateTime? now,
}) {
  final ts = now ?? DateTime.now();
  final buffer = StringBuffer()
    ..writeln('# 我的剪藏')
    ..writeln()
    ..writeln('> 导出于 ${formatDate(ts)} · 共 ${clips.length} 条')
    ..writeln();

  if (clips.isEmpty) {
    buffer.writeln('_暂无内容_');
    return buffer.toString();
  }

  final groups = groupByTime
      ? groupByDay(clips, now: ts)
      : [ClipGroup(label: '', items: [...clips]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))];

  for (final group in groups) {
    if (group.label.isNotEmpty) {
      buffer
        ..writeln('## ${group.label}')
        ..writeln();
    }
    for (final clip in group.items) {
      final url = clip.url.trim();
      final isLink = clip.type == ClipType.link && url.isNotEmpty;
      buffer.writeln(isLink ? '### [${clip.title}]($url)' : '### ${clip.title}');
      buffer.writeln(
        '- 来源：${clip.source.isEmpty ? '剪藏库' : clip.source} · ${formatDateTime(clip.createdAt)}${_tagSuffix(clip)}',
      );
      // 原文链接单独成行：标题上的链接在部分编辑器里点不动，这一行保证一定能访问
      if (url.isNotEmpty) {
        buffer.writeln('- 原文：$url');
      }
      if (clip.summary.trim().isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(clip.summary.trim())
          ..writeln();
      }
      if (includeImages && clip.imageFileName != null) {
        buffer
          ..writeln('![${clip.title}](images/${clip.imageFileName})')
          ..writeln();
      }
      buffer
        ..writeln('---')
        ..writeln();
    }
  }

  return '${buffer.toString().trimRight()}\n';
}

String exportText(
  List<Clip> clips, {
  bool groupByTime = true,
  bool includeImages = false,
  DateTime? now,
}) {
  final ts = now ?? DateTime.now();
  final buffer = StringBuffer()
    ..writeln('我的剪藏')
    ..writeln('导出于 ${formatDate(ts)} · 共 ${clips.length} 条')
    ..writeln();

  if (clips.isEmpty) {
    buffer.writeln('暂无内容');
    return buffer.toString();
  }

  final groups = groupByTime
      ? groupByDay(clips, now: ts)
      : [ClipGroup(label: '', items: [...clips]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))];

  for (final group in groups) {
    if (group.label.isNotEmpty) {
      buffer
        ..writeln('【${group.label}】')
        ..writeln();
    }
    for (final clip in group.items) {
      final url = clip.url.trim();
      buffer
        ..writeln('· ${clip.title}')
        ..writeln('  来源：${clip.source.isEmpty ? '剪藏库' : clip.source} · ${formatDateTime(clip.createdAt)}');
      if (clip.tags.isNotEmpty) {
        buffer.writeln('  标签：${clip.tags.join(' / ')}');
      }
      if (url.isNotEmpty) {
        buffer.writeln('  原文：$url');
      }
      if (includeImages && clip.imageFileName != null) {
        buffer.writeln('  图片：images/${clip.imageFileName}');
      }
      if (clip.summary.trim().isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(clip.summary.trim().split('\n').map((line) => '  $line').join('\n'));
      }
      buffer.writeln();
    }
  }

  return '${buffer.toString().trimRight()}\n';
}

/// fileDate 决定文件名里的日期（导出哪天就用哪天），now 只用于正文的相对时间分组。
String buildExportBaseName({DateTime? now, DateTime? fileDate}) =>
    'clips-${formatDate(fileDate ?? now ?? DateTime.now())}';

String buildExportFileName(String format, {DateTime? now, DateTime? fileDate}) =>
    '${buildExportBaseName(now: now, fileDate: fileDate)}.${format == 'md' ? 'md' : 'txt'}';

String buildExportZipFileName({DateTime? now, DateTime? fileDate}) =>
    '${buildExportBaseName(now: now, fileDate: fileDate)}.zip';

/// 导出方案：决定产出单个文本文件，还是把正文 + 图片打成压缩包。
/// 抽成纯函数是为了让「什么时候走 zip、用什么 MIME」能在单测里覆盖，
/// 而不是埋在界面代码里靠人工点。
class ExportPlan {
  /// 最终交付的文件名
  final String fileName;

  /// 压缩包内正文的文件名；不走压缩包时与 fileName 相同
  final String textFileName;

  final String mime;
  final String content;
  final bool asZip;

  const ExportPlan({
    required this.fileName,
    required this.textFileName,
    required this.mime,
    required this.content,
    required this.asZip,
  });
}

ExportPlan planExport(
  List<Clip> clips, {
  required String format,
  bool groupByTime = true,
  bool includeImages = true,
  bool hasImages = false,
  DateTime? now,
  DateTime? fileDate,
}) {
  final content = format == 'md'
      ? exportMarkdown(clips, groupByTime: groupByTime, includeImages: includeImages, now: now)
      : exportText(clips, groupByTime: groupByTime, includeImages: includeImages, now: now);
  final textFileName = buildExportFileName(format, now: now, fileDate: fileDate);

  // 勾了「包含图片」且确实有图片文件，才值得打成包
  if (includeImages && hasImages) {
    return ExportPlan(
      fileName: buildExportZipFileName(now: now, fileDate: fileDate),
      textFileName: textFileName,
      mime: 'application/zip',
      content: content,
      asZip: true,
    );
  }

  return ExportPlan(
    fileName: textFileName,
    textFileName: textFileName,
    mime: format == 'md' ? 'text/markdown' : 'text/plain',
    content: content,
    asZip: false,
  );
}

/// 启动时是否要写入示例数据：只有「一条内容都没有」且「从来没种过」才种。
/// 这条规则单独抽出来，是因为「清空全部数据后重启又冒出来」的 bug 出在这里：
/// 光判断「列表为空」会把「用户主动清空」误当成「首次安装」。
bool shouldSeedDemo({required bool hasClips, required bool demoSeeded}) =>
    !hasClips && !demoSeeded;

/// 展示用的来源文案：「站点名 · 域名」。
/// 抓到真实地址后要把 t.co 之类的短链换掉，来源也得跟着更新。
String describeSource(String url) {
  final domain = parseDomain(url);
  if (domain.isEmpty) return '剪藏库';
  final site = _siteNames[domain] ?? domain;
  return '$site · $domain';
}

/// 编辑表单 → 更新后的收藏。
/// 类型、域名、来源都是 url 的派生字段，统一在这里算，避免编辑后
/// 「链接已经换了，站点名还是旧的」或「链接删了但类型还是链接」。
///
/// 标题留空时保留原标题：空标题会让列表卡片和导出文件变成空白行。
Clip buildEditedClip(
  Clip original, {
  required String title,
  required String summary,
  required String url,
  required List<String> tags,
  required DateTime createdAt,
}) {
  final trimmedTitle = title.trim();
  final nextTitle = trimmedTitle.isEmpty ? original.title : trimmedTitle;

  // 手输地址常常不带协议；顺手去掉从别处粘贴时带过来的中文收尾标点
  var nextUrl = url.trim().replaceAll(RegExp(r'[，。；、）】\s]+$'), '');
  if (nextUrl.isNotEmpty && !nextUrl.contains('://')) {
    nextUrl = 'https://$nextUrl';
  }

  final hasImage = original.imageFileName != null;
  final nextType = hasImage
      ? ClipType.image
      : (nextUrl.isNotEmpty ? ClipType.link : ClipType.text);
  final nextDomain = nextUrl.isEmpty ? '' : parseDomain(nextUrl);

  // 原来有链接、用户清空了：来源别再挂着旧站点名
  final nextSource = nextUrl.isNotEmpty
      ? describeSource(nextUrl)
      : (original.type == ClipType.link && !hasImage ? '剪藏库 · 文本' : original.source);

  return original.copyWith(
    type: nextType,
    title: nextTitle,
    summary: summary.trim(),
    source: nextSource,
    url: nextUrl,
    domain: nextDomain,
    tags: tags,
    createdAt: createdAt,
  );
}
