/// 08 粘贴速存 / 02 分享速存确认：识别剪贴板或分享内容 → 预览 → 一键入库。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bridge.dart';
import '../core.dart';
import '../metadata.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// 待保存草稿（尚未入库）
class PasteDraft {
  final ClipType type;
  String title;
  String summary;
  String source;

  /// 可变：抓到网页后会把 t.co 短链换成真实地址，存短链以后会失效
  String url;
  String domain;

  final List<String> tags;
  final String? imagePath;

  PasteDraft({
    required this.type,
    required this.title,
    required this.summary,
    required this.source,
    required this.url,
    required this.domain,
    required this.tags,
    this.imagePath,
  });
}

/// 系统分享内容 → 草稿
PasteDraft? buildDraftFromShare(SharePayload payload) {
  final known = ClipStore.instance.tagCounts;

  if (payload.type == 'image' && (payload.imagePath?.isNotEmpty ?? false)) {
    final now = DateTime.now();
    final detected = Detected(
      type: ClipType.image,
      title: payload.title.trim().isEmpty ? '图片 ${formatClock(now)} 收藏' : payload.title.trim(),
      summary: payload.text.trim().isEmpty ? '来自系统分享的图片' : payload.text.trim(),
      source: '系统分享 · 图片',
      url: '',
      domain: '',
    );
    return PasteDraft(
      type: ClipType.image,
      title: detected.title,
      summary: detected.summary,
      source: detected.source,
      url: '',
      domain: '',
      tags: suggestTags(detected, known),
      imagePath: payload.imagePath,
    );
  }

  final detected = detectFromShare(
    title: payload.title,
    text: payload.text,
    url: payload.url,
  );
  if (detected == null) return null;

  return PasteDraft(
    type: detected.type,
    title: detected.title,
    summary: detected.summary,
    source: detected.source,
    url: detected.url,
    domain: detected.domain,
    tags: suggestTags(detected, known),
  );
}

/// 录入方式：剪贴板（默认，自动读取）或手动输入
enum PasteMode { clipboard, manual }

class PastePage extends StatefulWidget {
  final PasteDraft? initial;
  final PasteMode mode;

  const PastePage({super.key, this.initial, this.mode = PasteMode.clipboard});

  @override
  State<PastePage> createState() => _PastePageState();
}

class _PastePageState extends State<PastePage> {
  final TextEditingController _manual = TextEditingController();
  PasteDraft? _draft;
  bool _busy = false;
  bool _fetching = false;

