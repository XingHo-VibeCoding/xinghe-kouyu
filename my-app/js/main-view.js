/*
 * 星禾口语 · 主视图渲染逻辑（Day 8 板块③：mock 数据渲染）
 *
 * 页面有四种状态，同一块内容区在不同情况下长得完全不一样：
 *   loading 加载中 —— 数据还没到，显示骨架屏（占位块），让用户知道「正在来」
 *   empty   空     —— 请求成功，但一条数据都没有（新用户第一次打开就是这个）
 *   error   出错   —— 请求失败，必须给明确的错误说明 + 一个「重试」出口
 *   data    有数据 —— 正常渲染卡片和列表
 *
 * 数据来源是 mock-data.js 里的假数据；第 3 周换成真实数据时，只改 loadData() 里那一行。
 */

// ===================== 小工具函数 =====================
// 注意：esc（防注入转义）、fmtDuration（秒→分:秒）、progressPct（算进度）
// 已经收进组件库 components.js，这里不再重复定义，用的时候写 Components.xxx。

// 秒数 → 小时（保留一位小数，如 3585 秒 → 1.0）——只在这一页用来算「已听时长」卡片
function fmtHours(sec) {
  return (sec / 3600).toFixed(1);
}

// ===================== 页面元素 =====================
const elSkeleton = document.getElementById('mv-skeleton'); // 骨架屏
const elContent = document.getElementById('mv-content');   // 正常内容外壳
const elStats = document.getElementById('mv-stats');       // 统计卡片区
const elListPanel = document.getElementById('mv-list-panel');
const elEmpty = document.getElementById('mv-empty');       // 空状态
const elList = document.getElementById('mv-list');         // 素材列表
const elCount = document.getElementById('mv-count');       // 「共 N 个」
const elError = document.getElementById('mv-error');       // 出错状态
const elErrorMsg = document.getElementById('mv-error-msg');
const elStateBar = document.getElementById('mv-state-bar'); // 开发用的状态预览条

// ===================== 渲染 =====================

// 统计卡片：数字全部从素材数据里算出来（数据变了，卡片自动跟着变）
function renderStats(materials) {
  const total = materials.length;
  const listenedSec = materials.reduce((sum, m) => sum + m.listened, 0);
  const todo = materials.filter((m) => m.listened < m.duration).length; // 还没听完的算「今日待练」

  const cards = [
    { value: String(total), unit: '', label: '素材总数' },
    { value: fmtHours(listenedSec), unit: '小时', label: '已听时长' },
    { value: String(todo), unit: '', label: '今日待练' },
    { value: String(MOCK_STREAK_DAYS), unit: '天', label: '连续打卡' },
  ];

  // 交给组件渲染：cards 里每个对象就是一张卡片的 props。
  // 直接传函数名给 map 是 JS 里的小技巧，等价于 cards.map((c) => Components.statCard(c))
  elStats.innerHTML = cards.map(Components.statCard).join('');
}

// 素材列表：一条素材交给「列表条目组件」去画，这里只负责「传数据 + 拼起来」
function renderList(materials) {
  if (materials.length === 0) {
    elList.innerHTML = '';
    return;
  }
  elList.innerHTML = materials.map(Components.materialItem).join('');
}

// ===================== 状态切换 =====================

// 最近一次拿到的数据（切回「有数据」时不用重新请求）
let lastMaterials = [];

// 每次切状态，先把四块全部藏起来，再按需要打开对应的一块
function setState(state, materials) {
  elSkeleton.hidden = true;
  elContent.hidden = true;
  elError.hidden = true;

  if (state === 'loading') {
    // 加载中：只露骨架屏
    elSkeleton.hidden = false;

  } else if (state === 'error') {
    // 出错：只露出错块（消息由调用方写进 elErrorMsg）
    elError.hidden = false;

  } else if (state === 'empty') {
    // 空：内容壳露出来，但统计区藏掉（没素材时统计数字没意义），列表换成空状态
    renderStats([]);
    renderList([]);
    elContent.hidden = false;
    elStats.hidden = true;
    elListPanel.hidden = false;
    elCount.textContent = '共 0 个';
    elEmpty.hidden = false;
    elList.hidden = true;

  } else {
    // 有数据：正常渲染卡片和列表
    const list = materials || lastMaterials;
    renderStats(list);
    renderList(list);
    elContent.hidden = false;
    elStats.hidden = false;
    elListPanel.hidden = false;
    elCount.textContent = '共 ' + list.length + ' 个';
    elEmpty.hidden = true;
    elList.hidden = false;
  }

  // 预览条上的按钮高亮当前状态
  if (elStateBar) {
    elStateBar.querySelectorAll('button[data-state]').forEach((b) => {
      b.classList.toggle('on', b.dataset.state === state);
    });
  }
}

// ===================== 取数据 =====================

// 走一遍完整流程：先进「加载中」→ 拿到数据后进「有数据」或「空」→ 失败则进「出错」
async function loadData() {
  setState('loading');
  try {
    const materials = await fetchMockMaterials(); // ← 第 3 周只改这一行（换成读真实数据）
    lastMaterials = materials;
    setState(materials.length > 0 ? 'data' : 'empty', materials);
  } catch (err) {
    elErrorMsg.textContent = (err && err.message) || '未知错误';
    setState('error');
  }
}

// ===================== 初始化 =====================

document.addEventListener('DOMContentLoaded', () => {
  // 一进页面就走一次加载流程——真实应用也是这样，用户才有「正在加载」的预期
  loadData();

  // 出错时的重试：重新走一遍加载
  document.getElementById('mv-retry').addEventListener('click', () => loadData());

  // 空状态里的导入按钮：今天是假数据版，先诚实地说明功能还没接
  document.getElementById('mv-empty-import').addEventListener('click', () => {
    alert('导入功能还没接上——今天这一页用的是假数据，接入真实素材是第 3 周的事。');
  });

  // ---- 状态预览条（开发用，不是产品功能）----
  // 有了它，你不用去改代码就能挨个看四种状态长什么样
  elStateBar.querySelectorAll('button[data-state]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const s = btn.dataset.state;
      if (s === 'loading') {
        setState('loading'); // 停在这一屏，方便观察骨架屏
      } else if (s === 'empty') {
        setState('empty');
      } else if (s === 'error') {
        // 造一个像样的错误：模拟接口挂了的提示
        elErrorMsg.textContent = '网络不太顺畅，没能取到素材列表（mock 模拟的错误）。';
        setState('error');
      } else {
        loadData(); // 「有数据」重新走一遍加载流程
      }
    });
  });

  // 收起 / 展开预览条（截图时可以收起来，画面干净）
  const barToggle = document.getElementById('mv-bar-toggle');
  barToggle.addEventListener('click', () => {
    const collapsed = elStateBar.classList.toggle('collapsed');
    barToggle.textContent = collapsed ? '+' : '−';
    barToggle.title = collapsed ? '展开状态预览' : '收起状态预览';
  });

  console.log('星禾口语 · 主视图（Day 8）：mock 数据渲染 + 四态已就绪');
});
