// 星禾口语 · App 入口
// 职责：挂载全局状态（Provider）、配置主题、设定首页
// 当前阶段（班级管理 MVP）：底部导航壳（首页|班级|作业|我的）+

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'net/api_client.dart';
import 'pages/home_shell.dart';
import 'store/class_store.dart';
import 'store/material_store.dart';
import 'store/user_store.dart';

void main() {
  // 桌面端（Windows/Linux/macOS）没有 sqflite 官方插件自带的 SQLite 引擎，
  // 需要 FFI 方式初始化数据库工厂；安卓/iOS 不需要这一步（走官方插件）。
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const XingheApp());
}

class XingheApp extends StatelessWidget {
  const XingheApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 用 MultiProvider 挂多个全局状态：
    //   MaterialStore —— 素材仓库（播放器数据）
    //   UserStore     —— 设备身份（uid / 昵称 / 角色）
    //   ApiClient     —— 后端接口客户端（Provider 提供，方便测试替换）
    //   ClassStore    —— 班级仓库（依赖 ApiClient，uid 由页面调用时传入）
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final MaterialStore store = MaterialStore();
            store.load(); // 打开 App 时立刻加载一次（模拟加载 → 正常有数据）
            return store;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final UserStore store = UserStore();
            store.load(); // 启动时读本地身份，首次则生成 uid
            return store;
          },
        ),
        // ApiClient 是普通类（非 ChangeNotifier），用 Provider 提供单一实例
        Provider<ApiClient>(create: (_) => ApiClient()),
        // ClassStore 依赖 ApiClient，用 ProxyProvider 把 api 实例注入进去
        ChangeNotifierProxyProvider<ApiClient, ClassStore>(
          create: (_) => ClassStore(api: ApiClient()),
          update: (_, ApiClient api, ClassStore? store) =>
              store ?? ClassStore(api: api),
        ),
      ],
      child: MaterialApp(
        title: '星禾口语',
        theme: ThemeData(
          // 品牌色系（Day 20 视觉对齐「学在重邮」）：青绿主色、米白灰底
          //   primary 青绿 #2BC8B7：按钮、选中态、下划线等主强调
          //   页面底色 #F4F6F8 浅灰：卡片浮在上面
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2BC8B7),
            surface: const Color(0xFFF4F6F8),
          ),
          // 让卡片、对话框等表面统一用白色
          cardTheme: const CardThemeData(
            color: Color(0xFFFFFFFF),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F6F8),
          // FAB：青绿底白字
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF2BC8B7),
            foregroundColor: Colors.white,
          ),
          // chip 统一青绿系
          chipTheme: ChipThemeData(
            backgroundColor: const Color(0xFFFFFFFF),
            selectedColor: const Color(0xFFDFF5F2),
            side: BorderSide(color: const Color(0xFF2BC8B7).withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          // 弹出菜单（排序选择等）：默认样式是灰色块，和米色主题脱节，
          // 统一改成白底圆角卡片风格，和素材卡片同一视觉语言
          popupMenuTheme: PopupMenuThemeData(
            color: const Color(0xFFFFFFFF),
            // 关键：去掉 Material 3 默认的选中项灰色高亮带（surface tint）。
            // 不设这行，选中项背后会有一层灰底，和绿字叠加显脏。
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: const Color(0xFF6BBF8A).withValues(alpha: 0.15)),
            ),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.15),
            // 菜单项文字默认色
            textStyle: const TextStyle(color: Color(0xFF333333), fontSize: 15),
          ),
        ),
        // 首页 = 底部导航壳（首页|班级|作业|我的）
        home: const HomeShell(),
      ),
    );
  }
}
