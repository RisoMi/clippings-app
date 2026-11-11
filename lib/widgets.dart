/// 通用组件：卡片三态、类型标记、筛选条、页头、空状态、轻提示。
library;

import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';

void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 96),
      ),
    );
}

/// 关键词高亮（大小写不敏感，不改变原文）
List<TextSpan> highlightSpans(
  String text,
  String keyword,
  TextStyle base,
  TextStyle highlight,
) {
  if (keyword.trim().isEmpty) return [TextSpan(text: text, style: base)];
  final source = text.toLowerCase();
  final kw = keyword.trim().toLowerCase();
  final spans = <TextSpan>[];
  var cursor = 0;
  var index = source.indexOf(kw);
  while (index >= 0) {
    if (index > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, index), style: base));
    }
    spans.add(TextSpan(text: text.substring(index, index + kw.length), style: highlight));
    cursor = index + kw.length;
    index = source.indexOf(kw, cursor);
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return spans.isEmpty ? [TextSpan(text: text, style: base)] : spans;
}

String formatRelativeOf(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(time.year, time.month, time.day);
  final diffDays = today.difference(target).inDays;
  String two(int v) => v.toString().padLeft(2, '0');
  if (diffDays <= 0) {
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '今天 ${two(time.hour)}:${two(time.minute)}';
  }
  if (diffDays == 1) return '昨天 ${two(time.hour)}:${two(time.minute)}';
  return '${two(time.month)}-${two(time.day)}';
}

class TypePill extends StatelessWidget {
  final ClipType type;
  final bool accent;

  const TypePill({super.key, required this.type, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      height: 20,
      decoration: BoxDecoration(
        color: accent ? c.accentSoft : c.soft,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        type.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: accent ? c.accent : c.sub,
        ),
      ),
    );
  }
}

class TagPill extends StatelessWidget {
  final String label;
  final bool ghost;
  final VoidCallback? onTap;

  const TagPill({super.key, required this.label, this.ghost = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: ghost ? c.card : c.accentSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ghost
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                )
              : null,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: ghost ? c.sub : c.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class FilterChips extends StatelessWidget {
  final ClipType? selected;
  final ValueChanged<ClipType?> onChanged;
  final bool includeAll;

  const FilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.includeAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = <(ClipType?, String)>[
      if (includeAll) (null, '全部'),
      (ClipType.link, '链接'),
      (ClipType.text, '文本'),
      (ClipType.image, '图片'),
    ];

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (type, label) = options[index];
          final active = selected == type;
          return GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? c.accent : c.card,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: active ? c.accent : c.line),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? (isDark ? const Color(0xFF151917) : Colors.white) : c.sub,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final Widget? action;

  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow, style: TextStyle(fontSize: 12, color: c.sub, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
          if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 11, color: c.weak)),
        ],
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      child: Column(
        children: [
          Icon(icon, size: 44, color: c.line),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.7, color: c.sub),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class ClipThumb extends StatelessWidget {
  final Clip clip;
  final double width;
  final double height;
  final bool wide;

  const ClipThumb({
    super.key,
    required this.clip,
    this.width = 68,
    this.height = 68,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppRadii.thumb);
    final placeholder = Container(
      width: wide ? double.infinity : width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF24342B), const Color(0xFF33463A)]
              : [const Color(0xFFDDE7DF), const Color(0xFFB7C8BD)],
        ),
        borderRadius: radius,
      ),
      child: Icon(
        switch (clip.type) {
          ClipType.link => Icons.link_rounded,
          ClipType.text => Icons.notes_rounded,
          ClipType.image => Icons.image_outlined,
        },
        size: wide ? 34 : 26,
        color: c.accent,
      ),
    );

    if (clip.imageFileName == null) return placeholder;

    final file = ClipStore.instance.imageFile(clip.imageFileName!);
    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        file,
        width: wide ? double.infinity : width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class ClipCard extends StatelessWidget {
  final Clip clip;
  final VoidCallback? onTap;
  final bool selectable;
  final bool selected;
  final String keyword;

  const ClipCard({
    super.key,
    required this.clip,
    this.onTap,
    this.selectable = false,
    this.selected = false,
    this.keyword = '',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.42, color: c.ink);
    final hlStyle = titleStyle.copyWith(color: c.accent, backgroundColor: c.accentSoft);
    final subStyle = TextStyle(fontSize: 11, height: 1.55, color: c.sub);
    final metaStyle = TextStyle(fontSize: 11, color: c.weak);

    final checkbox = selectable
        ? Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.accent : Colors.transparent,
                border: Border.all(color: selected ? c.accent : c.weak, width: 1.6),
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: isDark ? const Color(0xFF151917) : Colors.white,
                    )
                  : null,
            ),
          )
        : null;

    final meta = Row(
      children: [
        Expanded(
          child: Text(
            '${clip.source.isEmpty ? '剪藏库' : clip.source} · ${formatRelativeOf(clip.createdAt)}',
            style: metaStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        TypePill(type: clip.type, accent: clip.type == ClipType.link),
      ],
    );

    Widget body;
    if (clip.type == ClipType.text) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(10)),
            child: RichText(
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: highlightSpans(
                  clip.summary,
                  keyword,
                  TextStyle(fontSize: 12, height: 1.65, color: c.ink),
                  hlStyle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(children: highlightSpans(clip.title, keyword, titleStyle, hlStyle)),
          ),
          const SizedBox(height: 6),
          meta,
        ],
      );
    } else if (clip.type == ClipType.image) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (clip.imageFileName != null) ...[
            ClipThumb(clip: clip, wide: true, height: 108),
            const SizedBox(height: 8),
          ],
          RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(children: highlightSpans(clip.title, keyword, titleStyle, hlStyle)),
          ),
          const SizedBox(height: 6),
          meta,
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipThumb(clip: clip),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(children: highlightSpans(clip.title, keyword, titleStyle, hlStyle)),
                ),
                const SizedBox(height: 4),
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(children: highlightSpans(clip.summary, keyword, subStyle, hlStyle)),
                ),
                const SizedBox(height: 8),
                meta,
              ],
            ),
          ),
        ],
      );
    }

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: selected ? c.accent : c.line, width: selected ? 1.4 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (checkbox != null) ...[checkbox, const SizedBox(width: 10)],
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
