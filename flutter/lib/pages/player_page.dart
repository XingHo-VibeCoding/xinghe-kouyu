// 页面 3「播放页」：壳界面
// 从素材列表点某条素材进入；当前阶段不接真实播放器（just_audio / video_player 后续接入）。
// 按钮只做外观演示：播放/暂停会切换图标，其余按钮点了弹「演示版」提示

import 'package:flutter/material.dart';

import '../models/material_item.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, required this.folderName});

  final MaterialItem item; // 从素材列表传进来的那条素材
  final String folderName; // 该素材所属文件夹的名字（列表页已查好传进来）

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // 仅用于切换播放/暂停图标的外观，不代表真的在发声
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final MaterialItem item = widget.item;
    final bool isVideo =
        item.format == 'mp4' || item.format == 'mov' || item.format == 'webm';

    return Scaffold(
      // 自带返回箭头 = 返回上一页（回到素材列表）
      appBar: AppBar(title: Text(item.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 24),
            // 大图标：音频用音符，视频用影片
            Icon(
              isVideo ? Icons.movie_outlined : Icons.audiotrack,
              size: 96,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              item.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.folderName} · ${item.format.toUpperCase()} · ${item.duration}',
              style: const TextStyle(color: Colors.black54),
            ),
            const Spacer(),
            // 进度条（占位）：真实进度与拖动要等播放器接入
            const Slider(value: 0, onChanged: null),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('0:00.0', style: TextStyle(color: Colors.black54, fontSize: 12)),
                Text(item.duration, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            // 主控制行：快退 / 播放暂停 / 快进
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  iconSize: 40,
                  onPressed: () => _showDemoTip(context, '演示版：快退 5 秒将在接入播放器后开放'),
                  icon: const Icon(Icons.fast_rewind),
                ),
                IconButton(
                  iconSize: 64,
                  onPressed: () => setState(() => _playing = !_playing), // 仅切图标外观
                  icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle),
                ),
                IconButton(
                  iconSize: 40,
                  onPressed: () => _showDemoTip(context, '演示版：快进 5 秒将在接入播放器后开放'),
                  icon: const Icon(Icons.fast_forward),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 复读功能行（占位）：变速 / 循环 / AB 复读
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: <Widget>[
                ActionChip(
                  label: const Text('1.0x'),
                  onPressed: () => _showDemoTip(context, '演示版：变速将在接入播放器后开放'),
                ),
                ActionChip(
                  label: const Text('🔁 循环'),
                  onPressed: () => _showDemoTip(context, '演示版：单集循环将在接入播放器后开放'),
                ),
                ActionChip(
                  label: const Text('A'),
                  onPressed: () => _showDemoTip(context, '演示版：AB 复读将在接入播放器后开放'),
                ),
                ActionChip(
                  label: const Text('B'),
                  onPressed: () => _showDemoTip(context, '演示版：AB 复读将在接入播放器后开放'),
                ),
                ActionChip(
                  label: const Text('↺ 重置'),
                  onPressed: () => _showDemoTip(context, '演示版：重置将在接入播放器后开放'),
                ),
              ],
            ),
            const SizedBox(height: 24),
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
