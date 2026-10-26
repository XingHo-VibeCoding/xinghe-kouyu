-- ============================================================
-- 星禾口语 · 种子数据脚本 v2（Day 20，配合 schema.sql v2）
-- 要求：可复现——「先清空、再插入」，每次执行都重置成完全一样的示例数据。
-- ⚠️ 注意：users.id 现在是匿名登录 uid（文本）。真实使用中 uid 由前端匿名
--    登录产生；种子数据里用假 uid 仅作开发联调用。
-- ============================================================

-- 先清空（顺序：先子表后父表，避免外键约束报错）
DELETE FROM class_files;
DELETE FROM class_members;
DELETE FROM classes;
DELETE FROM users;

-- 用户（假 uid 模拟两台设备的匿名登录结果）
INSERT INTO users (id, nickname, role) VALUES
  ('dev-uid-teacher-01', '王老师', 'teacher'),
  ('dev-uid-student-01', '小明', 'student');

-- 班级（班级码固定，方便联调）
INSERT INTO classes (id, name, code, teacher_id) VALUES
  ('dev-class-01', '高级班音频', 'XH7K2M', 'dev-uid-teacher-01');

-- 成员（老师 + 学生都在班里）
INSERT INTO class_members (class_id, user_id, role) VALUES
  ('dev-class-01', 'dev-uid-teacher-01', 'teacher'),
  ('dev-class-01', 'dev-uid-student-01', 'student');

-- 班级文件（cloud_path 是云存储里的路径，此处为占位演示）
INSERT INTO class_files (id, class_id, title, cloud_path, size, format, uploader_id) VALUES
  ('dev-file-01', 'dev-class-01', '第1课 跟读', 'class-files/demo-01.mp3', 2048000, 'mp3', 'dev-uid-teacher-01');
