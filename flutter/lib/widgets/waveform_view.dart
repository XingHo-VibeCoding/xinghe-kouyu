// =====================================================================
// 波形组件（F12 时域图）：播放头固定居中 + 拨动即定位 + AB 金色手柄
// ---------------------------------------------------------------------
// 职责边界（很重要）：
//   这个组件**不持有播放器、不认识 just_audio**。它只接收
//   「波形数据 + 时长 + 当前位置 + A/B 点」，把用户动作换算成时间，
//   通过回调交还给页面。所以音频页和视频页能共用同一个组件。
//
// 时间轴模型（v2.0 起，2026-10-28 用户拍板）：
//   · 屏幕只显示约 6 秒波形，**播放头固定居中**，波形从它下面流过；
//   · **拨动波形 = 改播放位置**（进度条、时间文字同步跟着变）。
//     与 v1.9 的区别：v1.9 是「拨动只平移视图、不动播放位置」，
//     现在改成「拨动就是拖播放头」——同一个动作不能有两个含义。
//   · 好处：播放头不动，眼睛不用跟着跑；拨动会真的跳到那段声音。
//
// v2.1（2026-10-28 晚）再改两点：
//   · **播放头永久居中**：窗口不再被 0 / 曲末卡住，轨道两端之外的那一段
//     画成淡灰底（表示「这里还没有音频」）。所以刚加载完、position=0 时
//     播放头就已经在正中央，不会「先贴左边、播到中间才卡住」。
//   · **去掉单击定位**：点一下波形不改变播放位置，只有横向拨动才改。
//     附带好处：拨完手一抖（tap 判定）也不会意外跳到别处。
//
// 手势三分支（按下瞬间判定一次，中途不换模式）：
//   · 落在 A 手柄 18px 内 → 拖 A 点
//   · 落在 B 手柄 18px 内 → 拖 B 点
//   · 其它位置横向拨动     → 定位（40ms 节流，边拨边跳）
//
// 坐标约定：绘制区左右各内缩 14px，与播放页 Slider 轨道的内部换算一致，
// 这样波形上的竖线播放头与滑动条上的小圆点落在同一个 x（不会看起来错位）。
//
// 语言：Dart（纯本地，无网络）。
// =====================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart';

/// 波形区状态
enum WaveformStatus {
  /// 不显示（平台不支持 / 播放器没就绪）：整块收起，不占空间
  hidden,

  /// 正在提取，显示进度
  loading,

  /// 可以绘制
  ready,

  /// 提取失败，显示重试入口
  failed,
}

/// 波形视图
class WaveformView extends StatefulWidget {
  const WaveformView({
    super.key,
    required this.status,
    required this.duration,
    required this.position,
    required this.onSeek,
    required this.onDragA,
    required this.onDragB,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    required this.onRetry,
    this.waveform,
    this.progress = 0,
    this.pointA,
    this.pointB,
    this.height = 96,
    this.windowSeconds = 6,
  });

  /// 当前状态（页面决定显示波形、进度、失败还是收起）
  final WaveformStatus status;

  /// 播放器给出的总时长（秒）。**定位一律以它为准**，
  /// 不用 waveform.duration：后者来自文件元数据，和播放器可能差几十毫秒到几秒。
  final double duration;

  /// 当前播放位置（秒）。窗口以它为中心（手指操作期间临时冻结）
  final double position;

  /// 波形数据（status == ready 时才有）
  final Waveform? waveform;

  /// 提取进度 0~1（status == loading 时用）
  final double progress;

  /// A / B 点（秒），null = 未打点
  final double? pointA;
  final double? pointB;

  /// 波形区总高度（含顶部秒刻度行）
  final double height;

  /// 一屏显示多少秒（短于此值的音频自动钳制为整曲）
  final double windowSeconds;

  /// 定位：把播放头移到这个时间（秒）。拨动波形时会被连续调用。
  final ValueChanged<double> onSeek;

  /// 拖动 A 手柄得到的新时间（秒）。是否合法（A < B）由页面判断。
  final ValueChanged<double> onDragA;

