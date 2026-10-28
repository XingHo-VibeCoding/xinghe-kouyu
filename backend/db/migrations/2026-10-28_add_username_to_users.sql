-- ============================================================
-- 星禾口语 · 增量迁移：users 表加 username 列（Day 24 追加任务）
-- 目标库：CloudBase PostgreSQL（控制台「数据库 → SQL 执行」里跑）
--
-- 目的：
--   账号系统上线后，users.id 已经是 CloudBase 账号 uid，但管理台
--   只看得到一串 uid，分不清谁是谁。补一列 username（注册时设置的
--   登录用户名），管理台就能把「账号 ↔ 业务资料」对上号。
--
-- 特性：可回放（重复执行不报错）——
--   IF NOT EXISTS 保证列已存在时跳过；存量行 UPDATE 用子查询判空。
--   旧测试账号没有 username，留 NULL，不影响现有功能。
-- ============================================================

-- 1. 加列：可空（旧账号没有 username，不补默认值避免脏数据）
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS username VARCHAR(32);

-- 2. （可选）给 username 建索引：将来「按用户名查资料」用得上；
--    PostgREST 网关不支持 JOIN，按列精确过滤是常用手段，有索引不慌。
CREATE INDEX IF NOT EXISTS idx_users_username ON users (username);

-- 3. 验证：执行后应能在结果里看到 username 列（全部为 NULL 属正常）
SELECT id, nickname, username, role, created_at FROM users ORDER BY created_at;
