// =====================================================================
// 波形提取服务（F12 播放页时域图的数据层）
// ---------------------------------------------------------------------
// 这一层干什么：把一个音视频文件的「振幅包络」算出来，给界面画波形。
// 界面只管「传路径、收进度、拿 Waveform」，不关心缓存、解码、平台差异。
//
// 三条硬约束（设计时定的，改代码前先读一遍）：
//   1. 只支持 Android / iOS：just_waveform 没有 Windows 实现，桌面端必须
//      先问 isSupported，否则调用会抛 MissingPluginException。
//   2. 先写 .tmp 再改名：插件没有取消接口，用户中途退出时原生线程仍在写文件。
//      直接写最终文件会留下半成品，下次被当成有效缓存读进来（波形错乱或解析崩溃）。
//   3. 缓存 key 不能用 String.hashCode：Dart 不保证跨进程稳定，
//      重启后全部失效，等于每次进播放页都要重新提取一遍。
//
// 语言：Dart。不做播放、不做界面。
//
// ⚠ 第 4 条约束（2026-10-28 实测踩坑）：**不要用 JustWaveform.parse()**。
// 0.0.7 的实现里写的是 `Int16List.view(bytes, headerLength ~/ 2)`，
// 但 Dart 里这个参数是「字节偏移」，不是「int16 元素个数」，
// 于是数据区被从第 10 字节开始读（正确是第 20 字节），整体错位 2.5 个像素，
// 大量列出现「最小值 > 最大值」，画出来是一条平线。
// 因此本文件自己实现 _parseWave()：手动读 20 字节头 + 正确偏移取 min/max。
// =====================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';

/// 提取进度回调：0.0 → 1.0
typedef WaveformProgressHandler = void Function(double progress);

/// 一次正在跑的提取。
///
/// 为什么需要它：用户可能在提取没完成时退出再进（或连点重试），
/// 此时若再发起一次提取，插件内部以「输出文件路径」为 key 存回调，
/// 后一次会覆盖前一次，两个回调都可能收不到结果。
/// 所以同一文件只跑一次解码，后来的调用「搭车」共享同一个 Future。
class _RunningExtraction {
  _RunningExtraction(WaveformProgressHandler firstListener) {
    listeners.add(firstListener);
  }

  /// 所有关心这次提取的进度回调（页面可能已经销毁，回调里自己判断 mounted）
  final List<WaveformProgressHandler> listeners = <WaveformProgressHandler>[];

  /// 最新的进度值（搭车者一进来就能先看到当前进度，不会从 0 开始跳）
  double progress = 0.0;

  /// 提取结果（拿到数据则为 Waveform，失败为 null）
  Future<Waveform?>? future;
}

/// 波形数据服务（纯静态，随用随取，不需要实例）
class WaveformService {
  WaveformService._(); // 私有构造：这是个工具类，不该被 new 出来

  /// 提取精度：每秒 20 列。
  ///
  /// 为什么是 20（2026-10-28 拍板，对标一心复读机）：把它的截图按刻度量了一遍——
  /// 满屏约 5~6 秒、秒与秒之间约 20 根细竖线，即「每秒 20 列、线距约 3.5~4px」。
  /// 这个密度肉眼已足够看清音节轮廓，且每根线都是清晰的独立竖线；
  /// 而我们之前用的 100 列/秒，6 秒窗口铺满屏后每根柱不足 1px（亚像素），
  /// 抗锯齿糊成一团，提取和缓存体积也白白大 5 倍（大音频卡顿的主因之一）。
  /// 数据量对比：1 小时音频 ≈ 7.2 万列、约 288KB（100 列/秒时要 36 万列、1.4MB）。
  static const int zoomPps = 20;

  /// 传给插件的精度对象（与 [zoomPps] 必须一致，不要各写一处）
  static const WaveformZoom _zoom = WaveformZoom.pixelsPerSecond(zoomPps);

