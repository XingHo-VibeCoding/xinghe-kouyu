// 页面 2「文件夹管理」：壳界面
// 当前阶段只展示文件夹树的样子（假数据）+ 占位按钮；
// 真实的新建 / 重命名 / 删除 / 移动等操作，等接入本地数据库（sqflite）后再做

import 'package:flutter/material.dart';

class FolderManagePage extends StatelessWidget {
  const FolderManagePage({super.key});

  // 演示用的文件夹树（假数据）：分布对齐素材列表页的假数据
  // 每项是（文件夹名, 素材数）的记录（record）
  static const List<(String, int)> _folders = <(String, int)>[
    ('全部素材', 10),
    ('基础口语', 2),
    ('场景对话', 2),
    ('职场英语', 2),
    ('发音练习', 2),
    ('泛听', 2),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar 自带的返回箭头就是「返回上一页」（Navigator.pop），顺带完成余力加练
      appBar: AppBar(title: const Text('文件夹管理')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _folders.length,
        itemBuilder: (BuildContext context, int index) {
          final (String name, int count) = _folders[index];
          return Card(
            child: ListTile(
              leading: Icon(
                index == 0 ? Icons.folder_special_outlined : Icons.folder_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(name),
              trailing: Text('$count 个'),
              onTap: () => _showDemoTip(context, '演示版：打开文件夹将在接入本地数据库后开放'),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDemoTip(context, '演示版：真实的新建文件夹将在接入本地数据库后开放'),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新建文件夹'),
      ),
    );
  }

  /// 演示阶段的占位提示：诚实地告诉用户这个功能还没接入
  void _showDemoTip(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
