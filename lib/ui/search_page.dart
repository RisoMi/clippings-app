/// 03 搜索：标题 / 正文 / 标签 / 来源四字段检索，关键词高亮，按类型收敛。
library;

import 'package:flutter/material.dart';

import '../core.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  final String initialKeyword;
  final bool onlyUntagged;

  const SearchPage({super.key, this.initialKeyword = '', this.onlyUntagged = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// 本次会话内的搜索历史（后续可迁到 settings.json 持久化）
  static final List<String> _history = [];

  late final TextEditingController _controller;
  String _keyword = '';
  ClipType? _type;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword);
    _keyword = widget.initialKeyword;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commitHistory(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _history.remove(trimmed);
    _history.insert(0, trimmed);
    if (_history.length > 8) _history.removeRange(8, _history.length);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final store = ClipStore.instance;

    final results = widget.onlyUntagged
        ? store.clips.where((clip) => clip.tags.isEmpty && (_type == null || clip.type == _type)).toList()
        : searchClips(store.clips, keyword: _keyword, type: _type);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.onlyUntagged ? '未分类内容' : '搜索'),
        actions: [
          if (_keyword.isNotEmpty || _type != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _keyword = '';
                  _type = null;
                  _controller.clear();
                });
              },
              child: const Text('清除'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          if (!widget.onlyUntagged)
            TextField(
              controller: _controller,
              autofocus: widget.initialKeyword.isEmpty,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索标题、正文、标签或来源',
                prefixIcon: Icon(Icons.search_rounded, size: 19, color: c.sub),
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close_rounded, size: 17, color: c.sub),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _keyword = '');
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _keyword = value),
              onSubmitted: (value) {
                _commitHistory(value);
                setState(() => _keyword = value);
              },
            ),
          if (!widget.onlyUntagged) const SizedBox(height: 12),
          FilterChips(
            selected: _type,
            onChanged: (type) => setState(() => _type = type),
          ),
          const SizedBox(height: 6),
          if (!widget.onlyUntagged && _keyword.isEmpty && _history.isNotEmpty) ...[
            const SectionHeader(title: '最近搜索'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final word in _history)
                  TagPill(
                    label: word,
                    ghost: true,
                    onTap: () {
                      _controller.text = word;
                      setState(() => _keyword = word);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SectionHeader(
            title: widget.onlyUntagged
                ? '共 ${results.length} 条未分类'
                : (_keyword.isEmpty ? '共 ${results.length} 条内容' : '找到 ${results.length} 条相关内容'),
            trailing: '按时间排序',
          ),
          if (results.isEmpty)
            EmptyView(
              icon: Icons.search_rounded,
              title: widget.onlyUntagged ? '没有未分类内容' : '没有匹配的内容',
              description: widget.onlyUntagged
                  ? '所有收藏都已经归类，很整洁。'
                  : '试试更短的关键词，或切换类型筛选。',
            )
          else
            for (final clip in results)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ClipCard(
                  clip: clip,
                  keyword: _keyword,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DetailPage(clipId: clip.id)),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(AppRadii.row)),
            child: Text(
              '可搜索标题、正文、标签与来源域名，全部在本机完成，离线也能用。',
              style: TextStyle(fontSize: 11, height: 1.7, color: c.sub),
            ),
          ),
        ],
      ),
    );
  }
}