  /// 拖动 B 手柄得到的新时间（秒）
  final ValueChanged<double> onDragB;

  /// 开始拖动/拨动（页面据此暂停 AB 自动循环的抢播放头）
  final VoidCallback onInteractionStart;

  /// 结束拖动/拨动
  final VoidCallback onInteractionEnd;

  /// 提取失败后点重试
  final VoidCallback onRetry;

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

/// 手势模式：按下时定一次，中途不切换（否则滑过手柄会突然变成拖手柄）
enum _GestureMode { none, pan, pointA, pointB }

class _WaveformViewState extends State<WaveformView> {
  /// 绘制区左右内缩，与页面上 Slider 的轨道换算保持一致
  static const double _inset = 14;

  /// 手柄命中半径（px）
  static const double _hitRadius = 18;

  /// 顶部刻度行高度
  static const double _tickHeight = 20;

  /// 拨动时的 seek 节流间隔：手指事件频率远高于它，
  /// 不节流会让 seek 请求排队，声音抖动、播放头黏滞。
  static const Duration _seekInterval = Duration(milliseconds: 40);

  _GestureMode _mode = _GestureMode.none;

  /// 手指操作期间冻结的窗口中心（秒）。
  /// 为什么要冻结：正常情况下中心 = 播放位置，而拨动时我们一边发 seek
  /// 一边改播放位置；若仍以回调回来的 position 为准，会出现
  /// 「手指已到右边、画面还在等播放器回报」的滞后感。
  double? _frozenCenter;

  /// 拨动起点：手指 x 与当时的中心时间
  double _panStartX = 0;
  double _panStartCenter = 0;

  /// 待发送的 seek 目标（节流用）
  double? _pendingSeek;
  Timer? _seekTicker;

  /// 拨动松手后「等播放器追上」的目标位置。
  ///
  /// 为什么需要它：seek 是异步的，松手瞬间可能还有几个 seek 在飞。
  /// 若立刻解冻，画面会以**回调回来的旧位置**为中心，出现「松手后画面
  /// 往回跳一下」的观感。所以松手后先钉住目标位置，等真实位置追上来
  /// （或超时兜底）再交还给正常跟随。
  double? _settleTarget;
  Timer? _settleTimer;

  /// 当前布局宽度（手势换算要用，LayoutBuilder 里更新）
  double _width = 0;

  // ---- 逐列振幅缓存（v2.3）----
  //
  // 为什么改成「全曲算一次 + 每帧只取可见列」：
  // 旧做法是每帧把「当前窗口」重新重采样成 120 根柱，柱子画在**固定的 x** 上，
  // 只有高度在变 —— 结果不是「波形在流动」，而是「一排柱子原地变形」。
  // 滚动时每根柱子每帧都在换形状，看起来就是抖、糊、一跳一跳。
  //
  // 新做法：每根柱子代表一个固定的时间片（1/20 秒），画在它真实的 x 上，
  // 每帧只是整体平移。柱子高度恒定，画面自然流动；而且逐列振幅只在换文件时
  // 算一次（O(n) 一次），每帧只剩「遍历约 120 根柱 + 画线」，不再碰波形数据。
  List<double> _amps = const <double>[];

  /// 缓存归属（换文件才重算）
  Waveform? _ampsSource;

  @override
  void didUpdateWidget(covariant WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换文件：丢掉冻结值，让窗口回到「以播放头为中心」
    if (!identical(oldWidget.waveform, widget.waveform)) {
      _frozenCenter = null;
      _settleTarget = null;
      _settleTimer?.cancel();
      return;
    }
    // 播放器回报的位置终于追上拨动的目标：解冻，恢复正常跟随
    final double? target = _settleTarget;
    if (target != null && (widget.position - target).abs() < 0.2) {
      _settleTarget = null;
      _settleTimer?.cancel();
      _frozenCenter = null;
    }
  }

