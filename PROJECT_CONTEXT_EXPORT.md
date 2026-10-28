# 星禾口语 · 项目关键上下文导出（供新任务导入）

> 用途：上下文过长时，把本文件整段复制到新任务的对话开头，让新会话无缝接续项目，不割裂。
> 导出时间：2026-10-28（Day 23 收尾后）。
> 重要：下面「协作规则」部分决定了 AI 必须以什么方式配合你，务必保留，不要删。

---

## 一、协作规则（最重要，决定 AI 怎么配合你）

来源：项目根目录 `AGENTS.md`（完整原文请以该文件为准，这里给速记）。核心约束：

1. **任务边界**：每天的任务范围 = 你当天发来的「今日任务清单」。清单外的事一律不做，想做也要先问。不提前做以后的天数。
2. **交互式推进**：收到清单后先给执行计划、停下等你确认；确认后**一次只做一个步骤**，做完停下等你回复「进入下一板块」才继续。绝不连着往下做。
3. **人机分工**：需要你人工操作的（点按钮、注册、截图、部署云函数、控制台配桶/RLS）不代做、不假装完成，只给操作指引；需要生成的内容等你说「开始」再生成；要拍板的地方列选项给你选。
4. **讲清楚环节**：你是来学习的。每步用「做了什么 → 结果 → 为什么」讲明白；术语/报错一两句话解释；先类比后术语；配图优于纯文字；忌堆术语忌长文。
5. **Git**：提交前先列改动文件清单等你确认；commit 格式 `Day X｜一句话说明`；密钥/`.env`/连接串永不提交；一天做完才提交（中途不边做边提交）。
6. **当日收尾**：你说「今天做完了」，AI 输出「完成标准 / 状态 / 证据」三列表格，诚实标注未完项。
7. **出问题时**：撤销只用 `git revert`，禁止 `git reset --hard` 和强制推送；同一操作反复失败要停下来报告，不循环重试。
8. **追加规则（Day 6 起）**：①任何新功能先改 PRD 再写代码；②重大方向调整走「摆选项→拍板→改文档→确认提交」完整流程；③每天安卓手机和电脑各测一遍；④追加/改规则前 AI 先复述旧规则全文；⑤代码注释全用中文；⑥代码放 `my-app` 文件夹（注意：Flutter 版在 `flutter/`，这条是 PWA 时代的规则）；⑦每次改完代码提醒刷新浏览器看效果。

## 二、项目定位（产品层，务必记牢）

- **项目名：星禾口语**（工作区目录叫 `vibeCoding`，两者是「项目名/目录名」关系）。
- **定位**：老师音频的**播放/复读工具**，不是 AI 口语陪练。目标用户 = 有老师带、老师发音频的口语学习者；对标/痛点来源 =「一心复读机」（文件管理乱、收费、VIP 广告多）。
- Day 7 MVP =「一心复读机 promax」：原复读功能 + 好用的文件夹管理 + 无广告。
- 远期想法：班级管理（老师直发结构化音频）、同屏老师提示词、AB 段打卡评分、实时字幕、AI 提取高频表达。
- **产品方向已拍板（2026-10-08）：必须做班级管理**，形态为「离线优先双状态 App」。

## 三、技术路线（架构层，务必记牢）

- **Flutter 独立 App**（Day 13 定，覆盖早期 PWA 决定）。代码在仓库 `flutter/` 目录，项目名 `xinghe_kouyu`，applicationId `com.xinghe.kouyu`。
- 技术栈：Provider（状态）+ Navigator 栈式导航 + sqflite（本地存储）+ just_audio/video_player（播放）+ file_picker（导入）+ dio（网络）+ cloudbase_flutter（云服务 SDK，仅用其 auth 部分）。
- `my-app/` 是早期 PWA 版（F1–F7 完整），作为 Flutter 版的界面与交互参照，不再主力开发。
- 后端：腾讯 CloudBase 云函数（`backend/functions/`）+ CloudBase「SQL 基础数据库」（共享型 PostgreSQL）+ CloudBase 云存储。

### 离线优先原则（决定数据层方向，务必遵守）
- **数据永远先落本地（sqflite），联网时再和云端同步；没网就纯用本地。**「本地是主、云端是同步」，不是「云端是主、本地是缓存」。
- 实现分层：①sqflite 主力（离线根基）②connectivity_plus 监听有网/没网、据此显示/隐藏「班级」入口 ③同步层有网时拉云推本、没网跳过。
- 已知远期难点：数据同步冲突（离线改本地 + 云端同时被改如何合并），暂不解决，记着即可。

### 底层认知（用户已悟透，别跑偏）
- 业务逻辑无天然归属：数据不出本设备 → 前端；要跨设备/要保密 → 后端。
- App 里只有前端，后端必须单独部署云端；App 绝不直连数据库（连接串写进 App = 把钥匙给每个用户），必须有云函数挡中间。
- 「形态（App/网页）」≠「联网（本地/云端）」：加班级管理是从「本地 App」变「联网 App」，形态不变。

