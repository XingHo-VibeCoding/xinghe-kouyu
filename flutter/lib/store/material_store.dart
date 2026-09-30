// 素材仓库：全局共享的列表状态（Provider 模式的核心类）
// 当前阶段用「模拟加载」演示四态；以后接真实存储（sqflite）时只改这里，页面不用动

import 'package:flutter/foundation.dart';

import '../models/material_item.dart';

/// 列表的四种状态：加载中 / 空 / 错误 / 正常有数据
/// 用一个枚举表达互斥状态，比多个 bool 组合更不容易出错
enum ListStatus { loading, empty, error, data }

/// 素材仓库：页面通过 Provider 读写这里的 status / items / errorMessage
class MaterialStore extends ChangeNotifier {
  ListStatus _status = ListStatus.loading;
  ListStatus get status => _status;

  final List<MaterialItem> _items = <MaterialItem>[];
  List<MaterialItem> get items => List.unmodifiable(_items);

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  /// 加载素材列表（模拟异步读取数据库）
  /// [demoMode] 是演示开关：'data' 正常 / 'empty' 空 / 'error' 出错
  /// 以后接真实存储时，去掉 demoMode，换成真实读取
  Future<void> load({String demoMode = 'data'}) async {
    _status = ListStatus.loading; // 先进入「加载中」
    notifyListeners();

    // 模拟读取耗时 1 秒，让「加载中」状态肉眼可见
    await Future.delayed(const Duration(seconds: 1));

    switch (demoMode) {
      case 'error':
        _errorMessage = '模拟错误：素材数据库暂时打不开（这是演示，不是真的坏了）';
        _status = ListStatus.error;
      case 'empty':
        _items.clear();
        _status = ListStatus.empty;
      default:
        _items
          ..clear()
          ..addAll(fakeItems);
        _status = ListStatus.data;
    }
    notifyListeners();
  }

  /// 【开发用】直接把状态拨到某一档（不模拟加载耗时），配合底部状态预览条逐个截图
  void preview(ListStatus target) {
    _status = target;
    switch (target) {
      case ListStatus.data:
        if (_items.isEmpty) _items.addAll(fakeItems);
      case ListStatus.error:
        if (_errorMessage.isEmpty) {
          _errorMessage = '模拟错误：素材数据库暂时打不开（这是演示，不是真的坏了）';
        }
      case ListStatus.empty:
        _items.clear();
      case ListStatus.loading:
        break; // 加载中不需要额外数据
    }
    notifyListeners();
  }

  /// 演示用假数据：思路同原 PWA 的 mock-data.js，内容对齐 Day 12 的示例音频库
  static const List<MaterialItem> fakeItems = <MaterialItem>[
    MaterialItem(id: '1', title: 'Lesson 01 打招呼', folder: '基础口语', format: 'mp3', duration: '02:35'),
    MaterialItem(id: '2', title: 'Lesson 02 自我介绍', folder: '基础口语', format: 'mp3', duration: '03:12'),
    MaterialItem(id: '3', title: '餐厅点餐对话', folder: '场景对话', format: 'm4a', duration: '04:08'),
    MaterialItem(id: '4', title: '机场值机对话', folder: '场景对话', format: 'm4a', duration: '05:21'),
    MaterialItem(id: '5', title: '商务会议开场白', folder: '职场英语', format: 'mp3', duration: '06:47'),
    MaterialItem(id: '6', title: '邮件写作模板讲解', folder: '职场英语', format: 'wav', duration: '08:03'),
    MaterialItem(id: '7', title: '发音示范 - 元音', folder: '发音练习', format: 'wav', duration: '01:45'),
    MaterialItem(id: '8', title: '发音示范 - 辅音', folder: '发音练习', format: 'wav', duration: '02:10'),
    MaterialItem(id: '9', title: '每日新闻速览 0912', folder: '泛听', format: 'mp4', duration: '03:30'),
    MaterialItem(id: '10', title: '演讲片段 - TED', folder: '泛听', format: 'mov', duration: '07:55'),
  ];
}