  @override
  void dispose() {
    _seekTicker?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // 窗口与坐标换算
  // ------------------------------------------------------------------

  double get _safeDuration => widget.duration > 0 ? widget.duration : 1.0;

  /// 一屏时长：短音频取整曲长度，避免出现「窗口比音频还长」的空白
  double get _windowLen {
    final double d = widget.duration;
    if (d <= 0) return widget.windowSeconds;
    return d < widget.windowSeconds ? d : widget.windowSeconds;
  }

  /// 窗口中心：正常跟着播放位置走，手指操作期间用冻结值
  double get _center =>
      (_frozenCenter ?? widget.position).clamp(0.0, _safeDuration);

  /// 窗口左边缘：**恒等于「中心 − 半窗」**，不受轨道两端限制。
  /// 曲首/曲末时它会变成负数、或超出曲末，多出来那一段由绘制层画成淡灰底
  /// （表示「这里还没有音频 / 已经播完」）。只有这样才能让播放头一直钉在
  /// 正中央——v2.1 拍板：宁可两端留白，也不要播放头来回跑。
  double get _windowStart => _center - _windowLen / 2;

  double get _drawLeft => _inset;
  double get _drawRight => _width - _inset;
  double get _drawWidth => _drawRight - _drawLeft;

  /// 时间（秒）→ x 像素（基于当前窗口，超出窗口时钳制到两端）
  double _timeToX(double seconds) {
    if (_drawWidth <= 0) return _drawLeft;
    final double frac = ((seconds - _windowStart) / _windowLen).clamp(0.0, 1.0);
    return _drawLeft + frac * _drawWidth;
  }

  /// x 像素 → 时间（秒），基于当前窗口
  double _xToTime(double x) {
    if (_drawWidth <= 0) return _windowStart;
    final double frac = ((x - _drawLeft) / _drawWidth).clamp(0.0, 1.0);
    return _windowStart + frac * _windowLen;
  }

  /// 手柄的可命中 x：只有真正落在窗口内才算（窗口外的只是「提示箭头」，
  /// 不能拖——否则会把 A/B 改到窗口边界对应的时间，等于悄悄改了用户的点）
  double? _handleX(double? seconds) {
    if (seconds == null) return null;
    if (seconds < _windowStart || seconds > _windowStart + _windowLen) {
      return null;
    }
    return _timeToX(seconds);
  }

  bool get _ready => widget.status == WaveformStatus.ready;

  // ------------------------------------------------------------------
  // 手势
  // ------------------------------------------------------------------

  void _onDragStart(DragStartDetails details) {
    if (!_ready || widget.duration <= 0) return;

    final double x = details.localPosition.dx;
    final double? ax = _handleX(widget.pointA);
    final double? bx = _handleX(widget.pointB);
    final double da = ax == null ? double.infinity : (x - ax).abs();
    final double db = bx == null ? double.infinity : (x - bx).abs();

    // 两个手柄都很近时取更近的那个（重叠也不至于判错）
    _GestureMode mode;
    if (da <= _hitRadius && da <= db) {
      mode = _GestureMode.pointA;
    } else if (db <= _hitRadius) {
      mode = _GestureMode.pointB;
    } else {
      mode = _GestureMode.pan;
    }

    widget.onInteractionStart(); // 先冻结 AB 自动循环，再动播放头

    _settleTimer?.cancel();
    setState(() {
      _mode = mode;
      _settleTarget = null;
      // 一律冻结：拖手柄时窗口不能动（否则手柄会从手指下面溜走），
      // 拨动时窗口由手指控制（不用等播放器回报）。
      _frozenCenter = widget.position;
      if (mode == _GestureMode.pan) {
        _panStartX = x;
        _panStartCenter = widget.position;
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_mode == _GestureMode.none) return;
    final double x = details.localPosition.dx;

    switch (_mode) {
      case _GestureMode.pan:
        if (_drawWidth <= 0) return;
        // 手指右移 = 往回听（时间减小），像把磁带往后拨
        final double dx = x - _panStartX;
        final double target = (_panStartCenter - dx / _drawWidth * _windowLen)
            .clamp(0.0, _safeDuration);
        setState(() => _frozenCenter = target);
        _applySeek(target);
      case _GestureMode.pointA:
        widget.onDragA(_xToTime(x).clamp(0.0, _safeDuration));
      case _GestureMode.pointB:
        widget.onDragB(_xToTime(x).clamp(0.0, _safeDuration));
      case _GestureMode.none:
        break;
    }
  }

  void _onDragEnd(DragEndDetails details) => _finishGesture();

  void _onDragCancel() => _finishGesture();

  void _finishGesture() {
    if (_mode == _GestureMode.none) return;
    _flushSeek(); // 别丢掉终点，否则松手后播放头会差一小段

    final bool wasPan = _mode == _GestureMode.pan;
    final double? aimed = _frozenCenter;

    setState(() {
      _mode = _GestureMode.none;
      if (wasPan && aimed != null) {
        // 先钉住目标，等播放器追上来再解冻（防「松手后往回跳」）
        _settleTarget = aimed;
        _frozenCenter = aimed;
      } else {
        _frozenCenter = null;
      }
    });

    if (wasPan && aimed != null) {
      _settleTimer?.cancel();
      _settleTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _settleTarget = null;
          _frozenCenter = null;
        });
      });
    }

