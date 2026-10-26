// =====================================================================
// 页面「班级」：1:1 复刻「学在重邮」课程页（Day 20 视觉对齐）
// ---------------------------------------------------------------------
// 结构：顶部搜索条（占位）+ 扫码/建班图标 → 「我的班级 | 公开课」tab
//       → 筛选 → 班级卡片列表（缩略图 + 进行中角标 + 名称 + 码 + 教师）。
//
// 保留的真实逻辑：班级列表四态加载、建班弹窗、输码加入弹窗（沿用原实现）。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/class_item.dart';
import '../store/class_store.dart';
import '../store/user_store.dart';
import 'class_detail_page.dart';

class ClassListPage extends StatefulWidget {
  const ClassListPage({super.key});

  @override
  State<ClassListPage> createState() => _ClassListPageState();
}

class _ClassListPageState extends State<ClassListPage> {
  // 品牌青绿（学在重邮同款）
  static const Color teal = Color(0xFF2BC8B7);

  // 当前选中的 tab：0 = 我的班级，1 = 公开课
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // 首次进入自动加载一次班级列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String uid = context.read<UserStore>().uid;
      context.read<ClassStore>().load(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ClassStore store = context.watch<ClassStore>();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 12),
            // ---------- 顶部：搜索条 + 扫码 + 建班/加入 ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.search,
                              size: 20, color: Color(0xFF999999)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '输入课程名称或访问码',
                              style: TextStyle(
                                  fontSize: 14, color: Color(0xFF999999)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 扫码图标（占位）
                  IconButton(
                    icon: const Icon(Icons.crop_free_outlined,
                        color: Color(0xFF666666)),
                    onPressed: () => _toast(context, '扫码功能开发中'),
                  ),
                  // 建班 / 加入 入口（保留真实逻辑）
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF666666)),
                    tooltip: '建班 / 加入',
                    onPressed: () => _showEntryMenu(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // ---------- tab：我的班级 | 公开课 ----------
            _buildTabs(),
            // ---------- 筛选 ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  GestureDetector(
                    onTap: () => _toast(context, '筛选功能开发中'),
                    child: const Row(
                      children: <Widget>[
                        Text('筛选',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFF666666))),
                        SizedBox(width: 4),
                        Icon(Icons.filter_list,
                            size: 18, color: Color(0xFF666666)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ---------- 列表主体（四态） ----------
            Expanded(
              child: _tabIndex == 0
                  ? _buildBody(context, store)
                  : _buildPublicEmpty(),
            ),
          ],
        ),
      ),
    );
  }

  /// tab 行：选中的加粗 + 青绿下划线
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          _tabItem('我的班级', 0),
          const SizedBox(width: 28),
          _tabItem('公开课', 1),
        ],
      ),
    );
  }

  Widget _tabItem(String label, int index) {
    final bool selected = _tabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: selected ? FontWeight.bold : FontWeight.w400,
              color: selected
                  ? const Color(0xFF333333)
                  : const Color(0xFF999999),
            ),
          ),
          const SizedBox(height: 6),
          // 选中态：青绿短下划线
          Container(
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              color: selected ? teal : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  /// 「公开课」占位（暂无此功能）
  Widget _buildPublicEmpty() {
    return const Center(
      child: Text('公开课功能即将上线', style: TextStyle(color: Color(0xFF999999))),
    );
  }

  /// 主体四态：加载中 / 空 / 出错 / 有数据
  Widget _buildBody(BuildContext context, ClassStore store) {
    return switch (store.status) {
      ClassListStatus.loading =>
        const Center(child: CircularProgressIndicator(color: teal)),
      ClassListStatus.empty => _buildEmpty(context),
      ClassListStatus.error => _buildError(context, store),
      ClassListStatus.data => _buildList(context, store),
    };
  }

  /// 空状态：引导去建班或加入
  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.school_outlined, size: 64, color: Color(0xFFCCCCCC)),
          const SizedBox(height: 12),
          const Text('还没有班级',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('老师创建班级，学生用班级码加入',
              style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: teal),
            onPressed: () => _showEntryMenu(context),
            icon: const Icon(Icons.add),
            label: const Text('建班 / 加入'),
          ),
        ],
      ),
    );
  }

  /// 出错状态：说清原因 + 重试
  Widget _buildError(BuildContext context, ClassStore store) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 64, color: Colors.orange),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(store.errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: teal),
            onPressed: () => store.load(context.read<UserStore>().uid),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 班级卡片列表（课程页风格）
  Widget _buildList(BuildContext context, ClassStore store) {
    return RefreshIndicator(
      color: teal,
      onRefresh: () => store.load(context.read<UserStore>().uid),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: store.classes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (BuildContext context, int index) {
          final ClassItem cls = store.classes[index];
          return _classCard(cls);
        },
      ),
    );
  }

  /// 单张班级卡片：左侧缩略图（带「进行中」角标）+ 右侧信息；点击进详情页
  Widget _classCard(ClassItem cls) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ClassDetailPage(cls: cls)),
        );
      },
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 左侧缩略图占位 + 进行中角标
          Stack(
            children: <Widget>[
              Container(
                width: 96,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9EEF9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(Icons.collections,
                      color: Color(0xFF7FB8D4), size: 30),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '进行中',
                    style: TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // 右侧信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cls.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cls.code,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                ),
                const SizedBox(height: 2),
                Text(
                  '教师: ${cls.teacherName ?? '未知'}',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF999999)),
                ),
              ],
            ),
          ),
          // 右侧竖点菜单（占位）
          const Icon(Icons.more_vert, size: 20, color: Color(0xFFBBBBBB)),
        ],
        ),
      ),
    );
  }

  // =====================================================================
  // 下面是保留的真实业务逻辑（建班 / 加入），与原版一致
  // =====================================================================

  /// 建班 / 加入 的入口菜单（底部弹窗二选一）
  Future<void> _showEntryMenu(BuildContext context) async {
    final UserStore userStore = context.read<UserStore>();
    // 未登记身份（没填昵称/角色）时，先引导去「我的」页登记
    if (!userStore.isRegistered) {
      _toast(context, '请先在「我的」页填写昵称和身份');
      return;
    }

    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('创建班级（我是老师）'),
              subtitle: const Text('生成班级码，发给学生加入'),
              onTap: () => Navigator.pop(ctx, 'create'),
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('输入班级码加入（我是学生）'),
              subtitle: const Text('用老师给的 6 位码加入'),
              onTap: () => Navigator.pop(ctx, 'join'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'create') {
      await _promptCreateClass(context);
    } else if (action == 'join') {
      await _promptJoinClass(context);
    }
  }

  /// 建班：弹输入框，成功后刷新列表
  Future<void> _promptCreateClass(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('创建班级'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入班级名，如「高一(3)班」'),
          onSubmitted: (String v) => Navigator.pop(ctx, v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: teal),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;

    final ClassStore store = context.read<ClassStore>();
    final String uid = context.read<UserStore>().uid;
    final result = await store.createClass(uid, name.trim());
    if (!context.mounted) return;
    if (result.ok) {
      _toast(context, '创建成功，班级码：${result.data!.code}');
      await store.load(uid); // 刷新列表
    } else {
      _toast(context, result.message);
    }
  }

  /// 输码加入：弹输入框，成功后刷新列表
  Future<void> _promptJoinClass(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('输入班级码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: '6 位班级码，如 XH7K2M'),
          onSubmitted: (String v) => Navigator.pop(ctx, v),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: teal),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    if (!context.mounted) return;

    final ClassStore store = context.read<ClassStore>();
    final String uid = context.read<UserStore>().uid;
    final result = await store.joinClass(uid, code.trim().toUpperCase());
    if (!context.mounted) return;
    if (result.ok) {
      _toast(context, '加入成功');
      await store.load(uid);
    } else {
      _toast(context, result.message);
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
