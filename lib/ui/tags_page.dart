/// 04 标签管理：数量聚合、未分类入口、新建标签。
library;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'search_page.dart';

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});

  static const _palette = [
    Color(0xFF2F6A54),
    Color(0xFF6E8F7C),
    Color(0xFF9AAE9F),
    Color(0xFFC1A47C),
    Color(0xFF8C8A80),
    Color(0xFFB5B0A2),
  ];

  Future<void> _createTag(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建标签', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：设计灵感'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;
    await ClipStore.instance.ensureTags([trimmed]);
    if (context.mounted) showToast(context, '标签已创建');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.bg,
      body: ListenableBuilder(
        listenable: ClipStore.instance,
        builder: (context, _) {
          final store = ClipStore.instance;
          final tags = store.tagCounts;
          final stats = store.stats;
          final accentFg = isDark ? const Color(0xFF151917) : Colors.white;

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              children: [
                PageHeader(
                  eyebrow: '把零散内容归位',
                  title: '标签',
                  action: FilledButton(
                    onPressed: () => _createTag(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(84, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('+ 新建'),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tags.length} 个标签 · ${stats.total - stats.uncategorized} 条已整理',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: accentFg),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '还有 ${stats.uncategorized} 条内容没归类，随时可以批量处理。',
                        style: TextStyle(fontSize: 12, height: 1.6, color: accentFg.withValues(alpha: 0.82)),
                      ),
                    ],
                  ),
                ),
                const SectionHeader(title: '全部标签', trailing: '按数量排序'),
                if (tags.isEmpty)
                  EmptyView(
                    icon: Icons.sell_outlined,
                    title: '还没有标签',
                    description: '保存内容时会自动推荐标签，也可以点右上角新建。',
                  )
                else
                  for (var i = 0; i < tags.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TagRow(
                        name: tags[i].name,
                        count: tags[i].count,
                        color: Color(tags[i].color == 0xFF2F6A54
                            ? _palette[i % _palette.length].toARGB32()
                            : tags[i].color),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SearchPage(initialKeyword: tags[i].name),
                          ),
                        ),
                        onLongPress: () => _tagActions(context, tags[i].name),
                      ),
                    ),
                if (stats.uncategorized > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _TagRow(
                      name: '未分类',
                      count: stats.uncategorized,
                      color: c.line,
                      highlight: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchPage(onlyUntagged: true)),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _tagActions(BuildContext context, String name) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
              title: const Text('重命名', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, size: 20),
              title: const Text('删除标签', style: TextStyle(fontSize: 14)),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    if (action == 'rename') {
      final controller = TextEditingController(text: name);
      final next = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名标签', style: TextStyle(fontSize: 16)),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (next != null && next.trim().isNotEmpty) {
        await ClipStore.instance.renameTag(name, next);
        if (context.mounted) showToast(context, '已重命名');
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除标签', style: TextStyle(fontSize: 16)),
          content: Text('删除「$name」后，内容本身不会被删除，只是移出该标签。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) {
        await ClipStore.instance.deleteTag(name);
        if (context.mounted) showToast(context, '标签已删除');
      }
    }
  }
}

class _TagRow extends StatelessWidget {
  final String name;
  final int count;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool highlight;

  const _TagRow({
    required this.name,
    required this.count,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: highlight ? c.soft : c.card,
      borderRadius: BorderRadius.circular(AppRadii.row),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadii.row),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.row),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: highlight ? c.sub : c.ink,
                  ),
                ),
              ),
              Text('$count', style: TextStyle(fontSize: 11, color: c.weak)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.weak),
            ],
          ),
        ),
      ),
    );
  }
}
