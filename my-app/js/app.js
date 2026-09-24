/* 星禾口语 · 页面逻辑（Day 8：细节优化中） */
/* 当前已实现：素材导入、素材重命名、素材排序、文件夹管理（嵌套树/级联删除/一键移出/默认展开/排序）、
   播放器（点播/快进快退/变速/平滑进度条/可拖拽视频浮窗）、AB 复读（A/B/重置 三按钮 + 位置校验）、
   单集循环、位置记忆（续播）、PWA 化。 */

// ===== 全局状态 =====

// 当前正在查看的文件夹：'all'=全部素材 / 文件夹 id
// 说明：没有单独的「未分类」视图——没归档的素材在「全部素材」里就能看到
let currentFolderId = 'all';

// 素材排序方式（记在浏览器里，下次打开还是你选的那种）：
//   time-desc 时间新→旧（默认） / time-asc 时间旧→新 / name-asc 名称 A→Z / name-desc 名称 Z→A
let sortMode = localStorage.getItem('materialSort') || 'time-desc';

// 文件夹排序方式（同样记在浏览器里；默认「时间旧→新」= 保持一贯的创建先后顺序）：
//   名称排序对「每一层」分别生效——顶层排顶层、子文件夹排各自的兄弟之间
let folderSortMode = localStorage.getItem('folderSort') || 'time-asc';

// 树的展开/收起状态（资源管理器式 ▸/▾）：
//   顶层文件夹默认「展开」（方便直接看到子文件夹），用户手动收起的记在 collapsedTopFolders；
//   更深层的默认「收起」，用户手动展开的记在 expandedFolders——互不干扰，都尊重手动操作
let expandedFolders = new Set();
let collapsedTopFolders = new Set();

// ===== 工具函数 =====

// 把字节数格式化成易读的大小文字（如 1.2 MB / 340 KB）
function formatSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(0) + ' KB';
  return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}

