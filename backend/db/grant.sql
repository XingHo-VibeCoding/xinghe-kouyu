-- ============================================================
-- 星禾口语 · 授权脚本 v1（Day 20，班级管理 MVP）
-- 用途：给 anon（匿名）角色开放 4 张表的「读/写」权限，让云函数能通过
--       HTTP API 网关（PostgREST）正常查表、插表。
--
-- 背景（为什么需要这一步）：
--   PostgREST 网关走的是 anon 角色；PostgreSQL 默认不给 anon 任何
--   数据权限，所以之前插 users 报「permission denied for table users」。
--
-- ⚠️ 安全说明（学习期可接受，上线前必须收紧）：
--   这条脚本本质是「把 4 张表的读写权限发给匿名角色」= 任何人只要
--   拿到网关地址，就能读写这些表（无登录、无鉴权）。这是为了先把
--   班级管理链路跑通。上线前请改用「createTicket 自定义登录 + RLS
--   行级权限」收紧（见 MEMORY.md「上线前安全清单」）。
--
-- 执行位置：CloudBase 控制台 → 数据库 → SQL 编辑器（或建表同款入口）
-- 执行顺序：先跑 schema.sql（建表），再跑本脚本（授权）。
-- ============================================================

-- 4 张表的读写权限
grant select, insert, update, delete on public.users to anon;
grant select, insert, update, delete on public.classes to anon;
grant select, insert, update, delete on public.class_members to anon;
grant select, insert, update, delete on public.class_files to anon;

-- 序列权限（class_members.id 是 BIGSERIAL，插入时要取 nextval，需授权）
grant usage, select on all sequences in schema public to anon;
