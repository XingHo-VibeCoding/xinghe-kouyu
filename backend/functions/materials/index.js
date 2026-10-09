// ============================================================
// GET /api/materials —— 资源列表读接口（星禾口语 · Day 17 v2）
// ------------------------------------------------------------
// v2 变更：pg 直连 → CloudBase HTTP API 网关（原因见 classes/index.js）。
// 支持可选参数 ?class_id=2：只看某个班的资源。
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

// 设备 ID：匿名登录必填的请求头（平台用来区分不同匿名用户）。
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
    // 解析 ?class_id=2
    const params = new URL(req.url, 'http://localhost').searchParams;
    const classId = params.get('class_id');

    // PostgREST 过滤语法：class_id=eq.2 等价于 SQL 的 WHERE class_id = 2
    // order=id.asc 等价于 ORDER BY id 升序
    let url = `${GATEWAY}/v1/rdb/rest/materials`
      + `?select=id,class_id,title,file_url,created_at&order=id.asc`;
    if (classId) {
      url += `&class_id=eq.${encodeURIComponent(classId)}`;
    }

    const token = await getToken();
    const result = await request(url, {
      method: 'GET',
      headers: { Authorization: 'Bearer ' + token },
    });

    if (result.status !== 200) {
      throw new Error('查询 materials 失败: HTTP ' + result.status + ' ' + JSON.stringify(result.body));
    }

    res.end(JSON.stringify({ code: 0, message: 'ok', data: result.body }));
  } catch (err) {
    res.end(JSON.stringify({
      code: 5000,
      message: '网关查询失败: ' + err.message,
      data: {},
    }));
  }
});

server.listen(9000);
