/// 01 内容列表：时间分组、类型快筛、三态卡片、左滑删除、悬浮「＋」由根容器提供。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_page.dart';
import 'paste_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ClipType? _filter;
  String _tagFilter = '';

  /// 刚删除、还在撤销窗口内的条目（图片先留着，撤销窗口过了再清理）
  Clip? _pendingPurge;
  Timer? _purgeTimer;

  /// 已划走但还没从 store 通知回来的 id。
  /// Dismissible 要求「划走」与「数据移除」同一帧完成，否则会抛
  /// "A dismissed Dismissible widget is still part of the tree"。
  final Set<String> _removing = {};

  @override
  void dispose() {
    _purgeTimer?.cancel();
    super.dispose();
  }

  void _cycleTheme() {
    final store = ClipStore.instance;
    final next = switch (store.themeMode) {
      'light' => 'dark',
      'dark' => 'system',
      _ => 'light',
    };
    store.setThemeMode(next);
    final label = switch (next) {
      'light' => '浅色模式',
      'dark' => '深色模式',
      _ => '跟随系统',
    };
    showToast(context, label);
  }

  Future<void> _deleteClip(Clip clip) async {
    final store = ClipStore.instance;

    // 先同步从列表里拿掉，让 Dismissible 这一帧就看不到自己
    setState(() => _removing.add(clip.id));

    // 上一笔还没撤销完就又被删了：先把它的图片清掉，避免留下孤儿文件
    final previous = _pendingPurge;
    if (previous?.imageFileName != null) {
      store.purgeImage(previous!.imageFileName!);
    }
    _purgeTimer?.cancel();

    await store.deleteClip(clip.id, keepImage: true);
    if (!mounted) return;

    _pendingPurge = clip;
    _purgeTimer = Timer(const Duration(seconds: 5), () {
      final pending = _pendingPurge;
      _pendingPurge = null;
      if (pending?.imageFileName != null) store.purgeImage(pending!.imageFileName!);
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '已删除「${clip.title}」',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              _purgeTimer?.cancel();
              _purgeTimer = null;
              _pendingPurge = null;
              if (mounted) setState(() => _removing.remove(clip.id));
              store.addClip(clip);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: ListenableBuilder(
        listenable: ClipStore.instance,
        builder: (context, _) {
          final store = ClipStore.instance;
          final filtered = store.clips.where((clip) {
            if (_removing.contains(clip.id)) return false;
            if (_filter != null && clip.type != _filter) return false;
            if (_tagFilter.isNotEmpty && !clip.tags.contains(_tagFilter)) return false;
            return true;
          }).toList();
          final groups = groupByDay(filtered);
          final stats = store.stats;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 130),
              children: [
                PageHeader(
                  eyebrow: '我的剪藏库',
                  title: '全部内容',
                  action: IconButton(
                    onPressed: _cycleTheme,
                    icon: Icon(
                      isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      size: 20,
                      color: c.ink,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: c.card,
                      side: BorderSide(color: c.line),
                      padding: const EdgeInsets.all(9),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '共 ${stats.total} 条 · 本周新增 ${stats.week} 条${_tagFilter.isEmpty ? '' : ' · 标签「$_tagFilter」'}',
                  style: TextStyle(fontSize: 12, color: c.sub),
                ),
                const SizedBox(height: 14),
                _SearchEntry(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                ),
                const SizedBox(height: 14),
                FilterChips(
                  selected: _filter,
                  onChanged: (type) => setState(() => _filter = type),
                ),
                if (_tagFilter.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TagPill(
                        label: '$_tagFilter  ×',
                        onTap: () => setState(() => _tagFilter = ''),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                if (filtered.isEmpty)
                  EmptyView(
                    icon: Icons.bookmark_border_rounded,
                    title: _tagFilter.isEmpty ? '这里还是空的' : '这个标签下还没有内容',
                    description: _tagFilter.isEmpty
                        ? '从其他 APP 分享链接进来，或复制内容后回到这里粘贴，一秒就能存下。'
                        : '换个标签看看，或把内容先存进来再归类。',
                    action: _tagFilter.isEmpty
                        ? FilledButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PastePage()),
                            ),
                            child: const Text('粘贴速存'),
                          )
                        : null,
                  )
                else
                  for (final group in groups) ...[
                    SectionHeader(title: group.label, trailing: '${group.items.length} 条'),
                    for (final clip in group.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Dismissible(
                          key: ValueKey('clip-${clip.id}'),
                          direction: DismissDirection.endToStart,
                          background: _DeleteBackground(color: c.danger),
                          onDismissed: (_) => _deleteClip(clip),
                          child: ClipCard(
                            clip: clip,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => DetailPage(clipId: clip.id)),
                            ),
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 左滑时露出的删除底
class _DeleteBackground extends StatelessWidget {
  final Color color;

  const _DeleteBackground({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, size: 20, color: color),
          const SizedBox(width: 6),
          Text('删除', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _SearchEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.row),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.row),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.row),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 18, color: c.sub),
              const SizedBox(width: 10),
              Expanded(
                child: Text('搜索标题、正文或标签', style: TextStyle(fontSize: 13, color: c.weak)),
              ),
              Icon(Icons.tune_rounded, size: 18, color: c.sub),
            ],
          ),
        ),
      ),
    );
  }
}
