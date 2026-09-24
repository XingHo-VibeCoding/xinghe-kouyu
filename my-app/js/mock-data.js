/*
 * 星禾口语 · mock 假数据（Day 8 板块③）
 *
 * 作用：今天不接真实数据，先用写死在代码里的一批「假素材」把页面渲染出来。
 * 为什么单独放一个文件：把「数据从哪来」和「页面怎么画」分成两层。
 *   第 3 周接真实数据时，只要把最下面的 fetchMockMaterials() 换成「读 IndexedDB」，
 *   main-view.js 里的渲染代码一行都不用改——这就是假数据的最大价值。
 *
 * 字段刻意和以后真实数据的字段对齐（id / name / type / folder / duration / listened）。
 */

// 一条素材长什么样：
//   id       唯一编号（以后用真实素材的 id 替换）
//   name     文件名
//   type     'audio' 音频 / 'video' 视频（决定列表里显示 🎵 还是 🎬）
//   folder   归属的文件夹名
//   duration 总时长（秒）
//   listened 已听时长（秒）—— 进度百分比由它俩算出来
const MOCK_MATERIALS = [
  { id: 'm1', name: '第03课-连读与弱读.mp3', type: 'audio', folder: '第三课', duration: 754, listened: 588 },
  { id: 'm2', name: '第02课-句子重音.mp3', type: 'audio', folder: '第三课', duration: 560, listened: 252 },
  { id: 'm3', name: '口语示范-日常对话.mp4', type: 'video', folder: '示范课', duration: 1510, listened: 181 },
  { id: 'm4', name: '晨读打卡-第7天.mp3', type: 'audio', folder: '顶层', duration: 245, listened: 0 },
  // 下面这条故意起个很长的名字：用来验证「名字太长不会把列表撑破」
  { id: 'm5', name: '第05课-雅思口语Part2话题串讲-如何描述一个你敬佩的人-完整版录音.mp3', type: 'audio', folder: '拓展课', duration: 2412, listened: 723 },
  { id: 'm6', name: '第01课-音标入门.mp3', type: 'audio', folder: '第一课', duration: 900, listened: 900 },
];

// 「连续打卡」这种整体数据不是从素材里算出来的，先用一个常量顶着
const MOCK_STREAK_DAYS = 6;

/*
 * 假接口：模拟「向服务器要数据」的过程。
 * 真接口一定是异步的（要等网络、要等数据库），所以这里也用 Promise 包一层，
 * 并故意延迟 900 毫秒——这样页面才能真的进入「加载中」状态，你才有机会看到骨架屏。
 */
function fetchMockMaterials() {
  return new Promise((resolve) => {
    setTimeout(() => {
      // 返回副本而不是原数组：避免页面上的改动污染这份「数据源」
      resolve(MOCK_MATERIALS.map((m) => Object.assign({}, m)));
    }, 900);
  });
}