  /// 进度多久不动就判定原生卡死（插件没有取消接口，只能自己收摊）
  static const Duration _stallLimit = Duration(seconds: 25);

  /// 临时文件最长保留时间：超过就认为是被遗弃的半成品，进页面时清掉
  static const Duration _tmpMaxAge = Duration(hours: 1);

  /// 正在跑的提取，key = 缓存文件名
  static final Map<String, _RunningExtraction> _running =
      <String, _RunningExtraction>{};

  /// 临时文件是否已清理过（每个进程只扫一次目录，别每次进页面都遍历）
  static bool _tmpCleaned = false;

  /// 当前平台能不能做波形
  ///
  /// Windows / Linux / macOS 一律 false：对应的原生实现不存在，
  /// 界面据此隐藏波形区（不是「失败」，是「这台设备没有这个能力」）。
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// 取这条素材的波形数据。
  ///
  /// [filePath] 素材的本地绝对路径（导入时已复制进 App 私有目录）。
  /// [onProgress] 进度回调，0→1；缓存命中时会直接给一次 1.0。
  /// [force] 忽略已有缓存，重新提取（「重试」按钮用）。
  ///
  /// 返回 null 表示：平台不支持 / 文件不存在 / 提取失败（调用方显示失败态）。
  static Future<Waveform?> obtain({
    required String filePath,
    required WaveformProgressHandler onProgress,
    bool force = false,
  }) async {
    if (!isSupported) return null;

    final File audio = File(filePath);
    if (!await audio.exists()) return null;

    final String key = await _cacheKey(audio);
    final Directory dir = await _cacheDir();
    final String sep = Platform.pathSeparator;
    final File target = File('${dir.path}$sep$key.wave'); // 最终缓存
    final File tmp = File('${dir.path}$sep$key.tmp'); // 提取中的半成品

    // —— 重试：先把旧缓存和残留都扔掉，逼后面走真正的提取 ——
    if (force) {
      await _safeDelete(target);
      await _safeDelete(tmp);
    } else if (await target.exists()) {
      // —— 缓存命中：解析 .wave（毫秒级），这是「退出再进秒开」的关键 ——
      final Waveform? cached = await _parseCached(target);
      if (cached != null) {
        _notify(onProgress, 1.0);
        return cached;
      }
      // 解析失败（文件损坏/太短）已在 _parseCached 里删掉了，继续往下走提取
    }

    // —— 已有同一次提取在跑：搭车，不再启动第二次解码 ——
    final _RunningExtraction? running = _running[key];
    if (running != null) {
      running.listeners.add(onProgress);
      _notify(onProgress, running.progress); // 先把当前进度告诉新来的
      final Future<Waveform?>? shared = running.future;
      if (shared == null) return null;
      return shared;
    }

    await _cleanupTmp(dir);

    final _RunningExtraction entry = _RunningExtraction(onProgress);
    _running[key] = entry;
    entry.future = _runExtraction(
      audio: audio,
      tmp: tmp,
      target: target,
      entry: entry,
    );
    try {
      return await entry.future;
    } finally {
      // 无论成功失败都要从表里摘掉，否则失败后重试会一直拿到那个 null
      _running.remove(key);
    }
  }

  /// 清空全部波形缓存（留给以后的「清理缓存」入口，目前界面没接）
  static Future<void> clearCache() async {
    try {
      final Directory dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
      _tmpCleaned = false;
    } catch (_) {
      // 清缓存失败不影响使用，静默
    }
  }

  // ------------------------------------------------------------------
  // 内部实现
  // ------------------------------------------------------------------

