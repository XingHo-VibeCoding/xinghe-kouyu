// 页面 1「素材列表」：App 首页，也是四种状态的主展示页
// 四种状态：加载中（骨架屏）/ 空 / 出错 / 正常有数据
// 底部「状态预览条」是开发用的临时工具，方便逐个状态截图，上线前会删掉

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/material_item.dart';
import '../store/material_store.dart';
import 'folder_manage_page.dart';
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
        ListStatus.data => _buildList(context, store.items),
      },
      // 开发用状态预览条（临时，上线前删）
      bottomNavigationBar: _buildDevStateBar(store),
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
            onPressed: () => _showDemoTip(context, '演示版：真实导入将在接入文件选择器后开放'),
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
  Widget _buildList(BuildContext context, List<MaterialItem> items) {
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
            subtitle: Text('${item.folder} · ${item.format.toUpperCase()} · ${item.duration}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // 入口 2：进「播放页」，把点中的素材传过去
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PlayerPage(item: item)),
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
}

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
