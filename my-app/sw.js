/*
 * 星禾口语 · Service Worker（Day 7 第 7 步 PWA 化）
 * 作用：把应用的骨架文件缓存到设备本地——第二次打开不联网也能进（素材本体在 IndexedDB，本来就是本地的）。
 * 策略：缓存优先，缓存里没有再走网络并顺手存一份。
 * 注意：以后改了前端代码（html/css/js），要把下面的 CACHE_VERSION 版本号 +1，
 *       并在浏览器里强刷一次，否则手机上可能一直用旧缓存。
 */

const CACHE_VERSION = 'v34'; // 缓存版本号：改前端代码后记得 +1（v34：✕ 补读屏标注；收起画面后轻提示「声音继续播放中」）
const CACHE_NAME = 'xinghe-kouyu-' + CACHE_VERSION;

// 预缓存的骨架文件（第一次打开时全部下载存好）
const CORE_FILES = [
  './',
  './index.html',
  './css/style.css',
  './js/db.js',
  './js/app.js',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  // Day 8 新增：「我的素材」主视图（Day 8 板块①③）+ 可复用组件（余力加练）
  './main-view.html',
  './css/main-view.css',
  './js/mock-data.js',
  './js/components.js',
  './js/main-view.js',
  './components-demo.html',
];

// 安装阶段：把骨架文件全部存进缓存
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(CORE_FILES))
      .then(() => self.skipWaiting()) // 新 SW 立即接管，不等旧页面关闭
  );
});

// 激活阶段：清掉旧版本的缓存（换版本后不留垃圾）
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// 拦截页面请求：缓存有就直接用，没有就走网络并缓存结果；断网时兜底回首页
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // 只管自己站内的文件

  event.respondWith(
    caches.match(req).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((resp) => {
        const copy = resp.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
        return resp;
      }).catch(() => caches.match('./index.html')); // 完全断网时的兜底
    })
  );
});
