/// 07 导出完成：文件名、大小、条数，再次分享与结束。
library;

import 'package:flutter/material.dart';

import '../bridge.dart';
import '../theme.dart';
import '../widgets.dart';

class DonePage extends StatelessWidget {
  final String fileName;
  final String filePath;
  final int byteSize;
  final int count;
  final String format;
  final bool shared;
  final int imageCount;

  const DonePage({
    super.key,
    required this.fileName,
    required this.filePath,
    required this.byteSize,
    required this.count,
    required this.format,
    required this.shared,
    this.imageCount = 0,
  });

  String get _sizeLabel => byteSize > 1024 * 1024
      ? '${(byteSize / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(byteSize / 1024).ceil()} KB';

  String get _formatLabel => switch (format) {
        'md' => 'Markdown',
        'txt' => '纯文本',
        'zip' => 'ZIP 压缩包',
        _ => format,
      };

  String get _mime => switch (format) {
        'md' => 'text/markdown',
        'txt' => 'text/plain',
        'zip' => 'application/zip',
        _ => 'application/octet-stream',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('导出完成'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('完成'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentSoft),
              child: Icon(Icons.check_rounded, size: 32, color: c.accent),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '文件已生成',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '$count 条内容已打包，随时可以传到电脑查看。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.sub),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.folder_open_rounded, size: 22, color: c.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$_formatLabel · $_sizeLabel · $count 条内容${imageCount > 0 ? ' · $imageCount 张图片' : ''}',
                        style: TextStyle(fontSize: 11, color: c.weak),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              final ok = await Bridge.shareFile(
                filePath,
                _mime,
                title: fileName,
              );
              if (context.mounted) {
                showToast(context, ok ? '已打开系统分享' : '分享不可用，文件已保存在应用目录');
              }
            },
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('再次分享 / 发送到电脑'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('完成'),
          ),
          const SizedBox(height: 18),
          Text(
            shared
                ? '已调起系统分享面板，选择微信、邮件或「保存到文件」即可发到电脑。'
                : '若未自动弹出分享面板，文件已保存在应用私有目录的 exports 文件夹内。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.7, color: isDark ? c.weak : c.sub),
          ),
        ],
      ),
    );
  }
}
