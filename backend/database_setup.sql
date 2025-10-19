-- Flutter Student Portal Database Setup
-- Database: flutter_api
-- Run this file in phpMyAdmin or MySQL command line to create the database and tables

-- Create database if it doesn't exist
CREATE DATABASE IF NOT EXISTS flutter_api;
USE flutter_api;

-- Users table for authentication and basic user info
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    -- Deprecated: role & is_super_admin are retained for backward compatibility only.
    role ENUM('Student', 'Teacher', 'Admin') DEFAULT 'Student',
    is_super_admin TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Separate role tables (new design)
-- A user may belong to exactly one of these role tables in this app's constraints.
-- Use these tables for authorization instead of relying on users.role.
CREATE TABLE IF NOT EXISTS admins (
    user_id INT PRIMARY KEY,
    is_super_admin TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_admins_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==================
-- Tickets (Student & Superadmin)
-- ==================
CREATE TABLE IF NOT EXISTS tickets (
  id INT AUTO_INCREMENT PRIMARY KEY,
  created_by INT NOT NULL,
  level1 ENUM('request','query','complaint') NOT NULL,
  level2 VARCHAR(64) NOT NULL,
  content TEXT NOT NULL,
  status ENUM('open','in_progress','resolved','closed') NOT NULL DEFAULT 'open',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_tickets_created_by (created_by),
  INDEX idx_tickets_status (status),
  CONSTRAINT fk_tickets_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ticket_replies (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ticket_id INT NOT NULL,
  replied_by INT NOT NULL,
  reply_text VARCHAR(255) NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_ticket_replies_ticket (ticket_id),
  CONSTRAINT fk_tr_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE,
  CONSTRAINT fk_tr_user FOREIGN KEY (replied_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==============================
-- Class Attendance (daily)
-- ==============================
-- Records daily attendance per student for a specific class
CREATE TABLE IF NOT EXISTS class_attendance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    attendance_date DATE NOT NULL,
    class_name VARCHAR(100) NOT NULL,
    student_user_id INT NOT NULL,
    status ENUM('present','absent','leave') NOT NULL DEFAULT 'present',
    remarks VARCHAR(255) NULL,
    taken_by INT NULL, -- teacher user id
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_attendance_day (attendance_date, class_name, student_user_id),
    INDEX idx_attendance_lookup (attendance_date, class_name),
    INDEX idx_attendance_student (student_user_id),
    CONSTRAINT fk_att_student_user FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_att_taken_by FOREIGN KEY (taken_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS teachers (
    user_id INT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_teachers_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS students (
    user_id INT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_students_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================
-- Role-mapping triggers (idempotent)
-- Keeps teachers/admins/students tables in sync with users
-- =====================================
DROP TRIGGER IF EXISTS trg_users_ai_rolemap;
DROP TRIGGER IF EXISTS trg_users_au_rolemap;
DELIMITER //
CREATE TRIGGER trg_users_ai_rolemap
AFTER INSERT ON users FOR EACH ROW
BEGIN
  -- Map Admins to admins/teachers, Students to students
  IF NEW.role = 'Admin' OR NEW.role = 'Teacher' THEN
    IF COALESCE(NEW.is_super_admin,0) = 1 THEN
      INSERT INTO admins (user_id, is_super_admin)
      VALUES (NEW.id, 1)
      ON DUPLICATE KEY UPDATE is_super_admin = VALUES(is_super_admin);
    ELSE
      INSERT IGNORE INTO teachers (user_id) VALUES (NEW.id);
    END IF;
  ELSEIF NEW.role = 'Student' THEN
    INSERT IGNORE INTO students (user_id) VALUES (NEW.id);
  END IF;
END //

CREATE TRIGGER trg_users_au_rolemap
AFTER UPDATE ON users FOR EACH ROW
BEGIN
  -- Clear previous mappings
  DELETE FROM admins   WHERE user_id = NEW.id;
  DELETE FROM teachers WHERE user_id = NEW.id;
  DELETE FROM students WHERE user_id = NEW.id;
  -- Re-apply mapping based on current values
  IF NEW.role = 'Admin' OR NEW.role = 'Teacher' THEN
    IF COALESCE(NEW.is_super_admin,0) = 1 THEN
      INSERT INTO admins (user_id, is_super_admin)
      VALUES (NEW.id, 1)
      ON DUPLICATE KEY UPDATE is_super_admin = VALUES(is_super_admin);
    ELSE
      INSERT IGNORE INTO teachers (user_id) VALUES (NEW.id);
    END IF;
  ELSEIF NEW.role = 'Student' THEN
    INSERT IGNORE INTO students (user_id) VALUES (NEW.id);
  END IF;
END //
DELIMITER ;

-- Upgrade path for existing databases (idempotent):
-- Ensure the is_super_admin column exists even if upgrading an older DB
ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `is_super_admin` TINYINT(1) NOT NULL DEFAULT 0 AFTER `role`;

-- User profiles table for detailed user information
CREATE TABLE IF NOT EXISTS user_profiles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    full_name VARCHAR(255),
    cnic VARCHAR(15),
    date_of_birth DATE,
    gender ENUM('Male', 'Female', 'Other'),
    blood_group VARCHAR(10),
    nationality VARCHAR(100),
    religion VARCHAR(100),
    roll_number VARCHAR(50),
    class VARCHAR(50),
    batch VARCHAR(50),
    enrollment_date DATE,
    phone VARCHAR(20),
    whatsapp VARCHAR(20),
    alternative_phone VARCHAR(20),
    emergency_contact VARCHAR(20),
    emergency_relationship VARCHAR(100),
    alternative_emergency VARCHAR(20),
    alternative_emergency_relationship VARCHAR(100),
    current_address TEXT,
    permanent_address TEXT,
    city VARCHAR(100),
    province VARCHAR(100),
    postal_code VARCHAR(20),
    registration_no VARCHAR(100) NULL,
    class_teacher_of VARCHAR(100) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Courses table
CREATE TABLE IF NOT EXISTS courses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    teacher_user_id INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_courses_teacher (teacher_user_id),
    CONSTRAINT fk_courses_teacher FOREIGN KEY (teacher_user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- Attendance table
CREATE TABLE IF NOT EXISTS attendance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    course_id INT NOT NULL,
    date DATE NOT NULL,
    status ENUM('present', 'absent', 'late', 'leave') DEFAULT 'present',
    topic VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
);

-- Insert sample data for testing (idempotent)

-- Passwords:
--  admin@example.com      / password         (admin staff)
--  superadmin@example.com / admin123         (principal)
--  teacher1@example.com   / teach123         (teacher)
--  student1@example.com   / stud123          (student)
--  john.doe@example.com   / password         (student)
--  jane.smith@example.com / password         (student)

INSERT IGNORE INTO users (name, email, password, role, is_super_admin) VALUES
('Admin User', 'admin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Admin', 0),
('Super Administrator', 'superadmin@example.com', '$2y$10$quz7YiBOQmO66NvqHpPqrOenNaUYeRwGp0G/6zY.IsE.7vuWL5X8i', 'Admin', 1),
('Teacher One', 'teacher1@example.com', '$2y$10$B0SBeZDO5vo4CtM.pWFVHu/HJIjJ8ga4cSsSsRcSYQAdykQgLxOPe', 'Admin', 0),
('Student One', 'student1@example.com', '$2y$10$0KVVRA/GJ9.COcS6HTCpg.2/rZuH.merrtYv8MtmssOrzZ4oX27n.', 'Student', 0),
('John Doe', 'john.doe@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0),
('Jane Smith', 'jane.smith@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0);

-- Generic role-based backfill to keep mapping tables consistent (idempotent)
INSERT INTO admins (user_id, is_super_admin)
SELECT id, 1 FROM users WHERE role = 'Admin' AND COALESCE(is_super_admin,0) = 1
ON DUPLICATE KEY UPDATE is_super_admin = VALUES(is_super_admin);

INSERT IGNORE INTO teachers (user_id)
SELECT id FROM users WHERE (role = 'Admin' OR role = 'Teacher') AND COALESCE(is_super_admin,0) = 0;

INSERT IGNORE INTO students (user_id)
SELECT id FROM users WHERE role = 'Student';

-- Sample courses
INSERT INTO courses (name, description) VALUES
('Mathematics', 'Advanced mathematics course covering calculus and algebra'),
('Physics', 'Fundamental physics principles and laboratory work'),
('Computer Science', 'Programming and computer science fundamentals'),
('English Literature', 'Study of classic and modern literature'),
('History', 'World history from ancient to modern times');

-- Seed teacher-course assignments (idempotent) for teacher1@example.com
UPDATE courses c
JOIN users u ON u.email = 'teacher1@example.com'
SET c.teacher_user_id = u.id
WHERE c.name IN ('Mathematics','Physics','Computer Science');

-- Sample user profile for John Doe
INSERT INTO user_profiles (
    user_id, full_name, cnic, date_of_birth, gender, blood_group, 
    nationality, religion, roll_number, class, batch, enrollment_date,
    phone, whatsapp, emergency_contact, emergency_relationship,
    current_address, city, province
) VALUES (
    1, 'John Doe', '12345-1234567-1', '2000-01-15', 'Male', 'O+',
    'Pakistani', 'Islam', 'STU001', '12th Grade', '2024', '2024-01-01',
    '+92-300-1234567', '+92-300-1234567', '+92-300-7654321', 'Father',
    '123 Main Street, Gulberg', 'Lahore', 'Punjab'
);

-- Sample attendance records
INSERT INTO attendance (user_id, course_id, date, status, topic) VALUES
(1, 1, '2024-01-15', 'present', 'Introduction to Calculus'),
(1, 2, '2024-01-15', 'present', 'Newton\'s Laws'),
(1, 3, '2024-01-16', 'present', 'Variables and Data Types'),
(2, 1, '2024-01-15', 'present', 'Introduction to Calculus'),
(2, 2, '2024-01-15', 'absent', 'Newton\'s Laws');

-- Create indexes for better performance
-- email is already indexed via UNIQUE constraint on users.email
-- so no separate idx_users_email is needed
ALTER TABLE user_profiles ADD INDEX IF NOT EXISTS idx_user_profiles_user_id (user_id);
ALTER TABLE attendance ADD INDEX IF NOT EXISTS idx_attendance_user_id (user_id);
ALTER TABLE attendance ADD INDEX IF NOT EXISTS idx_attendance_course_id (course_id);
ALTER TABLE attendance ADD INDEX IF NOT EXISTS idx_attendance_date (`date`);

-- ==========================
-- App Settings (key/value)
-- ==========================
CREATE TABLE IF NOT EXISTS app_settings (
    `key` VARCHAR(100) PRIMARY KEY,
    `value` VARCHAR(255) NOT NULL,
    `updated_at` DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed default term start date if not set
INSERT IGNORE INTO app_settings (`key`, `value`) VALUES ('term_start_date', '2025-08-01');


-- ==================================
-- Per-user Attendance (simple daily)
-- ==================================
CREATE TABLE IF NOT EXISTS attendance_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    `date` DATE NOT NULL,
    status ENUM('present','absent','leave') NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_user_date (user_id, `date`),
    INDEX idx_ar_user (user_id),
    INDEX idx_ar_date (`date`),
    CONSTRAINT fk_ar_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==========================
-- Calendar dates (2020-2030)
-- ==========================
-- Master calendar table covering all days in the given span
CREATE TABLE IF NOT EXISTS calendar_dates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    `date` DATE NOT NULL UNIQUE,
    `year` INT NOT NULL,
    `month` INT NOT NULL,
    `day` INT NOT NULL,
    `day_of_week` TINYINT NOT NULL, -- 1=Sunday ... 7=Saturday (MySQL DAYOFWEEK)
    `is_weekend` TINYINT(1) NOT NULL DEFAULT 0,
    `is_holiday` TINYINT(1) NOT NULL DEFAULT 0,
    `title` VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed dates from 2020-01-01 to 2030-12-31 (idempotent)
-- Use a numbers generator via cross joins to avoid recursion limits
SET @start_date = DATE('2020-01-01');
SET @end_date   = DATE('2030-12-31');

INSERT IGNORE INTO calendar_dates (`date`, `year`, `month`, `day`, `day_of_week`, `is_weekend`)
SELECT d AS `date`,
       YEAR(d) AS `year`,
       MONTH(d) AS `month`,
       DAY(d) AS `day`,
       DAYOFWEEK(d) AS `day_of_week`,
       CASE WHEN DAYOFWEEK(d) IN (1,7) THEN 1 ELSE 0 END AS `is_weekend`
FROM (
  SELECT DATE_ADD(@start_date, INTERVAL n DAY) AS d
  FROM (
    SELECT (ones.n
           + tens.n*10
           + hundreds.n*100
           + thousands.n*1000) AS n
    FROM (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
    CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) tens
    CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) hundreds
    CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) thousands
  ) seq
) AS dates
WHERE d BETWEEN @start_date AND @end_date;

-- Helpful indexes (use ALTER TABLE for IF NOT EXISTS compatibility)
ALTER TABLE calendar_dates ADD INDEX IF NOT EXISTS idx_calendar_date (`date`);
ALTER TABLE calendar_dates ADD INDEX IF NOT EXISTS idx_calendar_year_month (`year`, `month`);

-- Upgrade: ensure teacher/admin fields exist on user_profiles
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS registration_no VARCHAR(100) NULL;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS class_teacher_of VARCHAR(100) NULL;

-- ==============================
-- User-created Calendar Events
-- ==============================
CREATE TABLE IF NOT EXISTS calendar_user_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    `date` DATE NOT NULL,
    title VARCHAR(255) NOT NULL,
    duration VARCHAR(64) NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cue_date (`date`),
    INDEX idx_cue_user_date (user_id, `date`),
    CONSTRAINT fk_cue_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==================
-- Notices (NoticeBoard)
-- ==================
CREATE TABLE IF NOT EXISTS notices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    body TEXT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_by INT NULL,
    INDEX idx_notices_created_at (created_at),
    CONSTRAINT fk_notices_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Complaints removed in favor of unified Tickets system

-- =============================================
-- Mark fixed-date Pakistani holidays (2020-2030)
-- =============================================
-- Kashmir Solidarity Day: Feb 5
UPDATE calendar_dates SET is_holiday = 1, title = 'Kashmir Solidarity Day'
WHERE `month` = 2 AND `day` = 5 AND `date` BETWEEN @start_date AND @end_date;

-- Pakistan Day: Mar 23
UPDATE calendar_dates SET is_holiday = 1, title = 'Pakistan Day'
WHERE `month` = 3 AND `day` = 23 AND `date` BETWEEN @start_date AND @end_date;
UPDATE calendar_dates SET is_holiday = 1, title = 'Labour Day'
WHERE `month` = 5 AND `day` = 1 AND `date` BETWEEN @start_date AND @end_date;

-- Independence Day: Aug 14
UPDATE calendar_dates SET is_holiday = 1, title = 'Independence Day'
WHERE `month` = 8 AND `day` = 14 AND `date` BETWEEN @start_date AND @end_date;

-- Iqbal Day: Nov 9
UPDATE calendar_dates SET is_holiday = 1, title = 'Iqbal Day'
WHERE `month` = 11 AND `day` = 9 AND `date` BETWEEN @start_date AND @end_date;

-- Quaid-e-Azam Day / Christmas: Dec 25
UPDATE calendar_dates SET is_holiday = 1, title = 'Quaid-e-Azam Day / Christmas'
WHERE `month` = 12 AND `day` = 25 AND `date` BETWEEN @start_date AND @end_date;

-- ============================================
-- Hierarchical Classes, Subjects, Assignments
-- ============================================
-- Education levels used by UI: EarlyYears, Primary, Secondary
-- We normalize classes and subjects and map teacher -> class -> subject

CREATE TABLE IF NOT EXISTS classes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    level ENUM('EarlyYears','Primary','Secondary') NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_level_name (level, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS subjects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    level ENUM('EarlyYears','Primary','Secondary') NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_subject_level_name (level, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Mapping table of subjects offered in a class (independent of teacher assignments)
CREATE TABLE IF NOT EXISTS class_subjects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_class_subject_pair (class_id, subject_id),
    INDEX idx_cs_class (class_id),
    INDEX idx_cs_subject (subject_id),
    CONSTRAINT fk_cs_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_cs_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Mapping of a single responsible teacher per class+subject.
-- If you want multiple teachers per class+subject, drop the UNIQUE below.
CREATE TABLE IF NOT EXISTS teacher_class_subject_assignments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    teacher_user_id INT NOT NULL,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_class_subject (class_id, subject_id),
    INDEX idx_tcs_teacher (teacher_user_id),
    CONSTRAINT fk_tcs_teacher FOREIGN KEY (teacher_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_tcs_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_tcs_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==============================
-- Class Subject Planner
-- ==============================
CREATE TABLE IF NOT EXISTS class_subject_plans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    teacher_user_id INT NULL,
    teacher_assignment_id INT NULL,
    academic_term_label VARCHAR(100) NULL,
    frequency ENUM('Daily','Weekly','Monthly','Custom') NOT NULL DEFAULT 'Daily',
    single_date DATE NULL,
    range_start DATE NULL,
    range_end DATE NULL,
    assignment_deadline DATE NULL,
    quiz_deadline DATE NULL,
    status ENUM('active','archived') NOT NULL DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_csp_class_subject (class_id, subject_id),
    INDEX idx_csp_teacher (teacher_user_id),
    CONSTRAINT fk_csp_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_csp_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_csp_teacher FOREIGN KEY (teacher_user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_csp_teacher_assignment FOREIGN KEY (teacher_assignment_id) REFERENCES teacher_class_subject_assignments(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Upgrade path: ensure new deadline columns exist on existing databases
ALTER TABLE class_subject_plans
  ADD COLUMN IF NOT EXISTS assignment_deadline DATE NULL AFTER range_end,
  ADD COLUMN IF NOT EXISTS quiz_deadline DATE NULL AFTER assignment_deadline;

CREATE TABLE IF NOT EXISTS class_subject_plan_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    plan_id INT NOT NULL,
    item_type ENUM('syllabus','assignment','quiz') NOT NULL,
    assignment_number INT NULL,
    quiz_number INT NULL,
    title VARCHAR(255) NULL,
    topic VARCHAR(255) NULL,
    description TEXT NULL,
    total_marks INT NULL,
    weight_percent DECIMAL(6,2) NULL,
    scheduled_for DATETIME NULL,
    scheduled_until DATETIME NULL,
    status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled',
    status_changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    verification_notes TEXT NULL,
    deferred_to DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cspi_plan (plan_id),
    INDEX idx_cspi_assignment_num (assignment_number),
    INDEX idx_cspi_quiz_num (quiz_number),
    INDEX idx_cspi_status (status),
    INDEX idx_cspi_schedule (scheduled_for),
    CONSTRAINT fk_cspi_plan FOREIGN KEY (plan_id) REFERENCES class_subject_plans(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Upgrade: ensure new number columns exist on existing databases
ALTER TABLE class_subject_plan_items
  ADD COLUMN IF NOT EXISTS assignment_number INT NULL AFTER item_type,
  ADD COLUMN IF NOT EXISTS quiz_number INT NULL AFTER assignment_number,
  ADD INDEX IF NOT EXISTS idx_cspi_assignment_num (assignment_number),
  ADD INDEX IF NOT EXISTS idx_cspi_quiz_num (quiz_number);

CREATE TABLE IF NOT EXISTS class_subject_plan_sessions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    plan_item_id INT NOT NULL,
    session_date DATE NOT NULL,
    notes TEXT NULL,
    status ENUM('scheduled','covered','cancelled') NOT NULL DEFAULT 'scheduled',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_plan_item_session (plan_item_id, session_date),
    INDEX idx_csps_plan_item (plan_item_id),
    INDEX idx_csps_status (status),
    CONSTRAINT fk_csps_plan_item FOREIGN KEY (plan_item_id) REFERENCES class_subject_plan_items(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Helper procedures to upsert subjects and map them to a class
DROP PROCEDURE IF EXISTS add_subject_to_class;
DROP PROCEDURE IF EXISTS remove_subject_from_class;
DELIMITER //
CREATE PROCEDURE add_subject_to_class(IN p_class_id INT, IN p_subject_name VARCHAR(100))
BEGIN
    DECLARE v_level ENUM('EarlyYears','Primary','Secondary');
    DECLARE v_subject_id INT;

    -- Ensure class exists and get its level
    SELECT level INTO v_level FROM classes WHERE id = p_class_id;
    IF v_level IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Class not found';
    END IF;

    -- Insert subject if it doesn't exist for this level; capture its id
    INSERT INTO subjects (level, name)
    VALUES (v_level, p_subject_name)
    ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
    SET v_subject_id = LAST_INSERT_ID();

    -- Link subject to class (idempotent)
    INSERT IGNORE INTO class_subjects (class_id, subject_id)
    VALUES (p_class_id, v_subject_id);
END //

CREATE PROCEDURE remove_subject_from_class(IN p_class_id INT, IN p_subject_id INT)
BEGIN
    DELETE FROM class_subjects
    WHERE class_id = p_class_id AND subject_id = p_subject_id;
END //
DELIMITER ;


INSERT IGNORE INTO classes (level, name) VALUES
('EarlyYears','Montessori'),
('EarlyYears','Nursery'),
('EarlyYears','Prep'),
('EarlyYears','KG'),
('EarlyYears','Playgroup'),
('Primary','Class 1'),
('Primary','Class 2'),
('Primary','Class 3'),
('Primary','Class 4'),
('Primary','Class 5'),
('Primary','Class 6'),
('Primary','Class 7'),
('Secondary','Class 8'),
('Secondary','Class 9'),
('Secondary','Class 10');

-- Seed Subjects (idempotent)
-- Early Years subjects
INSERT IGNORE INTO subjects (level, name) VALUES
('EarlyYears','English'),
('EarlyYears','Urdu'),
('EarlyYears','Math'),
('EarlyYears','Islamiyat'),
('EarlyYears','General Knowledge'),
('EarlyYears','Nazra'),
('EarlyYears','Art');

-- Primary subjects
INSERT IGNORE INTO subjects (level, name) VALUES
('Primary','English'),
('Primary','Urdu'),
('Primary','Math'),
('Primary','Science'),
('Primary','Social Studies'),
('Primary','Islamiyat'),
('Primary','Computer'),
('Primary','Nazra'),
('Primary','Art');

-- Secondary subjects
INSERT IGNORE INTO subjects (level, name) VALUES
('Secondary','English'),
('Secondary','Urdu'),
('Secondary','Math'),
('Secondary','Physics'),
('Secondary','Chemistry'),
('Secondary','Biology'),
('Secondary','Computer'),
('Secondary','Islamiyat'),
('Secondary','Pakistan Studies');

-- ======================
-- Course Meta (per class+subject)
-- ======================
-- Stores upcoming lecture/quiz times, assignment link, lectures JSON, and diary fields
CREATE TABLE IF NOT EXISTS course_meta (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    upcoming_lecture_at DATETIME NULL,
    next_quiz_at DATETIME NULL,
    next_assignment_url VARCHAR(1024) NULL,
    total_lectures INT NOT NULL DEFAULT 0,
    lectures_json TEXT NULL,
    today_topics TEXT NULL,
    revise_topics TEXT NULL,
    updated_by INT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_class_subject_meta (class_id, subject_id),
    INDEX idx_cm_class_subject (class_id, subject_id),
    CONSTRAINT fk_cm_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_cm_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_cm_user FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==============================
-- Per-student Marks (quiz/assign)
-- ==============================
DROP TABLE IF EXISTS student_marks;
-- Stores assignment analytics per student for a class+subject
CREATE TABLE IF NOT EXISTS student_assignments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    student_user_id INT NOT NULL,
    assignment_number INT NOT NULL,
    title VARCHAR(255) NULL,
    description TEXT NULL,
    total_marks INT NOT NULL,
    obtained_marks DECIMAL(6,2) NULL,
    deadline DATETIME NULL,
    submitted_at DATETIME NULL,
    graded_at DATETIME NULL,
    graded_by INT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_student_assignment (class_id, subject_id, student_user_id, assignment_number),
    INDEX idx_sa_lookup (class_id, subject_id, assignment_number),
    INDEX idx_sa_student (student_user_id),
    CONSTRAINT fk_sa_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_sa_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_sa_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_sa_teacher FOREIGN KEY (graded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE student_assignments
    ADD COLUMN IF NOT EXISTS plan_item_id INT NULL AFTER graded_by,
    ADD COLUMN IF NOT EXISTS is_template TINYINT(1) NOT NULL DEFAULT 0 AFTER plan_item_id,
    ADD COLUMN IF NOT EXISTS coverage_status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled' AFTER is_template;

ALTER TABLE student_assignments
    ADD INDEX IF NOT EXISTS idx_sa_plan_item (plan_item_id);

-- Stores quiz analytics per student for a class+subject
CREATE TABLE IF NOT EXISTS student_quizzes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    student_user_id INT NOT NULL,
    quiz_number INT NOT NULL,
    title VARCHAR(255) NULL,
    topic VARCHAR(255) NULL,
    total_marks INT NOT NULL,
    obtained_marks DECIMAL(6,2) NULL,
    scheduled_at DATETIME NULL,
    attempted_at DATETIME NULL,
    graded_at DATETIME NULL,
    graded_by INT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_student_quiz (class_id, subject_id, student_user_id, quiz_number),
    INDEX idx_sq_lookup (class_id, subject_id, quiz_number),
    INDEX idx_sq_student (student_user_id),
    CONSTRAINT fk_sq_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_sq_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_sq_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_sq_teacher FOREIGN KEY (graded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE student_quizzes
    ADD COLUMN IF NOT EXISTS plan_item_id INT NULL AFTER graded_by,
    ADD COLUMN IF NOT EXISTS is_template TINYINT(1) NOT NULL DEFAULT 0 AFTER plan_item_id,
    ADD COLUMN IF NOT EXISTS coverage_status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled' AFTER is_template;

ALTER TABLE student_quizzes
    ADD INDEX IF NOT EXISTS idx_sq_plan_item (plan_item_id);

-- Stores first-term exam marks per student
CREATE TABLE IF NOT EXISTS student_first_term_marks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    student_user_id INT NOT NULL,
    total_marks INT NOT NULL,
    obtained_marks DECIMAL(6,2) NULL,
    exam_date DATE NULL,
    remarks VARCHAR(255) NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_first_term (class_id, subject_id, student_user_id),
    INDEX idx_ft_student (student_user_id),
    CONSTRAINT fk_ft_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_ft_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_ft_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Stores final-term exam marks per student
CREATE TABLE IF NOT EXISTS student_final_term_marks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    student_user_id INT NOT NULL,
    total_marks INT NOT NULL,
    obtained_marks DECIMAL(6,2) NULL,
    exam_date DATE NULL,
    remarks VARCHAR(255) NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_final_term (class_id, subject_id, student_user_id),
    INDEX idx_fft_student (student_user_id),
    CONSTRAINT fk_fft_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_fft_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_fft_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==============================
-- Challan (single-table workflow)
-- ==============================
-- Tracks the full lifecycle for fee/fine challans assigned to students, with optional files
-- for the original challan and the student's paid proof.
CREATE TABLE IF NOT EXISTS challan (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_user_id INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    category ENUM('fee','fine','other') NOT NULL DEFAULT 'fee',
    amount DECIMAL(10,2) NULL,
    due_date DATE NULL,
    status ENUM('unpaid','to_verify','processing','verified','rejected') NOT NULL DEFAULT 'unpaid',

    -- Original challan file (assigned/uploaded by admin or generated)
    challan_file_name VARCHAR(255) NULL,
    challan_original_file_name VARCHAR(255) NULL,
    challan_mime_type VARCHAR(100) NULL,
    challan_file_size INT NULL,

    -- Student paid proof file (uploaded by student)
    proof_file_name VARCHAR(255) NULL,
    proof_original_file_name VARCHAR(255) NULL,
    proof_mime_type VARCHAR(100) NULL,
    proof_file_size INT NULL,
    proof_uploaded_at DATETIME NULL,

    reviewed_by INT NULL,
    reviewed_at DATETIME NULL,
    review_note VARCHAR(255) NULL,

    created_by INT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_challan_student (student_user_id),
    INDEX idx_challan_status (status),
    INDEX idx_challan_due (due_date),

    CONSTRAINT fk_challan_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_challan_creator FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_challan_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Show the created tables
SHOW TABLES;

-- Show sample data
SELECT 'Users:' as table_name;
SELECT * FROM users;

SELECT 'User Profiles:' as table_name;
SELECT * FROM user_profiles;

SELECT 'Courses:' as table_name;
SELECT * FROM courses;

SELECT 'Attendance:' as table_name;
SELECT * FROM attendance;

SELECT 'Calendar Dates (sample):' as table_name;
SELECT * FROM calendar_dates ORDER BY `date` LIMIT 10;

ALTER TABLE user_profiles
ADD UNIQUE KEY uniq_class_teacher_of (class_teacher_of);

-- Assignment Submissions Table
-- Stores both file uploads and link submissions from students
CREATE TABLE IF NOT EXISTS assignment_submissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    student_id INT NOT NULL,
    subject_id INT NOT NULL,
    assignment_number INT NOT NULL,
    submission_type ENUM('link', 'file') NOT NULL,
    file_name VARCHAR(255),     -- Original filename if file upload
    file_type VARCHAR(100),     -- MIME type (e.g., 'application/pdf', 'image/jpeg')
    file_size INT,              -- File size in bytes
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('submitted', 'graded', 'late') DEFAULT 'submitted',
    feedback TEXT,              -- Optional teacher feedback
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    -- Foreign key constraints
    FOREIGN KEY (student_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    
    -- Indexes for better query performance
    INDEX idx_class_subject (class_id, subject_id),
    INDEX idx_student (student_id),
    INDEX idx_assignment (class_id, subject_id, assignment_number),
    INDEX idx_submission (student_id, class_id, subject_id, assignment_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE course_meta
  ADD COLUMN next_assignment_deadline DATETIME NULL AFTER next_assignment_url,
  ADD COLUMN next_assignment_number INT NULL AFTER next_assignment_deadline,
  ADD COLUMN next_quiz_topic VARCHAR(255) NULL AFTER next_quiz_at,
  ADD COLUMN last_quiz_taken_at DATETIME NULL AFTER next_quiz_at,
  ADD COLUMN last_quiz_number INT NULL AFTER last_quiz_taken_at,
  ADD COLUMN last_assignment_taken_at DATETIME NULL AFTER next_assignment_deadline,
  ADD COLUMN last_assignment_number INT NULL AFTER last_assignment_taken_at;

-- ==============================
-- User Uploaded Files Metadata
-- ==============================
-- Stores basic info about files uploaded by users
CREATE TABLE IF NOT EXISTS user_files (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    user_name VARCHAR(255) NOT NULL,
    original_file_name VARCHAR(255) NOT NULL,  -- File name as provided by user
    stored_file_name VARCHAR(255) NULL,        -- Optional: server-side stored name
    file_type VARCHAR(100) NOT NULL,           -- MIME type like 'image/png', 'application/pdf'
    file_size INT NOT NULL,                    -- Size in bytes
    uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_files_user (user_id),
    INDEX idx_user_files_uploaded (uploaded_at),
    CONSTRAINT fk_user_files_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Append-only migration for course_meta: drop unique key and add composite index including updated_at
-- This enables inserting multiple rows per (class_id, subject_id) while allowing fast retrieval of latest
ALTER TABLE course_meta DROP INDEX uniq_class_subject_meta;
ALTER TABLE course_meta ADD INDEX idx_cm_class_subject_updated (class_id, subject_id, updated_at);

-- App Settings Table for term start date (if not exists)
CREATE TABLE IF NOT EXISTS app_settings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    `key` VARCHAR(100) NOT NULL UNIQUE,
    `value` TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Insert term start date only if not exists
INSERT INTO app_settings (`key`, `value`) VALUES ('term_start_date', '2024-01-01') 
ON DUPLICATE KEY UPDATE `value` = VALUES(`value`);