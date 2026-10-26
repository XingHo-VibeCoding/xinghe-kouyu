// ============================================================
// /api/classes —— 班级接口（星禾口语 · Day 20 v3，班级管理 MVP）
// ------------------------------------------------------------
// v3 变更：
//   1. 支持两种方法：
//      GET  ?uid=xxx                 → 我的班级列表（按成员关系查）
//      POST { action, uid, ... }     → action = "create" 建班 / "join" 加入
//   2. 表结构换 v2：classes 有 code（班级码）、teacher_id 是匿名登录 uid 文本
//   3. 用户身份：前端匿名登录拿到 uid 后，通过查询参数/请求体传给本函数
//      （不走自定义请求头——自定义头可能被网关拦截，优先用参数传）
//   4. 本函数自己匿名登录网关，只为拿到「查表权限」（服务端管理员身份），
//      与「业务用户身份（uid）」是两码事。
// 环境变量：ENV_ID = 云开发环境 ID。
// ============================================================

const http = require('http');
const https = require('https');
const crypto = require('crypto');

const ENV_ID = process.env.ENV_ID;
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

// 设备 ID：云函数作为服务端匿名登录时的固定标识（这只是「查表管理员」的通行证，
// 不代表业务用户身份；业务用户身份由前端传 uid 过来）
const DEVICE_ID = 'xinghe-cloudfunction-server';

// ---------- 匿名登录，拿网关查表用的 token ----------
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

// ---------- 生成 6 位班级码（大写字母 + 数字，去掉易混淆的 0/O/1/I） ----------
function genClassCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[crypto.randomInt(chars.length)];
  }
  return code;
}

