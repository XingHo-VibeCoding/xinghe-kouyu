# 星禾口语 · 后端接口契约（api-contract）

> 版本：v0.3（Day 23，班级文件上传下载 + 多老师模型落地）｜ 状态：班级管理核心接口均已落地，仅文件「下载」走前端直连（见 3.4 说明）
> 配套：`backend/functions/`（云函数代码）｜ 上游：PRD.md 3.6、TECH_DESIGN.md 第 6 节

本文档是「前端页面」和「后端云函数」之间的约定。两边各自开发时，都以这份文档为准，
避免「前端以为回这个、后端实际回那个」的对不上。

> **定位说明（重要）**：本契约里的接口，服务于「**跨用户共享数据**」的功能——即
> **班级管理**（老师建班发文件、学生加入下载）。**纯本地播放器阶段（导入音频、本地播放、
> AB 复读、文件夹整理）不需要任何后端接口**——这些逻辑全在前端（App 内）完成。
>
> 第 2 节的 `/api/health` 是「打通云端链路」的第一块砖（Day 15 已落地）；第 3 节为
> 班级管理接口（Day 20 起规划，逐步落地）。

---

## 1. 通用约定（所有接口都必须遵守）

### 1.1 响应统一结构

所有接口的响应体，都是一个 JSON 对象，**固定三件套**：

```json
{
  "code": 0,
  "message": "ok",
  "data": { }
}
```

| 字段 | 类型 | 含义 |
|---|---|---|
| `code` | number | 返回码。**0 = 成功**，非 0 = 出错。前端拿到先看它，一眼判断成没成 |
| `message` | string | 给人看的状态说明。成功时通常 `"ok"`，失败时是具体原因（如「文件夹名重复」） |
| `data` | object | 业务数据。成功时放实际内容，失败时可省略或为 `{}` |

**约定**：判断成败一律看 `code`，**不要**用 HTTP 状态码来判断（某些云函数网关对非 2xx 的
处理不一致，容易误判）。业务成功但返回 HTTP 200 + `code: 0`；业务失败也尽量返回 HTTP 200 +
`code: 非0`，把「错在哪」写进 `message`。

### 1.2 基础信息

- **服务名**：`xinghe-kouyu-api`（出现在 `/api/health` 的 `data.service` 里，用于标识这是哪个后端）
- **环境 ID**：`xinghe-kouyu-d7gi1d7ttc7e032ba`（Day 15 注册）
- **基础域名**：`https://xinghe-kouyu-d7gi1d7ttc7e032ba-1501128141.ap-shanghai.app.tcloudbase.com`
- **API 前缀**：`/api`（所有业务接口都挂在 `/api/` 下，与健康检查同前缀）

---

## 2. 已落地接口

### 2.1 `GET /api/health` —— 健康检查

**用途**：验证「云端这条路是通的」。前端（或任何人）访问它，返回一段 JSON 证明后端在正常应答。

**请求**：
- 方法：`GET`
- 地址：`https://xinghe-kouyu-d7gi1d7ttc7e032ba-1501128141.ap-shanghai.app.tcloudbase.com/api/health`
- 参数：无

