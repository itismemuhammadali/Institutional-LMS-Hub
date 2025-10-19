-- Seed: New teacher + 4 students for Class 4, and assignments
-- Assumes database_setup.sql has been run and DB is `flutter_api`
USE flutter_api;

-- =====================
-- Accounts & Base Roles
-- =====================
-- Note: passwords use bcrypt hash for the plaintext 'password'
-- Hash reused from database_setup.sql: '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'

-- 1) Create a new teacher user (role stored as Admin for compatibility) and map into teachers table
INSERT IGNORE INTO users (name, email, password, role, is_super_admin)
VALUES ('Class 4 Teacher', 'teacher_class4@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Admin', 0);

INSERT IGNORE INTO teachers (user_id)
SELECT id FROM users WHERE email = 'teacher_class4@example.com' LIMIT 1;

-- (Optional) If you also want this teacher to have admin staff abilities in legacy checks, uncomment below
-- INSERT IGNORE INTO admins (user_id, is_super_admin)
-- SELECT id, 0 FROM users WHERE email = 'teacher_class4@example.com' LIMIT 1;

-- 2) Create 4 new students of Class 4
INSERT IGNORE INTO users (name, email, password, role, is_super_admin) VALUES
('Class4 Student One',   'class4.student1@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0),
('Class4 Student Two',   'class4.student2@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0),
('Class4 Student Three', 'class4.student3@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0),
('Class4 Student Four',  'class4.student4@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0);

INSERT IGNORE INTO students (user_id)
SELECT id FROM users WHERE email IN (
  'class4.student1@example.com',
  'class4.student2@example.com',
  'class4.student3@example.com',
  'class4.student4@example.com'
);

-- 3) Create user_profiles for those students and mark class as 'Class 4'
INSERT IGNORE INTO user_profiles (user_id, full_name, roll_number, class, batch, enrollment_date)
SELECT u.id, u.name, rn.roll_number, 'Class 4', '2025', '2025-08-01'
FROM users u
JOIN (
  SELECT 'class4.student1@example.com' AS email, 'C4-001' AS roll_number UNION ALL
  SELECT 'class4.student2@example.com', 'C4-002' UNION ALL
  SELECT 'class4.student3@example.com', 'C4-003' UNION ALL
  SELECT 'class4.student4@example.com', 'C4-004'
) rn ON rn.email = u.email
WHERE u.email IN (
  'class4.student1@example.com',
  'class4.student2@example.com',
  'class4.student3@example.com',
  'class4.student4@example.com'
);

-- ==============================
-- Assign Teacher -> Class 4 Subjects
-- ==============================
-- We link the teacher to Class 4 (Primary) for selected subjects.
-- If you want more/less subjects, edit the list in the IN() clause below.

-- Resolve ids
SET @teacher_id = (SELECT id FROM users WHERE email = 'teacher_class4@example.com' LIMIT 1);
SET @class4_id  = (
  SELECT id FROM classes WHERE level = 'Primary' AND name = 'Class 4' LIMIT 1
);

-- Insert assignments for common Primary subjects
INSERT IGNORE INTO teacher_class_subject_assignments (teacher_user_id, class_id, subject_id)
SELECT @teacher_id AS teacher_user_id, @class4_id AS class_id, s.id AS subject_id
FROM subjects s
WHERE s.level = 'Primary' AND s.name IN ('English','Urdu','Math','Science','Islamiyat');

-- ==================
-- Quick Verification
-- ==================
SELECT 'Teacher:' AS section; SELECT id, name, email FROM users WHERE email = 'teacher_class4@example.com';
SELECT 'Teacher Mapping:' AS section; SELECT * FROM teachers WHERE user_id = @teacher_id;
SELECT 'Class 4:' AS section; SELECT @class4_id AS class4_id;
SELECT 'Assignments:' AS section; SELECT * FROM teacher_class_subject_assignments WHERE teacher_user_id = @teacher_id AND class_id = @class4_id;
SELECT 'Students:' AS section; SELECT id, name, email FROM users WHERE email LIKE 'class4.student%';
SELECT 'Student Profiles:' AS section; SELECT user_id, full_name, roll_number, class FROM user_profiles WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'class4.student%');
