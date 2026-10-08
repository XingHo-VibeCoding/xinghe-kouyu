-- ============================================================
-- 星禾口语 · 种子数据脚本（Day 16）
-- 要求：可复现——「先清空、再插入」，每次执行都重置成完全一样的示例数据。
--       因此重复执行不会报错、也不会累积重复行。
-- ============================================================

-- 第一步：清空四张表（先子表后父表，避免外键拦截；RESTART IDENTITY 让 id 从 1 重来）
TRUNCATE TABLE materials, class_members, classes, users RESTART IDENTITY CASCADE;

-- 第二步：重新插入示例数据（每张核心表 ≥ 5 行）

-- 用户：2 位老师 + 5 位学生（共 7 行）
INSERT INTO users (name, role) VALUES
    ('王老师', 'teacher'),
    ('李老师', 'teacher'),
    ('张三',   'student'),
    ('李四',   'student'),
    ('王五',   'student'),
    ('赵六',   'student'),
    ('孙七',   'student');

-- 班级：5 个班，由两位老师创建（teacher_id 对应上面 users 的自增 id）
INSERT INTO classes (name, teacher_id) VALUES
    ('高级班', 1),
    ('中级班', 1),
    ('影视班', 1),
    ('中级班', 2),
    ('影视班', 2);

-- 班级成员：把 5 位学生分到各班（共 7 条关系；王五同时加了高级班和中级班）
INSERT INTO class_members (class_id, user_id) VALUES
    (1, 3),
    (1, 4),
    (2, 5),
    (2, 6),
    (3, 7),
    (4, 7),
    (1, 5);

-- 资源：老师发到各班的音视频（共 7 行，覆盖 5 个班）
INSERT INTO materials (class_id, title, file_url) VALUES
    (1, 'Lesson 01 · 问候语精讲', 'https://example.com/materials/lesson01.mp3'),
    (1, 'Lesson 02 · 餐厅点餐对话', 'https://example.com/materials/lesson02.mp3'),
    (2, 'Lesson 03 · 自我介绍',     'https://example.com/materials/lesson03.mp3'),
    (2, 'Lesson 04 · 发音对比',     'https://example.com/materials/lesson04.mp4'),
    (3, 'Lesson 05 · 字母表',       'https://example.com/materials/lesson05.mp3'),
    (4, 'Lesson 06 · 数字发音',     'https://example.com/materials/lesson06.mp3'),
    (5, 'Lesson 07 · 情景对话练习', 'https://example.com/materials/lesson07.mp3');
