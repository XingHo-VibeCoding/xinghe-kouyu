// ============================================================
// GET /api/classes —— 班级列表读接口（星禾口语 · Day 17 v2）
// ------------------------------------------------------------
// v2 变更：不再用 pg 直连数据库（共享集群不给连接地址），
// 改走 CloudBase 的 HTTP API 网关（PostgREST），平台帮我们读表。
//
// 流程：匿名登录拿 token → 带 token 查 classes 表 → 再查 users 表
//       → 代码里把老师名字拼进班级数据 → 返回。
// 环境变量：ENV_ID = 云开发环境 ID（不写死在代码里，安全红线）。
// ============================================================

const http = require('http');
const https = require('https');

// 读环境变量里的环境 ID
const ENV_ID = process.env.ENV_ID;
// 网关基础域名（官方固定格式：<envId>.api.tcloudbasegateway.com）
const GATEWAY = `https://${ENV_ID}.api.tcloudbasegateway.com`;

// ---------- 小工具：发 HTTPS 请求，返回 { status, body } ----------
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

// 设备 ID：匿名登录必填的请求头（平台用来区分不同匿名用户）。
// 云函数是服务端，固定用一个标识即可；文档建议客户端随机生成并缓存。
const DEVICE_ID = 'xinghe-cloudfunction-server';

// ---------- 第 1 步：匿名登录，拿 access_token ----------
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

// ---------- 第 2 步：查 classes 表全部班级 ----------
async function getClasses(token) {
  const url = `${GATEWAY}/v1/rdb/rest/classes?select=id,name,teacher_id,created_at&order=id.asc`;
  const res = await request(url, {
    method: 'GET',
    headers: { Authorization: 'Bearer ' + token },
  });
  if (res.status !== 200) {
    throw new Error('查询 classes 失败: HTTP ' + res.status + ' ' + JSON.stringify(res.body));
  }
  return res.body; // 数组
}

// ---------- 第 3 步：查 users 表（拿老师名字） ----------
async function getUsers(token) {
  const url = `${GATEWAY}/v1/rdb/rest/users?select=id,name&role=eq.teacher`;
  const res = await request(url, {
    method: 'GET',
    headers: { Authorization: 'Bearer ' + token },
  });
  if (res.status !== 200) {
    throw new Error('查询 users 失败: HTTP ' + res.status + ' ' + JSON.stringify(res.body));
  }
  return res.body; // [{id, name}, ...]
}

const server = http.createServer(async (req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });

  // 环境变量没配，直接给出人话提示（别让用户对着 500 猜）
  if (!ENV_ID) {
    res.end(JSON.stringify({
      code: 5001,
      message: '环境变量 ENV_ID 未配置（云函数设置 → 环境变量，填你的云开发环境 ID）',
      data: {},
    }));
    return;
  }

  try {
    const token = await getToken();
    const [classes, teachers] = await Promise.all([getClasses(token), getUsers(token)]);

    // 拼接：把老师名字贴到对应班级上（代替 SQL 里的 LEFT JOIN）
    const teacherMap = {};
    teachers.forEach((t) => { teacherMap[t.id] = t.name; });
    const data = classes.map((c) => ({
      ...c,
      teacher_name: teacherMap[c.teacher_id] || null,
    }));

    res.end(JSON.stringify({ code: 0, message: 'ok', data }));
  } catch (err) {
    res.end(JSON.stringify({
      code: 5000,
      message: '网关查询失败: ' + err.message,
      data: {},
    }));
  }
});

// 云函数容器约定监听 9000 端口
server.listen(9000);