**响应示例**：

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "service": "xinghe-kouyu-api",
    "health": "ok",
    "time": "2026-10-06T14:05:05.616Z"
  }
}
```

**字段说明**：

| 字段 | 含义 |
|---|---|
| `data.service` | 服务名，标识这是「星禾口语」的后端 |
| `data.health` | 健康状态，固定 `"ok"` |
| `data.time` | 当前时间（ISO 8601）。**每次刷新都会变**，用来证明这是实时响应、不是缓存死数据 |

**验收判定**：`code === 0`，且连续两次请求的 `data.time` 不同。

---

## 3. 班级管理接口（Day 20 起规划，Day 23 核心接口已落地）

> 这些接口依赖 TECH_DESIGN 6.1 的云端四表（users/classes/class_members/class_files），
> 字段结构以那节为准。已落地的接口在下方 3.1~3.4 有响应示例和字段表。

| 接口 | 方法 | 用途 | 状态 |
|---|---|---|---|
| `/api/users` | POST | 首次进入：登记昵称 + 角色（老师/学生） | 已落地 |
| `/api/classes` | POST | 老师建班（生成 uuid + 唯一班级码，老师入成员） | 已落地 |
| `/api/classes/join` | POST | 按班级码加入班级（学生/老师均可，按本人身份写入角色，支持多老师） | 已落地 |
| `/api/classes` | GET | 当前用户的班级列表（含所有老师昵称，多老师用「、」拼接） | 已落地 |
| `/api/classes/members` | GET | 某班成员列表（`?class_id=xxx`） | 已落地 |
| `/api/classes/files` | GET | 某班文件列表（`?class_id=xxx`） | 已落地 |
| `/api/classes/files` | POST | 上传文件记元数据（本体进云存储，元数据写 class_files） | 已落地 |
| 文件下载 | — | 前端直连 `get-objects-download-info` 拿签名 URL（不走云函数），见 3.4 | 已落地 |

### 3.1 `GET /api/classes/members` —— 某班成员列表

**用途**：查看某个班级有哪些成员（老师 + 学生），含各自昵称和班内角色。

**请求**：
- 方法：`GET`
- 地址：`/api/classes/members?class_id=<班级id>`
- 参数：`class_id`（必填，班级 id，即建班时返回的 uuid，不是 6 位班级码）

**响应示例**：

```json
{
  "code": 0,
  "message": "ok",
  "data": [
    { "user_id": "dev-uid-teacher-01", "nickname": "王老师", "role": "teacher", "joined_at": "..." },
    { "user_id": "dev-uid-student-01", "nickname": "小明", "role": "student", "joined_at": "..." }
  ]
}
```

**字段说明**：

| 字段 | 含义 |
|---|---|
| `user_id` | 成员 uid |
| `nickname` | 成员昵称（拼自 users 表，可能为 null） |
| `role` | 该成员在班内的角色（`teacher`/`student`） |
| `joined_at` | 加入时间 |

**验收判定**：`code === 0`，且 `data` 是数组，每项含上面四个字段。

### 3.2 `POST /api/classes/files` —— 上传文件记元数据

**用途**：文件本体已直传云存储后，把「文件信息」登记进 class_files 表（账本）。

**请求**：
- 方法：`POST`
- 地址：`/api/classes/files`
- 请求体（JSON）：

```json
{
  "class_id": "<班级id>",
  "title": "第1课 跟读",
  "cloud_path": "cloud://envId.xxx/class-files/xxx.mp3",
  "size": 2048000,
  "format": "mp3",
  "uploader_id": "<上传者uid>"
}
```

**字段说明**：

| 字段 | 必填 | 含义 |
|---|---|---|
| `class_id` | 是 | 所属班级 id |
| `title` | 是 | 展示名 |
| `cloud_path` | 是 | 云存储的 fileID（SDK 直传返回的 `cloud://...`） |
| `size` | 否 | 字节数 |
| `format` | 否 | 文件格式（mp3/mp4 等） |
| `uploader_id` | 是 | 上传者 uid |

**响应**：`code=0` 时 `data` 是插入后的文件记录。

**验收判定**：`code === 0`，且数据库 class_files 表多一行。

### 3.3 `GET /api/classes/files` —— 某班文件列表

**用途**：查某班的文件元数据列表（学生下载前先看这个）。

**请求**：
- 方法：`GET`
- 地址：`/api/classes/files?class_id=<班级id>`

**响应示例**：

```json
{
  "code": 0,
  "message": "ok",
  "data": [
    { "id": "uuid", "title": "第1课 跟读", "cloud_path": "cloud://...", "size": 2048000, "format": "mp3", "uploader_id": "...", "created_at": "..." }
  ]
}
```

**验收判定**：`code === 0`，`data` 是数组，按创建时间倒序。

### 3.4 文件下载（前端直连，不走云函数）

**用途**：学生点文件后，前端拿临时签名 URL 下载文件本体。

**实现方式**：前端直接调 CloudBase 存储 HTTP API（不经过本项目云函数）：

1. `POST /v1/storages/get-objects-download-info`（网关）
   - 请求体：`[{"cloudObjectId": "<带桶ID的fileID>"}]`
   - 注意：cloudObjectId 必须带「桶 ID 后缀」，格式 `cloud://envId.<桶ID>/桶/key`；
     数据库 class_files.cloud_path 存的是 `cloud://envId/桶/key`（缺后缀），前端做字符串转换补上。
2. 用返回的 `downloadUrl`（带签名）直接 `GET`/`dio.download` 下载文件到本地。

**下载后的去向**：文件落 App 私有目录 `materials/`，并注册进本地 sqflite（`materials` 表，
归属「班级下载」文件夹），之后由本地播放器统一处理（离线可用）。

**验收判定**：学生点文件 → 下载成功 → 播放器「班级下载」文件夹里出现该文件、可播放。

**实现时的要求**（提前写在这里，避免返工）：
1. 每个接口的响应都要遵守第 1 节的 `code/message/data` 三件套；
2. 写接口（POST/PUT/DELETE）必须有明确的 `message`，失败时把原因写清楚（如「班级码不存在」「已加入该班级」）；
3. 接口路径、方法、字段一经定稿，要**同步更新本文档**，前端和后端都以文档为准；
4. 匿名登录必带 `x-device-id` 请求头（缺了网关报 400），token 用匿名登录换取。

---

## 4. 已知边界与待办

- **跨域 CORS**：前端调后端时的跨域配置按计划完成（附录 M「HTTP 访问服务 → 跨域 CORS 配置」）。
- **认证**：MVP 用 CloudBase 匿名登录（领临时通行证）；真用户登录（手机号/微信）后置，届时只改「发证柜台」（`getToken()` 调哪个登录接口），查表逻辑、表结构、前端调用方式不变。
- **数据权限（RLS）**：当前 4 张表未开 RLS（学习期可接受）；上线前必须开 RLS 并限制/关闭匿名登录。
