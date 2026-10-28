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
import 'utils/design_tokens.dart';

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
    //   ApiClient     —— 后端接口客户端（Provider 提供，方便测试替换）
    //   UserStore     —— 身份 + 云端资料（依赖 ApiClient，故声明在其后）
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
        // ApiClient 是普通类（非 ChangeNotifier），用 Provider 提供单一实例。
        // 必须排在 UserStore 前面：UserStore 要用它拉 users 表资料。
        Provider<ApiClient>(create: (_) => ApiClient()),
        ChangeNotifierProvider(
          create: (BuildContext ctx) {
            final UserStore store = UserStore(api: ctx.read<ApiClient>());
            store.load(); // 启动：读本地身份 → 确认登录态 → 拉云端资料
            return store;
          },
        ),
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
          // 品牌色系（Day 23 视觉升级）：青绿主色 + 珊瑚橙强调 + 暖白底
          colorScheme: ColorScheme.fromSeed(
            seedColor: kTeal,
            surface: kBg,
          ),
          // 卡片统一白色 + 淡青描边 + 圆角（所有 Card 组件自动生效）
          cardTheme: CardThemeData(
            color: kCard,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusCard),
              side: const BorderSide(color: kBorder),
            ),
          ),
          scaffoldBackgroundColor: kBg,
          // FAB：青绿底白字
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: kTeal,
            foregroundColor: Colors.white,
          ),
          // chip 统一青绿系
          chipTheme: ChipThemeData(
            backgroundColor: kCard,
            selectedColor: kTealSoft,
            side: BorderSide(color: kTeal.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusBtn),
            ),
          ),
          // 弹出菜单：白底圆角卡片风格
          popupMenuTheme: PopupMenuThemeData(
            color: kCard,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: kBorder),
            ),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.15),
            textStyle: const TextStyle(color: kTextPrimary, fontSize: kFontBody),
          ),
          // 全局文字主题：统一主文字色（后续页面可直接用默认色，不用到处写死）
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: kTextPrimary),
            bodySmall: TextStyle(color: kTextSecondary),
          ),
        ),
        // 首页 = 底部导航壳（首页|班级|播放|我的）
        home: const HomeShell(),
      ),
    );
  }
}
