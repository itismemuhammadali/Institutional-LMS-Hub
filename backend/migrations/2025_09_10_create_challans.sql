-- Migration: Challan Workflow (Templates, Assignments, Proofs, Audit)
-- Target DB: flutter_api
-- Run this in phpMyAdmin or MySQL CLI after the base database_setup.sql

CREATE DATABASE IF NOT EXISTS flutter_api;
USE flutter_api;

-- ==============================
-- 1) Challan Templates (Admin)
-- ==============================
-- Superadmin uploads a master challan PDF (e.g., monthly fee, specific fine) to reuse or assign.
CREATE TABLE IF NOT EXISTS challan_templates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  description TEXT NULL,
  category ENUM('fee','fine','other') NOT NULL DEFAULT 'fee',
  file_name VARCHAR(255) NOT NULL,           -- stored filename on disk
  original_file_name VARCHAR(255) NULL,      -- original client filename
  mime_type VARCHAR(100) NULL,
  file_size INT NULL,
  created_by INT NULL,                       -- admin user id
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_ct_category (category),
  INDEX idx_ct_created_by (created_by),
  CONSTRAINT fk_ct_created_by FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================
-- 2) Student Challans (Assignments)
-- =====================================
-- A specific challan assigned to a student. Can optionally reference a template
-- and/or carry a per-student PDF if uploaded individually.
CREATE TABLE IF NOT EXISTS student_challans (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_user_id INT NOT NULL,
  template_id INT NULL,
  title VARCHAR(255) NOT NULL,
  amount DECIMAL(10,2) NULL,
  due_date DATE NULL,
  status ENUM('unpaid','to_verify','processing','verified','rejected') NOT NULL DEFAULT 'unpaid',
  challan_file_name VARCHAR(255) NULL,       -- stored filename for the specific student challan (optional if using template)
  original_file_name VARCHAR(255) NULL,
  mime_type VARCHAR(100) NULL,
  file_size INT NULL,
  created_by INT NULL,                       -- admin user id who assigned/created it
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_sc_student (student_user_id),
  INDEX idx_sc_status (status),
  INDEX idx_sc_due (due_date),
  INDEX idx_sc_template (template_id),
  CONSTRAINT fk_sc_student FOREIGN KEY (student_user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_sc_template FOREIGN KEY (template_id) REFERENCES challan_templates(id) ON DELETE SET NULL,
  CONSTRAINT fk_sc_creator FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ======================================
-- 3) Student Challan Proofs (Uploads)
-- ======================================
-- Student uploads payment proof (PDF/image). Keep history (append-only) to allow re-uploads.
CREATE TABLE IF NOT EXISTS student_challan_proofs (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_challan_id INT NOT NULL,
  uploaded_by INT NOT NULL,                  -- student user id
  file_name VARCHAR(255) NOT NULL,           -- stored filename on disk
  original_file_name VARCHAR(255) NULL,
  mime_type VARCHAR(100) NULL,
  file_size INT NULL,
  uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  processing_status ENUM('submitted','processing','approved','rejected') NOT NULL DEFAULT 'submitted',
  reviewer_user_id INT NULL,                 -- admin who approved/rejected this proof (optional)
  reviewed_at DATETIME NULL,
  review_note VARCHAR(255) NULL,
  INDEX idx_scp_challan (student_challan_id),
  INDEX idx_scp_uploader (uploaded_by),
  INDEX idx_scp_status (processing_status),
  CONSTRAINT fk_scp_challan FOREIGN KEY (student_challan_id) REFERENCES student_challans(id) ON DELETE CASCADE,
  CONSTRAINT fk_scp_uploader FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_scp_reviewer FOREIGN KEY (reviewer_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ==========================
-- 4) Audit Log (Optional)
-- ==========================
-- Track actions for transparency and debugging
CREATE TABLE IF NOT EXISTS challan_audit_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  student_challan_id INT NOT NULL,
  actor_user_id INT NULL,
  action ENUM('created','downloaded','uploaded_proof','status_changed','verified','rejected') NOT NULL,
  note VARCHAR(255) NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_cal_challan (student_challan_id),
  INDEX idx_cal_action (action),
  CONSTRAINT fk_cal_challan FOREIGN KEY (student_challan_id) REFERENCES student_challans(id) ON DELETE CASCADE,
  CONSTRAINT fk_cal_actor FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================
-- 5) Convenience Views (optional)
-- ============================
-- A view to fetch latest proof per challan (if any)
DROP VIEW IF EXISTS v_student_challan_latest_proof;
CREATE VIEW v_student_challan_latest_proof AS
SELECT p.*
FROM student_challan_proofs p
JOIN (
  SELECT student_challan_id, MAX(id) AS max_id
  FROM student_challan_proofs
  GROUP BY student_challan_id
) lastp ON lastp.student_challan_id = p.student_challan_id AND lastp.max_id = p.id;

-- ==========================
-- 6) Seed Example (optional)
-- ==========================
-- These are safe idempotent inserts only for demo DBs; remove in production.
-- INSERT INTO challan_templates (title, description, category, file_name, original_file_name, mime_type, file_size, created_by)
-- VALUES ('September Fee Challan', 'Monthly fee for September', 'fee', 'template_sep_fee_2025.pdf', 'sep_fee.pdf', 'application/pdf', 123456, 2);

-- Notes on storage paths:
--   - Store template PDFs under: backend/uploads/challans/templates/
--   - Store per-student challan PDFs under: backend/uploads/challans/student/
--   - Store student proofs under: backend/uploads/challans/proofs/
-- Actual folder creation and upload handling will be implemented in later steps.