## 四、CloudBase 后端关键结论（Day 17/23 踩坑定案，写后端必看）

- **数据库走 HTTP API（PostgREST 网关）**，不直连：`https://<envId>.api.tcloudbasegateway.com/v1/rdb/rest/:表名`，Bearer token 鉴权，**只支持 public schema 表**。共享集群不给连接地址，`pg` 直连是死路。代价：**不支持手写 JOIN**，拆两次查询 + 代码拼接。
- 三要素：①环境变量 `ENV_ID` ②匿名登录必填头 `x-device-id` ③表名 + PostgREST 过滤语法（`?select=&order=&xxx=eq.yyy`）。
- 环境 ID：`xinghe-kouyu-d7gi1d7ttc7e032ba`；region `ap-shanghai`。
- 身份：当前用**匿名登录**（PublishableKey）。坑：匿名登录控制台「身份认证→身份源」默认关闭，要手动开；缺 `x-device-id` 头报 400。将来换真用户登录只改「发证柜台」，查表逻辑/ENV_ID/表结构/前端调用全不变。
- **上线前安全清单（现在裸奔，学习期可接受）**：①限制/关闭匿名登录 ②4 张表 + storage.objects 开 RLS。

### 云存储（PG 桶模型，直传必看，Day 23 踩深坑）
- 桶名 = objectId 第一段；桶需**控制台手动建**（本项目桶名 `class-files`）。
- RLS 在 `storage.objects` 上配 `CREATE POLICY`（默认全拒）；本项目已配 public_select / public_insert 两条策略，允许 anon/authenticated 对 `class-files` 桶读写。
- **官方 Flutter SDK `cloudbase_flutter` 1.2.3 的 storage 不支持 PG 桶模型**（不带 `signedHeader`、无 bucket 参数），只有 auth 部分可用。上传/下载都**自封装走 HTTP**。
- **直传上传**：`get-objects-upload-info` 请求体**必须带 `signedHeader`** = `{"content-length":["<字节数>"],"content-type":["<mime>"]}`（数组值），缺了报 `STORAGE_CONTENT_LENGTH_REQUIRED`。拿到 uploadUrl/authorization/token 后，PUT 文件字节到 uploadUrl（带 `Authorization` + `x-cos-security-token`）。
- **下载**：`get-objects-download-info` 请求体 = `[{"cloudObjectId":"<带桶ID后缀的fileID>"}]`。**桶 ID 后缀是坑**：账本存的 cloud_path 是 `cloud://envId/path`（缺后缀），下载时要转成 `cloud://envId.<桶ID>/path`。桶 ID 固定 = `7869-xinghe-kouyu-d7gi1d7ttc7e032ba-1501128141`。
- 前端封装在 `flutter/lib/net/tcb_service.dart`（`uploadBytes` / `getDownloadUrl` / `ensureReady`）。

## 五、数据库表结构（4 张表，public schema）

- `users`：id(uuid) / nickname / role(teacher|student) / ...
- `classes`：id(uuid) / name / code(唯一班级码) / teacher_id(已降级为「创建者」记录) / ...
- `class_members`：class_id / user_id / role / joined_at，唯一约束 (class_id, user_id)。**老师 = 此表里 role=teacher 的所有成员，可有多个**。
- `class_files`：id(uuid) / class_id / title / cloud_path(存 fileID) / size / format / uploader_id / created_at。

后端接口全部在 `backend/functions/classes/index.js`（一个云函数 `classes` 内路由分发）。

## 六、已落地接口（api-contract.md 为准）

- `POST /api/users` 登记昵称+角色
- `POST /api/classes` 建班（生成 uuid + 唯一班级码，老师入成员）
- `POST /api/classes/join` 按班级码加入（**老师/学生均可**，按本人身份写 role，支持多老师）
- `GET /api/classes?uid=xxx` 我的班级列表（teacher_name 已改为「所有老师昵称顿号拼接」）
- `GET /api/classes/members?class_id=xxx` 成员列表
- `GET /api/classes/files?class_id=xxx` 文件列表
- `POST /api/classes/files` 上传文件记元数据（body: class_id/title/cloud_path/size/format/uploader_id）

## 七、当前进度与文件地图（Day 23 结束点）

**已完成的完整闭环**：老师上传文件 → 直传云存储 → 记元数据 → 学生点文件下载 → 落本地素材库（`materials/` + sqflite）→ 切「播放」栏 → 「班级下载」文件夹里播放。

