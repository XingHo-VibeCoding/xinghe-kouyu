// ============================================================
// /api/health 健康检查（星禾口语 · Day 15）
// HTTP 函数版：用 Node.js 内置 http 模块起一个最小服务，
// 任何路径访问都返回同一段 JSON，证明「云端是通的」。
// ============================================================
const http = require('http');

const server = http.createServer((req, res) => {
  // 返回 JSON：code 0 = 成功；time 实时生成，刷新会变，证明不是死数据
  res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify({
    code: 0,
    message: 'ok',
    data: {
      service: 'xinghe-kouyu-api',
      health: 'ok',
      time: new Date().toISOString(),
    },
  }));
});

// 云函数容器约定监听 9000 端口（模板里的 scf_bootstrap 启动脚本会运行本文件）
server.listen(9000);
