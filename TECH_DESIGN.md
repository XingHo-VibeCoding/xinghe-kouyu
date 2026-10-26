# 星禾口语 · 技术设计（TECH_DESIGN）

> 版本：v4.0（Day 20，新增班级管理 MVP 的技术方案：CloudBase 后端 + 四表数据模型 + 离线优先同步）｜ 上游文档：PRD.md、api-contract.md｜ 范围：Day 7 MVP「一心复读机 promax」+ Day 20 班级管理 MVP
>
> **v4.0 变更记录**：产品进入「离线优先双状态」阶段。原 v3.0 是纯本地（无后端）；本版新增后端——CloudBase（SQL 基础数据库 + 云存储 + 匿名登录 + HTTP API 网关），用于班级管理。播放器（F1–F9）仍是纯本地、无后端，两者边界清晰。

## 1. 技术路线

**选定：Flutter 独立 App + sqflite 本地数据库**

两句话：
- **形态**：以 Flutter 构建的**原生 App**（安卓为当前验收平台），打包成 `.apk` 安装，点图标启动，断网可用，用起来就是一个独立应用；
- **存储**：素材导入时**复制一份**进 App 私有目录（`path_provider` 定位），元数据、文件夹结构、播放位置全部存 **sqflite（SQLite）**，播放、整理不依赖原文件位置。

### 为什么这样选

1. **「手机端为主、电脑端兼容」**：Flutter 一套 Dart 代码通吃安卓/iOS（本期以安卓真机验收，与目标用户场景一致）。
2. **「独立 App 形态」**：原生 App 自带图标、全屏启动、无浏览器痕迹，是真正的独立应用，体验优于 PWA。
3. **「统一复制 + 本地库」**：素材复制进私有目录，元数据落 SQLite，一套逻辑通吃多端；离线优先（local-first），数据永远先落本地，联网同步是将来班级管理阶段才加的事。

### 技术栈

| 用途 | 选型 |
|---|---|
| 状态管理 | Provider |
| 导航 | Navigator 栈式导航 |
| 本地数据库 | sqflite（SQLite） |
| 音频播放 | just_audio |
| 视频播放 | video_player |
| 文件选择 | file_picker |
| 文件路径 | path_provider + path |

### 已知代价与风险备案

| 代价 / 风险 | 说明 | 应对 |
|---|---|---|
| 桌面端（Windows）跑不了 | sqflite 在 Windows 需 ff i 版（sqflite_common_ffi），其 sqlite3 依赖会去 GitHub 下载被墙 | 本阶段只在安卓真机验收；桌面端列为待办 |
| 大视频导入等待 | 复制需要时间，视频越大越久 | 导入时显示进度提示；音频文件小，不受影响 |
| 存储容量 | 手机存储有限 | 素材以老师发的一段段音频为主，量级可控 |

## 2. 前后端与数据库分工

| 角色 | 本项目的安排 | 说明 |
|---|---|---|
| 前端 | **星禾口语应用（Dart 代码）** | 播放器（素材导入、文件夹管理、播放/变速/AB 复读、位置记忆）纯本地；班级管理（列表/详情/下载）调后端云函数 |
| 后端 | **CloudBase（Day 20 新增）** | 班级管理的数据中枢：SQL 基础数据库（存班级/成员/文件元数据）+ 云存储（存文件本体）+ 匿名登录（发通行证）+ HTTP API 网关（PostgREST 查表） |
| 应用存储 | **sqflite（SQLite）本地数据库** | 存三样：素材元数据、文件夹结构、播放位置；班级文件下载后也注册进本地库 |
| 云端存储 | **CloudBase SQL 数据库 + 云存储** | 班级/成员/文件元数据落 SQL；音视频文件本体落云存储 |

**这个分工的直接后果**：
- A8「断网全功能可用」对**播放器**成立；班级管理是有网才有、没网降级隐藏，两者互不拖累；
- 班级管理需要后端，是因为「老师发文件」是**跨用户共享**——数据必须汇到云端一处，这不是播放器阶段能解决的，正是 Day 20 引入后端的技术根源。

## 3. 数据流

![数据流图](data-flow.svg)

**一句话说清数据从哪来、到哪去**：数据从「老师发来的本地音视频文件」来，导入时复制一份进 App 私有目录，此后只在您的设备里流转（整理、播放、记进度），最后以画面和声音回到您的眼睛和耳朵——**全程不出网**。

