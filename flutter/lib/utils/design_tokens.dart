// =====================================================================
// 设计令牌（Design Tokens）—— 全局视觉规范的唯一来源
// ---------------------------------------------------------------------
// 为什么要有这一层：以前颜色/字号/间距散落在每个页面里（写死 0xFF333333 等），
// 改一处要翻全项目。现在统一收进这里，所有页面只引用这些常量，
// 视觉升级只需改这一个文件。
//
// 风格方向：Playful × Refined（明快 + 精致）
//   - 主色：青绿（品牌延续）
//   - 强调：珊瑚橙（只用于关键动作：下载/播放/重要按钮）
//   - 背景：带青调的暖白，取代死灰
// =====================================================================

import 'package:flutter/material.dart';

/// 品牌青绿（主色，按钮/选中态/标签）
const Color kTeal = Color(0xFF2BC8B7);

/// 青绿深色（按压/渐变深端）
const Color kTealDark = Color(0xFF23B9A9);

/// 青绿浅底（选中背景/标签底）
const Color kTealSoft = Color(0xFFDFF5F2);

/// 珊瑚橙（强调色，仅用于关键动作，全 App 只此一个强调色）
const Color kCoral = Color(0xFFFF7A59);

/// 页面背景（带青调的暖白，取代死灰 F4F6F8）
const Color kBg = Color(0xFFF7FAF9);

/// 卡片白
const Color kCard = Color(0xFFFFFFFF);

/// 主文字（近黑）
const Color kTextPrimary = Color(0xFF1F2733);

/// 次要文字
const Color kTextSecondary = Color(0xFF5C6670);

/// 辅助文字（占位/提示）
const Color kTextHint = Color(0xFF98A2AB);

/// 分隔线/描边
const Color kBorder = Color(0xFFE6ECEA);

/// 字阶（星禾专用四级：大标题/卡片标题/正文/辅助）
const double kFontHero = 24; // 页面大标题（问候语）
const double kFontTitle = 16; // 卡片标题
const double kFontBody = 14; // 正文
const double kFontCaption = 12; // 辅助/说明

/// 圆角
const double kRadiusCard = 16; // 卡片
const double kRadiusBtn = 24; // 按钮/胶囊

/// 阴影三级（Y 偏移 2 / 8 / 24）
const List<BoxShadow> kShadowSm = [
  BoxShadow(color: Color(0x0A1F2733), blurRadius: 8, offset: Offset(0, 2)),
];
const List<BoxShadow> kShadowMd = [
  BoxShadow(color: Color(0x121F2733), blurRadius: 16, offset: Offset(0, 8)),
];
const List<BoxShadow> kShadowLg = [
  BoxShadow(color: Color(0x1A1F2733), blurRadius: 32, offset: Offset(0, 24)),
];

/// 卡片描边（1px 淡青描边，让白卡从背景里「浮」出来）
const Border kCardBorder = Border(
  top: BorderSide(color: kBorder, width: 1),
  left: BorderSide(color: kBorder, width: 1),
  right: BorderSide(color: kBorder, width: 1),
  bottom: BorderSide(color: kBorder, width: 1),
);
