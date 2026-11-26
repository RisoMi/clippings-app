/// 收藏二次编辑：改标题 / 正文 / 原文链接 / 收藏时间 / 标签。
/// 图片本身不提供替换，这里只改文字信息；类型由「有无图片、有无链接」自动判定。
library;

import 'package:flutter/material.dart';

import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class EditPage extends StatefulWidget {
  final String clipId;

  const EditPage({super.key, required this.clipId});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final bool _missing;
  late final Clip _original;
  late final TextEditingController _title;
  late final TextEditingController _summary;
  late final TextEditingController _url;
  late final List<String> _tags;
  late DateTime _createdAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Clip? found;
    for (final item in ClipStore.instance.clips) {
      if (item.id == widget.clipId) {
        found = item;
        break;
      }
    }
    _missing = found == null;
    _original = found ??
        Clip(
          id: '',
          type: ClipType.text,
          title: '',
          summary: '',
          source: '',
          url: '',
          domain: '',
          tags: [],
          createdAt: DateTime(2000),
        );
    _title = TextEditingController(text: _original.title);
    _summary = TextEditingController(text: _original.summary);
    _url = TextEditingController(text: _original.url);
    _tags = [..._original.tags];
    _createdAt = _original.createdAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _createdAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _createdAt.hour,
        _createdAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _createdAt = DateTime(
        _createdAt.year,
        _createdAt.month,
        _createdAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  /// 点已有标签：选中 / 取消。跟入库页一致，纯手动。
  void _toggleTag(String name) {
    setState(() {
      if (_tags.contains(name)) {
        _tags.remove(name);
      } else {
        _tags.add(name);
      }
    });
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增标签', style: TextStyle(fontSize: 16)),
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
    if (trimmed.isEmpty) return;
    await ClipStore.instance.ensureTags([trimmed]);
    if (!mounted || _tags.contains(trimmed)) return;
    setState(() => _tags.add(trimmed));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final edited = buildEditedClip(
        _original,
        title: _title.text,
        summary: _summary.text,
        url: _url.text,
        tags: _tags,
        createdAt: _createdAt,
      );
      await ClipStore.instance.updateClip(edited);
      await ClipStore.instance.ensureTags(_tags);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, '已保存修改');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, '保存失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (_missing) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(title: const Text('编辑收藏')),
        body: const EmptyView(
          icon: Icons.link_off_rounded,
          title: '内容不存在',
          description: '可能已被删除。',
        ),
      );
    }

    final existingTags = ClipStore.instance.tags;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('编辑收藏'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          Text(
            '直接改，保存后还是原来那一条，不会重复新增。',
            style: TextStyle(fontSize: 12, height: 1.7, color: c.sub),
          ),
          const SizedBox(height: 18),
          const _FieldLabel(label: '标题'),
          TextField(
            controller: _title,
            minLines: 1,
            maxLines: 2,
            decoration: const InputDecoration(hintText: '给它起个好找的名字'),
          ),
          const SizedBox(height: 18),
          const _FieldLabel(label: '正文 / 摘要'),
          TextField(
            controller: _summary,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '收藏的内容，可自由修改'),
          ),
          const SizedBox(height: 18),
          const _FieldLabel(label: '原文链接', hint: '可选，留空则按文本保存'),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'example.com/article'),
          ),
          const SizedBox(height: 18),
          const _FieldLabel(label: '收藏时间', hint: '影响列表分组和按日期导出'),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(formatDate(_createdAt), style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(formatClock(_createdAt), style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_original.imageFileName != null) ...[
            const SizedBox(height: 16),
            Text(
              '图片保持原样，这里只改文字和标签。',
              style: TextStyle(fontSize: 11, color: c.weak),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Text('选择标签', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(width: 8),
              Text('不选则无标签', style: TextStyle(fontSize: 11, color: c.weak)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in existingTags)
                GestureDetector(
                  onTap: () => _toggleTag(tag.name),
                  child: TagPill(
                    label: _tags.contains(tag.name) ? '✓ ${tag.name}' : tag.name,
                    ghost: !_tags.contains(tag.name),
                  ),
                ),
              TagPill(label: '+ 新增标签', ghost: true, onTap: _addTag),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存修改'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final String? hint;

  const _FieldLabel({required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink)),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(hint!, style: TextStyle(fontSize: 11, color: c.weak)),
          ],
        ],
      ),
    );
  }
}
