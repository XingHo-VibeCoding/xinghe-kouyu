# 星禾口语（Flutter 版）

老师发的音视频，整理好慢慢听。无广告的本地复读工具。

> 当前阶段：**壳工程**——三个页面骨架 + Navigator 切换 + 素材列表四态（模拟数据）。
> 真实导入 / 播放 / 存储将在后续版本逐步接入。

## 怎么运行

```powershell
cd D:\develop\Projects\workBuddy\vibeCoding\flutter
flutter pub get
flutter run
```

- 手机用数据线连接电脑并打开「USB 调试」后，`flutter run` 会直接装到手机上
- 也可以 `flutter build apk --debug` 生成安装包手动安装

## 技术选型

见 [TECH_STACK.md](TECH_STACK.md)。简版：Flutter + Provider（状态）+ Navigator（导航）+ sqflite（存储，待接入）+ just_audio / video_player（播放，待接入）；MVP 无后端。

## 当前页面

1. **素材列表**（首页）：空 / 加载中 / 出错 / 有数据 四种状态；底部「状态预览条」可手动切换（开发用，上线前删）
2. **文件夹管理**：文件夹树壳界面（AppBar 返回箭头 = 返回上一页）
3. **播放页**：播放控制布局壳界面，点素材列表某条进入
