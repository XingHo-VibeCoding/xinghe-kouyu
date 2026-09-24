# 星禾口语（MVP）

老师发的音视频，整理好慢慢听。无广告的本地复读工具：应用内文件夹管理 + AB 复读 + 单集循环 + 位置记忆，所有素材只存在你自己的设备里。

## 快速上手

- **导入**：「＋ 导入素材」一次选多个文件；「＋ 导入文件夹」直接选一整个文件夹，**按原目录结构自动建好文件夹树**（同名文件夹自动复用、相同文件自动跳过），非音视频文件自动忽略
- **整理**：左侧树支持多级文件夹（新建/重命名/删除），素材可 📤 移动、⤴️ 移出、✏️ 改名；右侧列表可按时间或名称排序
- **练习**：点素材即播 → 拖进度条定位 → 点 **A** 打起点、点 **B** 打终点即开始复读 → **重置** 退出复读；🔁 为单集循环
- 每个素材的播放位置会自动记住，下次点开从上次处继续

## 怎么运行

前提：电脑上装有 Node.js（官网 LTS 版即可）。

1. 打开 PowerShell，进入本目录（my-app 所在位置）：

   ```powershell
   cd D:\develop\Projects\workBuddy\vibeCoding\my-app
   ```

2. 启动本地服务器：

   ```powershell
   node server.js
   ```

3. 按窗口里打印的地址访问：
   - 电脑浏览器：`http://localhost:8080`
   - 手机（连同一个 WiFi）：`http://<局域网IP>:8080`（启动时会自动打印）

想换端口：`node server.js 3000`。

## 安装成 App（PWA）

- 安卓 Chrome：打开网站 → 菜单 →「添加到主屏幕 / 安装应用」
- iPhone Safari：分享 →「添加到主屏幕」
- 电脑 Chrome/Edge：地址栏右侧「安装」图标

安装后从桌面图标打开，全屏独立窗口运行。

## 数据在哪、安不安全

- 导入的音视频**复制**进浏览器的 IndexedDB（本地数据库），文件夹结构与播放位置记录存在 localStorage
- 全程**数据不出设备**：无上传、无账号、无广告

## 改了代码要注意

- 改 HTML/CSS/JS 后：浏览器 Ctrl+F5 强制刷新；同时把 `sw.js` 里的 `CACHE_VERSION` 版本号 +1，否则手机端可能一直用旧缓存
- 改 `server.js` 后：Ctrl+C 停掉服务器再重新 `node server.js`

## 技术栈

零依赖：原生 HTML/CSS/JS + IndexedDB + localStorage + PWA（manifest + Service Worker）+ 十几行 Node 静态服务器。后续升级路径：Capacitor（安卓 apk）+ Electron（电脑 exe）。