    widget.onInteractionEnd();
  }

  /// 节流后的 seek：第一次立刻发，之后每 40ms 发一次最新值
  void _applySeek(double t, {bool immediate = false}) {
    if (immediate) {
      _pendingSeek = null;
      widget.onSeek(t);
      return;
    }
    _pendingSeek = t;
    if (_seekTicker != null) return;
    _seekTicker = Timer.periodic(_seekInterval, (Timer timer) {
      final double? target = _pendingSeek;
      if (target == null) {
        timer.cancel();
        _seekTicker = null;
        return;
      }
      _pendingSeek = null;
      widget.onSeek(target);
    });
  }

  /// 手指抬起：把最后一个待发送的 seek 补发出去，别丢掉终点
  void _flushSeek() {
    _seekTicker?.cancel();
    _seekTicker = null;
    final double? target = _pendingSeek;
    _pendingSeek = null;
    if (target != null && _mode == _GestureMode.pan) widget.onSeek(target);
  }

  // ------------------------------------------------------------------
  // 逐列振幅：换文件时算一次，每帧只取窗口内的可见列
  // （20 列/秒 × 6 秒 = 120 根，线距约 3.6px，见 WaveformService.zoomPps）
  // ------------------------------------------------------------------

  /// 全局量程：对全曲按 stride 抽样后取 98 分位。
  /// 取 98 分位而不是最大值：解码器起始帧常吐一个爆音（单列顶到 ±32767），
  /// 拿最大值当量程会把其余所有列压成一条细线。
  double _computeRef(Waveform w) {
    final int n = w.length;
    if (n <= 0) return 0;
    final int stride = math.max(1, n ~/ 20000); // 最多抽 2 万点，排序才够快
    final List<double> samples = <double>[];
    for (int i = 0; i < n; i += stride) {
      final double amp = (w.getPixelMax(i) - w.getPixelMin(i)) / 2.0;
      if (amp > 0) samples.add(amp);
    }
    if (samples.isEmpty) return 0;
    samples.sort();
    final int idx = ((samples.length - 1) * 0.98)
        .floor()
        .clamp(0, samples.length - 1)
        .toInt();
    return samples[idx];
  }