## 4. 关键技术点

- **Provider 状态管理**：素材仓库等共享状态挂在应用顶层，各页面统一读写；
- **sqflite**：本地 SQLite 数据库，存素材元数据、文件夹树、播放位置（`materials.last_position`）；
- **just_audio / video_player**：音频、视频播放，变速用 `setSpeed` / `setPlaybackSpeed`，AB 循环靠监听播放位置 + `seek`；
- **file_picker**：系统文件选择器，替代浏览器的文件选择；
- **离线优先**：无需服务器计算能力，纯本地运行。

## 5. 后期升级路径（本期不做，仅记录方向）

- 桌面端打包：sqflite 的 Windows 版依赖 sqlite3 下载被墙，需另找方案后再支持；
- 多端同步 / 班级管理：需要引入后端（届时同步修订本文件与 PRD 不做清单）。

## 6. 班级管理 MVP 技术方案（Day 20 新增）

### 6.1 云端四表数据模型

> 建在 CloudBase「SQL 基础数据库」的 public schema，通过 HTTP API 网关（PostgREST）访问。字段为 MVP 最小集，后续可扩展。

**① `users`（用户）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | text PK | 匿名登录返回的 uid（设备标识，非真用户身份） |
| `nickname` | text | 昵称（首次进入填写） |
| `role` | text | `teacher` / `student` |

**② `classes`（班级）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | text PK | 班级 id（uuid） |
| `name` | text | 班级名 |
| `code` | text UNIQUE | 班级码（加入凭证，唯一） |
| `teacher_id` | text | 建班老师 uid（外键 users.id） |
| `created_at` | timestamp | 建班时间 |

**③ `class_members`（班级成员）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | serial PK | 自增 |
| `class_id` | text | 班级 id（外键） |
| `user_id` | text | 成员 uid（外键） |
| `role` | text | 该成员在班内的角色（`teacher`/`student`） |
| `joined_at` | timestamp | 加入时间 |

> 唯一约束：`(class_id, user_id)`，防重复加入。

**④ `class_files`（班级文件元数据）**

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | text PK | 文件记录 id（uuid） |
| `class_id` | text | 所属班级（外键） |
| `title` | text | 展示名 |
| `cloud_path` | text | 云存储里的文件路径（下载凭证来源） |
| `size` | bigint | 字节数 |
| `format` | text | mp3/mp4 等 |
| `uploader_id` | text | 上传者 uid |
| `created_at` | timestamp | 上传时间 |

### 6.2 云函数（接口清单）

> 对应 api-contract.md，走 HTTP API 网关（PostgREST），Bearer token 鉴权，匿名登录必带 `x-device-id` 头。详见 api-contract 第 3 节。

| 功能 | 说明 |
|---|---|
| 建班 | 生成 uuid + 唯一班级码 → 写 `classes` + 老师入 `class_members` |
| 加入班级 | 按班级码查 `classes` → 校验 → 写 `class_members` |
| 班级列表 | 按当前用户查其 `class_members` → 联查 `classes` |
| 班级成员 | 查某班全部 `class_members` → 联查 `users` |
| 上传文件 | 文件本体传云存储，元数据写 `class_files` |
| 班级文件列表 | 查某班 `class_files` |
| 下载凭证 | 按 `cloud_path` 换取云存储临时下载 URL |

### 6.3 离线优先同步策略

- **本地为主、云端同步**：班级文件下载后落本地 `materials/` + 注册进 sqflite，此后播放走本地（离线可用，对应 A13）。
- **联网监听**：用 `connectivity_plus` 监听有网/没网，据此显示/隐藏「班级」入口。
- **同步时机**：有网时拉班级/文件列表；下载文件是显式动作，不自动全量同步（省流量、可控）。
- **已知难点（后置，本期不做）**：本地改动与云端同时变更的冲突合并（如打卡重复提交）。

### 6.4 新增技术栈

| 用途 | 选型 |
|---|---|
| 联网监听 | connectivity_plus |
| HTTP 请求 | dio（或 http） |
| 匿名登录 / 鉴权 | CloudBase 匿名登录（换 token） |
| 云存储上传下载 | CloudBase 存储 SDK / 临时 URL |
