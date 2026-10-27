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
  static const Color teal = Color(0xFF2BC8B7);

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

      // 4. 确保 CloudBase 初始化 + 匿名登录
      await TcbService.ensureReady();

      // 5. 直传云存储（桶内 key 不含桶名，桶名由 TcbService 统一加）
      final String key =
          '${widget.classId}/${DateTime.now().millisecondsSinceEpoch}_${pf.name}';
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
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0,
        title: const Text('班级文件', style: TextStyle(fontSize: 17)),
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
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const CircularProgressIndicator(color: teal),
                    const SizedBox(height: 12),
                    Text(
                      _uploading ? '正在上传…' : '正在下载…',
                      style: const TextStyle(fontSize: 14),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: teal));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF999999))),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: teal),
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_files.isEmpty) {
      return const Center(
        child: Text('这个班还没有文件', style: TextStyle(color: Color(0xFF999999))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _files.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final ClassFile f = _files[index];
        return _fileCard(f);
      },
    );
  }

  /// 单个文件卡片：类型图标 + 标题 + 大小·格式；点击 = 下载播放
  Widget _fileCard(ClassFile f) {
    return InkWell(
      onTap: () => _downloadAndPlay(f),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            // 类型图标：视频/音频不同
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: f.isVideo ? const Color(0xFF8FB8D8) : teal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                f.isVideo ? Icons.movie_outlined : Icons.audiotrack,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
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
                        fontSize: 15,
                        color: Color(0xFF333333),
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [f.sizeLabel, f.format?.toUpperCase() ?? '']
                        .where((String s) => s.isNotEmpty)
                        .join(' · '),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
            // 下载/播放图标
            const Icon(Icons.play_circle_outline,
                size: 24, color: Color(0xFFBBBBBB)),
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
