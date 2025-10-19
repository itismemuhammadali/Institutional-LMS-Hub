# Demo App Credentials and Roles

This document lists dummy users, their roles, and passwords for local testing after running `backend/database_setup.sql`.

All users are stored in `users` (auth) and linked to a role table:
- Admins (school admins/principals): `admins(user_id, is_super_admin)`
- Teachers: `teachers(user_id)`
- Students: `students(user_id)`

The backend derives role on-the-fly from these role tables, and exposes:
- `user.role`: "Admin" or "Student" (teachers are treated as Admin for permissions)
- `user.is_super_admin`: 1 for principal, 0 otherwise

## Accounts

- Super Admin (Principal)
  - Email: superadmin@example.com
  - Password: admin123
  - Role: Admin, is_super_admin = 1

- Admin Staff (non-teaching admin)
  - Email: admin@example.com
  - Password: password
  - Role: Admin, is_super_admin = 0

- Teacher
  - Email: teacher1@example.com
  - Password: teach123
  - Effective Role: Admin, is_super_admin = 0

- Students
  - Email: student1@example.com
  - Password: stud123 
  - Role: Student

  - Email: john.doe@example.com
  - Password: password
  - Role: Student

  - Email: jane.smith@example.com
  - Password: password
  - Role: Student

## Notes
- The `users.role` and `users.is_super_admin` fields are retained for backward compatibility but are not authoritative. Authorization uses the role tables.
- JWT claims now carry the derived `role` and `is_super_admin`.
- Listing teachers now reads from the `teachers` table.
- Student listings use the `students` table.
  