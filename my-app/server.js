/*
 * 星禾口语 · 本地开发服务器（Day 7 第 1 步）
 * 作用：把 my-app 文件夹当作网站根目录，提供静态文件访问。
 * 为什么需要它：PWA 的安装、缓存功能要求页面必须通过 http://localhost 访问，
 *              直接双击 index.html（file:// 协议）无法满足。
 * 启动方式：在本文件所在目录执行  node server.js
 * 依赖：零依赖，只用 Node.js 内置的 http 模块。
 */

// 引入 Node 内置模块：http 用于创建服务器，path/fs 用于读文件，os 用于查本机 IP
const http = require('http');
const path = require('path');
const fs = require('fs');
const os = require('os');

// 网站根目录 = 本文件所在的 my-app 目录
const ROOT = __dirname;
// 端口号：命令行参数可改（node server.js 3000），默认 8080
const PORT = Number(process.argv[2]) || 8080;

// 各类文件扩展名对应的响应头类型（MIME），浏览器靠它决定怎么处理文件
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.js':   'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg':  'image/svg+xml',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico':  'image/x-icon',
  '.mp3':  'audio/mpeg',
  '.m4a':  'audio/mp4',
  '.wav':  'audio/wav',
  '.mp4':  'video/mp4',
  '.mov':  'video/quicktime',
  '.webm': 'video/webm',
  '.wasm': 'application/wasm',
};

const server = http.createServer((req, res) => {
  // 只处理 GET 请求，其他方法一律拒绝（本期用不到）
  if (req.method !== 'GET') {
    res.writeHead(405);
    return res.end('Method Not Allowed');
  }

  // 把 URL 解码成文件路径，/ 默认指向首页
  let urlPath = decodeURIComponent(req.url.split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';

  // 拼出磁盘上的真实路径，并做路径穿越防护（防止 .. 跳出 my-app 目录）
  const filePath = path.normalize(path.join(ROOT, urlPath));
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    return res.end('Forbidden');
  }

  // 读取文件：存在则按类型返回，不存在返回 404
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('404 Not Found: ' + urlPath);
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

// 启动并打印访问地址（英文输出，避免 Windows 控制台中文乱码）
server.listen(PORT, () => {
  // 找出本机在局域网里的 IPv4 地址，手机连同一个 WiFi 就能用它访问
  const ips = [];
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) ips.push(net.address);
    }
  }
  console.log('');
  console.log('  XingHe KouYu dev server is running!');
  console.log('  On this PC:               http://localhost:' + PORT);
  if (ips.length > 0) {
    console.log('  On your phone (same WiFi): http://' + ips[0] + ':' + PORT);
  }
  console.log('  Stop the server:          press Ctrl + C in this window');
  console.log('');
});
