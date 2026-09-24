/*
 * 星禾口语 · 可复用组件库（Day 8 余力加练）
 *
 * 什么是「组件」？一句话：给它一组参数（props），它还你一段 HTML。
 *   - 纯函数：同样的输入永远得到同样的输出，不碰页面、不碰数据库（没有副作用）
 *   - 自带转义：外部文字进来一律 esc()，谁用都不会漏掉这一步
 *   - 一处改、处处生效：卡片的样式逻辑只写在这里，三个页面用都是同一套
 *
 * 用法（直接当 map 的回调，很顺手）：
 *   elStats.innerHTML = cards.map(Components.statCard).join('');
 *   elList.innerHTML  = materials.map(Components.materialItem).join('');
 *
 * 注意：整体挂在 window 上的 Components 对象里，没有用 ES Module（保持零构建、双击即用）。
 */
const Components = (function () {

  /* ========== 第 1 部分：零件（组件内部要用到的小工具） ========== */

  // 把 & < > " ' 转成安全字符。文件名、标签这些文字都来自外部，
  // 直接塞进 innerHTML 有被注入的风险，一律先过这一道。
  function esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => (
      { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
    ));
  }

  // 秒数 → 分:秒（754 → 12:34）；超过一小时显示 时:分:秒
  function fmtDuration(sec) {
    const s = Math.max(0, Math.floor(Number(sec) || 0));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const ss = s % 60;
    const two = (n) => String(n).padStart(2, '0');
    return h > 0 ? h + ':' + two(m) + ':' + two(ss) : m + ':' + two(ss);
  }

  // 已听 / 总时长 → 进度百分比（整数，最高 100）
  function progressPct(listened, duration) {
    if (!duration || duration <= 0) return 0;
    return Math.min(100, Math.round((listened / duration) * 100));
  }

  /* ========== 第 2 部分：组件 ========== */

  /*
   * 统计卡片组件
   * props:
   *   value  主数字（字符串，如 '24' / '3.2'）——必填
   *   unit   单位后缀（如 '小时' / '天'），不需要就留空
   *   label  下面的说明文字（如 '素材总数'）
   */
  function statCard(props) {
    const p = props || {};
    const value = p.value === undefined ? '' : p.value;
    const unit = p.unit || '';
    const label = p.label || '';
    return '<div class="stat-card">' +
      '<span class="stat-value">' + esc(value) +
        (unit ? '<span class="stat-unit">' + esc(unit) + '</span>' : '') +
      '</span>' +
      '<span class="stat-label">' + esc(label) + '</span>' +
    '</div>';
  }

  /*
   * 素材列表条目组件
   * props:
   *   name      文件名（过长时 CSS 会自动省略号，不会撑破布局）
   *   type      'audio' 音频 / 'video' 视频 —— 决定显示 🎵 还是 🎬
   *   folder    归属文件夹名
   *   duration  总时长（秒）
   *   listened  已听时长（秒）—— 进度条宽度和百分比都由它算
   */
  function materialItem(props) {
    const m = props || {};
    const isVideo = m.type === 'video';
    // 每个字段都给一个兜底值：上游少传字段时，页面显示「未命名素材」而不是 undefined。
    // 组件被复用之后，你没法保证每个调用方都传全 —— 防御性写法就体现在这里。
    const name = m.name || '未命名素材';
    const folder = m.folder || '顶层';
    const duration = Number(m.duration) || 0;
    const pct = progressPct(m.listened, duration);
    return '<li class="mv-item">' +
      '<span class="mv-icon">' + (isVideo ? '🎬' : '🎵') + '</span>' +
      '<div class="mv-info">' +
        '<span class="mv-name">' + esc(name) + '</span>' +
        '<span class="mv-meta">📁 ' + esc(folder) + ' · ' + fmtDuration(duration) + '</span>' +
      '</div>' +
      '<div class="mv-progress"><div class="mv-bar" style="width: ' + pct + '%"></div></div>' +
      '<span class="mv-pct">' + pct + '%</span>' +
    '</li>';
  }

  // 对外只暴露这些（零件也给出去，页面算数字时用得上）
  return { esc, fmtDuration, progressPct, statCard, materialItem };
})();
