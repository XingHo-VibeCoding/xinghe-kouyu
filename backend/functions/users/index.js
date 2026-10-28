// ============================================================
// /api/users —— 用户接口（星禾口语 · Day 24 v5，ApiKey 鉴权 + username）
// ------------------------------------------------------------
// v5 变更（配套「关闭匿名登录」改造）：
//   1. 鉴权换 ApiKey：原来靠匿名登录换临时 token（2小时过期，每次
//      冷启动多一次登录往返），但产品决定关闭匿名登录，云函数必须
//      有自己的身份。ApiKey 是官方给服务端的凭证：长期有效、管理员
//      权限、官方明示严禁在客户端使用。密钥放云函数环境变量
//      TCB_API_KEY，不进代码、不进 Git。
//   2. POST 接受可选 username（注册时设置的登录用户名），upsert 落库；
//      GET 查询结果里也带 username。目的：管理台能对上「uid ↔ 用户名」。
// v4 变更：
//   1. GET 支持 ?uid=xxx 查单个用户资料（App 登录后拉昵称/角色用）；
//      仍保留 ?role= 列表查询。
//   2. 背景：登录（身份认证）只给 uid，昵称和角色在 users 表里，
//      资料没查到 = 该账号还没登记，前端据此引导「完善资料」。
// v3 变更：
//   1. 支持两种方法：
//      GET  ?role=teacher/student      → 用户列表（可选按角色过滤）
//      POST { uid, nickname, role }    → 登记身份（首次进入填昵称+角色）
//   2. 表结构换 v2：users.id 是登录 uid（文本）、name → nickname
//   3. 登记是「upsert」：同一个 uid 再登记就更新昵称/角色，不报错
//      （用 PostgREST 的 on_conflict=id + resolution=merge-duplicates）
// 环境变量：ENV_ID = 云开发环境 ID；TCB_API_KEY = 服务端 ApiKey。
// ============================================================

const http = require('http');
const https = require('https');

const ENV_ID = process.env.ENV_ID;
const GATEWAY = `https://${ENV_ID}.api.tcloudbasegateway.com`;

function request(url, options = {}, body = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, options, (res) => {
      let chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf-8');
        let parsed = raw;
        try { parsed = JSON.parse(raw); } catch (e) { /* 保留原文 */ }
        resolve({ status: res.statusCode, body: parsed });
      });
    });
    req.on('error', reject);
    req.setTimeout(8000, () => req.destroy(new Error('请求超时')));
    if (body) req.write(body);
    req.end();
  });
}

// ---------- 服务端鉴权：ApiKey（长期有效，管理员权限） ----------
// 官方文档：https://docs.cloudbase.net/http-api/basic/access-token
// 用法：Authorization: Bearer <ApiKey>，与原临时 token 完全同款，
// 所以调用处不用改，只换「token 从哪来」。
const API_KEY = process.env.TCB_API_KEY;

async function getToken() {
  if (!API_KEY) {
    throw new Error(
      '环境变量 TCB_API_KEY 未配置（控制台 → API Key 管理创建，' +
      '再配到本云函数的环境变量里，与 ENV_ID 同一位置）'
    );
  }
  return API_KEY; // 长期有效，无需登录/刷新
}

const server = http.createServer(async (req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });

  if (!ENV_ID) {
    res.end(JSON.stringify({
      code: 5001,
      message: '环境变量 ENV_ID 未配置（云函数设置 → 环境变量，填你的云开发环境 ID）',
      data: {},
    }));
    return;
  }

  try {
    // ---------- GET：查用户资料（单个 或 按角色列表） ----------
    if (req.method === 'GET') {
      const params = new URL(req.url, 'http://localhost').searchParams;
      const role = params.get('role'); // teacher / student
      const uid = params.get('uid');   // 查单个用户（App 登录后拉自己资料用）

      let url = `${GATEWAY}/v1/rdb/rest/users?select=id,username,nickname,role,created_at&order=id.asc`;
      if (uid) {
        // 按 uid 精确查：返回数组（0 或 1 条），前端据「空数组」判断资料未完善
        url += `&id=eq.${encodeURIComponent(uid)}`;
      } else if (role === 'teacher' || role === 'student') {
        url += `&role=eq.${role}`;
      }

      const token = await getToken();
      const result = await request(url, {
        method: 'GET',
        headers: { Authorization: 'Bearer ' + token },
      });

      if (result.status !== 200) {
        throw new Error('查询 users 失败: HTTP ' + result.status + ' ' + JSON.stringify(result.body));
      }

      res.end(JSON.stringify({ code: 0, message: 'ok', data: result.body }));
      return;
    }

    // ---------- POST：登记身份（upsert） ----------
    if (req.method === 'POST') {
      let reqBody = '';
      req.on('data', (c) => { reqBody += c; });
      req.on('end', async () => {
        let payload = {};
        try { payload = JSON.parse(reqBody || '{}'); } catch (e) { /* 空体 */ }

        const uid = (payload.uid || '').trim();
        const nickname = (payload.nickname || '').trim();
        const role = (payload.role || '').trim();
        // username 可选：注册时设置的登录用户名，来自 App 会话。
        // 留空不报错（兼容旧客户端 / 老账号），有值就一并落库。
        const username = (payload.username || '').trim();

        // 参数校验
        if (!uid) {
          res.end(JSON.stringify({ code: 4000, message: '缺少 uid（匿名登录返回的用户 id）', data: {} }));
          return;
        }
        if (!nickname) {
          res.end(JSON.stringify({ code: 4000, message: '缺少昵称 nickname', data: {} }));
          return;
        }
        if (role !== 'teacher' && role !== 'student') {
          res.end(JSON.stringify({ code: 4000, message: 'role 必须是 teacher 或 student', data: {} }));
          return;
        }

        const token = await getToken();
        // upsert：id 冲突时更新资料（同一账号重复登记不报错）。
        // username 只在有值时写入——避免空值把库里已有的用户名抹掉。
        const upsertBody = { id: uid, nickname, role };
        if (username) upsertBody.username = username;
        const result = await request(
          `${GATEWAY}/v1/rdb/rest/users?on_conflict=id`,
          {
            method: 'POST',
            headers: {
              Authorization: 'Bearer ' + token,
              'Content-Type': 'application/json',
              Prefer: 'resolution=merge-duplicates,return=representation',
            },
          },
          JSON.stringify(upsertBody)
        );

        if (result.status !== 201 && result.status !== 200) {
          res.end(JSON.stringify({
            code: 5004,
            message: '登记身份失败: HTTP ' + result.status + ' ' + JSON.stringify(result.body),
            data: {},
          }));
          return;
        }

        res.end(JSON.stringify({ code: 0, message: 'ok', data: result.body[0] || {} }));
      });
      return;
    }

    // 其他方法不支持
    res.end(JSON.stringify({ code: 4006, message: '不支持的请求方法: ' + req.method, data: {} }));
  } catch (err) {
    res.end(JSON.stringify({
      code: 5000,
      message: '网关查询失败: ' + err.message,
      data: {},
    }));
  }
});

server.listen(9000);
