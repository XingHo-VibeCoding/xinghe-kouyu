// 页面 1「素材列表」：App 首页，也是四种状态的主展示页
// 四种状态：加载中（骨架屏）/ 空 / 出错 / 正常有数据
// 底部「状态预览条」是开发用的临时工具，方便逐个状态截图，上线前会删掉

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/material_item.dart';
import '../store/material_store.dart';
import '../utils/design_tokens.dart';
import '../utils/sort_option.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/material_card.dart';
import '../widgets/skeleton_list.dart';
import '../widgets/sort_menu.dart';
import 'folder_manage_page.dart';
import 'import_flow.dart';
import 'player_page.dart';

class MaterialListPage extends StatefulWidget {
  const MaterialListPage({super.key});

  @override
  State<MaterialListPage> createState() => _MaterialListPageState();
}

class _MaterialListPageState extends State<MaterialListPage> {
  // 当前排序方式（默认「导入顺序」= id 升序）。只是展示层状态，不写回数据库。
  SortOption _sortOption = SortOption.importOrder;

  @override
  Widget build(BuildContext context) {
    // watch：仓库状态一变，这一页自动重新构建
    final MaterialStore store = context.watch<MaterialStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('星禾口语'),
        actions: <Widget>[
          // 排序入口：点开弹出四选一菜单
          _buildSortButton(store),
          // 入口 1：去「文件夹管理」页（Navigator.push 压栈，新页自带返回箭头）
          IconButton(
            icon: const Icon(Icons.folder_copy_outlined),
            tooltip: '文件夹管理',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FolderManagePage()),
              );
            },
          ),
        ],
      ),
      // 按当前状态渲染对应界面（switch 表达式：枚举四档全覆盖，少一档都编译不过）；
      // AnimatedSwitcher 让四态切换淡入淡出（动效·第三批 B1），KeyedSubtree 用状态枚举做 key 触发过渡
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(store.status),
          child: switch (store.status) {
            ListStatus.loading => const SkeletonList(),
            ListStatus.empty => _buildEmpty(context),
            ListStatus.error => _buildError(context, store),
            ListStatus.data => _buildList(context, store),
          },
        ),
      ),
      // 常驻「导入」悬浮按钮：有数据/空状态都能导，避免「导入第一条后入口消失」的断点
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startImport(context),
        tooltip: '导入素材',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 状态②：空 —— 没有素材是完全正常的情况，要引导用户去导入
  Widget _buildEmpty(BuildContext context) {
    return EmptyState(
      icon: Icons.eco_outlined,
      title: '还没有素材',
      description: '把老师发的音视频导入进来，这里就会长出你的素材列表。',
      action: FilledButton.icon(
        onPressed: () => _startImport(context),
        icon: const Icon(Icons.add),
        label: const Text('导入素材'),
      ),
    );
  }

  /// 状态③：出错 —— 三个要素：说清发生了什么、给出口（重试）、别让用户干等
  Widget _buildError(BuildContext context, MaterialStore store) {
    return ErrorState(
      message: store.errorMessage,
      onRetry: () => store.load(), // 重试 = 重新走一遍完整加载
    );
  }

  /// 状态④：正常有数据 —— 素材卡片列表，点某条进「播放页」
  /// 传入 store，是为了拿「文件夹名」（folderId → 名字）并传给播放页
  Widget _buildList(BuildContext context, MaterialStore store) {
    // 先按用户选的排序方式排一遍，再渲染（纯展示层，不改数据库原始顺序）
    final List<MaterialItem> items = sortMaterials(store.items, _sortOption);
    return ListView.separated(
      padding: const EdgeInsets.all(kSpaceSM),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: kSpaceXXS),
      itemBuilder: (BuildContext context, int index) {
        final MaterialItem item = items[index];
        return MaterialCard(
          item: item,
          subtitle: _materialSubtitle(store, item),
          // 长按：弹出操作菜单（重命名 / 移动 / 删除），和浏览页一致
          onLongPress: () => _showItemMenu(context, store, item),
          onOpen: () {
            // 入口 2：进「播放页」，把点中的素材和它的文件夹名一起传过去
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerPage(
                  item: item,
                  folderName: store.folderNameOf(item.folderId),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 排序入口按钮：AppBar 上的排序图标，点开弹出「四选一」菜单
  Widget _buildSortButton(MaterialStore store) {
    return SortMenu(
      option: _sortOption,
      onChanged: (SortOption opt) {
        setState(() => _sortOption = opt);
      },
    );
  }

  /// 演示阶段的占位提示：诚实地告诉用户这个功能还没接入
  void _showDemoTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 拼接素材卡片的副标题：「文件夹 · 格式 · 时长」。
  /// 只拼接非空的段，避免时长为空时末尾出现孤立的「·」分隔符。
  String _materialSubtitle(MaterialStore store, MaterialItem item) {
    final List<String> parts = <String>[
      store.folderNameOf(item.folderId),
      item.format.toUpperCase(),
      if (item.duration.isNotEmpty) item.duration,
    ];
    return parts.join(' · ');
  }

  /// 长按素材弹出的操作菜单：重命名 / 移动 / 删除
  Future<void> _showItemMenu(BuildContext context, MaterialStore store, MaterialItem item) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('移动'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text('删除', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    switch (action) {
      case 'rename':
        await _promptRename(context, store, item);
        break;
      case 'move':
        await _promptMove(context, store, item);
        break;
      case 'delete':
        await _confirmDelete(context, store, item);
        break;
    }
  }

  /// 重命名素材（含后缀保护，走 store.renameMaterial）
  Future<void> _promptRename(BuildContext context, MaterialStore store, MaterialItem item) async {
    final TextEditingController controller = TextEditingController(text: item.title);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('重命名素材'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入新名称'),
          onSubmitted: (String value) => Navigator.pop(ctx, value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    try {
      await store.renameMaterial(item, result);
    } catch (e) {
      _showError(context, e);
    }
  }

  /// 移动素材：弹「其他根文件夹」单选列表（不含当前）
  Future<void> _promptMove(BuildContext context, MaterialStore store, MaterialItem item) async {
    final List<Folder> targets =
        store.folders.where((f) => f.id != item.folderId).toList();
    if (targets.isEmpty) {
      _showDemoTip(context, '没有其他文件夹可移动，先去「文件夹管理」新建一个。');
      return;
    }

    final Folder? target = await showDialog<Folder>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('移动到哪个文件夹？'),
        contentPadding: const EdgeInsets.symmetric(vertical: kSpaceXS),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: targets
              .map(
                (Folder f) => ListTile(
                  leading: Icon(
                    Icons.folder_outlined,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  title: Text(f.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, f),
                ),
              )
              .toList(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (target == null) return;
    try {
      await store.moveMaterial(item.id, target.id);
    } catch (e) {
      _showError(context, e);
    }
  }

  /// 删除素材：二次确认（红字警示，连带本地文件）
  Future<void> _confirmDelete(BuildContext context, MaterialStore store, MaterialItem item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除「${item.title}」？'),
        content: const Text('素材和本地文件都会删除，且不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await store.deleteMaterial(item);
      } catch (e) {
        _showError(context, e);
      }
    }
  }

  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失败：$e'), backgroundColor: Colors.red),
    );
  }

  /// 【数据导入】入口：先让用户选「放进哪个文件夹」，再调文件选择器，最后写库。
  /// 具体编排放在 import_flow.dart（素材列表页 / 文件夹管理页 / 文件夹内容页共用一套）。
  Future<void> _startImport(BuildContext context) => importWithFolderPicker(context);
}
