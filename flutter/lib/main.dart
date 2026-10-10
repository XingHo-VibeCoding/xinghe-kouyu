// 星禾口语 · App 入口
// 职责：挂载全局状态（Provider）、配置主题、设定首页
// 当前阶段（壳工程）：三个页面骨架 + Navigator 切换 + 列表四态，真实功能后续逐步接入

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/material_list_page.dart';
import 'store/material_store.dart';

void main() {
  // 本阶段只在 Android 真机上运行，sqflite 官方插件会自动初始化数据库工厂，
  // 因此无需（也不应该）做任何平台判断或 FFI 初始化。
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
          // 品牌色系：淡蓝为主色、米色打底、淡黄点缀（Day 18 定）
          //   primary 淡蓝 #5B8FC9：按钮、图标、选中态等主强调（比 #6FA8DC 深一档，
          //     在米色背景上对比度足够，FAB 不再「隐形」）
          //   surface  米色  #FAF6EF：卡片/页面背景，柔和不刺眼
          //   淡黄 #F2C94C（进度条）/ #F7E8B0（高亮底）作为唯一强调色
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5B8FC9),
            surface: const Color(0xFFFAF6EF),
          ),
          // 让卡片、对话框等表面统一用米色，而不是默认白
          cardTheme: const CardThemeData(
            color: Color(0xFFFFFFFF),
          ),
          scaffoldBackgroundColor: const Color(0xFFFAF6EF),
          // FAB：用主色淡蓝做底色（默认就是 primary，这里显式点出，确保不褪成浅灰）
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF5B8FC9),
            foregroundColor: Colors.white,
          ),
          // 让「循环/AB/重置」等 chip 默认不再带 Material 默认的橙色/灰边框，
          // 统一走主题色，消灭页面里混进来的杂色
          chipTheme: ChipThemeData(
            backgroundColor: const Color(0xFFFFFFFF),
            selectedColor: const Color(0xFFF7E8B0),
            side: BorderSide(color: const Color(0xFF5B8FC9).withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          // 弹出菜单（排序选择等）：默认样式是灰色块，和米色主题脱节，
          // 统一改成白底圆角卡片风格，和素材卡片同一视觉语言
          popupMenuTheme: PopupMenuThemeData(
            color: const Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: const Color(0xFF5B8FC9).withValues(alpha: 0.15)),
            ),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.15),
            // 菜单项文字默认色
            textStyle: const TextStyle(color: Color(0xFF333333), fontSize: 15),
          ),
        ),
        // 首页 = 素材列表页
        home: const MaterialListPage(),
      ),
    );
  }
}
