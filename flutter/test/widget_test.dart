// 冒烟测试：验证 App 能正常启动并显示「星禾口语」首页
// 当前阶段只保证壳工程可跑；更细的页面逻辑测试后续再补

import 'package:flutter_test/flutter_test.dart';

import 'package:xinghe_kouyu/main.dart';

void main() {
  testWidgets('App 启动后能看到「星禾口语」标题', (WidgetTester tester) async {
    // 构建整个 App（此时仓库开始模拟加载，处于「加载中」）
    await tester.pumpWidget(const XingheApp());

    // 推进假时钟，让 1 秒的模拟加载走完，状态落到「有数据」
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    // 首页 AppBar 上应能看到「星禾口语」
    expect(find.text('星禾口语'), findsOneWidget);
  });
}
