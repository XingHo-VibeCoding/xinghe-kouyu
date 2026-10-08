-- ============================================================
-- 星禾口语 · 云端数据库建表脚本（Day 16）
-- 目标库：CloudBase PostgreSQL（给「班级管理」等跨用户功能用）
-- 注意：这是「云端共享数据」的表，不是播放器本地数据（本地用 sqflite）
-- ============================================================

-- 表 1：用户（老师、学生都是「用户」，靠 role 字段区分身份）
CREATE TABLE IF NOT EXISTS users (
    id         BIGSERIAL PRIMARY KEY,              -- 主键：每行唯一身份证，自增
    name       VARCHAR(50)  NOT NULL,              -- 姓名
    role       VARCHAR(10)  NOT NULL,              -- 身份：teacher / student
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now() -- 创建时间（带时区）
);

-- 表 2：班级（由某位老师创建）
CREATE TABLE IF NOT EXISTS classes (
    id         BIGSERIAL PRIMARY KEY,              -- 主键
    name       VARCHAR(50)  NOT NULL,              -- 班级名
    teacher_id BIGINT       NOT NULL REFERENCES users(id), -- 外键：这个班是哪个老师建的
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- 表 3：班级成员（多对多中间表：一个班多个学生、一个学生可加多个班）
CREATE TABLE IF NOT EXISTS class_members (
    id        BIGSERIAL PRIMARY KEY,
    class_id  BIGINT NOT NULL REFERENCES classes(id), -- 外键：哪个班
    user_id   BIGINT NOT NULL REFERENCES users(id),   -- 外键：哪个学生
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 表 4：资源（老师发到某个班的音视频）
CREATE TABLE IF NOT EXISTS materials (
    id         BIGSERIAL PRIMARY KEY,
    class_id   BIGINT       NOT NULL REFERENCES classes(id), -- 外键：发给哪个班
    title      VARCHAR(100) NOT NULL,              -- 资源标题
    file_url   VARCHAR(255) NOT NULL,              -- 文件在云端的地址（存 URL，不存文件本体）
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
