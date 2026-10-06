// 页面 1「素材列表」：App 首页，也是四种状态的主展示页
// 四种状态：加载中（骨架屏）/ 空 / 出错 / 正常有数据
// 底部「状态预览条」是开发用的临时工具，方便逐个状态截图，上线前会删掉

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/material_item.dart';
import '../store/material_store.dart';
import 'folder_manage_page.dart';
import 'folder_content_page.dart';
import 'player_page.dart';

class MaterialListPage extends StatelessWidget {
  const MaterialListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // watch：仓库状态一变，这一页自动重新构建
    final MaterialStore store = context.watch<MaterialStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('星禾口语'),
        actions: <Widget>[
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
      // 按当前状态渲染对应界面（switch 表达式：枚举四档全覆盖，少一档都编译不过）
      body: switch (store.status) {
        ListStatus.loading => _buildLoading(),
        ListStatus.empty => _buildEmpty(context),
        ListStatus.error => _buildError(context, store),
        ListStatus.data => _buildList(context, store),
      },
      // 开发用状态预览条（临时，上线前删）
      bottomNavigationBar: _buildDevStateBar(store),
      // 常驻「导入」悬浮按钮：有数据/空状态都能导，避免「导入第一条后入口消失」的断点
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startImport(context),
        tooltip: '导入素材',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 状态①：加载中 —— 骨架屏（灰块占位），好处是数据到达时布局不跳动
  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (_, __) => const _SkeletonRow(),
    );
  }

  /// 状态②：空 —— 没有素材是完全正常的情况，要引导用户去导入
  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.eco_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('还没有素材', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '把老师发的音视频导入进来，这里就会长出你的素材列表。',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _startImport(context),
            icon: const Icon(Icons.add),
            label: const Text('导入素材'),
          ),
        ],
      ),
    );
  }

  /// 状态③：出错 —— 三个要素：说清发生了什么、给出口（重试）、别让用户干等
  Widget _buildError(BuildContext context, MaterialStore store) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 72, color: Colors.orange),
          const SizedBox(height: 12),
          const Text('加载失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(store.errorMessage, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => store.load(), // 重试 = 重新走一遍完整加载
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 状态④：正常有数据 —— 素材卡片列表，点某条进「播放页」
  /// 传入 store，是为了拿「文件夹名」（folderId → 名字）并传给播放页
  Widget _buildList(BuildContext context, MaterialStore store) {
    final List<MaterialItem> items = store.items;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (BuildContext context, int index) {
        final MaterialItem item = items[index];
        final bool isVideo =
            item.format == 'mp4' || item.format == 'mov' || item.format == 'webm';
        return Card(
          child: ListTile(
            leading: Icon(
              isVideo ? Icons.movie_outlined : Icons.audiotrack,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(item.title),
            subtitle: Text(_materialSubtitle(store, item)),
            trailing: const Icon(Icons.chevron_right),
            // 长按：弹出操作菜单（重命名 / 移动 / 删除），和浏览页一致
            onLongPress: () => _showItemMenu(context, store, item),
            onTap: () {
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
          ),
        );
      },
    );
  }

  /// 底部状态预览条【开发用临时工具，上线前删除】
  /// 点按钮直接把列表拨到对应状态，方便逐个截图验收
  Widget _buildDevStateBar(MaterialStore store) {
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            const Text('状态预览（开发用）：', style: TextStyle(fontSize: 12, color: Colors.black54)),
            TextButton(
              onPressed: () => store.preview(ListStatus.loading),
              child: const Text('加载中'),
            ),
            TextButton(
              onPressed: () => store.preview(ListStatus.empty),
              child: const Text('空'),
            ),
            TextButton(
              onPressed: () => store.preview(ListStatus.error),
              child: const Text('出错'),
            ),
            TextButton(
              onPressed: () => store.preview(ListStatus.data),
              child: const Text('有数据'),
            ),
          ],
        ),
      ),
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
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
  /// 用 async 方法编排这条多步链路，每一步 await 等上一步完成再往下走。
  Future<void> _startImport(BuildContext context) async {
    // 不重新 read，直接通过 context 拿 store（导入后会 load 刷新，页面自动重建）
    final MaterialStore store = context.read<MaterialStore>();

    // 没有任何文件夹时，直接引导新建（否则素材没有归属）
    if (store.folders.isEmpty) {
      final bool created = await _createFolderInline(context, store);
      if (!created) return; // 新建失败或取消，就停在这里
    }

    // —— 第一步：选目标文件夹（方案 B）——
    // 用 AlertDialog 弹一个单选列表（带「取消」+「新建文件夹」）。
    // 返回类型用 Object：既可能是选中的 Folder，也可能是「新建文件夹」哨兵。
    final Object? target = await showDialog<Object>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('导入到哪个文件夹？'),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: store.folders
                .map(
                  (Folder f) => ListTile(
                    leading: Icon(
                      Icons.folder_outlined,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                    title: Text(f.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(dialogContext, f), // 点哪项就把哪个文件夹返回
                  ),
                )
                .toList(),
          ),
          actions: <Widget>[
            TextButton.icon(
              // 弹窗里就地新建文件夹，省得用户取消再跑一趟
              onPressed: () async {
                final bool created = await _createFolderInline(dialogContext, store);
                if (!created || !dialogContext.mounted) return;
                // 建好了要刷新弹窗里的文件夹列表（store 已 notify，但弹窗自身需重建）
                Navigator.pop(dialogContext, _FolderCreateSentinel());
              },
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新建文件夹'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), // 取消：返回 null
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
    // 用户点了取消或点了对话框外（返回 null）就直接结束，不往下走
    if (target == null) return;

    // 点的是「新建文件夹」：重新弹一次选择框，让用户选中刚建好的文件夹
    if (target is _FolderCreateSentinel) {
      await _startImport(context);
      return;
    }

    // 到这里 target 一定是选中的文件夹
    final Folder chosen = target as Folder;

    // —— 第二步：调文件选择器 + 复制 + 写库（这一步会真实地弹系统文件选择器）——
    try {
      final String? importedTitle = await store.importMaterial(chosen.id);
      if (importedTitle == null) {
        // 用户在选择文件那一步取消了，礼貌地告知即可，不算错误
        _showDemoTip(context, '已取消导入');
        return;
      }
      _showDemoTip(context, '已导入「$importedTitle」到「${chosen.name}」');
    } catch (e) {
      // 出错：把真实原因告诉用户，别吞掉
      _showDemoTip(context, '导入失败：$e');
    }
  }

  /// 就地新建文件夹（导入链路里复用）：弹输入框 → 调 store.addFolder → 返回是否成功。
  /// 成功返回 true；取消或名字为空返回 false。出错时用 SnackBar 提示并返回 false。
  Future<bool> _createFolderInline(BuildContext context, MaterialStore store) async {
    final String? name = await _askFolderName(context);
    if (name == null || name.trim().isEmpty) return false;
    try {
      await store.addFolder(name.trim());
      return true;
    } catch (e) {
      _showDemoTip(context, '新建文件夹失败：$e');
      return false;
    }
  }

  /// 弹一个「新建文件夹」输入框，返回用户输入的文字（取消返回 null）
  Future<String?> _askFolderName(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '请输入文件夹名'),
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
    return result;
  }
}

/// 哨兵：用来标记「用户在文件夹选择弹窗里点了『新建文件夹』」。
/// 选择弹窗返回这个对象时，表示不是选中的文件夹，而是要求新建后再选。
class _FolderCreateSentinel {}

/// 骨架屏的一行：圆形头像 + 两行灰条，模拟真实素材卡片的布局
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(width: double.infinity, height: 14, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    alignment: Alignment.centerLeft,
                    child: Container(height: 12, color: Colors.grey.shade200),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
