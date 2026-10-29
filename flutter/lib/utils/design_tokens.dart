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

/// 错误红（异常信号：加载失败/表单错误等，与登录页错误红同族）
const Color kError = Color(0xFFE53935);

/// 页面背景（带青调的暖白，取代死灰 F4F6F8）
const Color kBg = Color(0xFFF7FAF9);

/// 卡片白
const Color kCard = Color(0xFFFFFFFF);

/// 主文字（近黑）
const Color kTextPrimary = Color(0xFF1F2733);

/// 次要文字
const Color kTextSecondary = Color(0xFF5C6670);

/// 辅助文字（占位/提示）
const Color kTextHint = Color(0xFF7A8693);

/// 分隔线/描边
const Color kBorder = Color(0xFFE6ECEA);

/// 字阶（星禾专用七级：展示/大标题/大字/卡片标题/正文/辅助/微字）
const double kFontDisplay = 28; // 展示大标题（个人页/详情页）
const double kFontHero = 24; // 页面大标题（问候语）
const double kFontLarge = 20; // 大字（播放页标题/空状态标题）
const double kFontTitle = 16; // 卡片标题
const double kFontBody = 14; // 正文
const double kFontCaption = 12; // 辅助/说明
const double kFontMicro = 10; // 微字（波形刻度/角标）

/// 间距（8 点栅格）
const double kSpaceXXS = 4; // 微间距/图标文字间
const double kSpaceXS = 8; // 紧凑间距/列表分隔
const double kSpaceSM = 12; // 常规间距/卡片内边距
const double kSpaceMD = 16; // 默认间距/页面边距
const double kSpaceLG = 24; // 区块间距
const double kSpaceXL = 32; // 大区块/空状态

/// 圆角（五档：小元素/头像菜单/卡片/按钮胶囊/全圆）
const double kRadiusXS = 8; // 小元素/徽章/波形
const double kRadiusSM = 12; // 头像/菜单
const double kRadiusCard = 16; // 卡片
const double kRadiusBtn = 24; // 按钮/胶囊
const double kRadiusFull = 999; // 全圆（头像/唱片/播放键）

/// 图标尺寸（五档：微/小/常规/大/特大）
const double kIconXS = 16; // 微图标（锁/重试等行内小标）
const double kIconSM = 20; // 小图标（导航/筛选/更多等）
const double kIconMD = 24; // 常规图标（默认 Material 图标尺寸）
const double kIconLG = 36; // 大图标（功能宫格/收藏）
const double kIconXL = 64; // 特大图标（空状态/错误态）

/// 字重（三档）
const FontWeight kWeightRegular = FontWeight.w400; // 正文
const FontWeight kWeightMedium = FontWeight.w600; // 强调/副标题
const FontWeight kWeightBold = FontWeight.w700; // 标题

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

/// 唱片光晕（播放页音频态唱片外圈青绿光晕）
const List<BoxShadow> kShadowDisc = [
  BoxShadow(color: Color(0x732BC8B7), blurRadius: 24, offset: Offset(0, 8)),
];

/// 唱片中心标签阴影（柔和投影）
const List<BoxShadow> kShadowLabel = [
  BoxShadow(color: Color(0x1F000000), blurRadius: 6, offset: Offset(0, 2)),
];

/// 卡片描边（1px 淡青描边，让白卡从背景里「浮」出来）
const Border kCardBorder = Border(
  top: BorderSide(color: kBorder, width: 1),
  left: BorderSide(color: kBorder, width: 1),
  right: BorderSide(color: kBorder, width: 1),
  bottom: BorderSide(color: kBorder, width: 1),
);
