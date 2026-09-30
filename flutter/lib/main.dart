// 星禾口语 · App 入口
// 职责：挂载全局状态（Provider）、配置主题、设定首页
// 当前阶段（壳工程）：三个页面骨架 + Navigator 切换 + 列表四态，真实功能后续逐步接入

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/material_list_page.dart';
import 'store/material_store.dart';

void main() {
  runApp(const XingheApp());
}

class XingheApp extends StatelessWidget {
  const XingheApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider 把「素材仓库」挂在应用最顶层，
    // 之后所有页面拿到的都是同一个仓库实例（全局共享状态）
    return ChangeNotifierProvider(
      create: (_) {
        final MaterialStore store = MaterialStore();
        store.load(); // 打开 App 时立刻加载一次（模拟加载 → 正常有数据）
        return store;
      },
      child: MaterialApp(
        title: '星禾口语',
        theme: ThemeData(
          // 品牌绿（#3A8F6F），与原 PWA 的 theme-color 保持一致
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3A8F6F)),
        ),
        // 首页 = 素材列表页
        home: const MaterialListPage(),
      ),
    );
  }
}