// ---------- 建班：写 classes + 老师写入 class_members ----------
async function createClass(token, uid, name) {
  // 0. 前置校验：建班的人必须是「老师」
  const uRes = await request(
    `${GATEWAY}/v1/rdb/rest/users?select=id,role&id=eq.${encodeURIComponent(uid)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (uRes.status !== 200 || !Array.isArray(uRes.body) || uRes.body.length === 0) {
    return { code: 4001, message: '用户不存在，请先登记身份', data: {} };
  }
  if (uRes.body[0].role !== 'teacher') {
    return { code: 4002, message: '只有老师才能建班', data: {} };
  }

  // 1. 生成班级码并插入（code 全局唯一，撞码就重试，最多 5 次）
  const classId = crypto.randomUUID();
  let inserted = false;
  let lastErr = '';
  for (let i = 0; i < 5 && !inserted; i++) {
    const code = genClassCode();
    const res = await request(`${GATEWAY}/v1/rdb/rest/classes`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
        Prefer: 'return=representation', // 返回插入后的行，方便回传给前端
      },
    }, JSON.stringify({ id: classId, name, code, teacher_id: uid }));
    if (res.status === 201) {
      inserted = true;
      // 2. 老师自己也要进成员表（角色 teacher）
      await request(`${GATEWAY}/v1/rdb/rest/class_members`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + token,
          'Content-Type': 'application/json',
        },
      }, JSON.stringify({ class_id: classId, user_id: uid, role: 'teacher' }));
      return { code: 0, message: 'ok', data: res.body[0] };
    }
    // 409 = 班级码撞了（UNIQUE 冲突），换一个重试
    lastErr = 'HTTP ' + res.status + ' ' + JSON.stringify(res.body);
  }
  return { code: 5002, message: '建班失败（班级码生成冲突）: ' + lastErr, data: {} };
}

// ---------- 加入班级：按班级码查班 → 校验 → 写 class_members ----------
async function joinClass(token, uid, code) {
  // 1. 按码查班
  const cRes = await request(
    `${GATEWAY}/v1/rdb/rest/classes?select=id,name,teacher_id&code=eq.${encodeURIComponent(code)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (cRes.status !== 200 || !Array.isArray(cRes.body) || cRes.body.length === 0) {
    return { code: 4003, message: '班级码不存在，请核对后重试', data: {} };
  }
  const cls = cRes.body[0];

  // 2. 校验用户存在 + 不能重复加入
  const uRes = await request(
    `${GATEWAY}/v1/rdb/rest/users?select=id,role&id=eq.${encodeURIComponent(uid)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (uRes.status !== 200 || !Array.isArray(uRes.body) || uRes.body.length === 0) {
    return { code: 4001, message: '用户不存在，请先登记身份', data: {} };
  }
  const role = uRes.body[0].role;
  if (role !== 'student') {
    return { code: 4004, message: '只有学生才能加入班级', data: {} };
  }

  const mRes = await request(
    `${GATEWAY}/v1/rdb/rest/class_members?select=id&class_id=eq.${cls.id}&user_id=eq.${encodeURIComponent(uid)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (mRes.status === 200 && Array.isArray(mRes.body) && mRes.body.length > 0) {
    return { code: 4005, message: '你已经在这个班级里了', data: {} };
  }

  // 3. 写成员表
  const insRes = await request(`${GATEWAY}/v1/rdb/rest/class_members`, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json',
    },
  }, JSON.stringify({ class_id: cls.id, user_id: uid, role: 'student' }));
  if (insRes.status !== 201) {
    return { code: 5003, message: '加入失败: HTTP ' + insRes.status + ' ' + JSON.stringify(insRes.body), data: {} };
  }
  return { code: 0, message: 'ok', data: { class_id: cls.id, class_name: cls.name } };
}

// ---------- 我的班级列表：先查成员关系，再查班级，再拼老师名 ----------
async function myClasses(token, uid) {
  // 1. 我加入了哪些班
  const mRes = await request(
    `${GATEWAY}/v1/rdb/rest/class_members?select=class_id&user_id=eq.${encodeURIComponent(uid)}&order=id.asc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (mRes.status !== 200) {
    throw new Error('查询 class_members 失败: HTTP ' + mRes.status + ' ' + JSON.stringify(mRes.body));
  }
  const classIds = mRes.body.map((m) => m.class_id);
  if (classIds.length === 0) return []; // 没加入任何班，直接空列表

  // 2. 查这些班的详情（网关不支持 JOIN，用 id=in.(...) 一次查回）
  const cRes = await request(
    `${GATEWAY}/v1/rdb/rest/classes?select=id,name,code,teacher_id,created_at&id=in.(${classIds.join(',')})&order=created_at.desc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (cRes.status !== 200) {
    throw new Error('查询 classes 失败: HTTP ' + cRes.status + ' ' + JSON.stringify(cRes.body));
  }
  const classes = cRes.body;

  // 3. 查老师名字贴上去（代替 SQL JOIN）
  const teacherIds = [...new Set(classes.map((c) => c.teacher_id))];
  const tRes = await request(
    `${GATEWAY}/v1/rdb/rest/users?select=id,nickname&id=in.(${teacherIds.join(',')})`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  const teacherMap = {};
  if (tRes.status === 200 && Array.isArray(tRes.body)) {
    tRes.body.forEach((t) => { teacherMap[t.id] = t.nickname; });
  }
  return classes.map((c) => ({ ...c, teacher_name: teacherMap[c.teacher_id] || null }));
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
    // ---------- GET：我的班级列表 ----------
    if (req.method === 'GET') {
      const params = new URL(req.url, 'http://localhost').searchParams;
      const uid = params.get('uid');
      if (!uid) {
        res.end(JSON.stringify({ code: 4000, message: '缺少 uid 参数（当前用户身份）', data: {} }));
        return;
      }
      const token = await getToken();
      const data = await myClasses(token, uid);
      res.end(JSON.stringify({ code: 0, message: 'ok', data }));
      return;
    }

    // ---------- POST：建班 / 加入 ----------
    if (req.method === 'POST') {
      // 读请求体（JSON）
      let reqBody = '';
      req.on('data', (c) => { reqBody += c; });
      req.on('end', async () => {
        let payload = {};
        try { payload = JSON.parse(reqBody || '{}'); } catch (e) { /* 空体 */ }
        const { action, uid } = payload;
        if (!uid) {
          res.end(JSON.stringify({ code: 4000, message: '缺少 uid（当前用户身份）', data: {} }));
          return;
        }
        const token = await getToken();
        let result;
        if (action === 'create') {
          // 建班：需要班级名
          const name = (payload.name || '').trim();
          if (!name) {
            result = { code: 4000, message: '缺少班级名 name', data: {} };
          } else {
            result = await createClass(token, uid, name);
          }
        } else if (action === 'join') {
          // 加入：需要班级码
          const code = (payload.code || '').trim().toUpperCase();
          if (!code) {
            result = { code: 4000, message: '缺少班级码 code', data: {} };
          } else {
            result = await joinClass(token, uid, code);
          }
        } else {
          result = { code: 4000, message: '未知 action，应为 create 或 join', data: {} };
        }
        res.end(JSON.stringify(result));
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

// 云函数容器约定监听 9000 端口
server.listen(9000);
