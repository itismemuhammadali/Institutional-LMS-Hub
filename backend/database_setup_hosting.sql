SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS user_files;
DROP TABLE IF EXISTS challan;
DROP TABLE IF EXISTS student_final_term_marks;
DROP TABLE IF EXISTS student_first_term_marks;
DROP TABLE IF EXISTS student_quizzes;
DROP TABLE IF EXISTS student_assignments;
DROP TABLE IF EXISTS course_meta;
DROP TABLE IF EXISTS class_quizzes;
DROP TABLE IF EXISTS class_assignments;
DROP TABLE IF EXISTS class_subject_plan_sessions;
DROP TABLE IF EXISTS class_subject_plan_items;
DROP TABLE IF EXISTS class_subject_plans;
DROP TABLE IF EXISTS teacher_class_subject_assignments;
DROP TABLE IF EXISTS class_subjects;
DROP TABLE IF EXISTS subjects;
DROP TABLE IF EXISTS classes;
DROP TABLE IF EXISTS assignment_submissions;
DROP TABLE IF EXISTS notices;
DROP TABLE IF EXISTS calendar_user_events;
DROP TABLE IF EXISTS attendance_records;
DROP TABLE IF EXISTS app_settings;
DROP TABLE IF EXISTS attendance;
DROP TABLE IF EXISTS courses;
DROP TABLE IF EXISTS user_profiles;
DROP TABLE IF EXISTS class_attendance;
DROP TABLE IF EXISTS ticket_replies;
DROP TABLE IF EXISTS tickets;
DROP TABLE IF EXISTS students;
DROP TABLE IF EXISTS teachers;
DROP TABLE IF EXISTS admins;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS calendar_dates;
DROP TABLE IF EXISTS student_marks;

SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role ENUM('Student', 'Teacher', 'Admin') DEFAULT 'Student',
    is_super_admin TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE admins (
    user_id INT PRIMARY KEY,
    is_super_admin TINYINT(1) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_admins_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE teachers (
    user_id INT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_teachers_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE students (
    user_id INT PRIMARY KEY,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_students_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE tickets (
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

CREATE TABLE ticket_replies (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ticket_id INT NOT NULL,
  replied_by INT NOT NULL,
  reply_text VARCHAR(255) NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_ticket_replies_ticket (ticket_id),
  CONSTRAINT fk_tr_ticket FOREIGN KEY (ticket_id) REFERENCES tickets(id) ON DELETE CASCADE,
  CONSTRAINT fk_tr_user FOREIGN KEY (replied_by) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE class_attendance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    attendance_date DATE NOT NULL,
    class_name VARCHAR(100) NOT NULL,
    student_user_id INT NOT NULL,
    status ENUM('present','absent','leave') NOT NULL DEFAULT 'present',
    remarks VARCHAR(255) NULL,
    taken_by INT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_attendance_day (attendance_date, class_name, student_user_id),
    INDEX idx_attendance_lookup (attendance_date, class_name),
    INDEX idx_attendance_student (student_user_id),
    CONSTRAINT fk_att_student_user FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_att_taken_by FOREIGN KEY (taken_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_profiles (
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
    INDEX idx_user_profiles_user_id (user_id),
    UNIQUE KEY uniq_class_teacher_of (class_teacher_of),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE courses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    teacher_user_id INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_courses_teacher (teacher_user_id),
    CONSTRAINT fk_courses_teacher FOREIGN KEY (teacher_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE attendance (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    course_id INT NOT NULL,
    date DATE NOT NULL,
    status ENUM('present', 'absent', 'late', 'leave') DEFAULT 'present',
    topic VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_attendance_user_id (user_id),
    INDEX idx_attendance_course_id (course_id),
    INDEX idx_attendance_date (`date`),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE app_settings (
    `key` VARCHAR(100) PRIMARY KEY,
    `value` TEXT NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE attendance_records (
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

CREATE TABLE calendar_dates (
    id INT AUTO_INCREMENT PRIMARY KEY,
    `date` DATE NOT NULL UNIQUE,
    `year` INT NOT NULL,
    `month` INT NOT NULL,
    `day` INT NOT NULL,
    `day_of_week` TINYINT NOT NULL,
    `is_weekend` TINYINT(1) NOT NULL DEFAULT 0,
    `is_holiday` TINYINT(1) NOT NULL DEFAULT 0,
    `title` VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_calendar_date (`date`),
    INDEX idx_calendar_year_month (`year`, `month`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    SELECT (ones.n + tens.n*10 + hundreds.n*100 + thousands.n*1000) AS n
    FROM (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) ones
    CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) tens
    CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) hundreds
    CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) thousands
  ) seq
) AS dates
WHERE d BETWEEN @start_date AND @end_date;

UPDATE calendar_dates SET is_holiday = 1, title = 'Kashmir Solidarity Day' WHERE `month` = 2 AND `day` = 5;
UPDATE calendar_dates SET is_holiday = 1, title = 'Pakistan Day' WHERE `month` = 3 AND `day` = 23;
UPDATE calendar_dates SET is_holiday = 1, title = 'Labour Day' WHERE `month` = 5 AND `day` = 1;
UPDATE calendar_dates SET is_holiday = 1, title = 'Independence Day' WHERE `month` = 8 AND `day` = 14;
UPDATE calendar_dates SET is_holiday = 1, title = 'Iqbal Day' WHERE `month` = 11 AND `day` = 9;
UPDATE calendar_dates SET is_holiday = 1, title = 'Quaid-e-Azam Day / Christmas' WHERE `month` = 12 AND `day` = 25;

CREATE TABLE calendar_user_events (
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

CREATE TABLE notices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    body TEXT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    created_by INT NULL,
    INDEX idx_notices_created_at (created_at),
    CONSTRAINT fk_notices_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE classes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    level ENUM('EarlyYears','Primary','Secondary') NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_level_name (level, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE subjects (
    id INT AUTO_INCREMENT PRIMARY KEY,
    level ENUM('EarlyYears','Primary','Secondary') NOT NULL,
    name VARCHAR(100) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_subject_level_name (level, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE class_subjects (
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

CREATE TABLE teacher_class_subject_assignments (
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

CREATE TABLE class_subject_plans (
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

CREATE TABLE class_subject_plan_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    plan_id INT NOT NULL,
    item_type ENUM('syllabus','general') NOT NULL DEFAULT 'syllabus',
    title VARCHAR(255) NULL,
    topic VARCHAR(255) NULL,
    description TEXT NULL,
    scheduled_for DATETIME NULL,
    scheduled_until DATETIME NULL,
    status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled',
    status_changed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    verification_notes TEXT NULL,
    deferred_to DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cspi_plan (plan_id),
    INDEX idx_cspi_type (item_type),
    INDEX idx_cspi_status (status),
    INDEX idx_cspi_schedule (scheduled_for),
    CONSTRAINT fk_cspi_plan FOREIGN KEY (plan_id) REFERENCES class_subject_plans(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE class_subject_plan_sessions (
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

CREATE TABLE class_assignments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    session_id INT NULL,
    teacher_user_id INT NULL,
    created_by_user_id INT NULL,
    assignment_number INT NULL,
    assignment_name VARCHAR(255) NOT NULL,
    redline TEXT NULL,
    description TEXT NULL,
    deadline DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_ca_class_subject (class_id, subject_id),
    INDEX idx_ca_assignment_number (assignment_number),
    INDEX idx_ca_session (session_id),
    CONSTRAINT fk_ca_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_ca_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_ca_session FOREIGN KEY (session_id) REFERENCES class_subject_plan_sessions(id) ON DELETE SET NULL,
    CONSTRAINT fk_ca_teacher FOREIGN KEY (teacher_user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_ca_creator FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE class_quizzes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    session_id INT NULL,
    teacher_user_id INT NULL,
    created_by_user_id INT NULL,
    quiz_number INT NULL,
    quiz_name VARCHAR(255) NOT NULL,
    redline TEXT NULL,
    description TEXT NULL,
    deadline DATETIME NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cq_class_subject (class_id, subject_id),
    INDEX idx_cq_quiz_number (quiz_number),
    INDEX idx_cq_session (session_id),
    CONSTRAINT fk_cq_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_cq_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_cq_session FOREIGN KEY (session_id) REFERENCES class_subject_plan_sessions(id) ON DELETE SET NULL,
    CONSTRAINT fk_cq_teacher FOREIGN KEY (teacher_user_id) REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT fk_cq_creator FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE course_meta (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    subject_id INT NOT NULL,
    upcoming_lecture_at DATETIME NULL,
    next_quiz_at DATETIME NULL,
    next_assignment_url VARCHAR(1024) NULL,
    next_assignment_deadline DATETIME NULL,
    next_assignment_number INT NULL,
    next_quiz_topic VARCHAR(255) NULL,
    last_quiz_taken_at DATETIME NULL,
    last_quiz_number INT NULL,
    last_assignment_taken_at DATETIME NULL,
    last_assignment_number INT NULL,
    total_lectures INT NOT NULL DEFAULT 0,
    lectures_json TEXT NULL,
    today_topics TEXT NULL,
    revise_topics TEXT NULL,
    updated_by INT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_cm_class_subject (class_id, subject_id),
    INDEX idx_cm_class_subject_updated (class_id, subject_id, updated_at),
    CONSTRAINT fk_cm_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_cm_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_cm_user FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE student_assignments (
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
    plan_item_id INT NULL,
    is_template TINYINT(1) NOT NULL DEFAULT 0,
    coverage_status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_student_assignment (class_id, subject_id, student_user_id, assignment_number),
    INDEX idx_sa_lookup (class_id, subject_id, assignment_number),
    INDEX idx_sa_student (student_user_id),
    INDEX idx_sa_plan_item (plan_item_id),
    CONSTRAINT fk_sa_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_sa_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_sa_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_sa_teacher FOREIGN KEY (graded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE student_quizzes (
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
    plan_item_id INT NULL,
    is_template TINYINT(1) NOT NULL DEFAULT 0,
    coverage_status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_student_quiz (class_id, subject_id, student_user_id, quiz_number),
    INDEX idx_sq_lookup (class_id, subject_id, quiz_number),
    INDEX idx_sq_student (student_user_id),
    INDEX idx_sq_plan_item (plan_item_id),
    CONSTRAINT fk_sq_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_sq_subject FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    CONSTRAINT fk_sq_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_sq_teacher FOREIGN KEY (graded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE student_first_term_marks (
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

CREATE TABLE student_final_term_marks (
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

CREATE TABLE challan (
    id INT AUTO_INCREMENT PRIMARY KEY,
    student_user_id INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    category ENUM('fee','fine','other') NOT NULL DEFAULT 'fee',
    amount DECIMAL(10,2) NULL,
    due_date DATE NULL,
    status ENUM('unpaid','to_verify','processing','verified','rejected') NOT NULL DEFAULT 'unpaid',
    challan_file_name VARCHAR(255) NULL,
    challan_original_file_name VARCHAR(255) NULL,
    challan_mime_type VARCHAR(100) NULL,
    challan_file_size INT NULL,
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

CREATE TABLE assignment_submissions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_id INT NOT NULL,
    student_id INT NOT NULL,
    subject_id INT NOT NULL,
    assignment_number INT NOT NULL,
    submission_type ENUM('link', 'file') NOT NULL,
    file_name VARCHAR(255),
    file_type VARCHAR(100),
    file_size INT,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('submitted', 'graded', 'late') DEFAULT 'submitted',
    feedback TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (student_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE,
    INDEX idx_class_subject (class_id, subject_id),
    INDEX idx_student (student_id),
    INDEX idx_assignment (class_id, subject_id, assignment_number),
    INDEX idx_submission (student_id, class_id, subject_id, assignment_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_files (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    user_name VARCHAR(255) NOT NULL,
    original_file_name VARCHAR(255) NOT NULL,
    stored_file_name VARCHAR(255) NULL,
    file_type VARCHAR(100) NOT NULL,
    file_size INT NOT NULL,
    uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_files_user (user_id),
    INDEX idx_user_files_uploaded (uploaded_at),
    CONSTRAINT fk_user_files_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO classes (level, name) VALUES
('EarlyYears','Montessori'),('EarlyYears','Nursery'),('EarlyYears','Prep'),('EarlyYears','KG'),('EarlyYears','Playgroup'),
('Primary','Class 1'),('Primary','Class 2'),('Primary','Class 3'),('Primary','Class 4'),('Primary','Class 5'),('Primary','Class 6'),('Primary','Class 7'),
('Secondary','Class 8'),('Secondary','Class 9'),('Secondary','Class 10');

INSERT IGNORE INTO subjects (level, name) VALUES
('EarlyYears','English'),('EarlyYears','Urdu'),('EarlyYears','Math'),('EarlyYears','Islamiyat'),('EarlyYears','General Knowledge'),('EarlyYears','Nazra'),('EarlyYears','Art'),
('Primary','English'),('Primary','Urdu'),('Primary','Math'),('Primary','Science'),('Primary','Social Studies'),('Primary','Islamiyat'),('Primary','Computer'),('Primary','Nazra'),('Primary','Art'),
('Secondary','English'),('Secondary','Urdu'),('Secondary','Math'),('Secondary','Physics'),('Secondary','Chemistry'),('Secondary','Biology'),('Secondary','Computer'),('Secondary','Islamiyat'),('Secondary','Pakistan Studies');

INSERT IGNORE INTO users (name, email, password, role, is_super_admin) VALUES
('Admin User', 'admin@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Admin', 0),
('Super Administrator', 'superadmin@example.com', '$2y$10$quz7YiBOQmO66NvqHpPqrOenNaUYeRwGp0G/6zY.IsE.7vuWL5X8i', 'Admin', 1),
('Teacher One', 'teacher1@example.com', '$2y$10$B0SBeZDO5vo4CtM.pWFVHu/HJIjJ8ga4cSsSsRcSYQAdykQgLxOPe', 'Admin', 0),
('Student One', 'student1@example.com', '$2y$10$0KVVRA/GJ9.COcS6HTCpg.2/rZuH.merrtYv8MtmssOrzZ4oX27n.', 'Student', 0),
('John Doe', 'john.doe@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0),
('Jane Smith', 'jane.smith@example.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Student', 0);

INSERT INTO admins (user_id, is_super_admin)
SELECT id, 1 FROM users WHERE role = 'Admin' AND COALESCE(is_super_admin,0) = 1
ON DUPLICATE KEY UPDATE is_super_admin = VALUES(is_super_admin);

INSERT IGNORE INTO teachers (user_id)
SELECT id FROM users WHERE (role = 'Admin' OR role = 'Teacher') AND COALESCE(is_super_admin,0) = 0;

INSERT IGNORE INTO students (user_id)
SELECT id FROM users WHERE role = 'Student';

INSERT INTO courses (name, description) VALUES
('Mathematics', 'Advanced mathematics course covering calculus and algebra'),
('Physics', 'Fundamental physics principles and laboratory work'),
('Computer Science', 'Programming and computer science fundamentals'),
('English Literature', 'Study of classic and modern literature'),
('History', 'World history from ancient to modern times');

UPDATE courses c JOIN users u ON u.email = 'teacher1@example.com' SET c.teacher_user_id = u.id WHERE c.name IN ('Mathematics','Physics','Computer Science');

INSERT INTO user_profiles (user_id, full_name, cnic, date_of_birth, gender, blood_group, nationality, religion, roll_number, class, batch, enrollment_date, phone, whatsapp, emergency_contact, emergency_relationship, current_address, city, province) VALUES
(1, 'John Doe', '12345-1234567-1', '2000-01-15', 'Male', 'O+', 'Pakistani', 'Islam', 'STU001', '12th Grade', '2024', '2024-01-01', '+92-300-1234567', '+92-300-1234567', '+92-300-7654321', 'Father', '123 Main Street, Gulberg', 'Lahore', 'Punjab');

INSERT INTO attendance (user_id, course_id, date, status, topic) VALUES
(1, 1, '2024-01-15', 'present', 'Introduction to Calculus'),
(1, 2, '2024-01-15', 'present', 'Newton\'s Laws'),
(1, 3, '2024-01-16', 'present', 'Variables and Data Types'),
(2, 1, '2024-01-15', 'present', 'Introduction to Calculus'),
(2, 2, '2024-01-15', 'absent', 'Newton\'s Laws');

INSERT IGNORE INTO app_settings (`key`, `value`) VALUES ('term_start_date', '2025-08-01');
