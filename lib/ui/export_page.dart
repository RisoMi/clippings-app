/// 06 批量导出：多选、Markdown / 纯文本、图片与分组开关、文件预览。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../bridge.dart';
import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'done_page.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  final Set<String> _selected = {};
  bool _initialized = false;
  bool _busy = false;

  void _ensureSelection() {
    if (_initialized) return;
    _initialized = true;
    _selected.addAll(ClipStore.instance.clips.map((clip) => clip.id));
  }

  List<Clip> get _selectedClips =>
      ClipStore.instance.clips.where((clip) => _selected.contains(clip.id)).toList();

  String _preview() {
    final clips = _selectedClips;
    if (clips.isEmpty) return '还没有勾选内容。';
    final store = ClipStore.instance;
    final content = store.exportFormat == 'md'
        ? exportMarkdown(clips, groupByTime: store.exportGroup, includeImages: false)
        : exportText(clips, groupByTime: store.exportGroup);
    final lines = content.split('\n');
    return lines.take(14).join('\n') + (lines.length > 14 ? '\n…' : '');
  }

  Future<void> _export() async {
    final clips = _selectedClips;
    if (clips.isEmpty) return;
    setState(() => _busy = true);
    final store = ClipStore.instance;
    try {
      final format = store.exportFormat;
      final content = format == 'md'
          ? exportMarkdown(clips, groupByTime: store.exportGroup, includeImages: store.exportImages)
          : exportText(clips, groupByTime: store.exportGroup);

      final dir = Directory('${store.dataDir}/exports');
      await dir.create(recursive: true);

      if (format == 'md' && store.exportImages) {
        final imagesDir = Directory('${dir.path}/images');
        await imagesDir.create(recursive: true);
        for (final clip in clips) {
          final name = clip.imageFileName;
          if (name == null) continue;
          final source = store.imageFile(name);
          if (!await source.exists()) continue;
          final target = File('${imagesDir.path}/$name');
          if (!await target.exists()) {
            await source.copy(target.path);
          }
        }
      }

      final fileName = buildExportFileName(format);
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(content, flush: true);
      final size = await file.length();

      final shared = await Bridge.shareFile(
        file.path,
        format == 'md' ? 'text/markdown' : 'text/plain',
        title: fileName,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DonePage(
            fileName: fileName,
            filePath: file.path,
            byteSize: size,
            count: clips.length,
            format: format,
            shared: shared,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showToast(context, '导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = ClipStore.instance;

    return Scaffold(
      backgroundColor: c.bg,
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          _ensureSelection();
          final clips = store.clips;
          final selectedCount = _selectedClips.length;
          final allSelected = clips.isNotEmpty && selectedCount == clips.length;
          final visible = clips.take(8).toList();

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              children: [
                PageHeader(
                  eyebrow: '批量导出',
                  title: '导出内容',
                  action: TextButton(
                    onPressed: () {
                      setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(clips.map((clip) => clip.id));
                        }
                      });
                    },
                    child: Text(allSelected ? '取消全选' : '全选'),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已选 $selectedCount 条 · 共 ${clips.length} 条',
                  style: TextStyle(fontSize: 12, color: c.sub),
                ),
                const SizedBox(height: 14),
                if (clips.isEmpty)
                  const EmptyView(
                    icon: Icons.ios_share_rounded,
                    title: '还没有内容可导出',
                    description: '先存几条收藏，再回来打包成 Markdown 或纯文本。',
                  )
                else
                  for (final clip in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ClipCard(
                        clip: clip,
                        selectable: true,
                        selected: _selected.contains(clip.id),
                        onTap: () {
                          setState(() {
                            if (_selected.contains(clip.id)) {
                              _selected.remove(clip.id);
                            } else {
                              _selected.add(clip.id);
                            }
                          });
                        },
                      ),
                    ),
                if (clips.length > visible.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      '仅显示前 ${visible.length} 条，导出会包含全部已勾选内容。',
                      style: TextStyle(fontSize: 11, color: c.weak),
                    ),
                  ),
                const SectionHeader(title: '导出格式'),
                Row(
                  children: [
                    Expanded(
                      child: _FormatCard(
                        title: 'Markdown .md',
                        subtitle: '含标题、标签、来源链接',
                        active: store.exportFormat == 'md',
                        onTap: () => store.setExportOptions(format: 'md'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FormatCard(
                        title: '纯文本 .txt',
                        subtitle: '仅正文，体积最小',
                        active: store.exportFormat == 'txt',
                        onTap: () => store.setExportOptions(format: 'txt'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _SwitchRow(
                  label: '包含图片（复制到 images 文件夹）',
                  value: store.exportImages,
                  onChanged: (v) => store.setExportOptions(images: v),
                ),
                _SwitchRow(
                  label: '按收藏时间分组',
                  value: store.exportGroup,
                  onChanged: (v) => store.setExportOptions(group: v),
                ),
                const SectionHeader(title: '文件预览', trailing: '前 14 行'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(AppRadii.row)),
                  child: Text(
                    _preview(),
                    style: TextStyle(fontSize: 11, height: 1.7, color: c.ink, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: (_busy || selectedCount == 0) ? null : _export,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('生成文件并分享'),
                ),
                const SizedBox(height: 8),
                Text(
                  '生成的 .md / .txt 可直接用任意编辑器打开，也能发到电脑。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: c.weak),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FormatCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  const _FormatCard({
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : c.card,
          borderRadius: BorderRadius.circular(AppRadii.row),
          border: Border.all(color: active ? c.accent : c.line, width: active ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? c.accent : c.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 10, height: 1.5, color: active ? c.sub : c.weak)),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: c.ink))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF151917)
                : Colors.white,
            activeTrackColor: c.accent,
          ),
        ],
      ),
    );
  }
}
