/// 真实网络下验证抓取链路：重定向跟随 → HTML 解析 → 标题选择。
/// 用法：dart run tool/metadata_selftest.dart [url ...]
library;

import 'package:clippings/metadata.dart';

Future<void> main(List<String> args) async {
  final urls = args.isEmpty
      ? [
          // 实测用的真实推文（X 的分享就是这种链接）
          'https://x.com/elonmusk/status/2120589832963711162',
          'https://sspai.com/',
        ]
      : args;

  for (final url in urls) {
    final watch = Stopwatch()..start();
    final result = await fetchLinkMetadata(url);
    watch.stop();
    if (result.ok) {
      final meta = result.data!;
      print('OK   ${watch.elapsedMilliseconds}ms  $url');
      print('     final : ${meta.finalUrl}');
      print('     title : ${meta.title}');
      print('     desc  : ${meta.description}');
      print('     image : ${meta.imageUrl}');
    } else {
      print('FAIL ${watch.elapsedMilliseconds}ms  $url  →  ${result.error}');
    }
    print('');
  }
}
