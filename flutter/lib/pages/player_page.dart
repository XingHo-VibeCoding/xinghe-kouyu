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
import 'package:flutter/scheduler.dart'; // Ticker：跟随屏幕刷新逐帧回调
import 'package:just_audio/just_audio.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:video_player/video_player.dart';

import '../models/material_item.dart';
import '../services/waveform_service.dart';
import '../widgets/waveform_view.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, required this.folderName});

  final MaterialItem item; // 从素材列表传进来的那条素材
  final String folderName; // 该素材所属文件夹的名字（列表页已查好传进来）

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin {
  // ---- 播放器实例（二选一，视素材是音频还是视频）----
  AudioPlayer? _audio; // 音频播放器（just_audio）
  VideoPlayerController? _video; // 视频播放器（video_player）

  // ---- 播放状态 ----
  bool _playing = false; // 是否正在播放
  double _speed = 1.0; // 当前倍速（0.5 / 0.75 / 1.0 / 1.25 / 1.5 / 2.0）

  /// 当前播放位置（秒）。
  ///
  /// **为什么是 ValueNotifier 而不是普通字段 + setState**（2026-10-28 性能重构）：
  /// 位置每秒要变约 60 次，若走页面 setState，整页（唱片 + 阴影 + Chip + 按钮 +
  /// 时间轴 + 波形）都会跟着重建一遍；长音频下这就是「一顿一顿」的另一半原因。
  /// 改成 Notifier 后，只有真正订阅位置的三个地方（波形、时间轴、时间文字）
  /// 在 60fps 下重建，页面其余部分只在真正的状态变化时才重建。
  final ValueNotifier<double> _position = ValueNotifier<double>(0.0);

  double _duration = 0; // 总时长（秒）

  /// 逐帧位置刷新器（v2.4）。
  ///
  /// **为什么不再用 16ms 的定时器流**：屏幕是每 16.67ms 刷新一帧，而 16ms 的
  /// 定时器与它**不同拍**，于是每帧拿到的位置个数在 0 / 1 / 2 之间摆动——
  /// 拿到 0 个的那一帧画面不动、拿到 2 个的那一帧一次蹦两格。整块波形看起来
  /// 就是「一跳一跳」，看久了会晕。
  /// Ticker 由 Flutter 在**每帧开始**回调，与屏幕刷新严格同拍，一帧一次，
  /// 不多不少；位置用播放器的插值 getter（`position` = 上次事件位置 +
  /// 已过时长 × 倍速）现算，所以每帧拿到的都是此刻的真实位置。
  late final Ticker _frameTicker;


  /// 单调时钟：只用来量「隔了多久」，不受系统时间被改的影响
  final Stopwatch _clock = Stopwatch()..start();

  /// AB 循环触发后的冷却截止时间（毫秒）。位置流改成 60fps 后，
  /// 一次跳回 A 点、真实位置追上来之前会连续命中 B 点条件，
  /// 没有冷却就会连发好几个 seek。
  int _abCooldownUntilMs = 0;

  /// 进度条拖动节流：上一次真正发出 seek 的时刻（毫秒）。
  /// 拖动中的中间值不必补发——松手时 onChangeEnd 会补最终值。
  int _lastSliderSeekMs = 0;

  /// 正在等播放器追上的 seek 目标（秒）。
  /// 不为 null 时，位置流里「离目标还远」的回报会被忽略 —— 那些是跳转前的旧位置，
  /// 60fps 下会让界面先闪回旧位置再跳过去。
  double? _pendingSeekTarget;

  /// 上面那个等待的超时时刻（毫秒）：seek 失败时不能把界面永久冻住
  int _pendingSeekUntilMs = 0;

  /// 视频位置的基准点（秒）与它被采到的时刻（毫秒）。
  /// video_player 每 100ms 才轮询一次平台位置，逐帧读会得到 10Hz 的台阶；
  /// 记下基准后用「已过时长 × 倍速」外推，波形才能像音频那样连续滚动。
  double _vPosBase = 0;
  int _vPosBaseMs = 0;

  // ---- AB 复读状态（Day 19）----
  double? _pointA; // A 点时间（秒），null = 未设
  double? _pointB; // B 点时间（秒），null = 未设
  bool _dragging = false; // 是否正在拖进度条（拖动期间不抢播放头，方便拖到 AB 段外打新点）

  // ---- 波形时域图状态（F12）----
  WaveformStatus _waveStatus = WaveformStatus.hidden; // 四态：隐藏/加载/就绪/失败
  Waveform? _waveform; // 波形数据（就绪时才有）
  double _waveProgress = 0; // 提取进度 0~1
  int _waveToken = 0; // 请求号：重试/重进时让旧回调作废，不覆盖新状态

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
    // 逐帧位置刷新器：只在播放中运行（见 _onFrame 的说明）
    _frameTicker = createTicker(_onFrame);
    _initPlayer();
  }

  /// 初始化播放器：按素材格式选音频或视频，并设置数据源
  Future<void> _initPlayer() async {
    try {
      if (_isVideo) {
        // —— 视频：用 video_player，数据源是本地文件路径 ——
        final VideoPlayerController vc = VideoPlayerController.file(
          File(widget.item.filePath),
        );
        _video = vc;
        await vc.initialize();
        _duration = vc.value.duration.inMilliseconds / 1000.0;
        // 外推基准初始化（否则 _vPosBaseMs 还是 0，第一次外推会一次算出几十秒）
        _vPosBase = vc.value.position.inMilliseconds / 1000.0;
        _vPosBaseMs = _clock.elapsedMilliseconds;
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
        // ⚠ 位置刷新**不用任何定时器流**，统一交给 _frameTicker 逐帧读（v2.4）。
        //
        // 两条历史教训都留在这里，别走回头路：
        // ① 别用 player.positionStream（0.9.46 源码 609–621 行）：它内部是
        //    `Timer.periodic(时长 ~/ 800)` 并把周期夹在 16~200ms，
        //    ≥160 秒（2 分 40 秒）的音频会顶到 200ms 上限 —— 只有 5 次/秒，
        //    这就是「4 分钟以上音频一顿一顿」的根因。
        // ② 也别用自建 16ms 流：频率是够了，但 16ms 与屏幕的 16.67ms 不同拍，
        //    每帧拿到 0 或 2 个位置值，画面就变成「一顿一跳」（看得人发晕）。
        //    Ticker 跟着屏幕刷新走，一帧一次，位置再用播放器的插值 getter 现算，
        //    既不多也不少。
        ap.playingStream.listen((bool playing) {
          if (!mounted) return;
          if (_playing != playing) {
            setState(() => _playing = playing);
            _syncSpin(playing); // 内部会同时启停逐帧刷新器
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
      // 播放器就绪后再去取波形：波形上的定位/播放头都以真实时长为基准，
      // 早于它就取，_duration 还是 0，画出来会错位。
      _loadWaveform();
    } catch (e) {
      // 初始化失败（文件缺失、格式不支持等）：弹提示，不崩溃
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('播放器初始化失败：$e')));
      }
    }
  }

  /// 视频的监听：只同步「播放状态」，位置交给逐帧刷新器
  void _onVideoTick() {
    final VideoPlayerController? v = _video;
    if (v == null) return;
    // 记下新到的位置当「基准点」：video_player 自己每 100ms 才轮询一次位置
    // （源码 786 行 `Timer.periodic(100ms)`），两次轮询之间不重设基准，
    // 由 _readPlayerPosition 用「已过时长 × 倍速」外推补齐（见那里的说明）。
    _vPosBase = v.value.position.inMilliseconds / 1000.0;
    _vPosBaseMs = _clock.elapsedMilliseconds;

    final bool isPlaying = v.value.isPlaying;
    if (mounted && _playing != isPlaying) {
      setState(() {
        _playing = isPlaying;
        _syncSpin(isPlaying); // 内部会同时启停逐帧刷新器
      });
    }
    // 视频播放结束自动复位（图标由上面的 isPlaying 同步自动切回播放态）
    if (v.value.isCompleted) {
      if (mounted && _playing) {
        setState(() => _playing = false);
        _syncSpin(false);
      }
    }
  }

  /// 读当前真实播放位置（秒）。
  ///
  /// 音频：`AudioPlayer.position` 本身就是「上次事件位置 + 已过时长 × 倍速」
  /// 现算的（源码 590–600 行），直接读即可，每帧都是此刻的真实位置。
  ///
  /// 视频：`VideoPlayerController.value.position` **只是个 10Hz 的缓存值**
  /// （插件内部每 100ms 轮询一次平台），直接读会让波形以 10 次/秒的台阶跳。
  /// 所以这里用同样的思路外推：基准位置（最近一次轮询值） + 距那次轮询的时长 × 倍速。
  /// 每次 `_onVideoTick` 都会用平台的真实值重置基准，误差不会累积。
  double? _readPlayerPosition() {
    if (_isVideo) {
      final VideoPlayerController? v = _video;
      if (v == null || !v.value.isInitialized) return null;
      final VideoPlayerValue val = v.value;
      // 暂停 / 卡顿缓冲时不外推：那时候时间在走、画面没走，外推会让波形跑在视频前面
      if (!val.isPlaying || val.isBuffering) return _vPosBase;
      final double elapsed =
          (_clock.elapsedMilliseconds - _vPosBaseMs) / 1000.0;
      double p = _vPosBase + elapsed * _speed;
      if (_duration > 0 && p > _duration) p = _duration;
      return p;
    }
    final AudioPlayer? a = _audio;
    if (a == null) return null;
    return a.position.inMilliseconds / 1000.0;
  }

  /// 每帧回调（播放中才有）：读位置 → 更新 Notifier → 判 AB 回跳。
  ///
  /// 这里是「波形滚动平不平滑」的关键：一帧只产生一个位置值，
  /// 且这个值就是这一帧要画的那个时刻，不存在「这帧没新值、下帧蹦两格」。
  void _onFrame(Duration _) {
    if (!mounted) return;
    final double? p = _readPlayerPosition();
    if (p == null) return;
    // 拖动期间以手指为准：播放器报的是「拖动之前」的旧位置
    if (_dragging) return;
    // seek 在飞的时候，播放器还会报「跳转前」的旧位置（连续十几帧）。
    // 目标没追上之前先忽略；700ms 超时兜底（防 seek 失败把界面永久冻住）。
    final double? target = _pendingSeekTarget;
    if (target != null) {
      if ((p - target).abs() < 0.35) {
        _pendingSeekTarget = null; // 追上了，恢复正常跟随
      } else if (_clock.elapsedMilliseconds < _pendingSeekUntilMs) {
        return; // 还在飞：丢掉旧回报
      } else {
        _pendingSeekTarget = null; // 超时：别把界面冻在这一帧
      }
    }
    _position.value = p;
    _checkAbLoop(); // AB 复读：播到 B 点自动跳回 A
  }

  /// 启停逐帧刷新器：只在播放中运行（暂停时位置不会变，白跑 60fps 没意义）
  void _syncFrameTicker(bool playing) {
    if (playing) {
      if (!_frameTicker.isActive) _frameTicker.start();
    } else {
      if (_frameTicker.isActive) _frameTicker.stop();
    }
  }

  /// 同步旋转动画：播放中 → 无限循环旋转，暂停/停止 → 停在当前角度
  void _syncSpin(bool playing) {
    // 顺带启停逐帧刷新器：所有「播放状态变化」的地方都经过这里，
    // 放在一起就不会漏（音频 playingStream、视频监听、播放完成、错误兜底）。
    _syncFrameTicker(playing);
    if (_spinCtrl == null) return;
    if (playing) {
      if (!_spinCtrl!.isAnimating) _spinCtrl!.repeat();
    } else {
      _spinCtrl!.stop();
    }
  }

  /// 进度条拖动过程中的 seek：**视觉立刻跟手 + 真实 seek 每 60ms 最多一次**。
  ///
  /// 原来每个像素位移都发一次 seek。4 分钟以上的音频，一次 seek 要走平台侧
  /// 重新定位（解码器要从最近的索引点重新起播），一秒几十个请求会把播放器的
  /// 命令队列塞满 —— 表现就是「越拖越粘、松手后还追不上」。
  /// 现在圆点/波形由 Notifier 立刻跟上手指，真实定位按 60ms 节流，
  /// 松手时在 onChangeEnd 补齐终点（不会丢最后一格）。
  void _onSliderSeek(double seconds) {
    _position.value = seconds;
    final int nowMs = _clock.elapsedMilliseconds;
    if (nowMs - _lastSliderSeekMs < 60) return; // 60ms 内的中间值不单独发
    _lastSliderSeekMs = nowMs;
    _seekTo(seconds);
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
    final double target = (_position.value + delta).clamp(0, _duration);
    await _seekTo(target);
  }

  /// 跳转到指定位置（秒）
  ///
  /// 先改 Notifier（界面立刻跟手，不等播放器回报），再真正 seek。
  Future<void> _seekTo(double seconds) async {
    final double target = (_duration > 0)
        ? seconds.clamp(0.0, _duration).toDouble()
        : seconds;
    _position.value = target;
    // 记下目标：追上之前的旧回报一律忽略，避免界面闪回（见 _pendingSeekTarget）
    _pendingSeekTarget = target;
    _pendingSeekUntilMs = _clock.elapsedMilliseconds + 700;
    if (_isVideo) {
      await _video?.seekTo(Duration(milliseconds: (target * 1000).round()));
      // 视频的外推基准立刻换到目标点：否则「旧基准 + 已过时长」会算出
      // 一个离目标很远的值，白白撞上 _pendingSeekTarget 的守卫。
      _vPosBase = target;
      _vPosBaseMs = _clock.elapsedMilliseconds;
    } else {
      await _audio?.seek(Duration(milliseconds: (target * 1000).round()));
    }
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
    final double now = _position.value;
    if (_pointB != null && now >= _pointB! - 0.5) {
      _showTip('A 点必须在 B 点左边。先把进度条拖到 B 之前，再点 A。');
      return;
    }
    setState(() => _pointA = now);
  }

  /// 打 B 点：在当前播放位置设终点，从此 A↔B 循环自动开始。
  /// 规则：必须先有 A；B 必须落在 A 右边（当前位置 ≤ A+0.5s 视为无效）。
  void _onSetB() {
    final double now = _position.value;
    if (_pointA == null) {
      _showTip('请先打 A 点（起点），再打 B 点。');
      return;
    }
    if (now <= _pointA! + 0.5) {
      _showTip('B 点必须在 A 点右边。先把进度条拖到 A 之后，再点 B。');
      return;
    }
    setState(() => _pointB = now);
  }

  /// 重置 AB 点：清掉 A、B，退出复读，恢复正常播放（当前位置不动）。
  void _onAbReset() {
    setState(() {
      _pointA = null;
      _pointB = null;
    });
  }

  /// AB 循环核心：播放位置超过 B 点就跳回 A 点。
  /// 调用时机：音频在位置流（16ms）、视频在 _onVideoTick 里，每次位置更新都检查一次。
  /// 例外：正拖进度条时不抢播放头（让用户能把播放头拖到 AB 段外去打新点）。
  ///
  /// 冷却 250ms 的原因：位置流提到 60fps 后，从「判定超过 B」到「真实位置回到 A」
  /// 之间还会来十几个位置包，每个都会再次命中 B 点条件 —— 不加冷却会连发 seek，
  /// 反而把播放器拖卡。250ms 足够一次 seek 落地。
  void _checkAbLoop() {
    if (_dragging) return; // 拖动中不抢
    final double? a = _pointA;
    final double? b = _pointB;
    if (a == null || b == null) return;
    final int nowMs = _clock.elapsedMilliseconds;
    if (nowMs < _abCooldownUntilMs) return;
    if (_position.value >= b) {
      _abCooldownUntilMs = nowMs + 250;
      _seekTo(a); // 跳回 A，继续循环
    }
  }

  /// 播放时兜底：如果播放头在 AB 段之外（已过 B 或还没到 A），送回 A 点恢复正常复读。
  void _checkAbOnPlay() {
    final double? a = _pointA;
    final double? b = _pointB;
    if (a == null || b == null) return;
    if (_position.value >= b || _position.value < a) {
      _abCooldownUntilMs = _clock.elapsedMilliseconds + 250;
      _seekTo(a);
    }
  }

  // ===== 波形时域图（F12）=====

  /// 取波形数据：缓存命中则毫秒级返回，未命中则走原生提取并回显进度。
  /// [force] = true 表示「重试」：忽略已有缓存重新提取。
  Future<void> _loadWaveform({bool force = false}) async {
    if (!WaveformService.isSupported) {
      // Windows 等平台没有原生实现：整块收起，不报错也不占位置
      if (mounted) setState(() => _waveStatus = WaveformStatus.hidden);
      return;
    }

    final int token = ++_waveToken; // 本次请求的号码，旧回调凭它作废
    setState(() {
      _waveStatus = WaveformStatus.loading;
      _waveProgress = 0;
    });

    final Waveform? w = await WaveformService.obtain(
      filePath: widget.item.filePath,
      force: force,
      onProgress: (double p) {
        // 页面已关、或已被新的请求取代：这次进度直接丢掉
        if (!mounted || token != _waveToken) return;
        if (_waveStatus != WaveformStatus.loading) return;
        setState(() => _waveProgress = p);
      },
    );

    if (!mounted || token != _waveToken) return;
    setState(() {
      _waveform = w;
      _waveStatus = w == null ? WaveformStatus.failed : WaveformStatus.ready;
    });
  }

  /// 拖波形上的 A 手柄：只改 A 点，**不 seek**
  /// （正在边听边微调起点时，播放头被拽走会打断听感）
  void _onWaveDragA(double seconds) {
    // 没有 B 时，A 也要留出 0.5 秒余量，否则 A 拖到最末尾就永远打不了 B
    final double maxA = _pointB != null ? _pointB! - 0.5 : (_duration - 0.5);
    final double v = seconds.clamp(0.0, maxA < 0 ? 0.0 : maxA).toDouble();
    if (_pointA != v) setState(() => _pointA = v);
  }

  /// 拖波形上的 B 手柄：只改 B 点。
  /// 上限留 0.15 秒，避免 B 正好压在结尾：播放会「完成」，复读就停住了。
  void _onWaveDragB(double seconds) {
    if (_pointA == null) return; // 没有 A 就不会有 B 手柄
    const double tail = 0.15;
    final double maxB = _duration - tail;
    final double minB = _pointA! + 0.5;
    final double lower = minB <= maxB ? minB : maxB;
    final double upper = maxB > lower ? maxB : lower;
    final double v = seconds.clamp(lower, upper).toDouble();
    if (_pointB != v) setState(() => _pointB = v);
  }

  /// 波形区：四态渲染交给 WaveformView，这里只把状态和回调接上
  /// [pos] 由外层 ValueListenableBuilder 传进来（订阅位置，60fps 更新）
  Widget _buildWaveformArea(double pos) {
    return WaveformView(
      status: _waveStatus,
      waveform: _waveform,
      progress: _waveProgress,
      duration: _duration,
      position: pos,
      pointA: _pointA,
      pointB: _pointB,
      onSeek: _seekTo,
      onDragA: _onWaveDragA,
      onDragB: _onWaveDragB,
      // 拖动期间暂停 AB 自动循环抢播放头（和拖动滑动条同一套机制）
      onInteractionStart: () => _dragging = true,
      onInteractionEnd: () => _dragging = false,
      onRetry: () => _loadWaveform(force: true),
    );
  }

  // ---- 定时器已废弃：音频进度改用 positionStream、视频用 addListener，
  //      不再需要手动定时刷新（避免「第一次点播放不动」的时序 bug）。----

  @override
  void dispose() {
    // 让还在飞的提取回调作废：页面都关了，别再 setState
    _waveToken++;
    _frameTicker.dispose(); // 逐帧刷新器必须自己收，否则页面关了还在跑
    _spinCtrl?.dispose();
    _audio?.dispose();
    _video?.dispose();
    _position.dispose();
    super.dispose();
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
      // 加波形后内容变高，整页改成「可滚动」：
      // ConstrainedBox(minHeight) + Column(spaceBetween) 顶替原来的 Spacer——
      // 内容不满一屏时上块贴顶、控制区贴底（和加波形前位置一致）；
      // 内容超过一屏（矮屏 / 横屏）时可以滚动，不再黄黑条溢出。
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                // 左右内边距归零，让进度条从屏幕最左铺到最右；上下各留 24 保持呼吸感
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    // ===== 上块：唱片 / 视频画面 + 标题 =====
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(height: 12),

                        // ---- 视频画面区 / 音频唱片区 ----
                        if (_isVideo) _buildVideoArea() else _buildDisc(),

                        const SizedBox(height: 16),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.folderName} · ${item.format.toUpperCase()}',
                          // 副标题是「信息」不是「按钮」，用深一档的中性灰，保证对比度（之前 black54 偏浅）
                          style: const TextStyle(color: Colors.black87),
                        ),
                        // 视频页原来那条 36px 装饰波形已删除：现在统一用上面真正的波形时域图，
                        // 两条叠在一起既重复又挤高度。
                      ],
                    ),

                    // ===== 下块：波形 + 时间轴 + 控制区 =====
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // 波形时域图（F12）：滑动条上方，与滑动条并存，两者都能拖。
                        // 用 ValueListenableBuilder 只让「波形」跟着位置重建，
                        // 外面套 RepaintBoundary 把它的每帧重绘隔离成独立图层，
                        // 不再连累唱片、Chip、按钮这些静态内容重绘。
                        RepaintBoundary(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _position,
                            builder:
                                (
                                  BuildContext context,
                                  double pos,
                                  Widget? child,
                                ) => _buildWaveformArea(pos),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ---- 进度时间轴（模仿一心复读机）----
                        // 固定高度的三层结构：上排 A/B 字母 → 中间细轨道（播放头小圆点 +
                        // AB 小圆点）→ 下排时间（当前时间 | AB 时间按位置分布 | 总时长）。
                        // 轨道跟随父级宽度（body 已把左右内边距归零，轨道自然铺到屏幕最边）。
                        // 同样只订阅位置，避免 60fps 重建整页。
                        LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints constraints,
                              ) {
                                return ValueListenableBuilder<double>(
                                  valueListenable: _position,
                                  builder:
                                      (
                                        BuildContext context,
                                        double pos,
                                        Widget? child,
                                      ) => _buildTimeline(
                                        constraints.maxWidth,
                                        pos,
                                      ),
                                );
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
                              icon: Icon(
                                Icons.fast_rewind,
                                color: const Color(0xFF5B8FC9),
                              ),
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
                              icon: Icon(
                                Icons.fast_forward,
                                color: const Color(0xFF5B8FC9),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // ---- 复读功能区（第一行）：A / B / 重置 ----
                        // chip 只显示字母不显示时间（时间已在进度条上展示），激活时变金色即可。
                        ChipTheme(
                          data: ChipTheme.of(context).copyWith(
                            side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              // A 打点：未打点白底灰字，已打点金底（时间看进度条上的 A 标注）
                              ActionChip(
                                avatar: Icon(
                                  Icons.keyboard_arrow_up,
                                  size: 18,
                                  color: _pointA != null
                                      ? const Color(0xFFE8A33D)
                                      : Colors.black54,
                                ),
                                label: const Text('A'),
                                backgroundColor: _pointA != null
                                    ? const Color(0xFFF6E3C2)
                                    : null,
                                onPressed: _onSetA,
                              ),
                              const SizedBox(width: 12),
                              // B 打点：同 A 的规则
                              ActionChip(
                                avatar: Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 18,
                                  color: _pointB != null
                                      ? const Color(0xFFE8A33D)
                                      : Colors.black54,
                                ),
                                label: const Text('B'),
                                backgroundColor: _pointB != null
                                    ? const Color(0xFFF6E3C2)
                                    : null,
                                onPressed: _onSetB,
                              ),
                              const SizedBox(width: 12),
                              // 重置：有任一点被打就点亮成金色（提示「这里有东西可清」）
                              ActionChip(
                                avatar: Icon(
                                  Icons.restart_alt,
                                  size: 18,
                                  color: (_pointA != null || _pointB != null)
                                      ? const Color(0xFFE8A33D)
                                      : Colors.black54,
                                ),
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
                            side: BorderSide(
                              color: Colors.black.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              // 变速：点一下切下一档。非 1.0x 时蓝色底提示「已变速」（蓝=播放控制语义）。
                              ActionChip(
                                label: Text('${_speed}x'),
                                backgroundColor: _speed != 1.0
                                    ? const Color(0xFFD6E7F5)
                                    : null,
                                onPressed: _cycleSpeed,
                              ),
                              const SizedBox(width: 12),
                              // 循环：用 repeat 图标，不用 emoji（emoji 在不同系统渲染差异大，且配色不统一）
                              ActionChip(
                                avatar: Icon(
                                  Icons.repeat,
                                  size: 18,
                                  color: Colors.black54,
                                ),
                                label: const Text('循环'),
                                onPressed: () => _showTip('单集循环将在后续板块接入'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
                  colors: <Color>[discBlue.withValues(alpha: 0.95), discBlue],
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
            child: Icon(
              Icons.music_note,
              color: const Color(0xFF5B8FC9),
              size: 28,
            ),
          ),
        ],
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
  /// [pos] 当前播放位置（秒），由外层订阅 ValueNotifier 传入 —— 每帧刷新，
  /// 但只重建「时间轴」这一小块。
  Widget _buildTimeline(double trackW, double pos) {
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
        sliderLeft +
        trackInset +
        frac.clamp(0.0, 1.0) * (sliderW - trackInset * 2);

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
    final double playX = fracX(pos / (_duration == 0 ? 1 : _duration));

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
              child: const Text(
                'A',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE8A33D),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (bx != null && !abClose)
            Positioned(
              left: bx! - 12,
              top: 0,
              width: 24,
              child: const Text(
                'B',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE8A33D),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
                inactiveTrackColor: const Color(0xFF5B8FC9)
                    .withValues(alpha: 0.18),
                thumbColor: const Color(0xFF4A7EB8),
                thumbShape: const _DotThumbShape(radius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                value: pos.clamp(0, _duration == 0 ? 1 : _duration),
                max: _duration == 0 ? 1 : _duration,
                onChangeStart: (_) => _dragging = true,
                onChanged: (double v) {
                  final double snapped = (v * 10).round() / 10.0;
                  _onSliderSeek(snapped);
                },
                onChangeEnd: (double v) {
                  _dragging = false;
                  // 松手补齐终点：节流期间可能有中间值没发，最后一次必须落地
                  final double snapped = (v * 10).round() / 10.0;
                  _lastSliderSeekMs = _clock.elapsedMilliseconds;
                  _seekTo(snapped);
                },
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
            child: Text(_fmtTenth(pos), style: timeStyle),
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
              child: Text(
                _fmtTenth(_pointA!),
                textAlign: TextAlign.center,
                style: abTimeStyle,
              ),
            ),
          if (bx != null)
            Positioned(
              left: clampedLeft(bx!),
              // AB 过近：B 时间交错到上排（此时字母已隐藏，位置让给 B 时间）
              top: abClose ? 0 : null,
              bottom: abClose ? null : 0,
              width: 44,
              child: Text(
                _fmtTenth(_pointB!),
                textAlign: TextAlign.center,
                style: abTimeStyle,
              ),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 自定义滑块形状：把播放头画成一个小圆点（默认的 thumb 又大又圆）。
/// 一心复读机进度条头部就是个小点，这里刻意缩小、去掉外圈高光，走「细长克制」路线。
class _DotThumbShape extends SliderComponentShape {
  const _DotThumbShape({this.radius = 7});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(radius * 2, radius * 2);

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
