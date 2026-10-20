# 🎓 Institutional LMS/CMS Hub — Enterprise Academic Management & Role-Based Education Portal

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![PHP](https://img.shields.io/badge/PHP-8.x_REST_API-777BB4?style=for-the-badge&logo=php&logoColor=white)](https://php.net)
[![MySQL](https://img.shields.io/badge/MySQL-Relational_Engine-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://mysql.com)
[![Cross-Platform](https://img.shields.io/badge/Platforms-Android_%7C_iOS_%7C_macOS_%7C_Web-orange?style=for-the-badge)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](LICENSE)

---

## 🌟 Executive Overview

**Institutional LMS/CMS Hub** is a full-featured academic Learning Management System (LMS) and Campus Management System (CMS) engineered with Flutter and a decoupled relational REST API backend. The system unifies students, instructional faculty, and university administrators within a synchronized digital campus ecosystem.

### Three Unified Institutional Roles

1. **Student Academic Portal:**
   - **Academic Overview:** Real-time GPA/CGPA tracking, term attendance matrices, and course enrollment status.
   - **Assessment & Submission Desk:** Assignment downloads, digital project submissions, and instructor grading rubrics.
   - **Tuition & Dues Tracking:** Financial balance breakdowns, installment payment vouchers, and digital fee receipts.
   - **Direct Faculty Inquiries:** Secure communication channels with course instructors and academic advisors.

2. **Instructor & Faculty Management Suite:**
   - **Course Ledger Management:** Lecture syllabus publishing, dynamic course material distribution, and assignment creation.
   - **Assessment Scoring & Gradebook:** Digital exam and assessment scoring with automated statistical curve computations.
   - **Attendance Ledger:** Daily roll-call logging with automated absentee alerts and institutional reporting.

3. **University Administration & Registrar Desk:**
   - **User Provisioning:** Granular Role-Based Access Control (RBAC) governing students, faculty, department chairs, and registrars.
   - **Institutional Ledger & Dues Audit:** Campus-wide fee collection tracking, financial hold enforcements, and audit logs.
   - **Curriculum Architecture:** Academic department creation, semester degree pathways, and course prerequisites.

---

## 🏛️ System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CROSS-PLATFORM CLIENT TIERS                        │
│                                                                             │
│   ┌───────────────────────────────┐       ┌─────────────────────────────┐   │
│   │   Student Mobile / Web App    │       │   Faculty & Registrar Desk  │   │
│   │  • Attendance & Gradebook     │       │  • Course Management & Dues │   │
│   │  • Assignment Submission Hub  │       │  • Academic Record Auditing │   │
│   └───────────────┬───────────────┘       └──────────────┬──────────────┘   │
└───────────────────┼──────────────────────────────────────┼──────────────────┘
                    ▼                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RESTFUL API SERVICE TIER                            │
│                                                                             │
│   • Asynchronous PHP 8.x Microservice Endpoints (`backend/api.php`)         │
│   • Session Token & Cryptographic Credential Authentication                 │
│   • File Upload Pipeline with MIME Validation (PDF, DOCX, ZIP submissions)  │
│   • Role-Based Authorization Interceptors                                   │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       RELATIONAL DATABASE LAYER                             │
│       MySQL / MariaDB Academic Schema (`backend/database_setup.sql`)         │
│      • Students  • Faculty  • Courses  • Enrollments  • Dues  • Grades      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Complete Technology Stack

| Domain | Technology | Implementation Detail |
|---|---|---|
| **Frontend Framework** | Flutter 3.x / Dart | Single cross-platform codebase compiling to Android, iOS, Web & Desktop |
| **State Architecture** | Provider & Scoped Model | Predictable data flow with persistent local session caching |
| **Backend Services** | PHP 8.x / RESTful API | High-efficiency JSON endpoints with modular routing (`backend/`) |
| **Relational Database**| MySQL / MariaDB | 3NF normalized institutional schema with ACID transactions |
| **Document Engine** | PDF / Multi-part Stream | Dynamic academic transcript and payment voucher rendering |

---

## 🏛️ Engineering Provenance

Architected, engineered, and maintained by **Muhammad Ali** as Principal Mobile Architect.
