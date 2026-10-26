-- ============================================================
-- 星禾口语 · 云端数据库建表脚本 v2（Day 20，班级管理 MVP）
-- 目标库：CloudBase PostgreSQL（HTTP API 网关访问，仅 public schema）
-- 注意：这是「云端共享数据」的表，不是播放器本地数据（本地用 sqflite）
--
-- v2 变更（对照 TECH_DESIGN.md 6.1）：
--   1. users.id 从自增数字改为「匿名登录 uid（文本）」——身份能对上云登录
--   2. users.name → nickname（MVP 用户自填昵称）
--   3. classes 增加 code（唯一班级码，学生加入凭证）
--   4. class_members 增加 role（成员在班内的角色）+ 唯一约束防重复加入
--   5. materials → class_files（文件本体进云存储，表里只存 cloud_path 标签）
--
-- ⚠️ 执行前须知：脚本开头会 DROP 旧表（旧的是 Day 16 测试数据），
--    确认不需要保留旧数据后再执行。
-- ============================================================

-- 先删旧表（CASCADE = 连依赖一起删，顺序无所谓）
DROP TABLE IF EXISTS class_files CASCADE;
DROP TABLE IF EXISTS class_members CASCADE;
DROP TABLE IF EXISTS classes CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- 表 1：用户（MVP 用匿名登录 uid 当身份证，nickname 自填，role 区分老师/学生）
CREATE TABLE users (
    id         TEXT PRIMARY KEY,                   -- 匿名登录返回的 uid（设备维度，非真用户身份）
    nickname   VARCHAR(50)  NOT NULL,              -- 昵称（首次进入填写）
    role       VARCHAR(10)  NOT NULL,              -- 身份：teacher / student
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 表 2：班级（老师创建；code 是学生加入的凭证，全局唯一）
CREATE TABLE classes (
    id         TEXT PRIMARY KEY,                   -- 班级 id（uuid，由云函数生成）
    name       VARCHAR(50)  NOT NULL,              -- 班级名
    code       VARCHAR(10)  NOT NULL UNIQUE,       -- 班级码（6 位大写字母数字）
    teacher_id TEXT         NOT NULL REFERENCES users(id), -- 建班老师
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 表 3：班级成员（多对多中间表；role 记录成员在「这个班」里的角色）
CREATE TABLE class_members (
    id        BIGSERIAL PRIMARY KEY,
    class_id  TEXT NOT NULL REFERENCES classes(id),
    user_id   TEXT NOT NULL REFERENCES users(id),
    role      VARCHAR(10) NOT NULL,                -- teacher / student
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (class_id, user_id)                     -- 防重复加入
);

-- 表 4：班级文件（元数据账本；文件本体在云存储，cloud_path 是仓库里的位置）
CREATE TABLE class_files (
    id          TEXT PRIMARY KEY,                  -- 文件记录 id（uuid）
    class_id    TEXT         NOT NULL REFERENCES classes(id),
    title       VARCHAR(100) NOT NULL,             -- 展示名（如「第1课 跟读」）
    cloud_path  VARCHAR(255) NOT NULL,             -- 云存储里的路径（如 class-files/xxx.mp3）
    size        BIGINT,                            -- 字节数
    format      VARCHAR(10),                       -- mp3 / mp4 等
    uploader_id TEXT         NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