  bool get _isManual => widget.mode == PasteMode.manual;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    // 选了「从剪贴板新增」就直接读，不再让用户多点一次按钮。
    // 放在首帧之后：这时页面已经铺好，读不到也能安静停在空状态。
    if (_draft == null && widget.mode == PasteMode.clipboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _readClipboard(silent: true));
    } else if (_draft != null && _draft!.url.trim().isNotEmpty) {
      // 分享进来的链接：马上抓一次标题，用户看到的就不是光秃秃一条 URL
      WidgetsBinding.instance.addPostFrameCallback((_) => _enrichFromWeb());
    }
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  /// [silent] 为 true 表示进页面时自动读：读不到就安静停在空状态，不弹提示打扰。
  Future<void> _readClipboard({bool silent = false}) async {
    if (mounted) setState(() => _busy = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text ?? '';
      if (text.trim().isEmpty) {
        if (!silent && mounted) showToast(context, '剪贴板里没有可识别的内容');
        return;
      }
      final detected = detectContent(text: text);
      if (detected == null) {
        if (!silent && mounted) showToast(context, '没识别出内容');
        return;
      }
      if (!mounted) return;
      setState(() {
        _draft = PasteDraft(
          type: detected.type,
          title: detected.title,
          summary: detected.summary,
          source: detected.source,
          url: detected.url,
          domain: detected.domain,
          tags: suggestTags(detected, ClipStore.instance.tagCounts),
        );
      });
      if (detected.url.isNotEmpty) await _enrichFromWeb();
    } catch (_) {
      if (!silent && mounted) showToast(context, '读取剪贴板被拒绝，请手动粘贴');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _detectManual() {
    final text = _manual.text;
    if (text.trim().isEmpty) {
      showToast(context, '先粘贴或输入一点内容');
      return;
    }
    final detected = detectContent(text: text);
    if (detected == null) {
      showToast(context, '没识别出内容');
      return;
    }
    setState(() {
      _draft = PasteDraft(
        type: detected.type,
        title: detected.title,
        summary: detected.summary,
        source: detected.source,
        url: detected.url,
        domain: detected.domain,
        tags: suggestTags(detected, ClipStore.instance.tagCounts),
      );
    });
    if (detected.url.isNotEmpty) _enrichFromWeb();
  }

  /// 抓网页标题 / 摘要。失败不影响保存，只是标题停在自动生成的兜底文案。
  Future<void> _enrichFromWeb() async {
    final draft = _draft;
    if (draft == null || draft.url.trim().isEmpty) return;
    if (!ClipStore.instance.fetchMetadata) return;
    if (!mounted) return;

    setState(() => _fetching = true);
    final result = await fetchLinkMetadata(draft.url);
    if (!mounted) return;

    setState(() {
      _fetching = false;
      final data = result.data;
      if (data == null) return;

      // 短链解析出的真实地址要回写：t.co 这类链接过一阵就失效了
      final resolved = data.finalUrl.trim();
      if (resolved.isNotEmpty && resolved != draft.url) {
        draft.url = resolved;
        final host = parseDomain(resolved);
        if (host.isNotEmpty) {
          draft.domain = host;
          draft.source = describeSource(resolved);
        }
      }

      final title = data.title?.trim() ?? '';
      if (title.isNotEmpty) draft.title = title;

      final desc = data.description?.trim() ?? '';
      if (desc.isNotEmpty && desc != title) draft.summary = desc;
    });

    final error = result.error;
    if (error != null && error != '页面里没有标题信息' && mounted) {
      showToast(context, '没能获取标题：$error');
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _busy = true);
    try {
      String? fileName;
      if (draft.imagePath != null) {
        fileName = await ClipStore.instance.adoptImage(draft.imagePath!);
      }
      final clip = Clip(
        id: uid(),
        type: draft.type,
        title: draft.title,
        summary: draft.summary,
        source: draft.source,
        url: draft.url,
        domain: draft.domain,
        tags: draft.tags,
        createdAt: DateTime.now(),
        imageFileName: fileName,
      );
      await ClipStore.instance.addClip(clip);
      await ClipStore.instance.ensureTags(draft.tags);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, '已保存到剪藏库');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加标签', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：效率工具'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty || _draft == null) return;
    if (!_draft!.tags.contains(trimmed)) {
      setState(() => _draft!.tags.add(trimmed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final draft = _draft;
    final title = draft != null ? '确认保存' : (_isManual ? '手动新增' : '粘贴速存');
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(draft == null ? Icons.arrow_back_ios_new_rounded : Icons.close_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
        actions: [
          if (draft == null && !_isManual)
            IconButton(
              icon: const Icon(Icons.content_paste_rounded, size: 19),
              onPressed: _busy ? null : _readClipboard,
            )
          else if (draft != null)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, size: 19),
              onPressed: () => setState(() => _draft = null),
            ),
        ],
      ),
      body: draft == null ? _buildEmpty(context) : _buildConfirm(context, draft),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final c = context.colors;

    // 手动输入：不给「读取剪贴板」按钮，直接把输入框顶到前面
    if (_isManual) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          Text('手动新增', style: TextStyle(fontSize: 12, color: c.accent, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('写点什么存下来', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(
            '带链接的内容会自动存成「链接」，其余按「文本」保存，标题取首句。',
            style: TextStyle(fontSize: 12, height: 1.7, color: c.sub),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _manual,
            maxLines: 8,
            minLines: 5,
            autofocus: true,
            decoration: const InputDecoration(hintText: '粘贴链接、一段文字，或直接写下想法…'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _detectManual, child: const Text('识别并预览')),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _busy ? null : _readClipboard,
            child: const Text('改用剪贴板里的内容'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
      children: [
        Text('已自动读取剪贴板', style: TextStyle(fontSize: 12, color: c.accent, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('没读到可识别的内容', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 6),
        Text(
          '进页面时已经自动读过一次。可能是复制的不是文本，或系统没放权限；直接把内容粘到下面也一样能存。',
          style: TextStyle(fontSize: 12, height: 1.7, color: c.sub),
        ),
        const SizedBox(height: 16),
        const _StepBar(current: 2),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _readClipboard,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.content_paste_rounded, size: 18),
          label: const Text('再读一次剪贴板'),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(AppRadii.row)),
          child: Text(
            '内容只在本机识别，不上传。系统可能会提示「已粘贴」，这是读取剪贴板的正常提示。',
            style: TextStyle(fontSize: 11, height: 1.7, color: c.sub),
          ),
        ),
        const SizedBox(height: 24),
        Text('手动粘贴或输入', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.sub)),
        const SizedBox(height: 8),
        TextField(
          controller: _manual,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(hintText: '粘贴链接、一段文字，或直接输入想法…'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _detectManual, child: const Text('识别并预览')),
      ],
    );
  }

  Widget _buildConfirm(BuildContext context, PasteDraft draft) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
      children: [
        Row(
          children: [
            Text(
              '识别完成 · ${draft.type.label}',
              style: TextStyle(fontSize: 12, color: c.sub, fontWeight: FontWeight.w500),
            ),
            if (_fetching) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: c.accent),
              ),
              const SizedBox(width: 5),
              Text('正在获取标题…', style: TextStyle(fontSize: 11, color: c.accent)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          switch (draft.type) {
            ClipType.link => '剪贴板里有链接',
            ClipType.image => '检测到图片',
            ClipType.text => '检测到一段文字',
          },
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '自动识别为${draft.type.label}，不用选类型、不用填表单。',
          style: TextStyle(fontSize: 12, height: 1.7, color: c.sub),
        ),
        const SizedBox(height: 16),
        const _StepBar(current: 2),
        const SizedBox(height: 16),
        if (draft.type == ClipType.link && draft.url.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(AppRadii.row),
              border: Border.all(color: c.accentLine),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18, color: c.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('刚复制的内容', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent)),
                      const SizedBox(height: 2),
                      Text(draft.url, style: TextStyle(fontSize: 11, color: c.sub), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (draft.type == ClipType.link && draft.url.isNotEmpty) const SizedBox(height: 12),
        _DraftPreview(draft: draft),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('建议标签', style: TextStyle(fontSize: 12, color: c.sub)),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in draft.tags)
                    GestureDetector(
                      onTap: () => setState(() => draft.tags.remove(tag)),
                      child: TagPill(label: '$tag  ×'),
                    ),
                  TagPill(label: '+ 添加标签', ghost: true, onTap: _addTag),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('存入剪藏库'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消，回列表'),
        ),
        const SizedBox(height: 4),
        Text(
          '存入后可离线查看；整理可以留到之后。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: c.weak),
        ),
      ],
    );
  }
}

class _DraftPreview extends StatelessWidget {
  final PasteDraft draft;

  const _DraftPreview({required this.draft});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (draft.type == ClipType.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: draft.imagePath != null
            ? Image.file(File(draft.imagePath!), fit: BoxFit.cover, height: 220, width: double.infinity)
            : Container(
                height: 160,
                color: c.card,
                child: Icon(Icons.image_outlined, size: 36, color: c.accent),
              ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF24342B), const Color(0xFF33463A)]
                    : [const Color(0xFFDDE7DF), const Color(0xFFB7C8BD)],
              ),
              borderRadius: BorderRadius.circular(AppRadii.thumb),
            ),
            child: Icon(
              draft.type == ClipType.link ? Icons.link_rounded : Icons.notes_rounded,
              size: 26,
              color: c.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.42, color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  draft.summary,
                  style: TextStyle(fontSize: 11, height: 1.55, color: c.sub),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TypePill(type: draft.type, accent: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        draft.source,
                        style: TextStyle(fontSize: 11, color: c.weak),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  final int current;

  const _StepBar({required this.current});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = ['1 复制内容', '2 回到这里', '3 一键入库'];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index == current;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 6),
            child: Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? c.accent : c.soft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF151917)
                          : Colors.white)
                      : c.sub,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