### 前端关键文件（`flutter/lib/`）
- `pages/home_shell.dart`：底部导航 4 栏（首页 / 班级 / **播放** / 我的）。第三栏已从「作业」换成「播放」（原素材列表页 MaterialListPage）。
- `pages/home_page.dart`：首页（问候语按身份显示称谓 + 扫码/签到卡 + 最近访问 + 待办占位）。
- `pages/class_list_page.dart`：班级列表（「+」弹面板：创建班级仅老师可见；加入班级老师学生都可用）。
- `pages/class_detail_page.dart`：班级详情（宫格：班级成员/课件等已接真实跳转）。
- `pages/class_members_page.dart`：成员列表。
- `pages/class_files_page.dart`：文件列表 + 上传（仅老师可见按钮）+ 下载。
- `pages/material_list_page.dart`：播放器（素材列表，含文件夹管理）。
- `pages/profile_page.dart`：我的（昵称/角色登记）。
- `net/tcb_service.dart`：CloudBase 封装（初始化+匿名登录+直传上传+下载URL）。
- `net/api_client.dart`：后端接口封装。
- `store/user_store.dart` / `class_store.dart` / `material_store.dart`：状态 + 本地数据。
- `utils/design_tokens.dart`：设计令牌（颜色/字阶/圆角/阴影）。
- `models/`：class_item / class_member / class_file / material_item 等。

### UI 视觉升级（Day 23 刚做完，已提交）
方向 Playful×Refined：青绿主色 `#2BC8B7` 不变 + 珊瑚橙强调 `#FF7A59`（仅关键动作）+ 暖白背景 `#F7FAF9`（取代死灰）+ 卡片淡青描边 + 三级阴影 + 四级字阶（24/16/14/12）+ 底部导航选中态青绿胶囊。所有颜色/字号走 `design_tokens.dart`，不要硬编码颜色。

## 八、环境备忘（Windows 本机实测）

- 用户在 **Windows PowerShell** 执行命令（非 cmd）。
- **坑 1**：PowerShell 执行策略禁止 `.ps1` → 直接敲 `npm` 报 PSSecurityException，用 `npm.cmd`。
- **坑 2**：Git 选项是双横线（`--version` 不是 `-version`）。
- **坑 3**：不要在 Windows 写含中文的 `.ps1` 临时脚本执行（PowerShell 5.1 把无 BOM UTF-8 当 ANSI 读，必失败）。
- 全局 git 身份：`user.name=CQbfz`、`user.email=2183178212@qq.com`；分支 `main`。
- 工具环境：Bash 工具偶尔 PATH 异常，可行做法是用 PowerShell + `Set-Content` 到临时文件再 Read。
- **代理**：git push 走 `127.0.0.1:59010`，推 GitHub 前需开代理（否则超时）。当前 remote 已能正常 push。
- Flutter SDK 版本约 3.13/3.47；`file_picker` 是 **13.x**（API 已改：静态 `FilePicker.pickFiles()` 返回 `List<PlatformFile>`，字节用 `await readAsBytes()`）。

## 九、已踩的坑速查（别再踩）

1. **API Key 类型**：绝不用 `service_role`（is_system_admin=true 的万能钥匙），前端要用 **PublishableKey**（role=anon）。
2. **SDK storage 不支持 PG 桶** → 自封装 HTTP + signedHeader。
3. **下载要桶 ID 后缀**（`cloud://envId.<桶ID>/path`）。
4. **just_audio 不支持 Windows 桌面**（MissingPluginException）→ 平台判断，桌面端只下载不播。
5. **file_picker 13.x** API 大改。
6. **Container 无 decoration 不能带 clipBehavior**（崩溃）→ 用 Material 提供背景。
7. **ListTile 被带色 DecoratedBox 包住会吞水波纹**（警告）→ 用 Material。
8. **uid 竞态**：用户身份（匿名 uid）存本地，重装 App 会丢、生成新 uid（设备维度身份，换设备/重装就丢）→ 测试期尽量用热重载别反复重装。

## 十、下一步方向（Day 24+ 候选，未定，需你拍板）

1. **视频播放**：现在只通了音频，mp4/mkv 还没接 video_player。
2. **完整播放体验**：把下载的班级文件接到完整播放器（AB 复读、变速、进度条）。
3. **安全加固**：真用户登录（微信/手机号）+ RLS 全开（多老师模型放开后，匿名裸奔风险更突出，建议尽早）。
4. **数据同步**：离线优先的云端同步层（connectivity_plus + 同步），以及打卡等功能。
5. **视频文件上传优化**：大文件当前走「读进内存再传」，后续可改流式。

---

## 附：Git 提交历史（近期）

- `59befc7` Day 22｜成员列表接口 + uid 竞态修复
- `fc33d9a` Day 23｜班级文件上传下载全链路 + 下载落本地素材库 + 多老师模型
- `a765a28` Day 23｜全站 UI 视觉升级 + 同步 PRD
