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

// ---------- 服务端鉴权：ApiKey（长期有效，管理员权限） ----------
// Day 24 v2：原匿名登录方式随「关闭匿名登录」一起退役，改用 ApiKey。
// 密钥放环境变量 TCB_API_KEY，不进代码、不进 Git。
// 官方文档：https://docs.cloudbase.net/http-api/basic/access-token
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