// 把文本转成可安全插入 HTML 的形式（防止文件名里带 < > 等符号破坏页面）
function esc(text) {
  return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// 取文件夹的父 id（老数据没有 parentId 字段，按顶层 'root' 处理）
function parentOf(folder) {
  return folder.parentId || 'root';
}

// 按当前排序方式给「同一层」的文件夹排序（返回新数组，不改原数据）
//   名称排序用 localeCompare + numeric：中文按拼音、数字按大小（「第2课」排在「第10课」前面）
function sortFolders(list) {
  const arr = list.slice();
  arr.sort((a, b) => {
    if (folderSortMode === 'time-desc') return (b.createdAt || 0) - (a.createdAt || 0); // 新建的在前
    if (folderSortMode === 'time-asc')  return (a.createdAt || 0) - (b.createdAt || 0); // 先建的在前（默认）
    const cmp = a.name.localeCompare(b.name, 'zh-Hans-CN', { numeric: true, sensitivity: 'base' });
    return folderSortMode === 'name-asc' ? cmp : -cmp;
  });
  return arr;
}

// 把文件夹列表按 parentId 组装成「父 id → 子文件夹数组」的映射，并按当前排序方式排好每层顺序
// 注：左侧文件夹树和「移动素材」弹窗都用它，所以两处的顺序始终一致
function buildChildrenMap(folders) {
  const map = {};
  for (const f of folders) {
    const pid = parentOf(f);
    (map[pid] = map[pid] || []).push(f);
  }
  for (const pid in map) map[pid] = sortFolders(map[pid]);
  return map;
}

// ===== 文件夹树渲染 =====

// 重绘左侧文件夹树：顶部固定「全部素材」，下面按层级渲染用户自建的文件夹（支持嵌套）
async function renderFolderTree() {
  const treeEl = document.getElementById('folder-tree');
  const folders = await DB.getAllFolders();
  treeEl.innerHTML = '';

  // 固定节点「全部素材」永远排第一
  treeEl.appendChild(buildFolderNode({ id: 'all', icon: '🗂', name: '全部素材' }, 0, false));

  // 从顶层开始渲染；只有「已展开」的文件夹才渲染它的下一层（按需展开，不全铺开）
  const childrenMap = buildChildrenMap(folders);
  const renderLevel = (parentId, depth) => {
    for (const f of (childrenMap[parentId] || [])) {
      const hasChildren = (childrenMap[f.id] || []).length > 0;
      treeEl.appendChild(buildFolderNode({ id: f.id, icon: '📁', name: f.name, isUser: true }, depth, hasChildren));
      const expanded = depth === 0 ? !collapsedTopFolders.has(f.id) : expandedFolders.has(f.id);
      if (hasChildren && expanded) renderLevel(f.id, depth + 1);
    }
  };
  renderLevel('root', 0);
}

// 造一个树节点 <li>：depth 决定缩进；hasChildren 决定前面有没有展开箭头
function buildFolderNode(n, depth, hasChildren) {
  const li = document.createElement('li');
  li.className = 'folder-item' + (currentFolderId === n.id ? ' active' : '');
  li.dataset.id = n.id;
  li.style.paddingLeft = (10 + depth * 18) + 'px'; // 层级越深缩进越多，视觉上呈现嵌套
  // 展开箭头（资源管理器同款 ▸/▾）：有子文件夹才有，没有就留空占位对齐。
  // 展开状态：顶层看「是否被手动收起」，深层看「是否被手动展开」（默认值相反）
  const isOpen = depth === 0 ? !collapsedTopFolders.has(n.id) : expandedFolders.has(n.id);
  const arrowHtml = (n.isUser && hasChildren)
    ? '<span class="f-arrow" title="' + (isOpen ? '收起' : '展开') + '">' + (isOpen ? '▾' : '▸') + '</span>'
    : '<span class="f-arrow empty"></span>';
  li.innerHTML =
    arrowHtml +
    '<span class="f-name">' + n.icon + ' ' + esc(n.name) + '</span>' +
    // 用户自建的文件夹才显示操作按钮（固定的「全部素材」不可改删）
    (n.isUser
      ? '<span class="f-actions">' +
        '<button class="f-btn" data-act="add" title="在里面新建子文件夹">➕</button>' +
        '<button class="f-btn" data-act="rename" title="重命名">✏️</button>' +
        '<button class="f-btn" data-act="delete" title="删除（仅限空文件夹）">🗑</button>' +
        '</span>'
      : '');
  // 展开箭头：点了切换展开/收起（只重绘树，不影响右侧列表）
  const arrow = li.querySelector('.f-arrow');
  if (!arrow.classList.contains('empty')) {
    arrow.addEventListener('click', (e) => {
      e.stopPropagation();
      // 顶层：记「谁被收起」；深层：记「谁被展开」——与各自默认值互补
      if (depth === 0) {
        if (collapsedTopFolders.has(n.id)) collapsedTopFolders.delete(n.id);
        else collapsedTopFolders.add(n.id);
      } else {
        if (expandedFolders.has(n.id)) expandedFolders.delete(n.id);
        else expandedFolders.add(n.id);
      }
      renderFolderTree();
    });
  }
  // 点文件夹主体 = 切换查看
  li.querySelector('.f-name').addEventListener('click', () => {
    currentFolderId = n.id;
    renderAll(); // 切换后树高亮和列表都要刷新
  });
  // 小按钮：新建子文件夹 / 重命名 / 删除
  const addBtn = li.querySelector('[data-act="add"]');
  const renameBtn = li.querySelector('[data-act="rename"]');
  const deleteBtn = li.querySelector('[data-act="delete"]');
  if (addBtn) addBtn.addEventListener('click', (e) => { e.stopPropagation(); createFolderFlow(n.id, n.name); });
  if (renameBtn) renameBtn.addEventListener('click', (e) => { e.stopPropagation(); renameFolderFlow(n); });
  if (deleteBtn) deleteBtn.addEventListener('click', (e) => { e.stopPropagation(); deleteFolderFlow(n); });
  return li;
}

// 新建文件夹流程：parentId='root' 建在顶层；传文件夹 id 则建为它的子文件夹
async function createFolderFlow(parentId = 'root', parentName = '') {
  const tip = parentId === 'root' ? '新文件夹名称：' : '在「' + parentName + '」里新建子文件夹，名称：';
  const name = prompt(tip);
  if (name === null) return;              // 用户点了取消
  if (!name.trim()) { alert('名称不能为空'); return; }
  const folders = await DB.getAllFolders();
  // 重名检查只看同一个父文件夹下的兄弟（不同层级允许同名，和电脑上的文件夹一个道理）
  if (folders.some(f => parentOf(f) === parentId && f.name === name.trim())) { alert('这个位置已有同名文件夹'); return; }
  await DB.saveFolder(name, parentId);
  expandedFolders.add(parentId); // 自动展开父文件夹，让新建的子文件夹立刻可见
  await renderFolderTree();
}

// 重命名流程
async function renameFolderFlow(node) {
  const name = prompt('重命名为：', node.name);
  if (name === null) return;
  if (!name.trim()) { alert('名称不能为空'); return; }
  const folders = await DB.getAllFolders();
  // 重名检查：同一父文件夹下、排除自己
  if (folders.some(f => f.id !== node.id && parentOf(f) === parentOf(node) && f.name === name.trim())) { alert('这个位置已有同名文件夹'); return; }
  await DB.renameFolder(node.id, name);
  await renderFolderTree();
}

// 删除流程：子文件夹会一并删除；里面的素材先自动移到顶层（保证素材一个不丢，对应 PRD A1③）
async function deleteFolderFlow(node) {
  // 收集这个文件夹 + 它所有子孙文件夹的 id（嵌套删除范围）
  const folders = await DB.getAllFolders();
  const childrenMap = buildChildrenMap(folders);
  const allIds = [node.id];
  const collect = (pid) => {
    for (const f of (childrenMap[pid] || [])) { allIds.push(f.id); collect(f.id); }
  };
  collect(node.id);

  // 统计整棵子树里的内容，按实际情况生成提示语
  const folderCount = allIds.length - 1;
  let matCount = 0;
  for (const id of allIds) matCount += await DB.countMaterialsIn(id);

  let msg;
  if (folderCount > 0 && matCount > 0) {
    msg = '「' + node.name + '」里有 ' + folderCount + ' 个子文件夹和 ' + matCount + ' 个素材。\n\n' +
          '删除后：子文件夹会一并删除，里面的素材会自动移到顶层（不会丢失）。\n确定删除吗？';
  } else if (folderCount > 0) {
    msg = '「' + node.name + '」里有 ' + folderCount + ' 个子文件夹，将一并删除。\n确定删除吗？';
  } else if (matCount > 0) {
    msg = '「' + node.name + '」里有 ' + matCount + ' 个素材，删除后它们会自动移到顶层（不会丢失）。\n确定删除吗？';
  } else {
    msg = '确定删除空文件夹「' + node.name + '」吗？';
  }
  if (!confirm(msg)) return;

  await DB.moveMaterialsToRoot(allIds); // 先保素材
  await DB.deleteFolders(allIds);       // 再删文件夹（含子孙）
  for (const id of allIds) { // 清掉已删除文件夹的展开/收起状态（两套记录都清）
    expandedFolders.delete(id);
    collapsedTopFolders.delete(id);
  }
  // 如果删掉的这棵树里包含当前查看的文件夹，退回「全部素材」视图
  if (allIds.includes(currentFolderId)) currentFolderId = 'all';
  await renderAll();
}

// 按当前排序方式给素材排序（返回新数组，不改原数据）
//   名称排序用 localeCompare + numeric：中文按拼音、数字按大小（「第2课」排在「第10课」前面）
function sortMaterials(list) {
  const arr = list.slice();
  arr.sort((a, b) => {
    if (sortMode === 'time-desc') return b.addedAt - a.addedAt; // 新导入的在前（默认）
    if (sortMode === 'time-asc')  return a.addedAt - b.addedAt; // 最早的在前
    const cmp = a.name.localeCompare(b.name, 'zh-Hans-CN', { numeric: true, sensitivity: 'base' });
    return sortMode === 'name-asc' ? cmp : -cmp;
  });
  return arr;
}

// ===== 素材列表渲染 =====

// 从数据库读出当前文件夹的素材，重绘右侧列表
async function renderMaterialList() {
  const listEl = document.getElementById('material-list');
  const countEl = document.getElementById('list-count');
  const materials = await DB.getAllMaterials(currentFolderId);

  // 计数徽标
  countEl.textContent = materials.length + ' 个';

  // 空态文案按视图区分，引导更明确
  if (materials.length === 0) {
    const tip = currentFolderId === 'all'
      ? '还没有素材。<br>点右上角「＋ 导入素材」添加第一个文件。'
      : '这个文件夹是空的。<br>可在素材上点 📤 移入，或直接在此视图导入。';
    listEl.innerHTML = '<li class="empty-tip">' + tip + '</li>';
    return;
  }

  // 「全部素材」视图下显示每个素材的位置徽标（方便知道它归在哪个文件夹里）
  let nameMap = null;
  if (currentFolderId === 'all') {
    nameMap = {};
    for (const f of await DB.getAllFolders()) nameMap[f.id] = f.name;
  }

  // 清空后逐条渲染；条目主体点击 = 播放（第 4 步启用），📤 = 移动
  listEl.innerHTML = '';
  for (const m of sortMaterials(materials)) {
    const li = document.createElement('li');
    li.className = 'material-item' + (m.id === currentId ? ' playing' : ''); // 正在播的高亮
    li.dataset.id = m.id;
    li.title = '点击播放';
    const locHtml = (nameMap && m.folderId !== 'root' && nameMap[m.folderId])
      ? '<span class="m-loc">📁 ' + esc(nameMap[m.folderId]) + '</span>'
      : '';
    // 已归档的素材额外给一个 ⤴️ 一键移出（只改归属回顶层，素材不删除，全部素材里仍能看到）
    const unfileHtml = m.folderId !== 'root'
      ? '<button class="m-unfile" title="移出文件夹：回到顶层（素材不会删除）">⤴️</button>'
      : '';
    li.innerHTML =
      '<span class="m-icon">' + (m.type === 'video' ? '🎬' : '🎵') + '</span>' +
      '<span class="m-name">' + esc(m.name) + '</span>' +
      locHtml +
      '<span class="m-size">' + formatSize(m.size) + '</span>' +
      unfileHtml +
      '<button class="m-rename" title="重命名（只改应用里的名字，不动原文件）">✏️</button>' +
      '<button class="m-move" title="移动到其他文件夹">📤</button>';
    // 点条目主体 = 播放（第 4 步启用）
    li.addEventListener('click', () => playMaterial(m.id));
    li.querySelector('.m-move').addEventListener('click', (e) => {
      e.stopPropagation();
      openMoveModal(m);
    });
    // ✏️ 改名：不触发播放（stopPropagation）
    li.querySelector('.m-rename').addEventListener('click', (e) => {
      e.stopPropagation();
      renameMaterialFlow(m);
    });
    const unfileBtn = li.querySelector('.m-unfile');
    if (unfileBtn) unfileBtn.addEventListener('click', async (e) => {
      e.stopPropagation();
      await DB.moveMaterial(m.id, 'root');
      await renderAll();
    });
    listEl.appendChild(li);
  }
}

// 树和列表一起刷新（很多操作会同时影响两处）
async function renderAll() {
  await renderFolderTree();
  await renderMaterialList();
}

// ===== 播放器（第 4 步） =====
// 页面脚本在 </body> 前加载，此处元素已存在，可直接获取
const mediaPlayer = document.getElementById('media-player'); // 音视频共用的 <video> 元素
const videoFloat = document.getElementById('video-float');   // 视频浮窗（外层卡片）
const btnVideoClose = document.getElementById('video-close');
const btnPic = document.getElementById('btn-pic');           // 🖼 显示/隐藏画面
const nowPlayingEl = document.querySelector('.now-playing');
const btnPlay = document.getElementById('btn-play');
const btnBack = document.getElementById('btn-back');
const btnForward = document.getElementById('btn-forward');
const btnSpeed = document.getElementById('btn-speed');
const btnA = document.getElementById('btn-a');               // AB 复读：打 A 点（起点）
const btnB = document.getElementById('btn-b');               // AB 复读：打 B 点（终点）
const btnAbReset = document.getElementById('btn-ab-reset');  // AB 复读：重置
const btnLoop = document.getElementById('btn-loop'); // 单集循环
const abBand = document.getElementById('ab-band');   // 进度条上的 AB 段色带
const seekBar = document.getElementById('seek-bar');         // 进度条
const timeCur = document.getElementById('time-cur');
const timeDur = document.getElementById('time-dur');

let currentUrl = null;  // 当前素材 blob 的 objectURL（切换素材时释放，防内存泄漏）
let currentId = null;   // 当前播放的素材 id（列表高亮用）
let currentName = '';   // 当前播放的素材名（底栏显示用）
let dragging = false;   // 是否正在拖进度条（拖动期间不让 timeupdate 抢位置）

// AB 复读：A 点/B 点时间（秒），null = 未设
let abPointA = null;
let abPointB = null;

// 位置记忆的提示开关：刚续播时底栏短暂显示「已从上次位置继续」
let resumeHintUntil = 0;

// ===== 位置记忆（第 6 步） =====
// 每个素材听到几秒都记在 localStorage（素材 id → 秒数），下次播放自动续播
const POS_KEY = 'playbackPositions';

// 读取某素材的上次播放位置（秒）；没记录返回 0
function getSavedPosition(id) {
  try {
    const map = JSON.parse(localStorage.getItem(POS_KEY) || '{}');
    return map[id] || 0;
  } catch (e) { return 0; } // 数据坏了也不影响播放，当没记录处理
}

// 记录某素材的播放位置
function savePosition(id, sec) {
  if (!id || !isFinite(sec) || sec <= 0) return;
  try {
    const map = JSON.parse(localStorage.getItem(POS_KEY) || '{}');
    map[id] = Math.floor(sec);
    localStorage.setItem(POS_KEY, JSON.stringify(map));
  } catch (e) { /* 存不进去就放弃，不影响播放 */ }
}

// 清除某素材的记录（播完了就用它清，下次从头播）
function clearPosition(id) {
  if (!id) return;
  try {
    const map = JSON.parse(localStorage.getItem(POS_KEY) || '{}');
    delete map[id];
    localStorage.setItem(POS_KEY, JSON.stringify(map));
  } catch (e) { /* 同上 */ }
}

// 变速档位：点 btn-speed 按顺序循环（0.5 慢速精听用，对齐 PRD F4 的 0.5–2.0）
const RATES = [1, 1.25, 1.5, 2, 0.75, 0.5];
let rateIdx = 0;

// 秒数格式化成 m:ss（播放进度显示用）
function fmtTime(sec) {
  if (!isFinite(sec)) return '0:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return m + ':' + String(s).padStart(2, '0');
}

// 秒数格式化成 m:ss.d（带 0.1 秒位，进度条两端的时间用）
function fmtTime10(sec) {
  if (!isFinite(sec)) return '0:00.0';
  const m = Math.floor(sec / 60);
  const s = sec - m * 60;
  const whole = Math.floor(s);
  const tenth = Math.floor((s - whole) * 10);
  return m + ':' + String(whole).padStart(2, '0') + '.' + tenth;
}

// 播放指定素材：从 IndexedDB 取出 blob → 生成临时地址 → 交给播放元素
async function playMaterial(id) {
  const m = await DB.getMaterial(id);
  if (!m) return;
  if (currentUrl) URL.revokeObjectURL(currentUrl); // 释放上一个，防内存越占越多
  currentUrl = URL.createObjectURL(m.blob);
  currentId = id;
  currentName = m.name;
  updatePlayingHighlight(); // 点谁谁立刻高亮（不用等列表重新渲染）
  mediaPlayer.src = currentUrl;
  mediaPlayer.playbackRate = RATES[rateIdx]; // 保持当前选定的速度
  await mediaPlayer.play();
  // 视频：显示居中浮窗，🖼 按钮同时亮出；音频：浮窗隐藏只出声
  const isVideo = (m.type === 'video');
  videoFloat.hidden = !isVideo;
  btnPic.style.display = isVideo ? '' : 'none';
  // 新素材就绪：进度条归零并解锁；AB 点和循环一起复位（它们只对当前素材有意义）
  seekBar.disabled = false;
  seekBar.value = 0;
  timeCur.textContent = '0:00.0';
  timeDur.textContent = '0:00.0';
  abPointA = null;
  abPointB = null;
  mediaPlayer.loop = false;
  btnLoop.classList.remove('active');
  updateAbLabel();
  updateNowPlaying();
}

// 播放/暂停切换（底栏大按钮；还没选素材时默认播列表第一个）
async function togglePlay() {
  if (!currentId) {
    const first = document.querySelector('.material-item');
    if (first) await playMaterial(first.dataset.id);
    return;
  }
  if (mediaPlayer.paused) await mediaPlayer.play();
  else mediaPlayer.pause();
}

// 同步列表高亮：把 .playing 类挪到当前播放的条目上（旧的摘掉、新的戴上）。
// 之前只靠 renderMaterialList 渲染时上色，所以必须等列表重画才见高亮——这是个 bug
function updatePlayingHighlight() {
  document.querySelectorAll('.material-item.playing').forEach(el => {
    el.classList.remove('playing');
  });
  const now = document.querySelector('.material-item[data-id="' + currentId + '"]');
  if (now) now.classList.add('playing');
}

// 播放按钮图标跟随状态（▶ / ⏸）
function updatePlayIcon() {
  btnPlay.textContent = mediaPlayer.paused ? '▶' : '⏸';
}

// 底栏刷新：素材名（含续播提示）。进度条的数值更新交给 rAF 每帧刷（见 tickSeekBar），这里不重复
function updateNowPlaying() {
  let label = currentName || '未在播放';
  if (Date.now() < resumeHintUntil && currentName) label += '（已从上次位置继续）';
  nowPlayingEl.textContent = label;
}

// ===== AB 复读 / 单集循环（第 5 步；Day 8 拆成 A / B / 重置 三个独立按钮） =====

// A 按钮：在当前播放位置打 A 点（起点）。
// 支持「先拖进度条定位、再点 A」——每次点都把 A 挪到当前位置，方便反复微调。
// 规则：A 必须落在 B 点左边。已经打了 B 点时，如果在 B 点右侧（或贴得太近）位置点 A，视为无效
function onAClick() {
  if (!currentId) { alert('先播放一个素材，再打 A 点'); return; }
  if (abPointB !== null && mediaPlayer.currentTime >= abPointB - 0.5) {
    alert('这里打 A 点无效：A 点（起点）必须在 B 点左边。\n把进度条拖到 B 点之前，再点 A。');
    return;
  }
  abPointA = mediaPlayer.currentTime;
  updateAbLabel();
}

// B 按钮：在当前播放位置打 B 点（终点），从此刻开始 A↔B 循环。
// 同样支持先拖进度条再打点；再点可重新调整。
// 规则：B 必须落在 A 点右边，落在 A 点左侧（或贴得太近）位置点 B 视为无效
function onBClick() {
  if (!currentId) { alert('先播放一个素材，再打 B 点'); return; }
  if (abPointA === null) { alert('请先打 A 点（起点），再打 B 点。'); return; }
  if (mediaPlayer.currentTime <= abPointA + 0.5) {
    alert('这里打 B 点无效：B 点（终点）必须在 A 点右边。\n把进度条拖到 A 点之后，再点 B。');
    return;
  }
  abPointB = mediaPlayer.currentTime; // 记终点，循环自动开始（timeupdate 里会跳回 A）
  updateAbLabel();
}

// 重置按钮：清掉 A、B 点，退出复读，恢复正常播放（当前位置不动）
function onAbResetClick() {
  abPointA = null;
  abPointB = null;
  updateAbLabel();
}

// 三个 AB 按钮的文字和颜色跟随状态（A/B 已打点就显示时间并变琥珀色），同时刷新进度条色带
function updateAbLabel() {
  // A 按钮：未打点显示「A」，打了显示「A 0:12」并变琥珀色
  if (abPointA === null) {
    btnA.textContent = 'A';
    btnA.classList.remove('active');
  } else {
    btnA.textContent = 'A ' + fmtTime(abPointA);
    btnA.classList.add('active');
  }
  // B 按钮：未打点显示「B」；打了显示「B 0:18」并变琥珀色
  if (abPointB === null) {
    btnB.textContent = 'B';
    btnB.classList.remove('active');
  } else {
    btnB.textContent = 'B ' + fmtTime(abPointB);
    btnB.classList.add('active');
  }
  // 重置按钮：有任何一个点被打了就点亮（提示「这里有东西可清」）
  btnAbReset.classList.toggle('active', abPointA !== null || abPointB !== null);
  updateAbBand();
}

// 进度条上的 AB 段可视化：
//   只设 A 点 → 从 A 到「当前播放位置」这一段是琥珀色（0→A 绿、A→当前 橙、当前→结尾 灰），
//               橙色段随后续播放一格格往前长；
//   A、B 都有 → 琥珀色固定为 A~B 复读区间；
//   同时进度条加 .ab-active，圆点变琥珀色；取消后全部复原为绿色
function updateAbBand() {
  const dur = mediaPlayer.duration;
  if (abPointA === null || !isFinite(dur) || dur <= 0) {
    abBand.hidden = true;
    seekBar.classList.remove('ab-active'); // 取消 AB：圆点回绿色
    return;
  }
  const aPct = abPointA / dur * 100;
  abBand.hidden = false;
  abBand.style.left = aPct + '%';
  if (abPointB !== null) {
    abBand.style.width = ((abPointB - abPointA) / dur * 100) + '%'; // 复读区间整段高亮
  } else {
    // 还没设 B 点：橙色 = A 点到当前播放位置（还没播到的部分保持灰色）
    const played = Math.max(0, (mediaPlayer.currentTime - abPointA) / dur * 100);
    abBand.style.width = played + '%';
  }
  seekBar.classList.add('ab-active'); // AB 复读中：圆点琥珀色
}

// 单集循环：整个素材反复播放（mediaPlayer 自带 loop 开关）
function onLoopClick() {
  mediaPlayer.loop = !mediaPlayer.loop;
  btnLoop.classList.toggle('active', mediaPlayer.loop);
}

// ===== 素材重命名（应用内改名，不动原始文件、不影响已存的数据） =====
async function renameMaterialFlow(m) {
  const input = prompt('给这个素材换个名字：', m.name);
  if (input === null) return;                       // 点了取消
  let newName = input.trim();
  if (!newName) { alert('名字不能为空'); return; }
  if (newName === m.name) return;                   // 没改，什么都不做

  // 后缀保护：用户没写后缀时，自动补上原来的（避免素材看着像没有格式的文件）
  const dot = m.name.lastIndexOf('.');
  const ext = dot > 0 ? m.name.slice(dot) : '';
  if (ext && newName.indexOf('.') === -1) newName += ext;

  await DB.renameMaterial(m.id, newName);
  // 改的正好是正在播的那个 → 底栏名字跟着更新，不然会显示旧名
  if (m.id === currentId) {
    currentName = newName;
    updateNowPlaying();
  }
  await renderMaterialList(); // 只重画列表，树不受影响
}

// ===== 移动素材弹窗 =====

// 打开移动弹窗：目标按树形列出（第一项「顶层」，下面按层级缩进），当前所在处打勾
async function openMoveModal(material) {
  const folders = await DB.getAllFolders();
  const listEl = document.getElementById('move-target-list');
  listEl.innerHTML = '';

  // 组装树形选项列表：{ id, name, depth }
  // 注：这里不再提供「顶层」选项——把素材移出文件夹，用条目上的 ⤴️ 按钮一步到位
  const options = [];
  const childrenMap = buildChildrenMap(folders);
  const walk = (parentId, depth) => {
    for (const f of (childrenMap[parentId] || [])) {
      options.push({ id: f.id, name: f.name, depth });
      walk(f.id, depth + 1);
    }
  };
  walk('root', 0);

  for (const opt of options) {
    const btn = document.createElement('button');
    btn.className = 'move-target';
    btn.style.paddingLeft = (12 + opt.depth * 18) + 'px'; // 层级缩进，和左侧树对应
    btn.innerHTML =
      '📁 ' + esc(opt.name) +
      (material.folderId === opt.id ? ' <span class="here">✅ 当前</span>' : '');
    if (material.folderId === opt.id) {
      btn.disabled = true; // 已经在这里了，不允许选自己
    } else {
      btn.addEventListener('click', async () => {
        await DB.moveMaterial(material.id, opt.id);
        closeModal();
        await renderAll();
        alert('已把「' + material.name + '」移到「' + opt.name + '」');
      });
    }
    listEl.appendChild(btn);
  }
  document.getElementById('move-modal').classList.add('show'); // 显示弹窗
}

// 关闭移动弹窗
function closeModal() {
  document.getElementById('move-modal').classList.remove('show');
}

// ===== 导入功能（第 2 步实现） =====

// 判断是不是能收的音视频文件（按 MIME 类型或后缀认，PRD A2：非媒体文件忽略且不报错）
function isMediaFile(f) {
  return f.type.startsWith('audio') || f.type.startsWith('video') ||
         /\.(mp3|m4a|wav|mp4|mov|webm)$/i.test(f.name);
}

// 批量导入期间的按钮状态：禁用两个导入按钮并在主按钮上显示进度
// （几十个文件时才不会看起来像卡死）；返回的对象里 end() 负责恢复原状
function beginImportUI() {
  const btnImport = document.getElementById('btn-import');
  const btnFolder = document.getElementById('btn-import-folder');
  const originalText = btnImport.textContent;
  btnImport.disabled = true;
  btnFolder.disabled = true;
  return {
    progress(done, total) { btnImport.textContent = '导入中 ' + done + '/' + total; },
    end() {
      btnImport.textContent = originalText;
      btnImport.disabled = false;
      btnFolder.disabled = false;
    },
  };
}

// 处理用户选好的文件（多选文件）：逐个入库，全部完成后刷新列表
// 导入位置跟随当前视图：在某个文件夹视图里导入，就直接归进那个文件夹
// sourceLabel：来源说明，只用于结果提示
async function importFiles(fileList, sourceLabel) {
  const ok = Array.from(fileList).filter(isMediaFile);
  const skipped = fileList.length - ok.length; // 非音视频一律忽略（静默跳过，不报错）

  if (ok.length === 0) {
    alert('没有识别到音频或视频文件（支持 mp3 / m4a / wav / mp4 / mov / webm）');
    return;
  }

  const targetId = currentFolderId === 'all' ? 'root' : currentFolderId;
  const ui = beginImportUI();
  try {
    for (let i = 0; i < ok.length; i++) {
      ui.progress(i + 1, ok.length);
      await DB.saveMaterial(ok[i], targetId); // 逐个复制进 IndexedDB（统一复制存储）
    }
  } finally {
    ui.end();
  }

  await renderAll();

  // 归到哪个文件夹也在提示里说清楚，避免用户以为导入没生效
  let where = '顶层（全部素材可见）';
  if (targetId !== 'root') {
    const folders = await DB.getAllFolders();
    const hit = folders.find(f => f.id === targetId);
    if (hit) where = '「' + hit.name + '」';
  }
  alert('从' + (sourceLabel || '文件') + '导入 ' + ok.length + ' 个素材，已归入' + where +
        (skipped > 0 ? '（另有 ' + skipped + ' 个非音视频文件已忽略）' : ''));
}

// 处理「导入整个文件夹」：按原目录结构在应用里建出同样的文件夹树，文件各归各位。
// 两条防重复规则：同名同级的文件夹直接复用；同文件夹里同名同大小的文件视为重复，跳过。
async function importFolder(fileList) {
  const ok = Array.from(fileList).filter(isMediaFile);
  const skipped = fileList.length - ok.length;
  if (ok.length === 0) {
    alert('这个文件夹里没有识别到音频或视频文件（支持 mp3 / m4a / wav / mp4 / mov / webm）');
    return;
  }

  // 导入的起点：当前在某个文件夹视图里导入，就在它下面还原结构
  const rootTarget = currentFolderId === 'all' ? 'root' : currentFolderId;

  // 先把现有文件夹和素材读出来，做成「查询表」，边导入边判断复用/重复
  const folderIndex = new Map(); // '父id/名字' → 文件夹 id
  for (const f of await DB.getAllFolders()) folderIndex.set(parentOf(f) + '/' + f.name, f.id);
  const fileKeys = new Set((await DB.getAllMaterials('all')).map(m => m.folderId + '|' + m.name + '|' + m.size));

  const ui = beginImportUI();
  let imported = 0, dup = 0, created = 0;
  const expandIds = new Set(); // 新建文件夹的上一级：导入后自动展开，让结构一眼可见

  try {
    for (let i = 0; i < ok.length; i++) {
      const file = ok[i];
      ui.progress(i + 1, ok.length);

      // webkitRelativePath 形如「第三课/Unit1/lesson.mp3」：去掉文件名，剩下的逐级找/建文件夹
      const parts = (file.webkitRelativePath || file.name).split('/').filter(Boolean);
      parts.pop();
      let parentId = rootTarget;
      for (const seg of parts) {
        const key = parentId + '/' + seg;
        let id = folderIndex.get(key);
        if (!id) { // 这一级还没有 → 建一个（同名同级已存在的就复用，不重复建）
          const rec = await DB.saveFolder(seg, parentId);
          id = rec.id;
          folderIndex.set(key, id);
          expandIds.add(parentId);
          created++;
        }
        parentId = id;
      }

      const dupKey = parentId + '|' + file.name + '|' + file.size;
      if (fileKeys.has(dupKey)) { dup++; continue; } // 同一个文件夹里已有同样的文件 → 跳过
      await DB.saveMaterial(file, parentId);
      fileKeys.add(dupKey);
      imported++;
    }
  } finally {
    ui.end();
  }

  for (const id of expandIds) expandedFolders.add(id); // 新建的层级默认展开
  await renderAll();

  let msg = '已从文件夹导入 ' + imported + ' 个素材';
  if (created > 0) msg += '，按原目录结构新建了 ' + created + ' 个文件夹';
  if (dup > 0) msg += '\n（跳过 ' + dup + ' 个已存在的相同文件）';
  if (skipped > 0) msg += '\n（另有 ' + skipped + ' 个非音视频文件已忽略）';
  alert(msg);
}

// ===== 初始化 =====

document.addEventListener('DOMContentLoaded', async () => {
  console.log('星禾口语 v2.8：视频浮窗可锁定宽高比缩放（右下角手柄）');

  // 首次打开：渲染树和列表
  await renderAll();

  // 排序下拉：先把上次选择显示出来；改动时立即重排列表并记住选择
  const sortSelect = document.getElementById('sort-select');
  sortSelect.value = sortMode;
  sortSelect.addEventListener('change', async () => {
    sortMode = sortSelect.value;
    localStorage.setItem('materialSort', sortMode);
    await renderMaterialList();
  });

  // 文件夹排序下拉：同理——显示上次选择，改动时重排左侧树并记住
  const folderSortSelect = document.getElementById('folder-sort');
  folderSortSelect.value = folderSortMode;
  folderSortSelect.addEventListener('change', async () => {
    folderSortMode = folderSortSelect.value;
    localStorage.setItem('folderSort', folderSortMode);
    await renderFolderTree();
  });

  // ===== 播放器按钮点亮（第 4 步） =====
  btnPlay.disabled = false;
  btnBack.disabled = false;
  btnForward.disabled = false;
  btnSpeed.disabled = false;
  btnPlay.addEventListener('click', togglePlay);
  btnBack.addEventListener('click', () => { mediaPlayer.currentTime = Math.max(0, mediaPlayer.currentTime - 5); });
  btnForward.addEventListener('click', () => {
    if (isFinite(mediaPlayer.duration)) {
      mediaPlayer.currentTime = Math.min(mediaPlayer.duration, mediaPlayer.currentTime + 5);
    }
  });
  btnSpeed.addEventListener('click', () => {
    rateIdx = (rateIdx + 1) % RATES.length;
    mediaPlayer.playbackRate = RATES[rateIdx];
    btnSpeed.textContent = RATES[rateIdx] + 'x';
  });
  // 播放状态变化 → 图标和进度跟着刷
  mediaPlayer.addEventListener('play', updatePlayIcon);
  mediaPlayer.addEventListener('pause', updatePlayIcon);
  mediaPlayer.addEventListener('ended', updatePlayIcon);
  mediaPlayer.addEventListener('timeupdate', updateNowPlaying);

  // AB 复读的核心：播到 B 点就跳回 A 点（约每 0.25 秒检查一次）。
  // 例外：暂停中、或正用手拖进度条时，不抢你的播放头——
  //   这样你才能把播放头拖到 AB 段之外（比如 B 右边）去打新的点；
  //   等按下播放，'play' 里会把它送回 A 点，继续正常复读
  mediaPlayer.addEventListener('timeupdate', () => {
    if (mediaPlayer.paused || dragging) return;
    if (abPointA !== null && abPointB !== null && mediaPlayer.currentTime >= abPointB) {
      mediaPlayer.currentTime = abPointA;
    }
  });
  // 按播放（继续播放）时：如果播放头在 AB 段之外，把它送回 A 点，恢复正常复读
  mediaPlayer.addEventListener('play', () => {
    if (abPointA !== null && abPointB !== null &&
        (mediaPlayer.currentTime >= abPointB || mediaPlayer.currentTime < abPointA)) {
      mediaPlayer.currentTime = abPointA;
    }
  });
  // AB 复读：A / B / 重置 三个按钮（打点前可先拖进度条定位）
  btnA.disabled = false;
  btnB.disabled = false;
  btnAbReset.disabled = false;
  btnA.addEventListener('click', onAClick);
  btnB.addEventListener('click', onBClick);
  btnAbReset.addEventListener('click', onAbResetClick);
  btnLoop.disabled = false;
  btnLoop.addEventListener('click', onLoopClick);

  // ===== 位置记忆（第 6 步） =====
  // 新素材的时长一出来就检查：有没有上次的播放位置（>3 秒且离结尾还远才续播）
  mediaPlayer.addEventListener('loadedmetadata', () => {
    const saved = getSavedPosition(currentId);
    if (saved > 3 && isFinite(mediaPlayer.duration) && saved < mediaPlayer.duration - 5) {
      mediaPlayer.currentTime = saved;
      resumeHintUntil = Date.now() + 4000; // 底栏提示 4 秒「已从上次位置继续」
      updateNowPlaying();
    }
  });
  // 每 3 秒存一次当前位置；暂停和关页面时也补存一次
  let lastPosSave = 0;
  mediaPlayer.addEventListener('timeupdate', () => {
    const now = Date.now();
    if (now - lastPosSave > 3000) {
      lastPosSave = now;
      savePosition(currentId, mediaPlayer.currentTime);
    }
  });
  mediaPlayer.addEventListener('pause', () => savePosition(currentId, mediaPlayer.currentTime));
  window.addEventListener('beforeunload', () => savePosition(currentId, mediaPlayer.currentTime));
  // 播到结尾 = 听完了，清掉记录，下次从头播
  mediaPlayer.addEventListener('ended', () => clearPosition(currentId));

  // 进度条：拖动中只预览时间，松手才真正跳转（input → change 两阶段）
  // 刻度 0.1 秒：进度条范围 0–10000，跳转时四舍五入到最近的 0.1s
  seekBar.addEventListener('input', () => {
    dragging = true;
    const dur = mediaPlayer.duration;
    if (isFinite(dur) && dur > 0) {
      const pct = seekBar.value / 10000 * 100;
      seekBar.style.setProperty('--fill', pct + '%'); // 拖动预览：绿色填充跟着手走
      timeCur.textContent = fmtTime10(seekBar.value / 10000 * dur);
    }
  });
  seekBar.addEventListener('change', () => {
    const dur = mediaPlayer.duration;
    if (isFinite(dur) && dur > 0) {
      const t = Math.round(seekBar.value / 10000 * dur * 10) / 10; // 对齐 0.1s 刻度
      mediaPlayer.currentTime = t;
      timeCur.textContent = fmtTime10(t);
    }
    dragging = false;
  });

  // 进度条平滑增长：rAF 每帧（约 60 次/秒）直接读播放器的当前时间刷新圆点和时间。
  // 之前跟的是 timeupdate 事件（约 0.25 秒才触发一次），所以看起来一跳一跳的。
  // --fill 是自绘轨道的「已播进度」变量（CSS 里画绿色填充用）
  function tickSeekBar() {
    const dur = mediaPlayer.duration;
    if (!dragging && currentId && isFinite(dur) && dur > 0) {
      const pct = mediaPlayer.currentTime / dur * 100;
      seekBar.value = Math.round(pct / 100 * 10000);
      seekBar.style.setProperty('--fill', pct + '%');
      timeCur.textContent = fmtTime10(mediaPlayer.currentTime);
      timeDur.textContent = fmtTime10(dur);
      // 只设了 A 点还没设 B：橙色段跟着播放进度一格格往前长
      if (abPointA !== null && abPointB === null) updateAbBand();
    }
    requestAnimationFrame(tickSeekBar);
  }
  requestAnimationFrame(tickSeekBar);

  // 视频画面：✕ 收起浮窗（声音继续），🖼 随时调回
  btnVideoClose.addEventListener('click', () => { videoFloat.hidden = true; });
  btnPic.addEventListener('click', () => { videoFloat.hidden = !videoFloat.hidden; });

  // ===== 视频浮窗拖拽移动（QQ 视频窗同款：按住顶部抓手拖到任意位置） =====
  const videoDrag = document.getElementById('video-drag');
  let vfDragging = false, vfOffX = 0, vfOffY = 0;
  // 上次拖到的位置记在 localStorage，下次播放视频直接出现在老地方
  const savedVfPos = localStorage.getItem('videoFloatPos');
  if (savedVfPos) {
    try {
      const p = JSON.parse(savedVfPos);
      videoFloat.style.left = p.x + 'px';
      videoFloat.style.top = p.y + 'px';
      videoFloat.style.transform = 'none'; // 手动定位后不再用 CSS 的居中 transform
    } catch (e) { /* 记录坏了就当没有，用默认居中 */ }
  }
  videoDrag.addEventListener('pointerdown', (e) => {
    vfDragging = true;
    videoDrag.setPointerCapture(e.pointerId); // 指针事件锁定到抓手上，拖出窗口也不丢
    const r = videoFloat.getBoundingClientRect();
    vfOffX = e.clientX - r.left;              // 记住按下点相对浮窗的偏移，拖动时保持手感
    vfOffY = e.clientY - r.top;
    videoFloat.style.left = r.left + 'px';    // 从 CSS 居中切换为像素定位
    videoFloat.style.top = r.top + 'px';
    videoFloat.style.transform = 'none';
  });
  videoDrag.addEventListener('pointermove', (e) => {
    if (!vfDragging) return;
    const r = videoFloat.getBoundingClientRect();
    // 限制范围：至少一半宽度留在屏幕内、抓手不出屏，怎么拖都不会把窗口弄丢
    const x = Math.min(Math.max(e.clientX - vfOffX, -r.width * 0.5), window.innerWidth - r.width * 0.5);
    const y = Math.min(Math.max(e.clientY - vfOffY, 0), window.innerHeight - 24);
    videoFloat.style.left = x + 'px';
    videoFloat.style.top = y + 'px';
  });
  videoDrag.addEventListener('pointerup', () => {
    if (!vfDragging) return;
    vfDragging = false;
    const r = videoFloat.getBoundingClientRect();
    localStorage.setItem('videoFloatPos', JSON.stringify({ x: Math.round(r.left), y: Math.round(r.top) }));
  });
  // 双击抓手 = 清掉记忆位置，回到默认居中
  videoDrag.addEventListener('dblclick', () => {
    videoFloat.style.left = '';
    videoFloat.style.top = '';
    videoFloat.style.transform = '';
    localStorage.removeItem('videoFloatPos');
  });

  // ===== 视频浮窗缩放（QQ 视频窗同款：右下角手柄，宽高比锁定不变形） =====
  const videoResize = document.getElementById('video-resize');
  const VF_MIN_W = 200;    // 最小宽度：再小画面就看不清了
  const VF_MAX_H = 0.85;   // 高度上限 = 窗口高度的 85%（给抓手和底部播放条留位置）

  // 当前视频的宽高比（元数据还没加载出来时按 16:9 估，避免算出 0）
  function vfRatio() {
    const w = mediaPlayer.videoWidth, h = mediaPlayer.videoHeight;
    return (w > 0 && h > 0) ? (w / h) : (16 / 9);
  }

  // 把宽度夹进安全范围：不小于最小宽度、高度不超出屏幕、宽度不超出屏幕
  function vfClamp(px) {
    const r = videoFloat.getBoundingClientRect();
    // 从窗口顶部到屏幕底部还剩多少高度；至少给 35% 屏高，免得贴着屏幕底边时完全放不大
    const availH = Math.max(window.innerHeight * 0.35, window.innerHeight - Math.max(r.top, 0) - 12);
    const maxH = Math.min(window.innerHeight * VF_MAX_H, availH);
    const maxW = Math.min(window.innerWidth * 0.96, maxH * vfRatio());
    return Math.round(Math.max(VF_MIN_W, Math.min(px, maxW)));
  }

  // 应用宽度：只改宽度，高度跟着视频比例自动走——这就是「锁定横纵比」
  // 传 null = 回到 CSS 默认大小 min(640px, 92vw)
  function applyVideoSize(px) {
    videoFloat.style.width = (px == null) ? '' : vfClamp(px) + 'px';
  }

  // 打开页面时恢复上次调好的大小
  const savedVfW = parseInt(localStorage.getItem('videoFloatSize'), 10);
  if (savedVfW > 0) applyVideoSize(savedVfW);
  // 换视频后比例可能不同（横屏换竖屏），重新夹一次保证不出屏
  mediaPlayer.addEventListener('loadedmetadata', () => {
    const cur = parseInt(videoFloat.style.width, 10);
    if (cur > 0) applyVideoSize(cur);
  });
  // 浏览器窗口变大变小（含手机横竖屏切换）也跟着重新夹一次
  window.addEventListener('resize', () => {
    const cur = parseInt(videoFloat.style.width, 10);
    if (cur > 0) applyVideoSize(cur);
  });

  let vfResizing = false, vfStartW = 0, vfStartH = 0, vfAnchorX = 0, vfAnchorY = 0;
  videoResize.addEventListener('pointerdown', (e) => {
    if (videoFloat.hidden) return; // 音频素材没有画面，手柄也不该在
    e.preventDefault();
    e.stopPropagation();           // 别把按下事件传给下面的视频
    vfResizing = true;
    videoResize.setPointerCapture(e.pointerId); // 指针锁定，拖出屏幕也不丢
    const r = videoFloat.getBoundingClientRect();
    // 缩放期间改用像素定位：否则 CSS 的居中 transform 会让窗口边缩边漂
    videoFloat.style.left = r.left + 'px';
    videoFloat.style.top = r.top + 'px';
    videoFloat.style.transform = 'none';
    vfAnchorX = r.left;  // 左上角固定，右下角跟着手走
    vfAnchorY = r.top;
    vfStartW = r.width;
    vfStartH = r.height;
  });
  videoResize.addEventListener('pointermove', (e) => {
    if (!vfResizing) return;
    // 看「往右拖了多少」和「往下拖了多少」，取变化更大的那个定缩放比例——横着拖竖着拖都跟手
    const scale = Math.max((e.clientX - vfAnchorX) / vfStartW, (e.clientY - vfAnchorY) / vfStartH);
    applyVideoSize(vfStartW * scale);
  });
  videoResize.addEventListener('pointerup', () => {
    if (!vfResizing) return;
    vfResizing = false;
    const w = parseInt(videoFloat.style.width, 10);
    if (w > 0) localStorage.setItem('videoFloatSize', String(w)); // 记住大小，下次还是这个尺寸
    // 放大后如果右边/下边顶出屏幕，把窗口往回挪到看得见的位置
    // （只对「已拖到自定义位置」的窗口做——还在居中状态的本来就不会超屏）
    if (videoFloat.style.left) {
      const r = videoFloat.getBoundingClientRect();
      let x = r.left, y = r.top;
      if (r.right > window.innerWidth)  x = Math.max(0, window.innerWidth - r.width - 8);
      if (r.bottom > window.innerHeight) y = Math.max(0, window.innerHeight - r.height - 8);
      if (Math.round(x) !== Math.round(r.left) || Math.round(y) !== Math.round(r.top)) {
        videoFloat.style.left = x + 'px';
        videoFloat.style.top = y + 'px';
        localStorage.setItem('videoFloatPos', JSON.stringify({ x: Math.round(x), y: Math.round(y) }));
      }
    }
  });
  // 双击手柄 = 恢复默认大小
  videoResize.addEventListener('dblclick', () => {
    videoFloat.style.width = '';
    localStorage.removeItem('videoFloatSize');
  });

  // ===== 左栏宽度拖拽（长文件夹名看不全时用） =====
  const folderPanel = document.querySelector('.folder-panel');
  const resizer = document.getElementById('panel-resizer');
  const PANEL_MIN = 140, PANEL_MAX = 480, PANEL_DEFAULT = 220;

  // 打开页面时恢复上次的宽度（记在浏览器 localStorage 里）
  const savedW = parseInt(localStorage.getItem('folderPanelWidth'), 10);
  if (savedW >= PANEL_MIN && savedW <= PANEL_MAX) folderPanel.style.width = savedW + 'px';

  let resizing = false;
  resizer.addEventListener('mousedown', (e) => {
    resizing = true;
    document.body.style.userSelect = 'none'; // 拖拽期间不选中页面文字
    e.preventDefault();
  });
  document.addEventListener('mousemove', (e) => {
    if (!resizing) return;
    // 新宽度 = 鼠标位置 - 面板左边缘，并夹在最小/最大之间
    const w = Math.min(PANEL_MAX, Math.max(PANEL_MIN, e.clientX - folderPanel.getBoundingClientRect().left));
    folderPanel.style.width = w + 'px';
  });
  document.addEventListener('mouseup', () => {
    if (!resizing) return;
    resizing = false;
    document.body.style.userSelect = '';
    localStorage.setItem('folderPanelWidth', folderPanel.style.width); // 记住宽度
  });
  // 双击把手 = 恢复默认宽度
  resizer.addEventListener('dblclick', () => {
    folderPanel.style.width = '';
    localStorage.removeItem('folderPanelWidth');
  });

  // ===== PWA：注册 Service Worker（第 7 步） =====
  // 只在 http(s) 环境注册（file:// 双击打开时跳过）；注册成功后应用可安装、离线可开
  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    navigator.serviceWorker.register('sw.js')
      .then(() => console.log('Service Worker 注册成功：PWA 已就绪'))
      .catch((err) => console.log('Service Worker 注册失败（不影响使用）：', err));
  }

  // 导入按钮：点击触发隐藏的文件选择框
  const btnImport = document.getElementById('btn-import');
  const fileInput = document.getElementById('file-input');
  btnImport.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', async () => {
    if (fileInput.files.length > 0) await importFiles(fileInput.files, '文件');
    fileInput.value = ''; // 清空以便下次选同名文件也能触发
  });

  // 导入整个文件夹（PRD A1）：一次把文件夹里的音视频批量收进来（含子文件夹里的）
  const btnImportFolder = document.getElementById('btn-import-folder');
  const folderInput = document.getElementById('folder-input');
  // 部分浏览器不支持「选择文件夹」（例如 iPhone 的 Safari），先探测一下再给提示
  const canPickFolder = 'webkitdirectory' in document.createElement('input');
  btnImportFolder.addEventListener('click', () => {
    if (!canPickFolder) {
      alert('当前浏览器不支持「选择文件夹」（iPhone 的 Safari 就不支持）。\n可以改用「＋ 导入素材」一次多选文件，或在电脑上用 Chrome / Edge 导入。');
      return;
    }
    folderInput.click();
  });
  folderInput.addEventListener('change', async () => {
    if (folderInput.files.length > 0) await importFolder(folderInput.files); // 按原目录结构还原
    folderInput.value = '';
  });

  // 新建文件夹按钮：点亮（建在顶层；子文件夹请在文件夹上悬停点 ➕）
  const btnNewFolder = document.getElementById('btn-new-folder');
  btnNewFolder.disabled = false;
  btnNewFolder.addEventListener('click', () => createFolderFlow('root'));

  // 移动弹窗：点遮罩或关闭按钮即关闭
  document.getElementById('move-modal').addEventListener('click', (e) => {
    if (e.target.id === 'move-modal') closeModal(); // 只有点在遮罩上才关，点内容不关
  });
  document.getElementById('move-close').addEventListener('click', closeModal);

  // 小彩蛋保留：点 🌾 转一圈
  const logo = document.querySelector('.logo');
  if (logo) {
    logo.style.transition = 'transform 0.4s';
    logo.addEventListener('click', () => {
      logo.style.transform = 'rotate(360deg)';
      setTimeout(() => { logo.style.transform = ''; }, 450);
    });
  }
});
