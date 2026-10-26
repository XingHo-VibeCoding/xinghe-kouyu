// =====================================================================
// 页面 3「播放页」：真正接入播放器（音频 just_audio / 视频 video_player）
// ---------------------------------------------------------------------
// 从素材列表点某条素材进入。根据素材格式分两条路：
//   音频（mp3/m4a/wav/aac 等）→ just_audio 播放；
//   视频（mp4/mov/webm/m4v 等）→ video_player 播放，页面内显示画面。
// 两者共用同一套控制逻辑：播放/暂停、快进快退 5 秒、变速 0.5–2.0x、
// 进度条联动、AB 复读（A/B/重置 + 区间循环 + 色带）。
// 单集循环、播放位置记忆（last_position）留后续板块接入。
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

  // ---- AB 复读状态（Day 19）----
  double? _pointA; // A 点时间（秒），null = 未设
  double? _pointB; // B 点时间（秒），null = 未设
  bool _dragging = false; // 是否正在拖进度条（拖动期间不抢播放头，方便拖到 AB 段外打新点）

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
          _checkAbLoop(); // AB 复读：播到 B 点自动跳回 A
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
    _checkAbLoop(); // AB 复读：播到 B 点自动跳回 A（在 setState 之后，跳转动作安全）
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
        _checkAbOnPlay(); // 若播放头在 AB 段外，送回 A 点
      }
    } else {
      if (_audio == null) return;
      if (_audio!.playing) {
        await _audio!.pause();
      } else {
        await _audio!.play();
        _checkAbOnPlay(); // 若播放头在 AB 段外，送回 A 点
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

  // ===== AB 复读（Day 19）=====

  /// 打 A 点：在当前播放位置设起点，支持反复点微调。
  /// 规则：A 必须落在 B 左边（若已打 B，且当前位置 ≥ B-0.5s，视为无效）。
  void _onSetA() {
    if (_pointB != null && _position >= _pointB! - 0.5) {
      _showTip('A 点必须在 B 点左边。先把进度条拖到 B 之前，再点 A。');
      return;
    }
    setState(() => _pointA = _position);
  }

  /// 打 B 点：在当前播放位置设终点，从此 A↔B 循环自动开始。
  /// 规则：必须先有 A；B 必须落在 A 右边（当前位置 ≤ A+0.5s 视为无效）。
  void _onSetB() {
    if (_pointA == null) {
      _showTip('请先打 A 点（起点），再打 B 点。');
      return;
    }
    if (_position <= _pointA! + 0.5) {
      _showTip('B 点必须在 A 点右边。先把进度条拖到 A 之后，再点 B。');
      return;
    }
    setState(() => _pointB = _position);
  }

  /// 重置 AB 点：清掉 A、B，退出复读，恢复正常播放（当前位置不动）。
  void _onAbReset() {
    setState(() {
      _pointA = null;
      _pointB = null;
    });
  }

  /// AB 循环核心：播放位置超过 B 点就跳回 A 点。
  /// 调用时机：音频在 positionStream、视频在 _onVideoTick 里，每次位置更新都检查一次。
  /// 例外：正拖进度条时不抢播放头（让用户能把播放头拖到 AB 段外去打新点）。
  void _checkAbLoop() {
    if (_dragging) return; // 拖动中不抢
    if (_pointA == null || _pointB == null) return;
    if (_position >= _pointB!) {
      _seekTo(_pointA!); // 跳回 A，继续循环
    }
  }

  /// 播放时兜底：如果播放头在 AB 段之外（已过 B 或还没到 A），送回 A 点恢复正常复读。
  void _checkAbOnPlay() {
    if (_pointA == null || _pointB == null) return;
    if (_position >= _pointB! || _position < _pointA!) {
      _seekTo(_pointA!);
    }
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

  /// 格式化时间到 0.1 秒：mm:ss.t（如 01:16.1）。
  /// 一心复读机的 AB 打点时间就是这么标的，精度到十分之一秒。
  String _fmtTenth(double seconds) {
    final int m = seconds ~/ 60;
    final int s = (seconds % 60).floor();
    final int t = ((seconds - seconds.floor()) * 10).round() % 10;
    return '$m:${s.toString().padLeft(2, '0')}.$t';
  }

  @override
  Widget build(BuildContext context) {
    final MaterialItem item = widget.item;

    return Scaffold(
      // AppBar 只留返回键，不重复显示标题（标题已在页面中部大标题展示，避免信息重复）
      appBar: AppBar(),
      body: Padding(
        // 左右内边距归零，让进度条从屏幕最左铺到最右；上下各留 24 保持呼吸感
        padding: const EdgeInsets.symmetric(vertical: 24),
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
              // 副标题是「信息」不是「按钮」，用深一档的中性灰，保证对比度（之前 black54 偏浅）
              style: const TextStyle(color: Colors.black87),
            ),
            // 视频页：在标题下方放一条静态波形，和音频页的唱片形成「转盘/波形」呼应，
            // 同时填掉标题到进度条之间的空洞（视频画面已经当主角，不再叠唱片）
            if (_isVideo) ...<Widget>[
              const SizedBox(height: 20),
              _buildWaveform(),
            ],
            const Spacer(),

            // ---- 进度时间轴（模仿一心复读机）----
            // 固定高度的三层结构：上排 A/B 字母 → 中间细轨道（播放头小圆点 +
            // AB 小圆点）→ 下排时间（当前时间 | AB 时间按位置分布 | 总时长）。
            // 轨道跟随父级宽度（body 已把左右内边距归零，轨道自然铺到屏幕最边）。
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return _buildTimeline(constraints.maxWidth);
              },
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
                      color: const Color(0xFF5B8FC9)),
                ),
                const SizedBox(width: 16),
                // 播放大按钮：蓝色实心圆钮，是整个播放页最核心的操作，
                // 用蓝色 + 白色图标（主色虽是绿，但播放键特意保留蓝色作视觉重心）
                Material(
                  color: const Color(0xFF5B8FC9),
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
                      color: const Color(0xFF5B8FC9)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ---- 复读功能区（第一行）：A / B / 重置 ----
            // chip 只显示字母不显示时间（时间已在进度条上展示），激活时变金色即可。
            ChipTheme(
              data: ChipTheme.of(context).copyWith(
                side: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // A 打点：未打点白底灰字，已打点金底（时间看进度条上的 A 标注）
                  ActionChip(
                    avatar: Icon(Icons.keyboard_arrow_up, size: 18,
                        color: _pointA != null
                            ? const Color(0xFFE8A33D)
                            : Colors.black54),
                    label: const Text('A'),
                    backgroundColor:
                        _pointA != null ? const Color(0xFFF6E3C2) : null,
                    onPressed: _onSetA,
                  ),
                  const SizedBox(width: 12),
                  // B 打点：同 A 的规则
                  ActionChip(
                    avatar: Icon(Icons.keyboard_arrow_down, size: 18,
                        color: _pointB != null
                            ? const Color(0xFFE8A33D)
                            : Colors.black54),
                    label: const Text('B'),
                    backgroundColor:
                        _pointB != null ? const Color(0xFFF6E3C2) : null,
                    onPressed: _onSetB,
                  ),
                  const SizedBox(width: 12),
                  // 重置：有任一点被打就点亮成金色（提示「这里有东西可清」）
                  ActionChip(
                    avatar: Icon(Icons.restart_alt, size: 18,
                        color: (_pointA != null || _pointB != null)
                            ? const Color(0xFFE8A33D)
                            : Colors.black54),
                    label: const Text('重置'),
                    onPressed: _onAbReset,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ---- 播放控制区（第二行）：变速 / 循环 ----
            ChipTheme(
              data: ChipTheme.of(context).copyWith(
                side: BorderSide(color: Colors.black.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // 变速：点一下切下一档。非 1.0x 时蓝色底提示「已变速」（蓝=播放控制语义）。
                  ActionChip(
                    label: Text('${_speed}x'),
                    backgroundColor:
                        _speed != 1.0 ? const Color(0xFFD6E7F5) : null,
                    onPressed: _cycleSpeed,
                  ),
                  const SizedBox(width: 12),
                  // 循环：用 repeat 图标，不用 emoji（emoji 在不同系统渲染差异大，且配色不统一）
                  ActionChip(
                    avatar: Icon(Icons.repeat, size: 18, color: Colors.black54),
                    label: const Text('循环'),
                    onPressed: () => _showTip('单集循环将在后续板块接入'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 音频模式：旋转唱片视觉（播放时转、暂停时停），
  /// 填补播放页中部原本的空洞，同时成为「这是个播放器」的记忆点。
  /// 盘面用蓝色（和播放大按钮同色，作为播放器专属的视觉重心，区别于主色绿）。
  Widget _buildDisc() {
    final Color discBlue = const Color(0xFF5B8FC9); // 蓝色：唱片盘面
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
                  // 外深内浅：边缘饱和、中心略亮，让唱片看起来更「实」、更有体积感，
                  // 而不是从中心往外褪色发飘
                  colors: <Color>[
                    discBlue.withValues(alpha: 0.95),
                    discBlue,
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: discBlue.withValues(alpha: 0.45),
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
            child: Icon(Icons.music_note, color: const Color(0xFF5B8FC9), size: 28),
          ),
        ],
      ),
    );
  }

  /// 视频页：静态波形装饰（缩小版「声音」隐喻）。
  /// 用一排高低错落的圆角竖条模拟音波，中间几根高、两侧低，形成自然起伏。
  /// 和音频页的「旋转唱片」形成呼应（转盘 / 波形），但不抢视频画面的主角地位。
  /// 颜色用「蓝色」作点缀（主色是浅绿，蓝在这里退为次要），形成层次区分。
  Widget _buildWaveform() {
    final Color accentBlue = const Color(0xFF5B8FC9); // 蓝色：次要点缀色
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
              color: accentBlue.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 进度时间轴（模仿一心复读机）：固定高度的 Stack，三层结构——
  ///   上排：A / B 字母（金色小字，居中于断点）；AB 过近时此排让给 B 的时间；
  ///   中间：两端时间（当前/总时长，11px 小字贴最两边、与轨道同水平线）+
  ///         细轨道 Slider（左右各让出 52px 给两端时间）+ AB 金色小圆点；
  ///   下排：A / B 时间（金色，居中于断点）。
  /// AB 防挤规则：
  ///   · A 时间固定在轨道下方；B 时间默认也在下方；
  ///   · A/B 距离 < 64px 时，B 时间交错到轨道上方，同时隐藏字母（只交错显示时间）；
  ///   · 时间容器贴边时钳制在屏幕内，不溢出。
  Widget _buildTimeline(double trackW) {
    const double height = 64; // 时间轴总高
    // 轨道铺满整个宽度（不留空白区），两端时间贴最两边叠在轨道同一水平线上
    const double edgeW = 0;
    final double sliderLeft = edgeW;
    final double sliderW = trackW - edgeW * 2;

    // ★ 与 Flutter Slider 内部换算对齐（关键修正）：
    // RoundedRectSliderTrackShape.getPreferredRect 会把轨道左右各内缩
    // max(overlayWidth/2, thumbWidth/2) = max(14, 7) = 14px；
    // 播放头实际 x = 14 + value * (宽 - 28)。我们自己的 AB 点/字母/时间/
    // 色带必须用同一公式换算，否则越靠屏幕两端偏差越大（看起来像被拉伸）。
    const double trackInset = 14;
    // 时间分数(0~1) → 轨道上的像素 x（与 Slider 播放头完全同轨）
    double fracX(double frac) =>
        sliderLeft + trackInset + frac.clamp(0.0, 1.0) * (sliderW - trackInset * 2);

    // 断点的水平锚点（像素，相对整个 Stack）
    double? ax; // A 点
    double? bx; // B 点
    if (_pointA != null && _duration > 0) {
      ax = fracX(_pointA! / _duration);
    }
    if (_pointB != null && _duration > 0) {
      bx = fracX(_pointB! / _duration);
    }
    // 播放头当前位置的锚点（未设 B 时色带画到播放头）
    final double playX =
        fracX(_position / (_duration == 0 ? 1 : _duration));

    // AB 是否过近（< 64px）：过近时 B 时间交错到上排、隐藏字母
    final bool abClose = ax != null && bx != null && (bx! - ax!) < 64;

    const TextStyle timeStyle = TextStyle(
      color: Colors.black54,
      fontSize: 11,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );
    const TextStyle abTimeStyle = TextStyle(
      color: Color(0xFFE8A33D),
      fontSize: 11,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    // 时间容器水平钳制：44px 宽居中容器，不许溢出屏幕两边
    double clampedLeft(double x) => (x - 22).clamp(0.0, trackW - 44);

    // NaN/异常防护：宽度非有限或 <= 0 时（布局时序抖动的瞬间）不渲染，
    // 避免位置计算产生 NaN 引发 Matrix4 断言红屏
    if (!trackW.isFinite || trackW <= 0) {
      return const SizedBox(height: height);
    }

    return SizedBox(
      // width: infinity = 在有界约束下强制撑满父级宽度。
      // 关键修复：Stack 里全是 Positioned 子元素、没有普通子元素撑尺寸，
      // 重建瞬间可能塌缩成 0 宽（所有文字叠在一点、轨道消失），
      // 显式撑满后宽度永远稳定。
      width: double.infinity,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // ---- 上排：A / B 字母（居中于断点；AB 过近时隐藏，让位给 B 的时间）----
          if (ax != null && !abClose)
            Positioned(
              left: ax! - 12,
              top: 0,
              width: 24,
              child: const Text('A',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFE8A33D),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          if (bx != null && !abClose)
            Positioned(
              left: bx! - 12,
              top: 0,
              width: 24,
              child: const Text('B',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFE8A33D),
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),

          // ---- 中间：AB 色带 + 细轨道 Slider + AB 小圆点 + 两端时间 ----
          // 色带：A~B（或 A~当前播放位置）淡蓝底，垂直居中在轨道线上
          if (ax != null) _buildAbBand(ax!, bx ?? playX),
          // 细轨道 Slider：左右各让出 edgeW 给两端时间（轨道中线 y=32）
          Positioned(
            left: sliderLeft,
            right: edgeW,
            top: 12,
            bottom: 12,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: const Color(0xFF4A7EB8),
                inactiveTrackColor: const Color(0xFF5B8FC9).withValues(alpha: 0.18),
                thumbColor: const Color(0xFF4A7EB8),
                thumbShape: const _DotThumbShape(radius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: _position.clamp(0, _duration == 0 ? 1 : _duration),
                max: _duration == 0 ? 1 : _duration,
                onChangeStart: (_) => _dragging = true,
                onChanged: (double v) {
                  final double snapped = (v * 10).round() / 10.0;
                  _seekTo(snapped);
                },
                onChangeEnd: (_) => _dragging = false,
              ),
            ),
          ),
          // AB 小圆点：金色实心小点插在轨道上（中线 y=32，点半径 3）
          if (ax != null)
            Positioned(
              left: ax! - 3,
              top: 29,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8A33D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (bx != null)
            Positioned(
              left: bx! - 3,
              top: 29,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8A33D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          // 两端时间：当前时间（最左）/ 总时长（最右），11px 小字，与轨道同一
          // 水平线（top:26 使文字中线 ≈ 轨道中线 32）。
          Positioned(
            left: 0,
            top: 26,
            child: Text(_fmtTenth(_position), style: timeStyle),
          ),
          Positioned(
            right: 0,
            top: 26,
            child: Text(_fmtTenth(_duration), style: timeStyle),
          ),

          // ---- 下排：A / B 时间（金色，居中于断点，钳制不出屏）----
          // A 时间固定在轨道下方；B 时间默认也在下方，AB 过近时交错到上排。
          if (ax != null)
            Positioned(
              left: clampedLeft(ax!),
              bottom: 0,
              width: 44,
              child: Text(_fmtTenth(_pointA!),
                  textAlign: TextAlign.center, style: abTimeStyle),
            ),
          if (bx != null)
            Positioned(
              left: clampedLeft(bx!),
              // AB 过近：B 时间交错到上排（此时字母已隐藏，位置让给 B 时间）
              top: abClose ? 0 : null,
              bottom: abClose ? null : 0,
              width: 44,
              child: Text(_fmtTenth(_pointB!),
                  textAlign: TextAlign.center, style: abTimeStyle),
            ),
        ],
      ),
    );
  }

  /// AB 复读色带：A~B（或 A~当前播放位置）的淡蓝底，垂直居中叠在轨道线上。
  /// 直接接收两端像素锚点（由 _buildTimeline 按轨道实际区域换算好）。
  Widget _buildAbBand(double left, double right) {
    final double width = (right - left).clamp(0.0, double.infinity);
    if (width <= 0) return const SizedBox.shrink();
    // 轨道中线在 Stack 垂直中心 y=32，色带高 4 → top = 30
    return Positioned(
      left: left,
      top: 30,
      child: Container(
        width: width,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFF5B8FC9).withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(2),
        ),
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
    // body 左右内边距已归零，视频画面左右各留 24px，避免顶到屏幕边缘
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AspectRatio(
        aspectRatio: vc.value.aspectRatio,
        child: VideoPlayer(vc),
      ),
    );
  }

  /// 占位提示：板块④未接入的功能
  void _showTip(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 自定义滑块形状：把播放头画成一个小圆点（默认的 thumb 又大又圆）。
/// 一心复读机进度条头部就是个小点，这里刻意缩小、去掉外圈高光，走「细长克制」路线。
class _DotThumbShape extends SliderComponentShape {
  const _DotThumbShape({this.radius = 7});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(radius * 2, radius * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    // 实心小圆点，白色描边一圈加粗，在细轨道上更清晰、一眼看到播放头位置
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = sliderTheme.activeTrackColor ?? const Color(0xFF5B8FC9),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