  /// 真正驱动一次原生提取，把进度派发给所有搭车的人。
  static Future<Waveform?> _runExtraction({
    required File audio,
    required File tmp,
    required File target,
    required _RunningExtraction entry,
  }) {
    final Completer<Waveform?> done = Completer<Waveform?>();
    StreamSubscription<WaveformProgress>? sub;
    Timer? stall;

    // 收摊：停计时器 + 只完成一次（重复 complete 会抛 StateError）
    void settle(Waveform? value) {
      stall?.cancel();
      stall = null;
      if (!done.isCompleted) done.complete(value);
    }

    // 进度看门狗：插件没有取消接口，原生若卡住，Dart 侧只能放弃等待
    void armStall() {
      stall?.cancel();
      stall = Timer(_stallLimit, () async {
        await sub?.cancel();
        await _safeDelete(tmp); // 半成品删掉，避免下次被当缓存
        settle(null);
      });
    }

    sub =
        JustWaveform.extract(
          audioInFile: audio,
          waveOutFile: tmp,
          zoom: _zoom,
        ).listen(
          (WaveformProgress p) {
            armStall(); // 有进展就重置看门狗
            _publish(entry, p.progress);

            // 只看进度，**不用 p.waveform**：它也是用有 bug 的 parse 解析出来的。
            // 到 100% 时自己把 tmp 解析一遍，拿到的才是正确数据。
            if (p.progress < 1.0) return;

            unawaited(() async {
              await sub?.cancel();
              await _promote(tmp, target); // tmp → .wave（原子落盘）
              final Waveform? w = await _parseWave(target);
              if (w == null) {
                await _safeDelete(target); // 解析不出 = 文件无效，别留成“缓存”
                settle(null);
                return;
              }
              settle(w);
            }());
          },
          onError: (Object error, StackTrace stack) async {
            // 格式解不了、文件损坏等：删半成品，交给界面显示「提取失败 · 重试」
            await sub?.cancel();
            await _safeDelete(tmp);
            settle(null);
          },
          // 流结束但没收到 100%（极短文件会走这里）：兜底解析一次 tmp
          onDone: () {
            unawaited(() async {
              if (done.isCompleted) return;
              final Waveform? w = await _parseWave(tmp);
              if (w == null) {
                await _safeDelete(tmp);
                settle(null);
                return;
              }
              await _promote(tmp, target);
              settle(w);
            }());
          },
          cancelOnError: true,
        );
    armStall();

    return done.future;
  }

  /// 把结果派发给所有监听者。
  /// 拷贝一份再遍历：某个回调里如果又触发了新提取，直接遍历原表会并发修改报错。
  static void _publish(_RunningExtraction entry, double progress) {
    entry.progress = progress;
    for (final WaveformProgressHandler h in List<WaveformProgressHandler>.of(
      entry.listeners,
    )) {
      _notify(h, progress);
    }
  }

  /// 回调里包一层 try：界面销毁后回调还在飞，抛异常不该连累提取流程
  static void _notify(WaveformProgressHandler handler, double progress) {
    try {
      handler(progress.clamp(0.0, 1.0).toDouble());
    } catch (_) {
      // 忽略界面层的异常
    }
  }

  /// tmp → 最终文件。同目录 rename 是原子的，中途断电也不会留下半个 .wave
  static Future<void> _promote(File tmp, File target) async {
    try {
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    } catch (_) {
      // 极端情况（跨卷、权限）改不了名：退化为复制，保证最终文件有效
      try {
        await tmp.copy(target.path);
        await _safeDelete(tmp);
      } catch (_) {
        // 到此确实存不下，settle(null) 由调用处处理
      }
    }
  }

  /// 解析缓存文件；坏文件顺手删掉（只删自己目录里的派生数据，不碰素材本体）
  static Future<Waveform?> _parseCached(File file) async {
    final Waveform? w = await _parseWave(file);
    if (w == null) {
      // 文件太短（几乎无音频）/ 损坏 / 半成品：删掉，让调用方重新提取
      await _safeDelete(file);
    }
    return w;
  }

