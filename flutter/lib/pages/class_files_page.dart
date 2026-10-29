// =====================================================================
// 页面「班级文件」：某班的文件列表（班级管理 MVP）
// ---------------------------------------------------------------------
// 从「班级详情页」的「课件」宫格点进来，调后端 /classes/files 接口，
// 展示这个班的文件（图标 + 标题 + 大小 + 格式）。
//
// 四种状态：加载中 / 空 / 出错（可重试）/ 有数据。
// 说明：本页只做「看文件列表」；下载播放属后续步骤（需云存储临时 URL）。
// =====================================================================

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/class_file.dart';
import '../net/api_client.dart';
import '../net/tcb_service.dart';
import '../store/material_store.dart';
import '../store/user_store.dart';
import '../utils/design_tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/skeleton_list.dart';

class ClassFilesPage extends StatefulWidget {
  final String classId;
  final String className;

  const ClassFilesPage({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassFilesPage> createState() => _ClassFilesPageState();
}

class _ClassFilesPageState extends State<ClassFilesPage> {
  // 品牌青绿（学在重邮同款）
  

  bool _loading = true;
  String? _error;
  List<ClassFile> _files = <ClassFile>[];
  bool _uploading = false; // 是否正在上传
  bool _downloading = false; // 是否正在下载

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 调后端查文件列表
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ApiClient api = context.read<ApiClient>();
    final ApiResult<List<ClassFile>> result = await api.classFiles(widget.classId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _files = result.data!;
      } else {
        _error = result.message;
      }
    });
  }

  /// 上传主流程：选文件 → SDK 直传云存储 → 拿 fileID → 写元数据 → 刷新列表
  Future<void> _pickAndUpload() async {
    final UserStore userStore = context.read<UserStore>();

    // 1. 选文件（FileType.media = 音频+视频都放行，不靠扩展名白名单，
    //    避免 Android 上某些机型把 mkv 等格式漏掉导致选不到）
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      type: FileType.media,
    );
    if (picked.isEmpty) return; // 用户取消
    final PlatformFile pf = picked.first;

    // 2. 上传中状态
    setState(() => _uploading = true);
    try {
      // 3. 读文件字节（13.x 用 readAsBytes()，不再有 bytes 属性）
      final Uint8List bytes = await pf.readAsBytes();

      // 4. 上传内部会向 SDK 会话要鉴权 token（未登录会抛「请先登录」）
      //    （Day 24 改造：不再有独立的匿名登录预热步骤）

      // 5. 直传云存储（桶内 key 不含桶名，桶名由 TcbService 统一加）
      //    key = "可读时间_原文件名"：时间部分用于防同名覆盖（同班先后传
      //    同名文件，没前缀会互相覆盖），格式化成年月日-时分，控制台一眼可读
      final DateTime now = DateTime.now();
      final String stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
      final String key = '${widget.classId}/${stamp}_${pf.name}';
      final String contentType =
          _contentTypeOf(pf.extension?.toLowerCase() ?? 'bin');
      final String fileId =
          await TcbService.uploadBytes(key, bytes, contentType: contentType);
      if (!mounted) return;

      // 7. 写元数据进 class_files 表（走后端云函数）
      final ApiClient api = context.read<ApiClient>();
      final result = await api.addClassFile(
        classId: widget.classId,
        title: pf.name,
        cloudPath: fileId,
        size: bytes.length,
        format: pf.extension?.toLowerCase(),
        uploaderId: userStore.uid,
      );
      if (!result.ok) {
        throw Exception(result.message);
      }

      // 8. 成功：刷新列表
      if (!mounted) return;
      _toast('上传成功');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast('上传失败：$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 补零：把 1~9 的数字变成 "01"~"09"（拼时间戳用）
  String _two(int n) => n.toString().padLeft(2, '0');

  /// 按扩展名给 COS 一个正确的 Content-Type
  String _contentTypeOf(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/x-wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
        return 'audio/ogg';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'application/octet-stream';
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // watch 用户身份：老师才显示上传入口
    final UserStore userStore = context.watch<UserStore>();
    final bool isTeacher = userStore.role == UserRole.teacher;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kTextPrimary,
        elevation: 0,
        title: const Text('班级文件', style: TextStyle(fontSize: kFontTitle)),
        // 上传入口：仅老师可见
        actions: <Widget>[
          if (isTeacher)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: '上传文件',
              onPressed: _uploading ? null : _pickAndUpload,
            ),
        ],
      ),
      // 上传/下载中遮罩提示
      body: Stack(
        children: <Widget>[
          _buildBody(),
          if (_uploading || _downloading)
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(kSpaceLG),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(kRadiusSM),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(color: kTeal),
                    const SizedBox(height: kSpaceSM),
                    Text(
                      _uploading ? '正在上传…' : '正在下载…',
                      style: const TextStyle(fontSize: kFontBody),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final Widget child;
    final String stateKey;
    if (_loading) {
      child = const SkeletonList();
      stateKey = 'loading';
    } else if (_error != null) {
      child = ErrorState(message: _error!, onRetry: _load);
      stateKey = 'error';
    } else if (_files.isEmpty) {
      child = const EmptyState(
        icon: Icons.insert_drive_file_outlined,
        title: '这个班还没有文件',
        description: '老师上传课件后，这里会显示文件列表。',
      );
      stateKey = 'empty';
    } else {
      child = ListView.separated(
        padding: const EdgeInsets.all(kSpaceSM),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: kSpaceXS),
        itemBuilder: (BuildContext context, int index) {
          final ClassFile f = _files[index];
          return _fileCard(f);
        },
      );
      stateKey = 'data';
    }
    // AnimatedSwitcher 让四态切换淡入淡出（动效·第三批 B1）；KeyedSubtree 用状态 key 触发过渡
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }

  /// 单个文件卡片：类型图标 + 标题 + 大小·格式；点击 = 下载播放
  Widget _fileCard(ClassFile f) {
    return InkWell(
      onTap: () => _downloadAndPlay(f),
      borderRadius: BorderRadius.circular(kRadiusCard),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: kSpaceSM, vertical: kSpaceSM),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(kRadiusCard),
          border: kCardBorder,
          boxShadow: kShadowSm,
        ),
        child: Row(
          children: <Widget>[
            // 类型图标：视频/音频不同
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: f.isVideo ? kTextSecondary : kTeal,
                borderRadius: BorderRadius.circular(kRadiusSM),
              ),
              child: Icon(
                f.isVideo ? Icons.movie_outlined : Icons.audiotrack,
                color: Colors.white,
                size: kIconMD,
              ),
            ),
            const SizedBox(width: kSpaceSM),
            // 标题 + 大小·格式
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    f.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: kFontTitle,
                        color: kTextPrimary,
                        fontWeight: kWeightMedium),
                  ),
                  const SizedBox(height: kSpaceXXS),
                  Text(
                    [f.sizeLabel, f.format?.toUpperCase() ?? '']
                        .where((String s) => s.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                        fontSize: kFontCaption, color: kTextHint),
                  ),
                ],
              ),
            ),
            // 下载/播放图标
            const Icon(Icons.play_circle_outline,
                size: kIconMD, color: kTextHint),
          ],
        ),
      ),
    );
  }

  /// 下载文件：下载到本地素材库并注册成素材（方案 B，供播放器统一处理）
  Future<void> _downloadAndPlay(ClassFile f) async {
    setState(() => _downloading = true);
    try {
      // 1. 拿临时下载 URL
      final String url = await TcbService.getDownloadUrl(f.cloudPath);
      if (!mounted) return;

      // 2. 下载 + 注册进本地素材库（复用 MaterialStore 的现成落库逻辑）
      final MaterialStore store = context.read<MaterialStore>();
      await store.downloadClassFile(
        title: f.title,
        format: f.format ?? '',
        downloadUrl: url,
      );

      if (!mounted) return;
      _toast('已下载到本地素材库（文件夹：班级下载）');
    } catch (e) {
      if (!mounted) return;
      _toast('下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}
