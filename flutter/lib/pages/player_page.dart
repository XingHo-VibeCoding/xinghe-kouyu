// =====================================================================
// 页面 3「播放页」：真正接入播放器（音频 just_audio / 视频 video_player）
// ---------------------------------------------------------------------
// 从素材列表点某条素材进入。根据素材格式分两条路：
//   音频（mp3/m4a/wav/aac 等）→ just_audio 播放；
//   视频（mp4/mov/webm/m4v 等）→ video_player 播放，页面内显示画面。
// 两者共用同一套控制逻辑：播放/暂停、快进快退 5 秒、变速 0.5–2.0x、
// 进度条联动。AB 复读和播放位置记忆在板块④接入。
//
// 语言：Dart（纯本地播放，无后端）。
// =====================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../models/material_item.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, required this.folderName});

  final MaterialItem item; // 从素材列表传进来的那条素材
  final String folderName; // 该素材所属文件夹的名字（列表页已查好传进来）

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with SingleTickerProviderStateMixin {
  // ---- 播放器实例（二选一，视素材是音频还是视频）----
  AudioPlayer? _audio; // 音频播放器（just_audio）
  VideoPlayerController? _video; // 视频播放器（video_player）

  // ---- 播放状态 ----
  bool _playing = false; // 是否正在播放
  double _speed = 1.0; // 当前倍速（0.5 / 0.75 / 1.0 / 1.25 / 1.5 / 2.0）
  double _position = 0; // 当前播放位置（秒）
  double _duration = 0; // 总时长（秒）

  // ---- 唱片旋转动画（音频模式的中部视觉，播放时转、暂停时停）----
  AnimationController? _spinCtrl; // 0→1 无限循环，唱片角度由它驱动

  // 可选倍速档位（对照 PRD F4：0.5–2.0 倍）
  static const List<double> _rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// 这条素材是视频吗
  bool get _isVideo {
    const Set<String> videoFmt = <String>{'mp4', 'mov', 'webm', 'm4v'};
    return videoFmt.contains(widget.item.format);
  }

  @override
  void initState() {
    super.initState();
    // 旋转控制器：repeat() 无限循环（0→1 反复），一圈 8 秒。
    // 唱片角度直接读 controller.value * 一整圈弧度，暂停就 stop()、恢复就 repeat()，
    // 不需要手动累加角度（那种写法暂停恢复时会跳变，且 lastElapsedDuration 可能为 null）。
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8), // 一圈 8 秒，慢速优雅
    );
    _initPlayer();
  }

  /// 初始化播放器：按素材格式选音频或视频，并设置数据源
  Future<void> _initPlayer() async {
    try {
      if (_isVideo) {
        // —— 视频：用 video_player，数据源是本地文件路径 ——
        final VideoPlayerController vc =
            VideoPlayerController.file(File(widget.item.filePath));
        _video = vc;
        await vc.initialize();
        _duration = vc.value.duration.inMilliseconds / 1000.0;
        vc.addListener(_onVideoTick); // 监听视频播放位置变化
        if (mounted) setState(() {});
      } else {
        // —— 音频：用 just_audio，数据源是本地文件 ——
        final AudioPlayer ap = AudioPlayer();
        _audio = ap;
        await ap.setFilePath(widget.item.filePath);
        _duration = ap.duration?.inMilliseconds.toDouble() ?? 0 / 1000.0;
        if (ap.duration != null) {
          _duration = ap.duration!.inMilliseconds / 1000.0;
        }
        // 用 just_audio 自带的流驱动状态（比手动 setState 更可靠）：
        //   positionStream —— 播放时高频推送当前位置（秒），进度条靠它动；
        //   playingStream  —— 播放/暂停状态一变就推，图标靠它切。
        ap.positionStream.listen((Duration pos) {
          if (!mounted) return;
          setState(() => _position = pos.inMilliseconds / 1000.0);
        });
        ap.playingStream.listen((bool playing) {
          if (!mounted) return;
          if (_playing != playing) {
            setState(() => _playing = playing);
            _syncSpin(playing);
          }
        });
        // 播放完成：图标复位、旋转停（AB 复读板块会在这里接「跳回 A」）
        ap.processingStateStream.listen((ProcessingState s) {
          if (s == ProcessingState.completed && mounted) {
            setState(() => _playing = false);
            _syncSpin(false);
          }
        });
        if (mounted) setState(() {});
      }
    } catch (e) {
      // 初始化失败（文件缺失、格式不支持等）：弹提示，不崩溃
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放器初始化失败：$e')),
        );
      }
    }
  }

  /// 视频的监听：把播放位置 + 播放状态同步到页面状态
  void _onVideoTick() {
    if (_video == null) return;
    final double pos = _video!.value.position.inMilliseconds / 1000.0;
    // 同步播放状态：图标跟着真实 isPlaying 走（不靠手动切换）
    final bool isPlaying = _video!.value.isPlaying;
    if (mounted) {
      setState(() {
        _position = pos;
        if (_playing != isPlaying) {
          _playing = isPlaying;
          _syncSpin(isPlaying);
        }
      });
    }
    // 视频播放结束自动复位（图标由上面的 isPlaying 同步自动切回播放态）
    if (_video!.value.isCompleted) {
      if (mounted && _playing) {
        setState(() => _playing = false);
        _syncSpin(false);
      }
    }
  }

  /// 同步旋转动画：播放中 → 无限循环旋转，暂停/停止 → 停在当前角度
  void _syncSpin(bool playing) {
    if (_spinCtrl == null) return;
    if (playing) {
      if (!_spinCtrl!.isAnimating) _spinCtrl!.repeat();
    } else {
      _spinCtrl!.stop();
    }
  }

  /// 播放 / 暂停（音频视频通用）
  /// 只负责「触发播放器的播放/暂停」，图标和进度的变化交给上面的流去同步，
  /// 这样无论从哪个入口触发，界面都跟着真实状态走，不会卡住。
  Future<void> _togglePlay() async {
    if (_isVideo) {
      if (_video == null) return;
      if (_video!.value.isPlaying) {
        await _video!.pause();
      } else {
        await _video!.play();
      }
    } else {
      if (_audio == null) return;
      if (_audio!.playing) {
        await _audio!.pause();
      } else {
        await _audio!.play();
      }
    }
  }

  /// 快进 / 快退：相对当前位置跳 5 秒（PRD F3 单次 5 秒）
  Future<void> _seekBy(double delta) async {
    final double target = (_position + delta).clamp(0, _duration);
    await _seekTo(target);
  }

  /// 跳转到指定位置（秒）
  Future<void> _seekTo(double seconds) async {
    if (_isVideo) {
      await _video?.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    } else {
      await _audio?.seek(Duration(milliseconds: (seconds * 1000).round()));
    }
    if (mounted) setState(() => _position = seconds);
  }

  /// 变速：切到下一档倍速（PRD F4）
  Future<void> _cycleSpeed() async {
    final int idx = _rates.indexOf(_speed);
    final double next = _rates[(idx + 1) % _rates.length];
    if (_isVideo) {
      await _video?.setPlaybackSpeed(next);
    } else {
      await _audio?.setSpeed(next);
    }
    if (mounted) setState(() => _speed = next);
  }

  // ---- 定时器已废弃：音频进度改用 positionStream、视频用 addListener，
  //      不再需要手动定时刷新（避免「第一次点播放不动」的时序 bug）。----

  @override
  void dispose() {
    _spinCtrl?.dispose();
    _audio?.dispose();
    _video?.dispose();
    super.dispose();
  }

  /// 格式化时间：把秒数转成 mm:ss
  String _fmt(double seconds) {
    final int m = seconds ~/ 60;
    final int s = (seconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final MaterialItem item = widget.item;

    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 12),

            // ---- 视频画面区 / 音频唱片区 ----
            if (_isVideo)
              _buildVideoArea()
            else
              _buildDisc(),

            const SizedBox(height: 16),
            Text(
              item.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.folderName} · ${item.format.toUpperCase()}',
              // 副标题是「信息」不是「按钮」，用中性灰，不再用主题蓝
              style: const TextStyle(color: Colors.black54),
            ),
            // 视频页：在标题下方放一条静态波形，和音频页的唱片形成「转盘/波形」呼应，
            // 同时填掉标题到进度条之间的空洞（视频画面已经当主角，不再叠唱片）
            if (_isVideo) ...<Widget>[
              const SizedBox(height: 20),
              _buildWaveform(),
            ],
            const Spacer(),

            // ---- 进度条（可拖动，真实联动；拖动按 0.1 秒刻度吸附）----
            // 已播段用「淡黄」点缀，滑块与主色系（淡蓝）区分开
            Slider(
              value: _position.clamp(0, _duration == 0 ? 1 : _duration),
              max: _duration == 0 ? 1 : _duration,
              activeColor: const Color(0xFFF2C94C), // 淡黄：已播放进度段
              onChanged: (double v) {
                // 吸附到 0.1 秒的整数倍（如 12.34 → 12.3）
                final double snapped = (v * 10).round() / 10.0;
                _seekTo(snapped);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // 等宽数字：播放时数字不会左右跳动
                Text(_fmt(_position),
                    style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
                Text(_fmt(_duration),
                    style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 8),

            // ---- 主控制行：快退 / 播放暂停 / 快进 ----
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  iconSize: 40,
                  onPressed: () => _seekBy(-5),
                  icon: Icon(Icons.fast_rewind,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 16),
                // 播放大按钮：淡蓝实心圆钮，是整个播放页最核心的操作，
                // 用主色实心 + 白色图标，和主题统一（不再是默认的灰）
                Material(
                  color: Theme.of(context).colorScheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _togglePlay,
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(
                        _playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 40,
                  onPressed: () => _seekBy(5),
                  icon: Icon(Icons.fast_forward,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ---- 变速 + 复读功能区 ----
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: <Widget>[
                // 变速：点一下切下一档，非 1.0x 时淡黄底提示「已变速」
                ActionChip(
                  label: Text('${_speed}x'),
                  backgroundColor: _speed != 1.0 ? const Color(0xFFF7E8B0) : null,
                  onPressed: _cycleSpeed,
                ),
                // 循环：用 repeat 图标，不用 emoji（emoji 在不同系统渲染差异大，且配色不统一）
                ActionChip(
                  avatar: Icon(Icons.repeat, size: 18, color: Theme.of(context).colorScheme.primary),
                  label: const Text('循环'),
                  onPressed: () => _showTip('单集循环将在板块④接入'),
                ),
                // A/B 打点：用图标表示，激活后淡黄底（板块④接入后真正生效）
                ActionChip(
                  avatar: Icon(Icons.keyboard_arrow_up, size: 18, color: Theme.of(context).colorScheme.primary),
                  label: const Text('A'),
                  onPressed: () => _showTip('AB 复读将在板块④接入'),
                ),
                ActionChip(
                  avatar: Icon(Icons.keyboard_arrow_down, size: 18, color: Theme.of(context).colorScheme.primary),
                  label: const Text('B'),
                  onPressed: () => _showTip('AB 复读将在板块④接入'),
                ),
                ActionChip(
                  avatar: Icon(Icons.restart_alt, size: 18, color: Theme.of(context).colorScheme.primary),
                  label: const Text('重置'),
                  onPressed: () => _showTip('重置将在板块④接入'),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 音频模式：旋转唱片视觉（播放时转、暂停时停），
  /// 填补播放页中部原本的空洞，同时成为「这是个播放器」的记忆点。
  Widget _buildDisc() {
    final Color primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 唱片盘面：主色淡蓝，带柔和的同心圆纹理。
          // AnimatedBuilder 监听旋转控制器：value 0→1 循环，映射成一整圈 2π 弧度。
          // 只有这个子树随动画重建，中心标签等其余部分不受影响。
          AnimatedBuilder(
            animation: _spinCtrl!,
            builder: (BuildContext context, Widget? child) {
              return Transform.rotate(
                angle: _spinCtrl!.value * 2 * 3.14159,
                child: child,
              );
            },
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    primary.withValues(alpha: 0.98),
                    primary.withValues(alpha: 0.6),
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                // 多圈同心圆纹路，模拟黑胶唱片的沟槽（比单圈细线更有「唱片」的质感）
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 105,
                      height: 105,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 中心标签：米色小圆盘 + 音符，旋转时不转（固定），更有层次
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFAF6EF),
              // 一圈高光描边，让中心标签从盘面上「浮」起来
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.music_note, color: primary, size: 28),
          ),
        ],
      ),
    );
  }

  /// 视频页：静态波形装饰（缩小版「声音」隐喻）。
  /// 用一排高低错落的圆角竖条模拟音波，中间几根高、两侧低，形成自然起伏。
  /// 和音频页的「旋转唱片」形成呼应（转盘 / 波形），但不抢视频画面的主角地位。
  Widget _buildWaveform() {
    final Color primary = Theme.of(context).colorScheme.primary;
    // 24 根竖条的高度（0~1 之间的相对值），近似一条平滑的音波
    const List<double> heights = <double>[
      0.3, 0.5, 0.7, 0.55, 0.35, 0.6, 0.9, 0.75, 0.5, 0.4, 0.65, 1.0,
      0.8, 0.5, 0.35, 0.7, 0.95, 0.6, 0.4, 0.55, 0.8, 0.65, 0.45, 0.3,
    ];
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: heights.map((double h) {
          return Container(
            width: 3,
            height: 36 * h,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 视频模式：显示视频画面（页面内，16:9 黑底容器）
  Widget _buildVideoArea() {
    final VideoPlayerController? vc = _video;
    if (vc == null || !vc.value.isInitialized) {
      // 还没初始化好：显示加载占位
      return Container(
        height: 220,
        width: double.infinity,
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.white),
      );
    }
    return AspectRatio(
      aspectRatio: vc.value.aspectRatio,
      child: VideoPlayer(vc),
    );
  }

  /// 占位提示：板块④未接入的功能
  void _showTip(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
