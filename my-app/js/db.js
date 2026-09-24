/* 星禾口语 · 数据层：IndexedDB 封装（Day 7 第 3 步） */
/* 职责：所有与浏览器本地数据库打交道的代码集中在这里。
   其他文件（app.js 等）只调用本文件的函数，不直接碰 IndexedDB——
   这样将来想换存储方式时，只改这一个文件。 */

/* 用一个全局对象 DB 存放封装后的方法，避免污染更多全局变量 */
const DB = (() => {
  const DB_NAME = 'xinghe-kouyu';   // 数据库名
  const DB_VERSION = 2;             // 版本 2：第 3 步新增 folders（文件夹）表
  const STORE = 'materials';        // 表名：素材表
  const STORE_FOLDER = 'folders';   // 表名：文件夹表

  /* 内部函数：打开数据库连接（返回 Promise）。
     onupgradeneeded 只在「首次创建」或「版本升级」时触发，用于建表。
     注意：老用户（v1 库已存在）升级到 v2 时也会走到这里，老表不会被动。 */
  function open() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        // 建素材表：以 id 为主键；folderId 建索引，供按文件夹筛选
        if (!db.objectStoreNames.contains(STORE)) {
          const store = db.createObjectStore(STORE, { keyPath: 'id' });
          store.createIndex('folderId', 'folderId', { unique: false });
          store.createIndex('addedAt', 'addedAt', { unique: false });
        }
        // 第 3 步新增：文件夹表（应用内组织结构，与硬盘目录无关）
        if (!db.objectStoreNames.contains(STORE_FOLDER)) {
          const fstore = db.createObjectStore(STORE_FOLDER, { keyPath: 'id' });
          fstore.createIndex('createdAt', 'createdAt', { unique: false });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  /* 保存一个素材：把「元数据 + 文件内容(File 是 Blob 的子类，可直接入库)」写成一条记录 */
  async function saveMaterial(file, folderId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const record = {
        id: 'm_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8), // 简易唯一 id
        name: file.name,                                   // 原文件名（含扩展名）
        type: file.type.startsWith('video') ? 'video' : 'audio', // 按类型分音频/视频
        mime: file.type || '',                             // 原始 MIME 类型，播放时用
        size: file.size,                                   // 字节数，列表里显示用
        addedAt: Date.now(),                               // 导入时间戳，排序用
        folderId: folderId || 'root',                      // 所属文件夹：'root'=顶层（没归进任何文件夹），其余为文件夹 id
        blob: file,                                        // 文件内容本体（统一复制存储的核心）
      };
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).put(record); // put：存在则覆盖，不存在则新增
      tx.oncomplete = () => resolve(record);
      tx.onerror = () => reject(tx.error);
    });
  }

  /* 读取素材（可按文件夹筛选）：
     folderId 传 'all' 或不传 = 全部素材；传 'root' 或文件夹 id = 只取该文件夹下的 */
  async function getAllMaterials(folderId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly');
      const store = tx.objectStore(STORE);
      let req;
      if (!folderId || folderId === 'all') {
        req = store.getAll(); // 不筛选
      } else {
        req = store.index('folderId').getAll(folderId); // 按所属文件夹取
      }
      req.onsuccess = () => {
        const list = req.result || [];
        list.sort((a, b) => b.addedAt - a.addedAt);
        resolve(list);
      };
      req.onerror = () => reject(req.error);
    });
  }

  // 按 id 读取单个素材（点击播放时用）
  async function getMaterial(id) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const req = db.transaction(STORE, 'readonly').objectStore(STORE).get(id);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
  }

  /* 移动素材：改它的 folderId（应用内移动，不碰硬盘文件） */
  async function moveMaterial(materialId, targetFolderId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      const store = tx.objectStore(STORE);
      const getReq = store.get(materialId);
      getReq.onsuccess = () => {
        const m = getReq.result;
        if (!m) { reject(new Error('素材不存在: ' + materialId)); return; }
        m.folderId = targetFolderId;
        store.put(m); // 覆盖写回
      };
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  /* 重命名素材：只改显示名（应用内的名字），不碰原始文件 */
  async function renameMaterial(materialId, newName) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      const store = tx.objectStore(STORE);
      const getReq = store.get(materialId);
      getReq.onsuccess = () => {
        const m = getReq.result;
        if (!m) { reject(new Error('素材不存在: ' + materialId)); return; }
        m.name = newName;
        store.put(m); // 覆盖写回
      };
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  /* ===== 以下为文件夹表操作（第 3 步新增） ===== */

  // 新建文件夹：parentId 指定放在哪（'root'=顶层；传某文件夹 id = 建成它的子文件夹）
  async function saveFolder(name, parentId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const record = {
        id: 'f_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
        name: name.trim(),
        parentId: parentId || 'root', // 父文件夹：支持文件夹套文件夹；老数据没有这个字段，读取时按顶层处理
        createdAt: Date.now(),
      };
      const tx = db.transaction(STORE_FOLDER, 'readwrite');
      tx.objectStore(STORE_FOLDER).put(record);
      tx.oncomplete = () => resolve(record);
      tx.onerror = () => reject(tx.error);
    });
  }

  // 读取全部文件夹（按创建时间正序：先建的排前面）
  async function getAllFolders() {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_FOLDER, 'readonly');
      const req = tx.objectStore(STORE_FOLDER).getAll();
      req.onsuccess = () => {
        const list = req.result || [];
        list.sort((a, b) => a.createdAt - b.createdAt);
        resolve(list);
      };
      req.onerror = () => reject(req.error);
    });
  }

  // 重命名文件夹
  async function renameFolder(folderId, newName) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_FOLDER, 'readwrite');
      const store = tx.objectStore(STORE_FOLDER);
      const getReq = store.get(folderId);
      getReq.onsuccess = () => {
        const f = getReq.result;
        if (!f) { reject(new Error('文件夹不存在')); return; }
        f.name = newName.trim();
        store.put(f);
      };
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  // 删除文件夹（调用方负责先确认是空文件夹）
  async function deleteFolder(folderId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_FOLDER, 'readwrite');
      tx.objectStore(STORE_FOLDER).delete(folderId);
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  // 统计某文件夹下的素材数量（删文件夹前的安全检查用）
  async function countMaterialsIn(folderId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly');
      const req = tx.objectStore(STORE).index('folderId').getAll(folderId);
      req.onsuccess = () => resolve((req.result || []).length);
      req.onerror = () => reject(req.error);
    });
  }

  // 批量把一组文件夹里的素材移到顶层（删除文件夹树之前调用，保证素材一个不丢）
  async function moveMaterialsToRoot(folderIds) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      const store = tx.objectStore(STORE);
      for (const fid of folderIds) {
        const req = store.index('folderId').getAll(fid);
        req.onsuccess = () => {
          for (const m of (req.result || [])) {
            m.folderId = 'root'; // 只改归属，不删数据
            store.put(m);
          }
        };
      }
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  // 批量删除文件夹（传入 id 数组；调用方负责先移走素材并征得用户确认）
  async function deleteFolders(folderIds) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_FOLDER, 'readwrite');
      const store = tx.objectStore(STORE_FOLDER);
      for (const fid of folderIds) store.delete(fid);
      tx.oncomplete = () => resolve(true);
      tx.onerror = () => reject(tx.error);
    });
  }

  /* 对外暴露的方法 */
  return { saveMaterial, getMaterial, getAllMaterials, moveMaterial, renameMaterial,
           saveFolder, getAllFolders, renameFolder, deleteFolder, deleteFolders,
           countMaterialsIn, moveMaterialsToRoot };
})();
