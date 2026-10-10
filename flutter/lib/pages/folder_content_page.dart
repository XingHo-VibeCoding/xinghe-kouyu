// =====================================================================
// 页面「文件夹内容浏览页」（界面层，Flutter 进阶新增 F9）
// ---------------------------------------------------------------------
// 这层是什么：点根文件夹进入的「聚焦浏览页」，只显示这一个文件夹下的素材。
// 和「素材列表页」的区别：列表页看全部素材 + 入口；本页聚焦单一文件夹，
// 顶部标题 = 文件夹名 + 素材数量，自带返回箭头（返回式进出，方式 A）。
//
// 页内素材同样支持长按出菜单：重命名 / 移动 / 删除（复用同一套交互）。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/material_item.dart';
import '../store/material_store.dart';
import '../utils/sort_option.dart';
import 'player_page.dart';

class FolderContentPage extends StatefulWidget {
  const FolderContentPage({super.key, required this.folderId, required this.folderName});

  final int folderId; // 要浏览的根文件夹 id
  final String folderName; // 文件夹名（列表页已传进来）

  @override
  State<FolderContentPage> createState() => _FolderContentPageState();
}

class _FolderContentPageState extends State<FolderContentPage> {
  // 当前排序方式（默认「导入顺序」）。只是展示层状态，不写回数据库。
  SortOption _sortOption = SortOption.importOrder;

  @override
  Widget build(BuildContext context) {
    final MaterialStore store = context.watch<MaterialStore>();
    // 只筛出「属于这个文件夹」的素材，再按用户选的排序方式排一遍
    final List<MaterialItem> items = sortMaterials(
      store.items.where((m) => m.folderId == widget.folderId).toList(),
      _sortOption,
    );

    return Scaffold(
      // 标题 = 文件夹名 + 素材数量，如「高级班音频 · 12」
      appBar: AppBar(
        title: Text('${widget.folderName} · ${items.length}'),
        actions: <Widget>[
          // 排序入口：和主列表页共用同一套排序逻辑与菜单样式
          PopupMenuButton<SortOption>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            initialValue: _sortOption,
            onSelected: (SortOption opt) {
              setState(() => _sortOption = opt);
            },
            // 自定义菜单项（主题蓝勾 + 图标），和主列表页同款
            itemBuilder: (BuildContext context) {
              final Color primary = Theme.of(context).colorScheme.primary;
              return SortOption.values.map((SortOption opt) {
                final bool selected = opt == _sortOption;
                return PopupMenuItem<SortOption>(
                  value: opt,
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 28,
                        child: selected
                            ? Icon(Icons.check, size: 20, color: primary)
                            : null,
                      ),
                      Icon(opt.icon, size: 20,
                          color: selected ? primary : Colors.black45),
                      const SizedBox(width: 10),
                      Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? primary : const Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: items.isEmpty
          ? _buildEmpty(context)
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (BuildContext context, int index) {
                final MaterialItem item = items[index];
                return _buildItem(context, store, item);
              },
            ),
    );
  }

  /// 单条素材卡片：点进播放页、长按出操作菜单
  Widget _buildItem(BuildContext context, MaterialStore store, MaterialItem item) {
    final bool isVideo =
        item.format == 'mp4' || item.format == 'mov' || item.format == 'webm';
    return Card(
      child: ListTile(
        leading: _mediaBadge(context, isVideo),
        title: Text(item.title),
        subtitle: Text(
          _subtitle(item),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        trailing: const Icon(Icons.chevron_right),
        // 长按：弹出操作菜单（重命名 / 移动 / 删除）
        onLongPress: () => _showItemMenu(context, store, item),
        onTap: () {
          // 点进播放页（和列表页一致）
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlayerPage(item: item, folderName: widget.folderName),
            ),
          );
        },
      ),
    );
  }

  /// 素材类型徽章：圆角彩色底 + 白图标（和列表页保持一致）
  Widget _mediaBadge(BuildContext context, bool isVideo) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isVideo ? Icons.movie_outlined : Icons.audiotrack,
        color: Colors.white,
        size: 22,
      ),
    );
  }

  /// 拼副标题：只拼非空段，避免时长为空时出现孤立「·」
  String _subtitle(MaterialItem item) {
    final List<String> parts = <String>[
      item.format.toUpperCase(),
      if (item.duration.isNotEmpty) item.duration,
    ];
    return parts.join(' · ');
  }

  /// 空状态：这个文件夹还没有素材
  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.folder_open, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('这个文件夹还是空的', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('回列表页导入素材，或把素材移动到这里。', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
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
    if (action == null) return; // 点了空白处取消

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

  /// 重命名素材：弹输入框（预填当前名），走 store.renameMaterial（含后缀保护）
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

  /// 移动素材：弹「其他根文件夹」单选列表（不含当前、不含子文件夹）
  Future<void> _promptMove(BuildContext context, MaterialStore store, MaterialItem item) async {
    // 目标 = 除当前文件夹外的所有根文件夹
    final List<Folder> targets =
        store.folders.where((f) => f.id != item.folderId).toList();
    if (targets.isEmpty) {
      _showTip(context, '没有其他文件夹可移动，先去「文件夹管理」新建一个。');
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

  void _showTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失败：$e'), backgroundColor: Colors.red),
    );
  }
}
