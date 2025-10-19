# Testing Seed: Class 4 + New Teacher

This seed creates a new teacher account, four Class 4 students with profiles (roll numbers), and assigns the new teacher to Class 4 subjects so you can test the Teacher Attendance and related flows quickly.

## Contents
- File: `backend/seed_teacher_class4.sql`
- Creates:
  - 1 teacher: `teacher_class4@example.com`
  - 4 students in Class 4 with roll numbers C4-001..C4-004
  - Teacher → Class 4 subject assignments (Primary: English, Urdu, Math, Science, Islamiyat)

## Prerequisites
- Make sure you've already created the schema using `backend/database_setup.sql`.
- MySQL/MariaDB with database `flutter_api` (the scripts call `USE flutter_api;`).

## How to Run
1. Run the main setup (if not already):
   - In phpMyAdmin: import `backend/database_setup.sql`
   - Or MySQL CLI:
     ```sql
     SOURCE c:/DemoApp/demoapp/backend/database_setup.sql;
     ```
2. Run the seed:
   - In phpMyAdmin: import `backend/seed_teacher_class4.sql`
   - Or MySQL CLI:
     ```sql
     SOURCE c:/DemoApp/demoapp/backend/seed_teacher_class4.sql;
     ```

You should see verification SELECTs at the end showing the created rows.

## Test Logins
- Teacher (new):
  - Email: `teacher_class4@example.com`
  - Password: `password`
  - Role: Admin (teacher), is_super_admin = 0

- Students (all passwords: `password`):
  - `class4.student1@example.com` (Roll: C4-001)
  - `class4.student2@example.com` (Roll: C4-002)
  - `class4.student3@example.com` (Roll: C4-003)
  - `class4.student4@example.com` (Roll: C4-004)

## What it touches
- `users`, `teachers`, `students`, `user_profiles`
- `teacher_class_subject_assignments`
- No changes to `courses` table are required for this seed.

## Clean Up (Optional)
To remove the seeded accounts and assignments:
```sql
USE flutter_api;
SET @tid = (SELECT id FROM users WHERE email = 'teacher_class4@example.com' LIMIT 1);
DELETE FROM teacher_class_subject_assignments WHERE teacher_user_id = @tid;
DELETE FROM teachers WHERE user_id = @tid;
DELETE FROM users WHERE id = @tid;

DELETE FROM user_profiles WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'class4.student%');
DELETE FROM students WHERE user_id IN (SELECT id FROM users WHERE email LIKE 'class4.student%');
DELETE FROM users WHERE email LIKE 'class4.student%';
```

## Notes
- Password hash used is the same bcrypt from `database_setup.sql` for the plaintext `password`.
- If you want this teacher to also appear in legacy `admins` checks, uncomment the `admins` insert in `seed_teacher_class4.sql`.
