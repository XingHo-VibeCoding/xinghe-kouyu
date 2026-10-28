// =====================================================================
// 页面「我的」：1:1 复刻「学在重邮」我的页（Day 20 视觉对齐）
// ---------------------------------------------------------------------
// 结构：青绿渐变头部（昵称 + 白色圆形头像）→ 白色圆角菜单卡片
//       （资源库/我的关注/我的收藏 + 反馈/帮助中心/设置 两组）。
//
// 保留的真实逻辑：
//   - 点击头部（昵称/头像）→ 弹登记弹窗（昵称 + 身份），本地保存 + 同步云端；
//   - 长按昵称 → 复制当前 uid（联调用，藏在长按里，不破坏 1:1 视觉）；
//   - 账号区（Day 24）：未登录显示「登录 / 注册」，已登录显示「退出登录」；
//   - 其余菜单项点击均为占位提示，后续接真实功能。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../net/api_client.dart';
import '../store/class_store.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import 'login_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final UserStore userStore = context.watch<UserStore>();

    return Scaffold(
      backgroundColor: kBg,
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            // ---------- 青绿渐变头部 ----------
            _buildHeader(context, userStore),
            // ---------- 菜单卡片（白色圆角，上移遮住渐变底部） ----------
              Transform.translate(
              offset: const Offset(0, -20),
              child: Column(
                children: <Widget>[
                  // ---------- 账号区（Day 24）：随登录态切换 ----------
                  _menuGroup(context, <_MenuItem>[
                    if (userStore.isSignedIn)
                      _MenuItem(Icons.logout, '退出登录',
                          onTap: (BuildContext ctx) => _confirmSignOut(ctx))
                    else
                      const _MenuItem(Icons.account_circle_outlined, '登录 / 注册',
                          onTap: _openLoginPage),
                  ]),
                  const SizedBox(height: 12),
                  _menuGroup(context, <_MenuItem>[
                    const _MenuItem(Icons.inventory_2_outlined, '资源库'),
                    const _MenuItem(Icons.person_outline, '我的关注'),
                    const _MenuItem(Icons.star_outline, '我的收藏'),
                  ]),
                  const SizedBox(height: 12),
                  _menuGroup(context, <_MenuItem>[
                    const _MenuItem(Icons.chat_bubble_outline, '反馈'),
                    const _MenuItem(Icons.help_outline, '帮助中心'),
                    const _MenuItem(Icons.settings_outlined, '设置'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 渐变头部：蓝→青绿，左侧大字昵称，右侧白色圆形头像
  Widget _buildHeader(BuildContext context, UserStore userStore) {
    return Container(
      height: 230,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF56C3E0), Color(0xFF2FBFAF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        // 底部圆角让白色卡片有「叠上来」的层次
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: <Widget>[
              // 昵称：点击 = 登记/修改；长按 = 复制 uid
              Expanded(
                child: GestureDetector(
                  onTap: () => _showRegisterDialog(context, userStore),
                  onLongPress: () => _copyUid(context, userStore),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    userStore.nickname.isEmpty ? '点击登记' : userStore.nickname,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              // 白色圆形头像：点击 = 登记/修改
              GestureDetector(
                onTap: () => _showRegisterDialog(context, userStore),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person,
                      size: 44, color: Color(0xFFDDDDDD)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一组菜单（白色圆角卡片包住若干行）
  Widget _menuGroup(BuildContext context, List<_MenuItem> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        // 用 Material 提供白底（不用 Container 的 BoxDecoration）：
        // ListTile 的背景和水波纹画在最近的 Material 祖先上，
        // 中间隔一层带颜色的 DecoratedBox 会吞掉它们（触发框架警告）。
        // 注意：圆角裁切(clipBehavior)也放 Material 上，外层 Container 不再带
        // clipBehavior（没有 decoration 时带 clipBehavior 会触发断言崩溃）。
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusCard),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: items
              .map(( _MenuItem item) => _menuRow(context, item))
              .toList(),
        ),
      ),
    );
  }

  /// 单行菜单：线性图标 + 标题 + 右箭头；有 onTap 走真实逻辑，否则占位提示
  Widget _menuRow(BuildContext context, _MenuItem item) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(item.icon, size: 24, color: kTextSecondary),
      title: Text(
        item.label,
        style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
      ),
      trailing:
          const Icon(Icons.chevron_right, size: 22, color: Color(0xFFCCCCCC)),
      onTap: () {
        if (item.onTap != null) {
          item.onTap!(context);
          return;
        }
        // 占位：后续接各菜单的真实功能
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.label} 功能开发中')),
        );
      },
    );
  }

  /// 打开登录页（Day 24：账号入口，登录页里可跳注册页）
  static void _openLoginPage(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const LoginPage()));
  }

  /// 退出登录：先确认，再清云端会话
  ///
  /// 只清「登录态」，不清本地数据——昵称、角色、素材库、播放进度全部保留，
  /// 退出后自动回落成游客（用设备 uid），班级栏变成登录引导页。
  static Future<void> _confirmSignOut(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后「班级」需要重新登录才能使用。\n本地素材、播放进度和昵称都会保留。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kTeal),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await context.read<UserStore>().signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  /// 长按昵称：复制当前身份 uid（联调用；已登录 = 账号 uid，游客 = 设备 uid）
  void _copyUid(BuildContext context, UserStore userStore) {
    Clipboard.setData(ClipboardData(text: userStore.uid));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(userStore.isSignedIn ? '账号 uid 已复制' : '设备 uid 已复制（游客态）'),
    ));
  }

  /// 登记弹窗：昵称 + 身份单选，**先写云端、成功后才更新本地**
  /// 已有班级记录时，身份不可改（锁定），只允许改昵称。
  Future<void> _showRegisterDialog(
      BuildContext context, UserStore userStore) async {
    // 游客态：昵称/角色是「账号资料」，存在云端 users 表，先登录才有归属
    if (!userStore.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录后才能设置昵称和身份')),
      );
      _openLoginPage(context);
      return;
    }

    final TextEditingController controller =
        TextEditingController(text: userStore.nickname);
    // 初始角色以云端为准（userStore.role 已从 users 表同步）。
    // 注意：不能在这里用"本地没值就当学生"兜底——那正是老师换设备
    // 登录后被降级成学生的原因。
    UserRole selectedRole = userStore.role ?? UserRole.student;

    // 先查「我是否已有班级记录」：有则锁定身份，不能再改老师/学生
    final ClassStore classStore = context.read<ClassStore>();
    final ApiResult<bool> hasClass = await classStore.hasAnyClass(userStore.uid);
    final bool roleLocked = hasClass.ok && hasClass.data == true;
    if (!context.mounted) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        // 用 StatefulBuilder 让身份单选能即时刷新选中态
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setState) {
            return AlertDialog(
              title: const Text('填写信息'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 20,
                    decoration: const InputDecoration(
                        hintText: '昵称', counterText: ''),
                  ),
                  const SizedBox(height: 16),
                  // 身份锁定提示
                  if (roleLocked)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.lock_outline,
                              size: 14, color: Color(0xFF999999)),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '你已有班级记录，身份已锁定不可修改',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF999999)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 身份单选
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _roleChip(
                          ctx,
                          label: '我是老师',
                          icon: Icons.school,
                          selected: selectedRole == UserRole.teacher,
                          enabled: !roleLocked,
                          onTap: () =>
                              setState(() => selectedRole = UserRole.teacher),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _roleChip(
                          ctx,
                          label: '我是学生',
                          icon: Icons.face,
                          selected: selectedRole == UserRole.student,
                          enabled: !roleLocked,
                          onTap: () =>
                              setState(() => selectedRole = UserRole.student),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kTeal),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('保存')),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    final String nickname = controller.text.trim();
    if (nickname.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('昵称不能为空')));
      }
      return;
    }

    // 保存：先云端成功、再更新本地
    // （顺序不能反：先写本地的话，云端一失败就出现「App 认为你是老师、
    //   数据库里没你这人」的分裂状态，要到建班时才暴露）
    final ApiResult<void> result = await userStore.saveProfile(
      nickname: nickname,
      role: selectedRole,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.ok ? '保存成功' : '保存失败：${result.message}')),
    );
  }

  /// 身份选择 chip；enabled=false 时置灰不可点
  Widget _roleChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final bool effective = enabled && selected;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: effective ? kTeal : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effective ? kTeal : (enabled ? Colors.black26 : Colors.black12),
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              icon,
              color: effective
                  ? Colors.white
                  : (enabled ? Colors.black54 : Colors.black26),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: effective
                    ? Colors.white
                    : (enabled ? Colors.black87 : Colors.black26),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 菜单项数据（onTap 非空 = 有真实逻辑的菜单项）
class _MenuItem {
  final IconData icon;
  final String label;
  final void Function(BuildContext)? onTap;
  const _MenuItem(this.icon, this.label, {this.onTap});
}
