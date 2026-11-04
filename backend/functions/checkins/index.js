// ============================================================
// /api/checkins —— 签到接口（星禾口语 · Day 25，签到功能）
// ------------------------------------------------------------
// 方法：
//   GET  ?session_id=xxx            → 某场签到实时状态（老师监控轮询 / 学生查自己）
//   GET  ?class_id=xxx              → 该班进行中的签到（学生查「本班有没有签到」）
//   GET  ?class_id=xxx&history=1    → 该班签到历史（场次列表 + 汇总 + 明细）
//   POST { action, uid, ... }       → create 发布 / checkin 签到 / close 终止 / update 改状态
//
// 状态枚举（checkin_records.status，四种）：
//   absent 缺勤（红）/ late 迟到（橙）/ leave 请假（浅橙）/ present 已到（绿）
//   —— 初态 absent；学生签到只能签成 present；late / leave 由老师手动改。
//
// 自动终止：不落库。所有接口按「created_at + 10 分钟 < 当前时间」惰性判定
//   为已终止，前端据此显示「已结束」，签到接口对超时场次一律拒绝。
//   老师也可手动 close 提前终止（落库 closed）。
//
// 环境变量：ENV_ID = 云开发环境 ID；TCB_API_KEY = API Key（同 classes）。
// 建表：见同目录 schema.sql（在控制台 SQL 编辑器执行一次即可）。
// ============================================================

const http = require('http');
const https = require('https');
const crypto = require('crypto');

const ENV_ID = process.env.ENV_ID;
const GATEWAY = `https://${ENV_ID}.api.tcloudbasegateway.com`;

// 签到窗口：10 分钟（毫秒）
const CHECKIN_WINDOW_MS = 10 * 60 * 1000;

// 合法状态集合（改状态接口用它做白名单校验）
const VALID_STATUS = ['absent', 'late', 'leave', 'present'];

// ---------- 小工具：发 HTTPS 请求，返回 { status, body } ----------
function request(url, options = {}, body = null) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let timer = null;
    const settle = (fn, arg) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      fn(arg);
    };
    const req = https.request(url, options, (res) => {
      let chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString('utf-8');
        let parsed = raw;
        try { parsed = JSON.parse(raw); } catch (e) { /* 保留原文 */ }
        settle(resolve, { status: res.statusCode, body: parsed });
      });
    });
    req.on('error', (e) => settle(reject, e));
    // 整体超时：无论「请求发送」还是「等待响应」卡住，10 秒后强制中断，
    // 避免网关收到请求但不响应时永久 await、前端永远卡住。
    timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        req.destroy(new Error('请求超时(10s)'));
      }
    }, 10000);
    if (body) req.write(body);
    req.end();
  });
}

// ---------- 服务端鉴权：ApiKey（长期有效，管理员权限，同 classes） ----------
const API_KEY = process.env.TCB_API_KEY;

async function getToken() {
  if (!API_KEY) {
    throw new Error(
      '环境变量 TCB_API_KEY 未配置（控制台 → API Key 管理创建，' +
      '再配到本云函数的环境变量里，与 ENV_ID 同一位置）'
    );
  }
  return API_KEY;
}

// ---------- 生成 6 位纯数字签到码（首位 1-9，避免前导 0 引起输入歧义） ----------
function genCheckinCode() {
  let code = String(crypto.randomInt(1, 10));
  for (let i = 0; i < 5; i++) {
    code += crypto.randomInt(10);
  }
  return code;
}

// ---------- 判断场次是否已超时（惰性终止的核心判定） ----------
function isExpired(session) {
  if (!session || !session.created_at) return true;
  const t = new Date(session.created_at).getTime();
  if (Number.isNaN(t)) return true;
  return t + CHECKIN_WINDOW_MS < Date.now();
}

