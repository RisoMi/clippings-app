/// 05 内容详情：查看、改标签、复制全文、打开原文、删除。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class DetailPage extends StatelessWidget {
  final String clipId;

  const DetailPage({super.key, required this.clipId});

  Future<void> _delete(BuildContext context, Clip clip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条收藏', style: TextStyle(fontSize: 16)),
        content: Text('「${clip.title}」将被删除，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await ClipStore.instance.deleteClip(clip.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      showToast(context, '已删除');
    }
  }

  Future<void> _copy(BuildContext context, Clip clip) async {
    final payload = clip.type == ClipType.link && clip.url.isNotEmpty
        ? '${clip.title}\n${clip.url}\n\n${clip.summary}'.trim()
        : '${clip.title}\n\n${clip.summary}'.trim();
    await Clipboard.setData(ClipboardData(text: payload));
    if (context.mounted) showToast(context, '已复制全文');
  }

  Future<void> _addTag(BuildContext context, Clip clip) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加标签', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '支持用逗号分隔多个'),
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
    final raw = (name ?? '').trim();
    if (raw.isEmpty) return;
    final added = raw
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final next = <String>{...clip.tags, ...added}.toList();
    await ClipStore.instance.updateClip(clip.copyWith(tags: next));
    await ClipStore.instance.ensureTags(added);
    if (context.mounted) showToast(context, '标签已更新');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('内容详情'),
        actions: [
          ListenableBuilder(
            listenable: ClipStore.instance,
            builder: (context, _) {
              final clip = ClipStore.instance.clips.where((item) => item.id == clipId).firstOrNull;
              if (clip == null) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.danger),
                onPressed: () => _delete(context, clip),
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ClipStore.instance,
        builder: (context, _) {
          final clip = ClipStore.instance.clips.where((item) => item.id == clipId).firstOrNull;
          if (clip == null) {
            return const EmptyView(
              icon: Icons.link_off_rounded,
              title: '内容不存在',
              description: '可能已被删除。',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            children: [
              Row(
                children: [
                  TypePill(type: clip.type, accent: true),
                  const SizedBox(width: 10),
                  Text(
                    '${formatDateTime(clip.createdAt)} 收藏',
                    style: TextStyle(fontSize: 11, color: c.weak),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(clip.title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(clip.source, style: TextStyle(fontSize: 12, color: c.sub)),
              if (clip.imageFileName != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    ClipStore.instance.imageFile(clip.imageFileName!),
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: c.card,
                      child: Icon(Icons.image_outlined, size: 32, color: c.weak),
                    ),
                  ),
                ),
              ],
              if (clip.summary.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    clip.summary,
                    style: TextStyle(fontSize: 13, height: 1.8, color: c.ink),
                  ),
                ),
              ],
              const SectionHeader(title: '标签'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in clip.tags)
                    GestureDetector(
                      onTap: () async {
                        final next = clip.tags.where((t) => t != tag).toList();
                        await ClipStore.instance.updateClip(clip.copyWith(tags: next));
                        if (context.mounted) showToast(context, '已移出「$tag」');
                      },
                      child: TagPill(label: '$tag  ×'),
                    ),
                  TagPill(
                    label: '+ 添加',
                    ghost: true,
                    onTap: () => _addTag(context, clip),
                  ),
                ],
              ),
              if (clip.url.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(AppRadii.row),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 18, color: c.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          clip.url,
                          style: TextStyle(fontSize: 12, color: c.accent),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => _copy(context, clip),
                icon: const Icon(Icons.content_copy_rounded, size: 17),
                label: const Text('复制全文'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _delete(context, clip),
                icon: Icon(Icons.delete_outline_rounded, size: 17, color: c.danger),
                label: Text('删除这条收藏', style: TextStyle(color: c.danger)),
              ),
            ],
          );
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