  /// 把整条音轨的每一列算成归一化振幅（0~1），**只做一次**（换文件才重算）。
  ///
  /// 成本：一次 O(n) 遍历。4 分钟音频 n≈4800、1 小时 n≈72000，
  /// 一次性几毫秒，之后每帧都只是读这个数组，不再访问波形数据。
  void _prepareAmps(Waveform w) {
    final int n = w.length;
    // 全局量程（98 分位）：**必须全局算一次、所有窗口共用**。
    // 若按窗口各算各的，拨动时波形会一屏大一屏小（忽胖忽瘦），看起来像故障。
    final double ref = _computeRef(w);
    if (n <= 0) {
      _amps = const <double>[];
      _ampsSource = w;
      return;
    }
    final List<double> out = List<double>.filled(n, 0.0);
    // ref <= 1 说明振幅只有 1 个采样单位，是数字静音：放大只会得到底噪，
    // 全部留 0（绘制层会给静音列画最小 1px 的细线，不会留断口）。
    if (ref > 1) {
      final double scale = 0.92 / ref;
      for (int i = 0; i < n; i++) {
        final double amp = (w.getPixelMax(i) - w.getPixelMin(i)) / 2.0;
        final double v = amp * scale;
        out[i] = v > 1.0 ? 1.0 : v;
      }
    }
    _amps = out;
    _ampsSource = w;
  }

  // ------------------------------------------------------------------
  // 构建
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    switch (widget.status) {
      case WaveformStatus.hidden:
        return const SizedBox.shrink();
      case WaveformStatus.loading:
        return _buildLoading();
      case WaveformStatus.failed:
        return _buildFailed();
      case WaveformStatus.ready:
        return _buildWaveform();
    }
  }

  Widget _buildLoading() {
    final int pct = (widget.progress * 100).round();
    return SizedBox(
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                // 进度为 0 时显示「无限滚动」，避免一直停在 0% 像卡死
                value: widget.progress > 0 ? widget.progress : null,
                minHeight: 3,
                backgroundColor: const Color(0xFF5B8FC9)
                    .withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF4A7EB8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              pct > 0 ? '正在生成波形 $pct%' : '正在生成波形…',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailed() {
    return SizedBox(
      height: widget.height,
      child: Center(
        child: InkWell(
          onTap: widget.onRetry,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.refresh, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  // 说明「不影响听」：波形只是辅助，别让用户以为播放坏了
                  '波形无法生成 · 点此重试（不影响播放）',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _width = constraints.maxWidth;
        final double len = _windowLen;
        final double start = _windowStart;
        final double center = _center;

        final Waveform? w = widget.waveform;
        // 逐列振幅只在换文件时算一次（O(n) 一次）；之后每帧只是读数组。
        if (w != null && !identical(w, _ampsSource)) {
          _prepareAmps(w);
        }

        // 线距：屏幕宽度 ÷ 窗口内的列数（6 秒 × 20 列/秒 = 120 根 → 约 3.6px）
        final double pps = _safeDuration > 0 ? _amps.length / _safeDuration : 0;
        final double pitch = (pps > 0 && _drawWidth > 0)
            ? _drawWidth / (len * pps)
            : 4.0;
        // 线宽 = 线距的一半（下限 1px、上限 2px）：6 秒窗口下画约 2px 的线、
        // 留约 1.6px 的间隙，每根都是清晰分离的细竖线。
        // 不随线距无限变粗：短音频线距再宽，线也保持纤细，观感才统一。
        final double strokeW = (pitch * 0.55).clamp(1.0, 2.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 只有「横向拨动」会改播放位置（v2.1 拍板：单击不改时间）
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              // 每帧都在变：明确告诉引擎「别缓存这张位图」，
              // 否则光栅缓存反复失效、重建，反而更慢
              isComplex: true,
              willChange: true,
              painter: _WaveformPainter(
                amps: _amps,
                windowStart: start,
                windowLen: len,
                center: center,
                duration: widget.duration,
                pointA: widget.pointA,
                pointB: widget.pointB,
                left: _drawLeft,
                right: _drawRight,
                strokeWidth: strokeW.toDouble(),
                tickHeight: _tickHeight,
                mode: _mode,
              ),
            ),
          ),
        );
      },
    );
  }
}