// ---------- 校验某人是否某班老师（class_members 里 role=teacher） ----------
async function isTeacherOfClass(token, uid, classId) {
  const r = await request(
    `${GATEWAY}/v1/rdb/rest/class_members?select=user_id&class_id=eq.${encodeURIComponent(classId)}&user_id=eq.${encodeURIComponent(uid)}&role=eq.teacher`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  return r.status === 200 && Array.isArray(r.body) && r.body.length > 0;
}

// ---------- 校验某人是否某班学生（class_members 里 role=student） ----------
async function isStudentOfClass(token, uid, classId) {
  const r = await request(
    `${GATEWAY}/v1/rdb/rest/class_members?select=user_id&class_id=eq.${encodeURIComponent(classId)}&user_id=eq.${encodeURIComponent(uid)}&role=eq.student`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  return r.status === 200 && Array.isArray(r.body) && r.body.length > 0;
}

// ---------- 发布签到：建 session + 批量建全班学生 record(absent) ----------
async function createSession(token, uid, classId) {
  // 0. 前置校验：发起者必须是这个班的老师
  if (!(await isTeacherOfClass(token, uid, classId))) {
    return { code: 4003, message: '只有本班老师才能发起签到', data: {} };
  }

  // 1. 生成签到码并插入 session（code 全局唯一，撞码重试最多 5 次）
  const sessionId = crypto.randomUUID();
  let inserted = false;
  let lastErr = '';
  let code = '';
  for (let i = 0; i < 5 && !inserted; i++) {
    code = genCheckinCode();
    const res = await request(`${GATEWAY}/v1/rdb/rest/checkin_sessions`, {
      method: 'POST',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
    }, JSON.stringify({
      id: sessionId,
      class_id: classId,
      teacher_id: uid,
      code,
      status: 'ongoing',
    }));
    if (res.status === 201) {
      inserted = true;
    } else {
      // 409 = 签到码撞了（UNIQUE 冲突），换一个重试
      lastErr = 'HTTP ' + res.status + ' ' + JSON.stringify(res.body);
    }
  }
  if (!inserted) {
    return { code: 5002, message: '发起签到失败（签到码生成冲突）: ' + lastErr, data: {} };
  }

  // 2. 查该班所有学生
  const mRes = await request(
    `${GATEWAY}/v1/rdb/rest/class_members?select=user_id&class_id=eq.${encodeURIComponent(classId)}&role=eq.student&order=id.asc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (mRes.status !== 200) {
    return { code: 5000, message: '查询班级学生失败: HTTP ' + mRes.status, data: {} };
  }
  const students = mRes.body || [];

  // 2.5 查学生昵称（拼明细返回用）
  const nicknameMap = {};
  if (students.length > 0) {
    try {
      const uRes = await request(
        `${GATEWAY}/v1/rdb/rest/users?select=id,nickname&id=in.(${students.map((s) => s.user_id).join(',')})`,
        { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
      );
      if (uRes.status === 200 && Array.isArray(uRes.body)) {
        uRes.body.forEach((u) => { nicknameMap[u.id] = u.nickname; });
      }
    } catch (e) {
      // 查昵称失败（超时等）不阻塞主流程，昵称留 null
    }
  }

  // 3. 批量建记录（初态缺勤 absent），并发插入，加快速度
  const records = [];
  if (students.length > 0) {
    const items = students.map((s) => ({ rid: crypto.randomUUID(), user_id: s.user_id }));
    const insResults = await Promise.all(items.map((item) =>
      request(`${GATEWAY}/v1/rdb/rest/checkin_records`, {
        method: 'POST',
        headers: {
          Authorization: 'Bearer ' + token,
          'Content-Type': 'application/json',
        },
      }, JSON.stringify({
        id: item.rid,
        session_id: sessionId,
        class_id: classId,
        student_id: item.user_id,
        status: 'absent',
        checked_at: null,
        updated_by: null,
      }))
    ));
    const failed = insResults.filter((r) => r.status !== 201);
    if (failed.length > 0) {
      return { code: 5003, message: '写入签到记录失败: HTTP ' + failed[0].status, data: {} };
    }
    items.forEach((item) => {
      records.push({
        id: item.rid,
        session_id: sessionId, // 前端 CheckinRecord.fromJson 必需字段，不能漏
        student_id: item.user_id,
        nickname: nicknameMap[item.user_id] || null,
        status: 'absent',
        checked_at: null,
      });
    });
  }

  // 4. 组装完整返回（含明细与汇总，前端监控页秒开不用再查）
  const createdAt = new Date().toISOString();
  const summary = { present: 0, late: 0, leave: 0, absent: records.length };

  return {
    code: 0,
    message: 'ok',
    data: {
      id: sessionId,
      class_id: classId,
      teacher_id: uid,
      code,
      status: 'ongoing',
      created_at: createdAt,
      closed_at: null,
      expired: false,
      student_count: students.length,
      summary,
      records,
    },
  };
}

// ---------- 学生签到：按码找 ongoing 场次 → 该生记录改为 present ----------
async function checkin(token, uid, code) {
  // 1. 按码查场次（不限定 status，方便区分「码不存在」和「已结束」）
  const sRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?select=id,class_id,code,status,created_at,closed_at&code=eq.${encodeURIComponent(code)}&order=created_at.desc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (sRes.status !== 200 || !Array.isArray(sRes.body) || sRes.body.length === 0) {
    return { code: 4004, message: '签到码不存在，请核对后重试', data: {} };
  }
  const session = sRes.body[0];

  // 2. 校验场次有效（未手动关闭 + 未超时）
  if (session.status !== 'ongoing' || isExpired(session)) {
    return { code: 4005, message: '签到已结束', data: {} };
  }

  // 3. 校验是该班学生
  if (!(await isStudentOfClass(token, uid, session.class_id))) {
    return { code: 4006, message: '你不是这个班的学生，无法签到', data: {} };
  }

  // 4. 查该生这条记录（发布签到时会批量建好）
  const rRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_records?select=id,status&session_id=eq.${encodeURIComponent(session.id)}&student_id=eq.${encodeURIComponent(uid)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (rRes.status !== 200 || !Array.isArray(rRes.body) || rRes.body.length === 0) {
    return { code: 5000, message: '查询签到记录失败', data: {} };
  }
  const record = rRes.body[0];
  if (record.status === 'present') {
    return { code: 4007, message: '你已经签到过了', data: {} };
  }

  // 5. 更新为已到（present）+ 记录时间
  const upRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_records?id=eq.${encodeURIComponent(record.id)}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
    },
    JSON.stringify({ status: 'present', checked_at: new Date().toISOString() })
  );
  if (upRes.status !== 200) {
    return { code: 5000, message: '签到失败: HTTP ' + upRes.status + ' ' + JSON.stringify(upRes.body), data: {} };
  }
  return { code: 0, message: 'ok', data: { session_id: session.id, status: 'present' } };
}

// ---------- 终止签到：老师手动置 closed + closed_at ----------
async function closeSession(token, uid, sessionId) {
  // 1. 查场次
  const sRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?select=id,class_id,status&id=eq.${encodeURIComponent(sessionId)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (sRes.status !== 200 || !Array.isArray(sRes.body) || sRes.body.length === 0) {
    return { code: 4004, message: '签到不存在', data: {} };
  }
  const session = sRes.body[0];

  // 2. 校验是本班老师
  if (!(await isTeacherOfClass(token, uid, session.class_id))) {
    return { code: 4003, message: '只有本班老师才能终止签到', data: {} };
  }
  if (session.status === 'closed') {
    return { code: 4005, message: '签到已经结束了', data: {} };
  }

  // 3. 置 closed
  const upRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?id=eq.${encodeURIComponent(sessionId)}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
    },
    JSON.stringify({ status: 'closed', closed_at: new Date().toISOString() })
  );
  if (upRes.status !== 200) {
    return { code: 5000, message: '终止失败: HTTP ' + upRes.status + ' ' + JSON.stringify(upRes.body), data: {} };
  }
  return { code: 0, message: 'ok', data: upRes.body[0] };
}

// ---------- 改状态：老师手动调整单条记录（absent/late/leave/present） ----------
async function updateRecord(token, uid, payload) {
  const { session_id, student_id, status } = payload;
  if (!VALID_STATUS.includes(status)) {
    return { code: 4008, message: '未知状态，应为 absent/late/leave/present', data: {} };
  }

  // 1. 查场次拿 class_id
  const sRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?select=id,class_id&id=eq.${encodeURIComponent(session_id)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (sRes.status !== 200 || !Array.isArray(sRes.body) || sRes.body.length === 0) {
    return { code: 4004, message: '签到不存在', data: {} };
  }
  const session = sRes.body[0];

  // 2. 校验是本班老师
  if (!(await isTeacherOfClass(token, uid, session.class_id))) {
    return { code: 4003, message: '只有本班老师才能调整状态', data: {} };
  }

  // 3. 查该生记录
  const rRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_records?select=id,status,checked_at&session_id=eq.${encodeURIComponent(session_id)}&student_id=eq.${encodeURIComponent(student_id)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (rRes.status !== 200 || !Array.isArray(rRes.body) || rRes.body.length === 0) {
    return { code: 5000, message: '查询签到记录失败', data: {} };
  }
  const record = rRes.body[0];

  // 4. 更新状态。改成 present 且原本没签到时间时补一个时间；
  //    改成 absent 时清掉时间；其余保留原时间。
  const patch = {
    status,
    updated_by: uid,
  };
  if (status === 'present') {
    if (!record.checked_at) patch.checked_at = new Date().toISOString();
  } else if (status === 'absent') {
    patch.checked_at = null;
  }

  const upRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_records?id=eq.${encodeURIComponent(record.id)}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: 'Bearer ' + token,
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
    },
    JSON.stringify(patch)
  );
  if (upRes.status !== 200) {
    return { code: 5000, message: '更新状态失败: HTTP ' + upRes.status + ' ' + JSON.stringify(upRes.body), data: {} };
  }
  return { code: 0, message: 'ok', data: upRes.body[0] };
}

// ---------- 某场签到实时状态：session + 记录（含昵称）+ 汇总 ----------
async function getSession(token, sessionId) {
  const sRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?select=id,class_id,teacher_id,code,status,created_at,closed_at&id=eq.${encodeURIComponent(sessionId)}`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (sRes.status !== 200 || !Array.isArray(sRes.body) || sRes.body.length === 0) {
    return { code: 4004, message: '签到不存在', data: {} };
  }
  const session = sRes.body[0];
  // 惰性终止：超时但还没落库 closed 的，打标记让前端显示「已结束」
  const expired = session.status === 'ongoing' && isExpired(session);

  // 查该场所有记录（session_id 必须取：前端 CheckinRecord.fromJson 必需字段）
  const rRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_records?select=id,session_id,student_id,status,checked_at&session_id=eq.${encodeURIComponent(sessionId)}&order=id.asc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (rRes.status !== 200) {
    return { code: 5000, message: '查询签到记录失败: HTTP ' + rRes.status, data: {} };
  }
  const records = rRes.body || [];

  // 拼学生昵称（网关不支持 JOIN，用 id=in.(...) 一次查回）
  const userIds = [...new Set(records.map((r) => r.student_id))];
  const nicknameMap = {};
  if (userIds.length > 0) {
    try {
      const uRes = await request(
        `${GATEWAY}/v1/rdb/rest/users?select=id,nickname&id=in.(${userIds.join(',')})`,
        { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
      );
      if (uRes.status === 200 && Array.isArray(uRes.body)) {
        uRes.body.forEach((u) => { nicknameMap[u.id] = u.nickname; });
      }
    } catch (e) {
      // 查昵称失败（超时等）不阻塞主流程，昵称留 null
    }
  }

  const recordsWithName = records.map((r) => ({
    ...r,
    nickname: nicknameMap[r.student_id] || null,
  }));

  const summary = { present: 0, late: 0, leave: 0, absent: 0 };
  recordsWithName.forEach((r) => { summary[r.status] = (summary[r.status] || 0) + 1; });

  return {
    code: 0,
    message: 'ok',
    data: {
      ...session,
      expired,
      summary,
      records: recordsWithName,
    },
  };
}

// ---------- 该班进行中的签到（学生查「本班有没有签到」，返回最新未超时的一场） ----------
async function getActive(token, classId) {
  const sRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?select=id,class_id,teacher_id,code,status,created_at,closed_at&class_id=eq.${encodeURIComponent(classId)}&status=eq.ongoing&order=created_at.desc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (sRes.status !== 200) {
    return { code: 5000, message: '查询签到失败: HTTP ' + sRes.status, data: {} };
  }
  const list = sRes.body || [];
  // 取最新的未超时场次；全超时则视为「无进行中」
  const session = list.find((s) => !isExpired(s));
  return { code: 0, message: 'ok', data: session ? { ...session, expired: false } : null };
}

// ---------- 该班签到历史：场次列表 + 每场汇总 + 明细 ----------
async function getHistory(token, classId) {
  const sRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_sessions?select=id,class_id,teacher_id,code,status,created_at,closed_at&class_id=eq.${encodeURIComponent(classId)}&order=created_at.desc`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (sRes.status !== 200) {
    return { code: 5000, message: '查询签到历史失败: HTTP ' + sRes.status, data: {} };
  }
  const sessions = sRes.body || [];
  if (sessions.length === 0) return { code: 0, message: 'ok', data: [] };

  // 一次查回这些场次的所有记录
  const sids = sessions.map((s) => s.id);
  const rRes = await request(
    `${GATEWAY}/v1/rdb/rest/checkin_records?select=id,session_id,student_id,status,checked_at&session_id=in.(${sids.join(',')})`,
    { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
  );
  if (rRes.status !== 200) {
    return { code: 5000, message: '查询签到记录失败: HTTP ' + rRes.status, data: {} };
  }
  const records = rRes.body || [];

  // 拼学生昵称
  const userIds = [...new Set(records.map((r) => r.student_id))];
  const nicknameMap = {};
  if (userIds.length > 0) {
    try {
      const uRes = await request(
        `${GATEWAY}/v1/rdb/rest/users?select=id,nickname&id=in.(${userIds.join(',')})`,
        { method: 'GET', headers: { Authorization: 'Bearer ' + token } }
      );
      if (uRes.status === 200 && Array.isArray(uRes.body)) {
        uRes.body.forEach((u) => { nicknameMap[u.id] = u.nickname; });
      }
    } catch (e) {
      // 查昵称失败（超时等）不阻塞主流程，昵称留 null
    }
  }

  return {
    code: 0,
    message: 'ok',
    data: sessions.map((s) => {
      const recs = records
        .filter((r) => r.session_id === s.id)
        .map((r) => ({ ...r, nickname: nicknameMap[r.student_id] || null }));
      const summary = { present: 0, late: 0, leave: 0, absent: 0 };
      recs.forEach((r) => { summary[r.status] = (summary[r.status] || 0) + 1; });
      const expired = s.status === 'ongoing' && isExpired(s);
      return { ...s, expired, summary, records: recs };
    }),
  };
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
    // ---------- GET：某场状态 / 该班进行中 / 该班历史 ----------
    if (req.method === 'GET') {
      const url = new URL(req.url, 'http://localhost');
      const params = url.searchParams;
      const sessionId = params.get('session_id');
      const classId = params.get('class_id');
      const history = params.get('history');

      const token = await getToken();

      if (sessionId) {
        res.end(JSON.stringify(await getSession(token, sessionId)));
        return;
      }
      if (classId) {
        if (history === '1') {
          res.end(JSON.stringify(await getHistory(token, classId)));
          return;
        }
        res.end(JSON.stringify(await getActive(token, classId)));
        return;
      }
      res.end(JSON.stringify({ code: 4000, message: '缺少 session_id 或 class_id', data: {} }));
      return;
    }

    // ---------- POST：发布 / 签到 / 终止 / 改状态 ----------
    if (req.method === 'POST') {
      let reqBody = '';
      req.on('data', (c) => { reqBody += c; });
      req.on('end', async () => {
        try {
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
            const classId = payload.class_id;
            result = !classId
              ? { code: 4000, message: '缺少班级 id（class_id）', data: {} }
              : await createSession(token, uid, classId);
          } else if (action === 'checkin') {
            const code = (payload.code || '').trim();
            result = !code
              ? { code: 4000, message: '缺少签到码 code', data: {} }
              : await checkin(token, uid, code);
          } else if (action === 'close') {
            const sessionId = payload.session_id;
            result = !sessionId
              ? { code: 4000, message: '缺少签到 id（session_id）', data: {} }
              : await closeSession(token, uid, sessionId);
          } else if (action === 'update') {
            const { session_id, student_id } = payload;
            result = (!session_id || !student_id)
              ? { code: 4000, message: '缺少 session_id 或 student_id', data: {} }
              : await updateRecord(token, uid, payload);
          } else {
            result = { code: 4000, message: '未知 action，应为 create/checkin/close/update', data: {} };
          }
          res.end(JSON.stringify(result));
        } catch (err) {
          // 兜底：任何未捕获异常都返回错误，而不是让响应永久挂起
          res.end(JSON.stringify({
            code: 5000,
            message: '服务器错误: ' + (err && err.message ? err.message : String(err)),
            data: {},
          }));
        }
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
