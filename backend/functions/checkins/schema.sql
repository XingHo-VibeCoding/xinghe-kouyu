-- ============================================================
-- 签到功能建表 SQL（星禾口语 · Day 25）
-- ------------------------------------------------------------
-- 用法：登录腾讯云开发控制台 → 你的环境 → 数据库（PG 模式）→ SQL 编辑器，
--       整段粘贴执行一次即可（幂等，重复执行不会报错）。
-- ============================================================

-- 签到场次表（一次「发起签到」= 一行）
CREATE TABLE IF NOT EXISTS checkin_sessions (
  id text PRIMARY KEY,                          -- 场次 id（UUID）
  class_id text NOT NULL,                       -- 所属班级 id
  teacher_id text NOT NULL,                     -- 发起老师 uid
  code text NOT NULL UNIQUE,                    -- 6 位纯数字签到码
  status text NOT NULL DEFAULT 'ongoing',       -- ongoing 进行中 / closed 已终止
  created_at timestamptz NOT NULL DEFAULT now(),-- 发起时间（自动终止据此计算）
  closed_at timestamptz                         -- 手动终止时间（可空）
);

-- 签到记录表（一场次 × 每名学生 = 一行，发布时批量建好）
CREATE TABLE IF NOT EXISTS checkin_records (
  id text PRIMARY KEY,                          -- 记录 id（UUID）
  session_id text NOT NULL,                     -- 所属场次 id
  class_id text NOT NULL,                       -- 冗余班级 id（便于按班查）
  student_id text NOT NULL,                     -- 学生 uid
  status text NOT NULL DEFAULT 'absent',        -- absent 缺勤 / late 迟到 / leave 请假 / present 已到
  checked_at timestamptz,                       -- 签到时间（可空）
  updated_by text                               -- 最后手动调整的老师 uid（可空）
);

-- 常用查询索引
CREATE INDEX IF NOT EXISTS idx_checkin_sessions_class ON checkin_sessions(class_id);
CREATE INDEX IF NOT EXISTS idx_checkin_sessions_code ON checkin_sessions(code);
CREATE INDEX IF NOT EXISTS idx_checkin_records_session ON checkin_records(session_id);
CREATE INDEX IF NOT EXISTS idx_checkin_records_student ON checkin_records(session_id, student_id);