// =====================================================================
// 绘制
// =====================================================================

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.amps,
    required this.windowStart,
    required this.windowLen,
    required this.center,
    required this.duration,
    required this.left,
    required this.right,
    required this.strokeWidth,
    required this.tickHeight,
    required this.mode,
    this.pointA,
    this.pointB,
  });

  /// 全曲逐列归一化振幅（0~1），**每根柱子对应固定的 1/20 秒**，
  /// 画在它真实的时间位置上 —— 这样滚动时是整体平移，不是柱子原地变形。
  final List<double> amps;

  /// 窗口左边缘（秒）、窗口时长（秒）、窗口中心（= 播放位置，秒）
  final double windowStart;
  final double windowLen;
  final double center;

  /// 音频总时长（秒）：用来判定窗口越出轨道两端的那段空白
  final double duration;

  final double? pointA;
  final double? pointB;
  final double left;
  final double right;
  final double strokeWidth;

  /// 顶部刻度行高度（波形从它下方开始）
  final double tickHeight;

  final _GestureMode mode;

  static const Color _played = Color(0xFF4A7EB8);
  static const Color _unplayed = Color(0xFF5B8FC9);
  static const Color _gold = Color(0xFFE8A33D);

  /// 秒刻度文字缓存（key = 显示文本，样式固定）。
  ///
  /// 为什么需要：位置流改成 60fps 后，就算波形不发糊，绘色仍是每秒 60 次，
  /// 而 `TextPainter.layout()` 是纯 CPU 的文本排版；6 个刻度标签 = 每秒 360 次
  /// 重复排版，低端机上直接吃掉几毫秒。缓存后每个标签只排版一次。
  /// 上限 512 个：1 小时音频也只有 3600 个不同标签，超了整体清空重来即可。
  static final Map<String, TextPainter> _tickLabelCache =
      <String, TextPainter>{};

  static TextPainter _tickLabel(String text) {
    final TextPainter? cached = _tickLabelCache[text];
    if (cached != null) return cached;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 9,
          color: Colors.black.withValues(alpha: 0.42),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (_tickLabelCache.length > 512) _tickLabelCache.clear();
    _tickLabelCache[text] = tp;
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = right - left;
    if (w <= 0 || windowLen <= 0) return;

    final double waveTop = tickHeight;
    final double waveH = size.height - tickHeight;
    if (waveH <= 6) return;

    final double midY = waveTop + waveH / 2;
    final double halfH = waveH / 2 - 8;

    /// 时间 → x（窗口内），超出则钳制
    double xOf(double seconds) =>
        left + ((seconds - windowStart) / windowLen).clamp(0.0, 1.0) * w;

    // ---- 0. 顶部整秒刻度行 ----
    _paintTicks(canvas, xOf, size);

    // ---- 0.5 轨道之外（曲首之前 / 曲末之后）：淡灰底 ----
    // 居中模型下窗口会让出两端，这段没有数据。若什么都不画，会像「波形断了」；
    // 铺一层极淡的灰，语义就变成「这里还没有音频」。
    final double zeroX = xOf(0);
    final double endX = xOf(duration);
    final Paint outsidePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.035);
    if (zeroX > left) {
      canvas.drawRect(
        Rect.fromLTRB(left, waveTop, zeroX, size.height),
        outsidePaint,
      );
    }
    if (endX < right) {
      canvas.drawRect(
        Rect.fromLTRB(endX, waveTop, right, size.height),
        outsidePaint,
      );
    }

    // ---- 1. AB 区间淡蓝底（裁到窗口内）----
    final double? ax = pointA == null ? null : xOf(pointA!);
    final double? bx = pointB == null ? null : xOf(pointB!);
    if (ax != null && bx != null && bx > ax) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(left, waveTop, right, size.height));
      canvas.drawRect(
        Rect.fromLTRB(ax, waveTop + 2, bx, size.height - 2),
        Paint()..color = _played.withValues(alpha: 0.10),
      );
      canvas.restore();
    }

    // ---- 2. 波形柱：播放头左侧算「已播」，右侧算「未播」----
    //
    // v2.3 画法（关键改动）：每根柱代表固定的 1/20 秒，按**它自己的时间**算 x。
    // 因此窗口滑动时整排柱子一起平移（真正的「流动」），柱高保持不变 ——
    // 旧写法是「固定 x + 每帧重采样高度」，柱子会原地抽搐、滚动时一片糊。
    // 逐列振幅已预先算好（_prepareAmps），这里只遍历可见列，不访问波形数据。
    final double playX = xOf(center);
    if (amps.isNotEmpty && duration > 0 && windowLen > 0) {
      final double pps = amps.length / duration; // 实际列密度（≈ 20 列/秒）
      if (pps > 0) {
        final Path playedPath = Path();
        final Path restPath = Path();
        final double scaleX = w / windowLen; // 秒 → 像素

        int i0 = (windowStart * pps).floor();
        int i1 = ((windowStart + windowLen) * pps).ceil();
        if (i0 < 0) i0 = 0;
        if (i1 > amps.length) i1 = amps.length;

        for (int i = i0; i < i1; i++) {
          final double t = (i + 0.5) / pps;
          // 轨外（曲首之前 / 曲末之后）不画柱：那里已经铺了淡灰底，
          // 再画 1px 兜底线会让人误以为「这段是静音」。
          if (t < 0 || t > duration) continue;
          // ⚠ 不要取整到整数像素（v2.4 改动，踩过坑）：
          // 竖线间距是 3.58px（6 秒 / 430px / 20 列每秒）这种非整数，一旦每根线
          // 各自 `round()`，间距就变成 3px/4px 交替，而且小数部分不同的线会在
          // **不同帧**上跳格（这根这帧跳、那根下帧跳）—— 整块波形看起来像在
          // 互相挤压、抖动，看久了发晕。
          // 保持小数坐标 = 所有线共享同一个亚像素位移，间距恒定、整体平移，
          // 每帧移动量完全一致。代价是边缘有半像素抗锯齿，但手机 DPR≥2.5，
          // 折算到物理像素不到 1px，几乎看不出来；换来的是真正平滑的滚动。
          final double x = left + (t - windowStart) * scaleX;
          if (x < left - 1 || x > right + 1) continue;
          // 最小 1px：音频内的静音段也要留一条细线，否则看起来像「波形缺了一块」
          double amp = amps[i] * halfH;
          if (amp < 1) amp = 1;
          final Path target = x <= playX ? playedPath : restPath;
          target.moveTo(x, midY - amp);
          target.lineTo(x, midY + amp);
        }
        final Paint stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt; // 平头：细竖线上下端更干净
        canvas.drawPath(
          restPath,
          stroke..color = _unplayed.withValues(alpha: 0.38),
        );
        canvas.drawPath(
          playedPath,
          stroke..color = _played.withValues(alpha: 0.85),
        );
      }
    }

    // ---- 3. 播放头：固定竖线 + 顶端小圆点 ----
    // 居中模型下它平时就在屏幕中央；只有轨道最前/最后 3 秒会被边界推开。
    canvas.drawLine(
      Offset(playX, waveTop + 2),
      Offset(playX, size.height - 4),
      Paint()
        ..color = _played
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(playX, waveTop + 2), 3, Paint()..color = _played);

    // ---- 4. A / B 金色手柄：窗口内的画手柄，窗口外的画边缘小箭头 ----
    if (pointA != null) _paintHandleOrArrow(canvas, pointA!, xOf, size, 'A');
    if (pointB != null) _paintHandleOrArrow(canvas, pointB!, xOf, size, 'B');

    // ---- 5. 拖手柄时浮出时间气泡（0.1 秒精度；拨动时不显示）----
    if (mode == _GestureMode.pointA && pointA != null) {
      _paintBubble(canvas, xOf(pointA!), pointA!, size.width, waveTop);
    } else if (mode == _GestureMode.pointB && pointB != null) {
      _paintBubble(canvas, xOf(pointB!), pointB!, size.width, waveTop);
    }
  }

  /// 整秒刻度：窗口内每个整秒一条短竖线 + 时间文字。
  /// 6 秒窗口约 6 个刻度，间距 60~70px，写 `m:ss` 不会挤。
  void _paintTicks(Canvas canvas, double Function(double) xOf, Size size) {
    final double end = windowStart + windowLen;
    final int first = windowStart.ceil();
    final int last = end.floor();

    final Paint tick = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;

    for (int s = first; s <= last; s++) {
      // 窗口越出轨道两端时会算出 -2、-1 这种「负秒」和曲末之后的刻度：
      // 它们对应的是空白区，标上去反而让人以为那里有音频
      if (s < 0 || s > duration) continue;
      final double x = xOf(s.toDouble());
      canvas.drawLine(Offset(x, 10), Offset(x, 16), tick);

      final TextPainter tp = _tickLabel(_fmt(s.toDouble()));
      // 贴边时把文字往里推，避免被裁掉一半
      final double tx = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(tx, 0));
    }
  }

  /// 手柄在窗口内 → 正常竖条 + 字母标签；在窗口外 → 边缘小三角提示
  void _paintHandleOrArrow(
    Canvas canvas,
    double seconds,
    double Function(double) xOf,
    Size size,
    String label,
  ) {
    final bool inside =
        seconds >= windowStart && seconds <= windowStart + windowLen;
    if (inside) {
      _paintHandle(canvas, xOf(seconds), size.height, label, tickHeight);
      return;
    }

    // 窗口外：在对应一侧画一个 5px 金色小三角，告诉你「A/B 在那边」
    final bool isLeft = seconds < windowStart;
    final double x = isLeft ? left + 1 : right - 1;
    final double y = tickHeight + (size.height - tickHeight) / 2;
    final Path p = Path();
    const double s = 5;
    if (isLeft) {
      p.moveTo(x, y);
      p.lineTo(x + s, y - s);
      p.lineTo(x + s, y + s);
    } else {
      p.moveTo(x, y);
      p.lineTo(x - s, y - s);
      p.lineTo(x - s, y + s);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = _gold.withValues(alpha: 0.85));
  }

  /// 手柄：金色竖条 + 顶部小圆角标签（写 A / B，肉眼一眼分得清）
  void _paintHandle(
    Canvas canvas,
    double x,
    double height,
    String label,
    double top,
  ) {
    final Paint bar = Paint()
      ..color = _gold
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, top + 14), Offset(x, height - 6), bar);

    final RRect cap = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, top + 9), width: 18, height: 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(cap, Paint()..color = _gold);

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width / 2, top + 9 - tp.height / 2));
  }

  /// 时间气泡（m:ss.t），左右钳制在控件内，避免贴边时被裁掉
  void _paintBubble(
    Canvas canvas,
    double x,
    double seconds,
    double width,
    double top,
  ) {
    const double bw = 46;
    const double bh = 18;
    final double bx = (x - bw / 2).clamp(0.0, width - bw).toDouble();

    final RRect r = RRect.fromRectAndRadius(
      Rect.fromLTWH(bx, top + 1, bw, bh),
      const Radius.circular(9),
    );
    canvas.drawRRect(r, Paint()..color = _gold.withValues(alpha: 0.92));

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: _fmt(seconds, tenths: true),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(bx + (bw - tp.width) / 2, top + 1 + (bh - tp.height) / 2),
    );
  }

  /// 时间格式：刻度行用 `m:ss`，气泡用 `m:ss.t`（带 0.1 秒）
  String _fmt(double seconds, {bool tenths = false}) {
    final int total = seconds.floor();
    final int m = total ~/ 60;
    final int s = total % 60;
    final String base = '$m:${s.toString().padLeft(2, '0')}';
    if (!tenths) return base;
    final int t = ((seconds - total) * 10).round().clamp(0, 9);
    return '$base.$t';
  }

  @override
  bool shouldRepaint(_WaveformPainter old) {
    // 只比真正影响画面的字段：居中模型下 center 每帧都在变，这里必须便宜
    return !identical(old.amps, amps) ||
        old.center != center ||
        old.windowStart != windowStart ||
        old.windowLen != windowLen ||
        old.duration != duration ||
        old.pointA != pointA ||
        old.pointB != pointB ||
        old.left != left ||
        old.right != right ||
        old.strokeWidth != strokeWidth ||
        old.tickHeight != tickHeight ||
        old.mode != mode;
  }
}
