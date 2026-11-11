/// 01 内容列表：时间分组、类型快筛、三态卡片、空状态、悬浮「＋」由根容器提供。
library;

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
                        child: ClipCard(
                          clip: clip,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => DetailPage(clipId: clip.id)),
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
