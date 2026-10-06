// =====================================================================
// 页面 2「文件夹管理」（界面层）
// ---------------------------------------------------------------------
// 这层是什么：负责「画界面 + 响应用户操作」。它不写 SQL，也不直接碰数据库，
// 而是调用数据层（MaterialStore）里封装好的方法，由 store 转发给存储层。
//
// 语言：Dart（星禾口语整个 App 都是 Dart，没有前后端之分。
//       这里的「接口」= 界面层调用 MaterialStore 的方法，
//       MaterialStore 再调 DatabaseHelper 去读写 SQLite）。
//
// 本页实现的真实功能：新建文件夹 / 重命名 / 删除，全部落到 SQLite。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/material_store.dart';
import 'folder_content_page.dart';

class FolderManagePage extends StatelessWidget {
  const FolderManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    // watch：订阅素材仓库。文件夹列表一变（增删改后 store 会 notifyListeners），
    // 这一页自动重新构建，界面立即刷新
    final MaterialStore store = context.watch<MaterialStore>();
    final List<Folder> folders = store.folders;

    return Scaffold(
      // AppBar 自带的返回箭头就是「返回上一页」（Navigator.pop）
      appBar: AppBar(title: const Text('文件夹管理')),
      // 空文件夹时给个提示，否则显示文件夹列表
      body: folders.isEmpty
          ? _buildEmpty(context)
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: folders.length,
              itemBuilder: (BuildContext context, int index) {
                final Folder folder = folders[index];
                // 每个文件夹显示「它下面有多少条素材」
                final int count = store.items
                    .where((m) => m.folderId == folder.id)
                    .length;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.folder_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(folder.name),
                    // 点卡片本体 → 进入「文件夹内容浏览页」（F9，返回式进出）
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FolderContentPage(
                            folderId: folder.id,
                            folderName: folder.name,
                          ),
                        ),
                      );
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('$count 个', style: const TextStyle(color: Colors.black54)),
                        // 重命名按钮（铅笔图标）
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: '重命名',
                          onPressed: () => _promptRename(context, store, folder),
                        ),
                        // 删除按钮（垃圾桶图标）：红色警示 + 与编辑按钮拉开间距，防误触
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          tooltip: '删除',
                          onPressed: () => _confirmDelete(context, store, folder),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      // 右下角「新建文件夹」按钮
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptCreate(context, store),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新建文件夹'),
      ),
    );
  }

  /// 空状态：还没有任何文件夹时提示
  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.folder_off_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('还没有文件夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('点右下角「新建文件夹」开始整理素材。', style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }

  /// 新建文件夹：弹一个输入框，用户输入名字后调用 store.addFolder
  Future<void> _promptCreate(BuildContext context, MaterialStore store) async {
    final String? name = await _askName(context, '新建文件夹', '');
    if (name == null || name.trim().isEmpty) return; // 取消或空名则不做任何事
    try {
      await store.addFolder(name.trim()); // 调数据层：插入 SQLite 并刷新
    } catch (e) {
      _showError(context, e); // 失败时把真实错误弹出来，方便定位
    }
  }

  /// 重命名：弹输入框（预填旧名），确认后调用 store.renameFolder
  Future<void> _promptRename(
      BuildContext context, MaterialStore store, Folder folder) async {
    final String? name = await _askName(context, '重命名文件夹', folder.name);
    if (name == null || name.trim().isEmpty) return;
    try {
      await store.renameFolder(folder.id, name.trim());
    } catch (e) {
      _showError(context, e);
    }
  }

  /// 删除：先弹确认框（防手滑误删），确认后调用 store.deleteFolder
  Future<void> _confirmDelete(
      BuildContext context, MaterialStore store, Folder folder) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删除「${folder.name}」？'),
        content: const Text('该文件夹下的素材也会一并删除，且不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await store.deleteFolder(folder.id); // 调数据层：删 SQLite 记录并刷新
      } catch (e) {
        _showError(context, e);
      }
    }
  }

  /// 弹出操作失败的提示（带真实错误信息，方便定位问题）
  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('操作失败：$e'), backgroundColor: Colors.red),
    );
  }

  /// 通用输入框：返回用户输入的文字（取消返回 null）
  Future<String?> _askName(
      BuildContext context, String title, String initial) async {
    final TextEditingController controller = TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true, // 弹出来光标自动聚焦，直接打字
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
