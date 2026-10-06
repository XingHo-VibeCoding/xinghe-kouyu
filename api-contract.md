# 星禾口语 · 后端接口契约（api-contract）

> 版本：v0.1（Day 15）｜ 状态：仅 `/api/health` 已落地，其余为规划占位
> 配套：`backend/functions/`（云函数代码）｜ 上游：PRD.md、FEATURE_REVIEW.md

本文档是「前端页面」和「后端云函数」之间的约定。两边各自开发时，都以这份文档为准，
避免「前端以为回这个、后端实际回那个」的对不上。

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

## 3. 后续接口规划（Day 16–20 落地，当前未实现）

> 这些接口依赖 Day 16 的数据库建表，字段结构要到建表后才能定死，这里先立名字和用途，
> 避免后续各写各的。状态统一为「规划中」，实现时再回填响应示例和字段表。

| 接口 | 方法 | 用途 | 状态 |
|---|---|---|---|
| `/api/materials` | GET | 拉取素材列表（供前端展示） | 规划中（Day 17） |
| `/api/materials/:id` | GET | 拉取单条素材详情 | 规划中（Day 17） |
| `/api/folders` | GET | 拉取文件夹列表 | 规划中（Day 17） |
| `/api/folders` | POST | 新建文件夹 | 规划中（Day 18） |
| `/api/materials` | POST | 新增素材记录 | 规划中（Day 18） |
| `/api/materials/:id` | PUT | 修改素材（重命名/移位） | 规划中（Day 18） |
| `/api/materials/:id` | DELETE | 删除素材 | 规划中（Day 19） |
| `/api/folders/:id` | DELETE | 删除文件夹 | 规划中（Day 19） |

**实现时的要求**（提前写在这里，避免返工）：
1. 每个接口的响应都要遵守第 1 节的 `code/message/data` 三件套；
2. 写接口（POST/PUT/DELETE）必须有明确的 `message`，失败时把原因写清楚（如「名称重复」「文件夹不存在」）；
3. 接口路径、方法、字段一经定稿，要**同步更新本文档**，前端和后端都以文档为准。

---

## 4. 已知边界与待办

- **跨域 CORS**：今日（Day 15）不做。前端 mock 版尚未真正调用 `/api/health`，前端调后端时的
  跨域配置按计划在 **Day 20** 完成（附录 M「HTTP 访问服务 → 跨域 CORS 配置」）。
- **认证**：现阶段所有接口走「免鉴权」公开访问（HTTP 网关路由的身份认证已关），后续若需要
  用户登录，再引入鉴权（不在 Day 15–20 范围）。