  /// 自己解析 audiowaveform 格式的 .wave 文件（**不要用 JustWaveform.parse**）
  ///
  /// 文件结构（小端）：
  ///   [0..20)  头：version / flags / sampleRate / samplesPerPixel / length（各 4 字节 int32）
  ///   [20..)   数据：每列两个值（min, max），16 位时各占 2 字节，8 位时各占 1 字节
  ///
  /// 插件自带的 parse 把「int16 元素偏移」当成字节偏移传了，导致整体错位 10 字节，
  /// 画出来是一条平线。这里用正确偏移 20 字节自己读，顺带支持 8 位（flags bit0 = 1）。
  static Future<Waveform?> _parseWave(File file) async {
    try {
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length < 20) return null;

      final ByteData bd = ByteData.sublistView(bytes);
      final int version = bd.getInt32(0, Endian.little);
      final int flags = bd.getInt32(4, Endian.little);
      final int sampleRate = bd.getInt32(8, Endian.little);
      final int samplesPerPixel = bd.getInt32(12, Endian.little);
      final int length = bd.getInt32(16, Endian.little);

      // 头字段不合法（半成品文件常见全 0）→ 当作坏缓存
      if (length <= 0 || sampleRate <= 0 || samplesPerPixel <= 0) return null;

      final bool eightBit = (flags & 1) == 1;
      final int count = length * 2; // 每列 min + max 两个值
      final int need = 20 + count * (eightBit ? 1 : 2);
      // 数据不完整 = 写一半被打断，宁可判坏也不要画出错位波形
      if (bytes.length < need) return null;

      final List<int> data = eightBit
          ? Int8List.sublistView(bytes, 20, need)
          : Int16List.sublistView(bytes, 20, need);

      return Waveform(
        version: version,
        flags: flags,
        sampleRate: sampleRate,
        samplesPerPixel: samplesPerPixel,
        length: length,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }

  /// 缓存 key：文件路径 + 大小 + 修改时间 + 提取精度。
  ///
  /// 前三者任一变化都会生成新 key（同名文件被替换 / 重新导入都能自动失效）。
  /// **精度也必须进 key**：否则把精度从 10 提到 100 之后，手机上那份旧的
  /// 10 列/秒缓存会被当成新数据直接用，波形成了一屏 6 秒就只剩 60 列，
  /// 而且永远自愈不了（缓存一直命中）。带上精度后旧缓存自动作废，
  /// 重进播放页会重新提取一次（几秒）。
  static Future<String> _cacheKey(File audio) async {
    final FileStat stat = await audio.stat();
    return _fnv1a64(
      '${audio.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}'
      '|z$zoomPps',
    );
  }

  /// FNV-1a 64 位哈希，转成 16 进制字符串当文件名。
  ///
  /// 为什么不用 String.hashCode：Dart 只保证同一次运行内稳定，
  /// 跨进程可能变，重启后缓存会全部失效（等于每次都要重新提取）。
  static String _fnv1a64(String input) {
    // 0xcbf29ce484222325 的有符号表示（Dart 的 int 是 64 位补码）
    int hash = -3750763034362895579;
    const int prime = 1099511628211;
    for (final int byte in utf8.encode(input)) {
      hash ^= byte;
      hash *= prime; // 64 位溢出自动回绕，正是 FNV 需要的行为
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  /// 波形缓存目录：App 私有支持目录下的 `waveforms/`
  /// 放 AppSupport 而不是 Documents：这是派生数据，不该出现在用户可见的文档区。
  static Future<Directory> _cacheDir() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}waveforms',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 清理被遗弃的 .tmp（用户提取中途退出留下的）。每个进程只扫一次。
  static Future<void> _cleanupTmp(Directory dir) async {
    if (_tmpCleaned) return;
    _tmpCleaned = true;
    try {
      final DateTime now = DateTime.now();
      await for (final FileSystemEntity e in dir.list()) {
        if (e is! File || !e.path.endsWith('.tmp')) continue;
        final FileStat stat = await e.stat();
        if (now.difference(stat.modified) > _tmpMaxAge) {
          await _safeDelete(e);
        }
      }
    } catch (_) {
      // 清理失败不影响主流程
    }
  }

  /// 删文件不抛异常（文件可能正被原生线程持有，删不掉就算了）
  static Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 忽略
    }
  }
}
