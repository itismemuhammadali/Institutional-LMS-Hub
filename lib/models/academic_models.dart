import 'package:flutter/material.dart';

class AssessmentComponent {
  final String type; // e.g. Mid Term, Final, Quiz, Assignment
  final double obtained;
  final double total;
  final DateTime? takenAt;
  final String? remark;
  final Color? accent;

  const AssessmentComponent({
    required this.type,
    required this.obtained,
    required this.total,
    this.takenAt,
    this.remark,
    this.accent,
  });

  double get percentage => total <= 0 ? 0 : (obtained / total) * 100;
}

class SubjectMarkBreakdown {
  final String subjectId;
  final String subjectName;
  final String? teacherName;
  final List<AssessmentComponent> components;
  final double overallPercentage;
  final double targetPercentage;
  final Color accent;

  const SubjectMarkBreakdown({
    required this.subjectId,
    required this.subjectName,
    this.teacherName,
    required this.components,
    required this.overallPercentage,
    this.targetPercentage = 75,
    required this.accent,
  });
}

class AcademicTerm {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final double overallPercentage;
  final double gpa;
  final List<SubjectMarkBreakdown> subjects;
  final List<String> upcomingAssessments;

  const AcademicTerm({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.overallPercentage,
    required this.gpa,
    required this.subjects,
    this.upcomingAssessments = const [],
  });
}

class SchemeResource {
  final String label;
  final String url;

  const SchemeResource({
    required this.label,
    required this.url,
  });
}

class SchemeAssessmentWeight {
  final String component;
  final double weight;

  const SchemeAssessmentWeight({
    required this.component,
    required this.weight,
  });
}

class SchemeItem {
  final String subjectName;
  final String description;
  final List<String> learningOutcomes;
  final List<SchemeAssessmentWeight> assessmentWeights;
  final List<SchemeResource> resources;

  const SchemeItem({
    required this.subjectName,
    required this.description,
    this.learningOutcomes = const [],
    this.assessmentWeights = const [],
    this.resources = const [],
  });
}

class TermSummary {
  final String termName;
  final double percentage;
  final double gpa;
  final String? remarks;

  const TermSummary({
    required this.termName,
    required this.percentage,
    required this.gpa,
    this.remarks,
  });
}

class EnrollmentHistoryItem {
  final String academicYear;
  final String className;
  final String rollNumber;
  final List<TermSummary> termSummaries;

  const EnrollmentHistoryItem({
    required this.academicYear,
    required this.className,
    required this.rollNumber,
    this.termSummaries = const [],
  });
}

class AttendanceDetail {
  final String label;
  final String value;

  const AttendanceDetail({
    required this.label,
    required this.value,
  });
}

class AttendanceAnalytics {
  final double present;
  final double absent;
  final double late;
  final double excused;
  final List<AttendanceDetail> details;

  const AttendanceAnalytics({
    this.present = 0,
    this.absent = 0,
    this.late = 0,
    this.excused = 0,
    this.details = const [],
  });

  double get total => present + absent + late + excused;
}

class AcademicMetric {
  final String label;
  final double obtained;
  final double total;

  const AcademicMetric({
    required this.label,
    required this.obtained,
    required this.total,
  });

  double get ratio => total <= 0 ? 0 : (obtained / total).clamp(0, 1);
}

class AcademicYearAnalytics {
  final String yearLabel;
  final List<String> highlights;
  final List<AcademicMetric> metrics;

  const AcademicYearAnalytics({
    required this.yearLabel,
    this.highlights = const [],
    this.metrics = const [],
  });
}

class StudentAnalytics {
  final String studentId;
  final String studentName;
  final String className;
  final AttendanceAnalytics attendance;
  final AcademicYearAnalytics academics;

  const StudentAnalytics({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.attendance,
    required this.academics,
  });
}

