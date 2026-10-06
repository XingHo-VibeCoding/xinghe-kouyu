# 星禾口语 · Flutter 版技术选型（TECH_STACK.md）

> 版本：v1.0（Day 13）｜ 上游文档：PRD.md v1.2、TECH_DESIGN.md v2.0（PWA 版，由本文件接续）
> 背景：产品从 PWA 迁移为 Flutter 独立 App（Day 6 拍板 → Day 12 环境跑通 → Day 13 建项目）。

## 1. 产品形态与边界

- **纯本地 App**：无账号、无上传、无广告；断网全部可用（对应 PRD 验收 A8）。
- **MVP 阶段没有后端、没有服务器数据库**。素材只存用户设备，数据不出设备。
- 未来做「班级管理 / 老师直发音频 / 打卡汇报 / 实时字幕」时才需要后端（触发条件见第 4 节）。

## 2. 技术栈总表

| 层 | 选型 | 用途 / 理由 |
|---|---|---|
| App 框架 | Flutter (Dart) | 一码打包安卓 + 未来 iOS/桌面；已拍板替代 PWA |
| 状态管理 | Provider | 状态规模中等、概念少、资料多；一个人开发够用到最终版，不换 Riverpod |
| 页面导航 | Navigator（栈式 push/pop） | 贴近手机 App 交互，天然支持返回上一页 |
| 结构化存储 | sqflite（SQLite） | 文件夹树、素材元数据、播放位置 |
| 大文件存储 | App 私有目录（沙盒） | 音视频本体存文件，数据库只存引用 |
| 轻量配置 | shared_preferences | 排序方式、变速倍率等零散设置（**后续接入**） |
| 音频播放 | just_audio | 变速、循环、AB 段支持全（**后续接入**） |
| 视频播放 | video_player | Flutter 官方插件（**后续接入**） |
| 文件选择 | file_picker | 替代 PWA 的文件/文件夹选择 |
| 后端 | 无（MVP） | 见第 1 节 |
| Android 包名 | applicationId = `com.xinghe.kouyu` | 装机唯一标识；代码 namespace 保持 `com.xinghe.xinghe_kouyu`，两者允许不同 |

## 3. 与 PWA 版的关系

**同一个产品、两套实现，是重写不是移植**：

| PWA 里的东西 | Flutter 里的对应物 |
|---|---|
| IndexedDB / localStorage | sqflite + App 沙盒文件 + shared_preferences |
| `<audio>` / `<video>` | just_audio / video_player |
| `<input type=file>` / webkitdirectory | file_picker |
| 三段式界面（顶栏 / 左树右列 / 底部播放条） | 照搬 PWA 已验证的布局方案 |
| 四态设计（骨架屏/空/错误/数据） | 照搬 PWA main-view 已验证的方案 |

## 4. 什么时候才需要后端（触发条件备忘）

| 功能 | 需要引入的东西 |
|---|---|
| 班级管理、老师直发音频 | 账号体系 + 服务器 + 推送 |
| AB 段打卡评分、汇报老师 | 后端存储 + 评分引擎 |
| 实时字幕 + 人数统计 | 语音识别 + 后端统计 |
| AI 提取高频表达 | AI 接口 + 成本控制 |

## 5. 目录结构（当前阶段）

```
flutter/
├── lib/
│   ├── main.dart                     # 入口：挂 Provider + 主题 + 首页
│   ├── models/
│   │   └── material_item.dart        # 素材条目模型
│   ├── store/
│   │   └── material_store.dart       # 素材仓库（四态状态机 + SQLite 数据访问）
│   └── pages/
│       ├── material_list_page.dart   # 页面1 素材列表（四态主展示页）
│       ├── folder_manage_page.dart   # 页面2 文件夹管理（壳）
│       └── player_page.dart          # 页面3 播放页（壳）
└── TECH_STACK.md                     # 本文件
```

## 6. 版本记录

- v1.0（2026-09-30）：建项目；定 Provider / Navigator / sqflite 等选型；壳工程（3 页面 + 四态）。
- v1.1（2026-10-02）：接入 sqflite 真实存储 + file_picker 导入 + 文件夹管理真实化。
