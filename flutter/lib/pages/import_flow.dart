// =====================================================================
// 「导入素材」流程（共用逻辑，不是页面）
// ---------------------------------------------------------------------
// 为什么单独拎出来：现在有三个地方能发起导入——
//   ① 素材列表页的「＋」按钮（要先问放进哪个文件夹）
//   ② 文件夹管理页的「导入」按钮（同样要先问）
//   ③ 文件夹内容页的「导入到此文件夹」（目标已知，不用问）
// 三处如果各写一遍，就会出现「列表页导 3 个、别处只导 1 个」这种走样。
// 所以这里只放流程编排，真正的复制+写库仍在 MaterialStore.importMaterials。
// =====================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store/material_store.dart';
import '../utils/design_tokens.dart';

/// 目标文件夹已知：直接弹系统文件选择器 → 整批导入 → 出汇总提示。
/// 用于「文件夹内容页」这类已经明确知道导到哪儿的地方。
Future<void> importIntoFolder(
  BuildContext context, {
  required int folderId,
  required String folderName,
}) async {
  final MaterialStore store = context.read<MaterialStore>();
  try {
    final ImportResult? result = await store.importMaterials(folderId);
    if (!context.mounted) return; // 等待期间页面可能已被销毁，别对已卸载的 context 动手
    if (result == null) {
      _tip(context, '已取消导入');
      return;
    }
    _tip(context, _withFailures(result.summary(folderName), result.failures));
  } catch (e) {
    if (!context.mounted) return;
    _tip(context, '导入失败：$e');
  }
}

/// 目标文件夹未知：先弹窗让用户选一个（里面可顺手新建），再走导入。
/// 用于「素材列表页」「文件夹管理页」。
Future<void> importWithFolderPicker(BuildContext context) async {
  final MaterialStore store = context.read<MaterialStore>();

  // 一个文件夹都没有时，先引导新建——否则素材没有归属，导入无从谈起
  if (store.folders.isEmpty) {
    final bool created = await _createFolderInline(context, store);
    if (!created) return;
    if (!context.mounted) return;
  }

  // 用 AlertDialog 弹一个单选列表（带「取消」+「新建文件夹」）。
  // 返回类型用 Object：既可能是选中的 Folder，也可能是「新建文件夹」哨兵。
  final Object? target = await showDialog<Object>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('导入到哪个文件夹？'),
        contentPadding: const EdgeInsets.symmetric(vertical: kSpaceXS),
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
                  onTap: () => Navigator.pop(dialogContext, f),
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
              // 建好了：关掉弹窗并让调用方重新弹一次，好让新文件夹出现在列表里
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

  if (target == null) return; // 点取消或点弹窗外面

  // 点的是「新建文件夹」：重新来一遍（新文件夹已在 store.folders 里）
  if (target is _FolderCreateSentinel) {
    if (!context.mounted) return;
    await importWithFolderPicker(context);
    return;
  }

  final Folder chosen = target as Folder;
  if (!context.mounted) return;
  await importIntoFolder(context, folderId: chosen.id, folderName: chosen.name);
}

/// 就地新建文件夹：弹输入框 → 调 store.addFolder → 返回是否成功。
/// 成功返回 true；取消或名字为空返回 false。出错时提示并返回 false。
Future<bool> _createFolderInline(BuildContext context, MaterialStore store) async {
  final String? name = await _askFolderName(context);
  if (name == null || name.trim().isEmpty) return false;
  try {
    await store.addFolder(name.trim());
    return true;
  } catch (e) {
    if (context.mounted) _tip(context, '新建文件夹失败：$e');
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

/// 汇总文案 + 失败明细（最多列 3 条，够定位问题又不刷屏）
String _withFailures(String summary, List<String> failures) {
  if (failures.isEmpty) return summary;
  final Iterable<String> head = failures.take(3);
  final String more = failures.length > 3 ? '\n…另有 ${failures.length - 3} 个' : '';
  return '$summary\n${head.join('\n')}$more';
}

/// 轻提示（一行 SnackBar）
void _tip(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 哨兵：标记「用户在文件夹选择弹窗里点了『新建文件夹』」
class _FolderCreateSentinel {}