class AcademicDashboardSampleData {
  static List<AcademicTerm> sampleTerms() {
    const accentPalette = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFFDC2626),
      Color(0xFFF59E0B),
    ];

    final subjects = [
      SubjectMarkBreakdown(
        subjectId: 'math',
        subjectName: 'Mathematics',
        teacherName: 'Mr. Usman',
        overallPercentage: 88,
        targetPercentage: 85,
        accent: accentPalette[0],
        components: const [
          AssessmentComponent(type: 'First Term', obtained: 42, total: 50, remark: 'Well done'),
          AssessmentComponent(type: 'Final Term', obtained: 88, total: 100),
          AssessmentComponent(type: 'Quiz', obtained: 18, total: 20),
          AssessmentComponent(type: 'Assignment', obtained: 9, total: 10),
        ],
      ),
      SubjectMarkBreakdown(
        subjectId: 'eng',
        subjectName: 'English Literature',
        teacherName: 'Ms. Anam',
        overallPercentage: 92,
        targetPercentage: 80,
        accent: accentPalette[1],
        components: const [
          AssessmentComponent(type: 'First Term', obtained: 46, total: 50),
          AssessmentComponent(type: 'Final Term', obtained: 94, total: 100),
          AssessmentComponent(type: 'Assignment', obtained: 10, total: 10),
        ],
      ),
      SubjectMarkBreakdown(
        subjectId: 'phy',
        subjectName: 'Physics',
        teacherName: 'Sir Imran',
        overallPercentage: 81,
        targetPercentage: 85,
        accent: accentPalette[2],
        components: const [
          AssessmentComponent(type: 'First Term', obtained: 38, total: 50),
          AssessmentComponent(type: 'Final Term', obtained: 84, total: 100),
          AssessmentComponent(type: 'Quiz', obtained: 16, total: 20),
          AssessmentComponent(type: 'Lab Assignment', obtained: 18, total: 20),
        ],
      ),
    ];

    return [
      AcademicTerm(
        id: 'term-2025-mid',
        name: 'Mid Term 2025',
        startDate: DateTime(2025, 1, 15),
        endDate: DateTime(2025, 3, 30),
        overallPercentage: 87.3,
        gpa: 3.6,
        subjects: subjects,
        upcomingAssessments: const [
          'Physics Practical on 15 Mar',
          'Mathematics Quiz on 18 Mar',
        ],
      ),
      AcademicTerm(
        id: 'term-2024-final',
        name: 'Final Term 2024',
        startDate: DateTime(2024, 8, 1),
        endDate: DateTime(2024, 12, 15),
        overallPercentage: 84.1,
        gpa: 3.4,
        subjects: subjects.map((s) {
          final adjustment = s == subjects.first ? -5 : -2;
          return SubjectMarkBreakdown(
            subjectId: '${s.subjectId}-prev',
            subjectName: s.subjectName,
            teacherName: s.teacherName,
            accent: s.accent.withOpacity(0.8),
            overallPercentage: (s.overallPercentage + adjustment).clamp(70, 95),
            targetPercentage: s.targetPercentage,
            components: s.components,
          );
        }).toList(),
        upcomingAssessments: const [
          'Result announced on 20 Dec 2024',
        ],
      ),
    ];
  }

  static List<SchemeItem> sampleScheme() {
    return const [
      SchemeItem(
        subjectName: 'Mathematics',
        description: 'Advanced algebra, calculus fundamentals, and problem solving.',
        learningOutcomes: [
          'Apply derivatives to solve rate problems',
          'Integrate rational functions using substitution',
          'Model real-world scenarios with quadratic equations',
        ],
        assessmentWeights: [
          SchemeAssessmentWeight(component: 'Quizzes', weight: 20),
          SchemeAssessmentWeight(component: 'First Term', weight: 30),
          SchemeAssessmentWeight(component: 'Final Term', weight: 40),
          SchemeAssessmentWeight(component: 'Assignments', weight: 10),
        ],
        resources: [
          SchemeResource(label: 'Course Outline PDF', url: 'https://example.com/math-outline.pdf'),
          SchemeResource(label: 'Khan Academy', url: 'https://khanacademy.org'),
        ],
      ),
      SchemeItem(
        subjectName: 'Physics',
        description: 'Mechanics, electricity, and thermodynamics covered with labs.',
        learningOutcomes: [
          'Explain Newtonian mechanics principles',
          'Apply laws of thermodynamics to heat engines',
          'Design experiments to measure charge and current',
        ],
        assessmentWeights: [
          SchemeAssessmentWeight(component: 'Lab Work', weight: 25),
          SchemeAssessmentWeight(component: 'Quizzes', weight: 15),
          SchemeAssessmentWeight(component: 'First Term', weight: 25),
          SchemeAssessmentWeight(component: 'Final Term', weight: 35),
        ],
        resources: [
          SchemeResource(label: 'Physics Lab Manual', url: 'https://example.com/physics-lab'),
        ],
      ),
    ];
  }

  static List<EnrollmentHistoryItem> sampleHistory() {
    return const [
      EnrollmentHistoryItem(
        academicYear: '2024 - 2025',
        className: 'Class 10 (Science)',
        rollNumber: 'STU-1024',
        termSummaries: [
          TermSummary(termName: 'First Term 2025', percentage: 87.3, gpa: 3.6, remarks: 'Excellent progress'),
          TermSummary(termName: 'Final Term 2024', percentage: 84.1, gpa: 3.4, remarks: 'Consistent performance'),
        ],
      ),
      EnrollmentHistoryItem(
        academicYear: '2023 - 2024',
        className: 'Class 9 (Science)',
        rollNumber: 'STU-0910',
        termSummaries: [
          TermSummary(termName: 'Final Term 2023', percentage: 82.5, gpa: 3.3),
          TermSummary(termName: 'First Term 2023', percentage: 79.8, gpa: 3.1),
        ],
      ),
    ];
  }

  static List<StudentAnalytics> sampleStudentAnalytics() {
    return [
      StudentAnalytics(
        studentId: 'stu-1024',
        studentName: 'Ayesha Khan',
        className: 'Class 10 (Science)',
        attendance: const AttendanceAnalytics(
          present: 92,
          absent: 3,
          late: 2,
          excused: 3,
          details: [
            AttendanceDetail(label: 'Present Days', value: '184'),
            AttendanceDetail(label: 'Absent Days', value: '6'),
            AttendanceDetail(label: 'Late Arrivals', value: '4'),
            AttendanceDetail(label: 'Excused Leaves', value: '6'),
            AttendanceDetail(label: 'Attendance Trend', value: 'Consistently above 90%'),
          ],
        ),
        academics: const AcademicYearAnalytics(
          yearLabel: '2024 - 2025',
          highlights: [
            'Overall GPA 3.7',
            'Top performer in Mathematics',
            'Needs improvement in Physics lab work',
          ],
          metrics: [
            AcademicMetric(label: 'First Term', obtained: 88, total: 100),
            AcademicMetric(label: 'Final Term', obtained: 91, total: 100),
            AcademicMetric(label: 'Quizzes', obtained: 78, total: 85),
            AcademicMetric(label: 'Assignments', obtained: 45, total: 50),
          ],
        ),
      ),
      StudentAnalytics(
        studentId: 'stu-1088',
        studentName: 'Bilal Ahmed',
        className: 'Class 9 (Science)',
        attendance: const AttendanceAnalytics(
          present: 85,
          absent: 8,
          late: 4,
          excused: 3,
          details: [
            AttendanceDetail(label: 'Present Days', value: '170'),
            AttendanceDetail(label: 'Absent Days', value: '16'),
            AttendanceDetail(label: 'Late Arrivals', value: '8'),
            AttendanceDetail(label: 'Excused Leaves', value: '6'),
            AttendanceDetail(label: 'Attendance Trend', value: 'Recovering after mid term drop'),
          ],
        ),
        academics: const AcademicYearAnalytics(
          yearLabel: '2024 - 2025',
          highlights: [
            'Overall GPA 3.2',
            'Improved Chemistry grades in final term',
            'Requires support in English composition',
          ],
          metrics: [
            AcademicMetric(label: 'Mid Term', obtained: 72, total: 100),
            AcademicMetric(label: 'Final Term', obtained: 80, total: 100),
            AcademicMetric(label: 'Quizzes', obtained: 60, total: 80),
            AcademicMetric(label: 'Assignments', obtained: 36, total: 45),
          ],
        ),
      ),
    ];
  }
}
