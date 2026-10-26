// ============================================================
// /api/users —— 用户接口（星禾口语 · Day 20 v3，班级管理 MVP）
// ------------------------------------------------------------
// v3 变更：
//   1. 支持两种方法：
//      GET  ?role=teacher/student      → 用户列表（可选按角色过滤）
//      POST { uid, nickname, role }    → 登记身份（首次进入填昵称+角色）
//   2. 表结构换 v2：users.id 是匿名登录 uid（文本）、name → nickname
//   3. 登记是「upsert」：同一个 uid 再登记就更新昵称/角色，不报错
//      （用 PostgREST 的 on_conflict=id + resolution=merge-duplicates）
// 环境变量：ENV_ID = 云开发环境 ID。
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

// 设备 ID：云函数作为服务端匿名登录时的固定标识（查表管理员通行证）
const DEVICE_ID = 'xinghe-cloudfunction-server';

async function getToken() {
  const res = await request(`${GATEWAY}/auth/v1/signin/anonymously`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-device-id': DEVICE_ID, // 必填：缺了会报「请在请求头添加设备id」
    },
  }, '{}');
  if (res.status !== 200 || !res.body || !res.body.access_token) {
    throw new Error('匿名登录失败: HTTP ' + res.status + ' ' + JSON.stringify(res.body));
  }
  return res.body.access_token;
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
    // ---------- GET：用户列表（可选按角色过滤） ----------
    if (req.method === 'GET') {
      const params = new URL(req.url, 'http://localhost').searchParams;
      const role = params.get('role'); // teacher / student

      let url = `${GATEWAY}/v1/rdb/rest/users?select=id,nickname,role,created_at&order=id.asc`;
      if (role === 'teacher' || role === 'student') {
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
        // upsert：id 冲突时更新 nickname/role（同一设备重复登记不报错）
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
          JSON.stringify({ id: uid, nickname, role })
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
