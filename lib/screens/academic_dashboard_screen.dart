import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/academic_models.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'home.dart';

class AcademicDashboardScreen extends StatefulWidget {
  const AcademicDashboardScreen({super.key, this.initialTermId});

  final String? initialTermId;

  @override
  State<AcademicDashboardScreen> createState() => _AcademicDashboardScreenState();
}

class _DeadlineButton extends StatelessWidget {
  const _DeadlineButton({
    required this.onPressed,
    required this.formatDate,
    this.date,
  });

  final VoidCallback onPressed;
  final DateTime? date;
  final String Function(DateTime) formatDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String label = date == null ? 'Set Deadline' : formatDate(date!);
    final bool hasDate = date != null;
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(hasDate ? Icons.event_available : Icons.event, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: hasDate ? theme.colorScheme.primary : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

List<String> _extractLines(String value) {
  return value
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

class _SummaryItem {
  const _SummaryItem({
    required this.title,
    required this.controller,
    this.extraLinesBuilder,
    this.onTap,
    this.includeBaseLines = true,
  });

  final String title;
  final TextEditingController controller;
  final List<_SummaryLine> Function()? extraLinesBuilder;
  final VoidCallback? onTap;
  final bool includeBaseLines;
}

class _SummaryLine {
  const _SummaryLine({required this.text, this.leading, this.useBullet = true});

  final String text;
  final String? leading;
  final bool useBullet;
}

String _normalizePlannerStatus(String? status) {
  if (status == null) {
    return 'scheduled';
  }
  final normalized = status.trim().toLowerCase();
  return normalized == 'covered' ? 'covered' : 'scheduled';
}

class _AcademicDashboardScreenState extends State<AcademicDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  bool _loading = true;
  bool _roleLoading = true;

  bool _isAdminView = false;
  bool _isSuperAdmin = false;

  List<_AdminAssignment> _adminAssignments = const [];

  List<AcademicTerm> _terms = const [];
  List<SchemeItem> _scheme = const [];
  List<EnrollmentHistoryItem> _history = const [];
  List<StudentAnalytics> _studentAnalytics = const [];
  StudentAnalytics? _selectedStudentAnalytics;
  String? _selectedTermId;
  String _studentName = 'Student';
  final TextEditingController _studentSearchController = TextEditingController();
  String? _studentSearchError;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
    _controller.addListener(_handleTabSelection);
    _initializeRoleAndAssignments();
  }

  String _formatFriendlyDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  static const List<Color> _adminAccentPalette = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFFF59E0B),
  ];

  static const List<String> _adminComponentTypes = [
    'First Term',
    'Final Term',
    'Quiz',
    'Assignment',
  ];

  Future<void> _initializeRoleAndAssignments() async {
    setState(() {
      _roleLoading = true;
    });

    try {
      final user = await ApiService.getCurrentUser();
      final role = (user?['role'] ?? '').toString().toLowerCase();
      final bool isSuperAdmin = user?['is_super_admin'] == 1 || user?['is_super_admin'] == '1';

      List<Map<String, dynamic>> assignments = const [];
      bool isAdminView = false;

      if (role == 'admin' && !isSuperAdmin) {
        try {
          assignments = await ApiService.getMyCourses();
        } catch (_) {
          assignments = const [];
        }
        isAdminView = true;
      }

      if (!mounted) return;
      setState(() {
        _isSuperAdmin = isSuperAdmin;
        _isAdminView = isAdminView;
        _adminAssignments = _parseAssignments(assignments);
      });

      if (isAdminView) {
        _syncAdminAssignmentsIntoTerms();
      } else {
        _seedSampleData();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdminView = false;
        _isSuperAdmin = false;
        _adminAssignments = const [];
      });
      _seedSampleData();
    } finally {
      if (!mounted) return;
      setState(() {
        _roleLoading = false;
        if (_terms.isNotEmpty) {
          _loading = false;
        }
      });
    }
  }

  void _seedSampleData() {
    final terms = AcademicDashboardSampleData.sampleTerms();
    final scheme = AcademicDashboardSampleData.sampleScheme();
    final history = AcademicDashboardSampleData.sampleHistory();

    setState(() {
      _terms = terms;
      _scheme = scheme;
      _history = history;
      _studentAnalytics = AcademicDashboardSampleData.sampleStudentAnalytics();
      _selectedStudentAnalytics = null;
      _studentSearchError = null;
      _selectedTermId = widget.initialTermId ?? (terms.isNotEmpty ? terms.first.id : null);
      _studentName = history.isNotEmpty ? history.first.rollNumber : 'Student';
      _loading = false;
    });
    _studentSearchController.clear();
  }

  List<_AdminAssignment> _parseAssignments(List<Map<String, dynamic>> raw) {
    if (raw.isEmpty) return const [];
    final List<_AdminAssignment> parsed = [];
    for (final map in raw) {
      final assignment = _AdminAssignment.tryParse(map);
      if (assignment != null) {
        parsed.add(assignment);
      }
    }
    return parsed;
  }

  void _syncAdminAssignmentsIntoTerms() {
    if (!_isAdminView) {
      return;
    }

    final assignments = _adminAssignments;
    if (assignments.isEmpty) {
      setState(() {
        _terms = const [];
        _selectedTermId = null;
        _loading = false;
        _studentAnalytics = AcademicDashboardSampleData.sampleStudentAnalytics();
        _selectedStudentAnalytics = null;
        _studentSearchError = null;
      });
      _studentSearchController.clear();
      return;
    }

    final List<SubjectMarkBreakdown> subjects = [];
    for (var index = 0; index < assignments.length; index++) {
      final assignment = assignments[index];
      final Color accent = _adminAccentPalette[index % _adminAccentPalette.length];
      final String fallbackName = assignment.subjectId.isNotEmpty ? assignment.subjectId : 'Subject';
      final String? rawSubjectName = assignment.subjectName;
      final String subjectName = rawSubjectName != null && rawSubjectName.trim().isNotEmpty
          ? rawSubjectName.trim()
          : fallbackName;

      subjects.add(
        SubjectMarkBreakdown(
          subjectId: assignment.subjectId,
          subjectName: subjectName,
          teacherName: null,
          components: _buildAdminComponents(accent),
          overallPercentage: 0,
          targetPercentage: 0,
          accent: accent,
        ),
      );
    }

    final DateTime today = DateTime.now();
    final AcademicTerm term = AcademicTerm(
      id: 'assigned-subjects',
      name: 'Assigned Subjects',
      startDate: today,
      endDate: today,
      overallPercentage: 0,
      gpa: 0,
      subjects: subjects,
      upcomingAssessments: const [],
    );

    setState(() {
      _terms = [term];
      _selectedTermId = term.id;
      _loading = false;
      _studentAnalytics = AcademicDashboardSampleData.sampleStudentAnalytics();
      _selectedStudentAnalytics = null;
      _studentSearchError = null;
    });
    _studentSearchController.clear();
  }

  List<AssessmentComponent> _buildAdminComponents(Color accent) {
    return _adminComponentTypes
        .map(
          (type) => AssessmentComponent(
            type: type,
            obtained: 0,
            total: 100,
            accent: accent,
          ),
        )
        .toList();
  }

  Future<void> _refreshData() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_isAdminView) {
      _syncAdminAssignmentsIntoTerms();
    } else {
      _seedSampleData();
    }
  }

  void _handleTermChanged(String? termId) {
    if (termId == null || termId == _selectedTermId) {
      return;
    }

    final exists = _terms.any((term) => term.id == termId);
    if (!exists) {
      return;
    }

    setState(() => _selectedTermId = termId);
  }

  void _handleStudentSearch() {
    final query = _studentSearchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _studentSearchError = 'Enter a student name to search.';
        _selectedStudentAnalytics = null;
      });
      return;
    }

    final normalized = query.toLowerCase();
    StudentAnalytics? found;
    for (final student in _studentAnalytics) {
      if (student.studentName.toLowerCase().contains(normalized)) {
        found = student;
        break;
      }
    }

    setState(() {
      if (found == null) {
        _studentSearchError = 'No student found for "$query".';
      } else {
        _studentSearchError = null;
      }
      _selectedStudentAnalytics = found;
    });
  }

  void _handleStudentSelected(StudentAnalytics analytics) {
    setState(() {
      _studentSearchController.text = analytics.studentName;
      _selectedStudentAnalytics = analytics;
      _studentSearchError = null;
    });
  }

  void _handleTabSelection() {
    if (!mounted) return;

    if (_controller.indexIsChanging) {
      return;
    }

    setState(() {});
  }

  Widget _buildHeaderTab(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String tooltip,
  }) {
    final bool isSelected = _controller.index == index;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          if (_controller.index != index) {
            _controller.animateTo(index);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  AcademicTerm? get _selectedTerm {
    if (_terms.isEmpty) return null;
    final lookup = _selectedTermId;
    if (lookup == null) return _terms.first;
    return _terms.firstWhere(
      (term) => term.id == lookup,
      orElse: () => _terms.first,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTabSelection);
    _controller.dispose();
    _studentSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);

    if (_loading || _roleLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        toolbarHeight: isMobile ? 56 : 64,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Back',
          onPressed: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const StudentDashboard()),
              (route) => false,
            );
          },
        ),
        title: Text(
          'Academic Records',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: isMobile ? 4 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeaderTab(
                  context,
                  index: 0,
                  icon: Icons.bar_chart_rounded,
                  tooltip: 'Results',
                ),
                SizedBox(width: isMobile ? 6 : 12),
                _buildHeaderTab(
                  context,
                  index: 1,
                  icon: Icons.menu_book_rounded,
                  tooltip: 'Scheme',
                ),
                SizedBox(width: isMobile ? 6 : 12),
                _buildHeaderTab(
                  context,
                  index: 2,
                  icon: Icons.timeline_rounded,
                  tooltip: 'History',
                ),
                SizedBox(width: isMobile ? 4 : 12),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh',
                  onPressed: _refreshData,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_isAdminView) ...[
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.responsiveValue(
                    context,
                    mobile: 16,
                    tablet: 24,
                    desktop: 32,
                    largeDesktop: 48,
                  ),
                  vertical: 16,
                ),
                child: StudentSummaryBanner(
                  studentName: _studentName,
                  currentClass: _history.isNotEmpty ? _history.first.className : 'Class',
                  rollNumber: _history.isNotEmpty ? _history.first.rollNumber : 'Roll',
                  overallGpa: _selectedTerm?.gpa ?? 0,
                  overallPercentage: _selectedTerm?.overallPercentage ?? 0,
                  termName: _selectedTerm?.name ?? 'Active Term',
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _controller,
                children: [
                  ResultsTabView(
                    terms: _terms,
                    selectedTerm: _selectedTerm,
                    onTermChanged: _handleTermChanged,
                    isAdminView: _isAdminView && !_isSuperAdmin,
                    adminAssignments: _adminAssignments,
                    onComponentTap: _isAdminView ? _handleAdminComponentTap : null,
                  ),
                  const SizedBox.shrink(),
                  HistoryTabView(
                    history: _history,
                    showAdminAnalytics: _isAdminView || _isSuperAdmin,
                    studentSearchController: _studentSearchController,
                    onStudentSearch: _handleStudentSearch,
                    onStudentSelected: _handleStudentSelected,
                    selectedStudentAnalytics: _selectedStudentAnalytics,
                    searchError: _studentSearchError,
                    availableStudents: _studentAnalytics,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAdminComponentTap(
    SubjectMarkBreakdown subject,
    AssessmentComponent component,
    _AdminAssignment assignment,
  ) {
    final String? className = assignment.className;
    if (className == null || className.isEmpty) {
      _showSnackBar('Class information missing for ${subject.subjectName}.');
      return;
    }

    final int? classId = assignment.classId;
    final int? subjectId = assignment.subjectIdInt ?? int.tryParse(subject.subjectId);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _AdminMarksDialog(
          subject: subject,
          component: component,
          assignment: assignment,
          className: className,
          classId: classId,
          subjectId: subjectId,
          onSuccess: () {
            Navigator.of(dialogContext).pop();
            _showSnackBar('${component.type} marks saved for ${subject.subjectName}.');
          },
        );
      },
    );
  }

  Future<void> _showQuizDetailsDialog(BuildContext context, _SubjectPlanInfo plan) async {
    final String quizNumber = plan.coveredQuizzesController.text.trim();
    final DateTime? deadline = plan.deadlineFor('quiz');
    final List<String> plannedNotes = _extractLines(plan.plannedQuizzesController.text);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final String deadlineLabel = deadline != null ? _formatFriendlyDate(deadline) : 'Not set';
        final String numberLabel = quizNumber.isEmpty ? 'Not set' : quizNumber;
        final String notesBody = plannedNotes.isEmpty
            ? 'No planned quiz notes added yet.'
            : plannedNotes.join('\n\n');

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quiz Details',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Planner overview',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quiz number: $numberLabel',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Deadline: $deadlineLabel',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        notesBody,
                        style: GoogleFonts.inter(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

}

_AdminAssignment? _matchAssignmentForSubject(
  SubjectMarkBreakdown subject,
  List<_AdminAssignment> assignments,
) {
  if (assignments.isEmpty) return null;
  final subjectKey = _subjectLookupKey(subject);
  for (final assignment in assignments) {
    if (assignment.matchesKey(subjectKey)) {
      return assignment;
    }
  }

  // Attempt class + name matching
  final normalizedSubjectName = _normalizeKey(subject.subjectName);
  for (final assignment in assignments) {
    if (assignment.matchesKey(normalizedSubjectName)) {
      return assignment;
    }
  }

  return null;
}

String _subjectLookupKey(SubjectMarkBreakdown subject) {
  if (subject.subjectId.isNotEmpty) {
    return _normalizeKey(subject.subjectId);
  }
  return _normalizeKey(subject.subjectName);
}

class StudentSummaryBanner extends StatelessWidget {
  const StudentSummaryBanner({
    super.key,
    required this.studentName,
    required this.currentClass,
    required this.rollNumber,
    required this.overallGpa,
    required this.overallPercentage,
    required this.termName,
  });

  final String studentName;
  final String currentClass;
  final String rollNumber;
  final double overallGpa;
  final double overallPercentage;
  final String termName;

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFFE8E1DE);
    const bannerBlue = Color(0xFF1E3A8A);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText = bannerBlue.withValues(alpha: isDark ? 0.92 : 0.9);
    final Color secondaryText = bannerBlue.withValues(alpha: isDark ? 0.75 : 0.65);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome back,',
                  style: GoogleFonts.inter(color: secondaryText),
                ),
                const SizedBox(height: 2),
                Text(
                  studentName,
                  style: GoogleFonts.inter(
                    color: primaryText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  termName,
                  style: GoogleFonts.inter(
                    color: secondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${overallPercentage.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(
                  color: primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Overall',
                style: GoogleFonts.inter(
                  color: secondaryText,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                overallGpa.toStringAsFixed(2),
                style: GoogleFonts.inter(
                  color: primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'GPA',
                style: GoogleFonts.inter(
                  color: secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ResultsTabView extends StatelessWidget {
  const ResultsTabView({
    super.key,
    required this.terms,
    required this.selectedTerm,
    required this.onTermChanged,
    this.isAdminView = false,
    this.adminAssignments = const [],
    this.onComponentTap,
  });

  final List<AcademicTerm> terms;
  final AcademicTerm? selectedTerm;
  final ValueChanged<String?> onTermChanged;
  final bool isAdminView;
  final List<_AdminAssignment> adminAssignments;
  final void Function(SubjectMarkBreakdown subject, AssessmentComponent component, _AdminAssignment assignment)? onComponentTap;

  @override
  Widget build(BuildContext context) {
    if (selectedTerm == null) {
      return const _EmptyState(
        icon: Icons.school,
        title: 'No term data',
        subtitle: 'Marks will appear after your first assessments.',
      );
    }

    final isWide = MediaQuery.of(context).size.width >= ResponsiveHelper.desktopBreakpoint;
    final padding = EdgeInsets.fromLTRB(
      ResponsiveHelper.responsiveValue(context, mobile: 16, tablet: 24, desktop: 32, largeDesktop: 48),
      0,
      ResponsiveHelper.responsiveValue(context, mobile: 16, tablet: 24, desktop: 32, largeDesktop: 48),
      0,
    );

    final term = selectedTerm!;

    final selector = _TermSelector(terms: terms, selected: term.id, onChanged: onTermChanged);

    final showSelector = !isAdminView;

    final Map<String, _AdminAssignment?> subjectAssignments = {};
    final List<SubjectMarkBreakdown> subjectList = [];
    for (final subject in term.subjects) {
      final assignment = _matchAssignmentForSubject(subject, adminAssignments);
      if (!isAdminView || assignment != null) {
        subjectList.add(subject);
        subjectAssignments[_subjectLookupKey(subject)] = assignment;
      }
    }

    if (isAdminView && subjectList.isEmpty) {
      return Padding(
        padding: padding,
        child: const _EmptyState(
          icon: Icons.info_outline,
          title: 'No assigned subjects',
          subtitle: 'You are not assigned to any subjects for this term.',
        ),
      );
    }

    if (isWide) {
      return Padding(
        padding: padding,
        child: Column(
          children: [
            if (showSelector) ...[
              selector,
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 12),
            Expanded(
              child: isAdminView
                  ? _SubjectList(
                      subjects: subjectList,
                      isAdminView: true,
                      assignmentLookup: subjectAssignments,
                      onComponentTap: onComponentTap,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SubjectList(
                            subjects: subjectList,
                            assignmentLookup: subjectAssignments,
                            isAdminView: false,
                            onComponentTap: onComponentTap,
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                TermSummaryPanel(term: term),
                                const SizedBox(height: 16),
                                UpcomingAssessmentsCard(assessments: term.upcomingAssessments),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: ListView(
        children: [
          if (showSelector) ...[
            selector,
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 8),
          if (!isAdminView) ...[
            TermSummaryPanel(term: term),
            const SizedBox(height: 16),
            UpcomingAssessmentsCard(assessments: term.upcomingAssessments),
            const SizedBox(height: 16),
          ],
          ...subjectList.map((subject) {
            final assignment = subjectAssignments[_subjectLookupKey(subject)];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SubjectPerformanceCard(
                subject: subject,
                adminAssignment: assignment,
                isAdminView: isAdminView,
                onComponentTap: assignment == null ? null : onComponentTap,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SubjectList extends StatelessWidget {
  const _SubjectList({
    required this.subjects,
    this.isAdminView = false,
    this.assignmentLookup = const {},
    this.onComponentTap,
  });

  final List<SubjectMarkBreakdown> subjects;
  final bool isAdminView;
  final Map<String, _AdminAssignment?> assignmentLookup;
  final void Function(SubjectMarkBreakdown subject, AssessmentComponent component, _AdminAssignment assignment)? onComponentTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: subjects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, index) {
        final subject = subjects[index];
        final assignment = assignmentLookup[_subjectLookupKey(subject)];
        return SubjectPerformanceCard(
          subject: subject,
          isAdminView: isAdminView,
          adminAssignment: assignment,
          onComponentTap: assignment == null ? null : onComponentTap,
        );
      },
    );
  }
}

class SchemeTabView extends StatefulWidget {
  const SchemeTabView({
    super.key,
    required this.scheme,
    this.isAdminView = false,
    this.adminAssignments = const [],
  });

  final List<SchemeItem> scheme;
  final bool isAdminView;
  final List<_AdminAssignment> adminAssignments;

  @override
  State<SchemeTabView> createState() => _SchemeTabViewState();
}

class _SchemeTabViewState extends State<SchemeTabView> {
  final List<_SubjectPlanInfo> _plans = [];
  String? _assignmentsSignature;

  bool get _isAdminView => widget.isAdminView;

  int get _targetPlanCount => _isAdminView ? widget.adminAssignments.length : 0;

  String _formatFriendlyDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  List<_SummaryLine> _buildSyllabusScheduleLines(_SubjectPlanInfo plan) {
    if (plan.scheduledDates.isEmpty) {
      return const <_SummaryLine>[];
    }

    if (plan.frequency == 'Weekly' || plan.frequency == 'Monthly') {
      final DateTime start = plan.scheduledDates.first;
      final DateTime end = plan.scheduledDates.last;
      final String rangeLabel = plan.frequency == 'Weekly'
          ? '${_formatFriendlyDate(start)} → ${_formatFriendlyDate(end)}'
          : '${DateFormat('MMM d').format(start)} → ${_formatFriendlyDate(end)}';
      final List<String> snippets = plan.scheduledDates
          .map((date) => plan.controllerForDate(date).text.trim())
          .where((text) => text.isNotEmpty)
          .map(_summarizeNoteLine)
          .toList(growable: true);
      if (snippets.isEmpty) {
        snippets.addAll(
          _extractLines(plan.plannedSyllabusController.text)
              .map(_summarizeNoteLine)
              .where((text) => text.isNotEmpty),
        );
      }
      final String snippet = snippets.isEmpty ? 'No notes added yet.' : snippets.first;
      final int extraCount = snippets.length > 1 ? snippets.length - 1 : 0;
      final String snippetLine = extraCount > 0 ? '$snippet (+$extraCount more)' : snippet;

      return <_SummaryLine>[
        _SummaryLine(leading: rangeLabel, text: '', useBullet: false),
        _SummaryLine(text: snippetLine, useBullet: false),
      ];
    }

    final Map<String, List<String>> grouped = {};
    for (final date in plan.scheduledDates) {
      final formattedDate = _formatFriendlyDate(date);
      final note = plan.controllerForDate(date).text.trim();
      grouped.putIfAbsent(formattedDate, () => []).add(note);
    }

    return grouped.entries
        .map(
          (entry) => _SummaryLine(
            leading: entry.key,
            text: _summarizeScheduleNotes(entry.value),
          ),
        )
        .toList(growable: false);
  }

  List<_SummaryLine> _buildDeadlineLines(_SubjectPlanInfo plan, String itemType, String label) {
    final DateTime? deadline = plan.deadlineFor(itemType);
    if (deadline == null) {
      return const <_SummaryLine>[];
    }
    return <_SummaryLine>[
      _SummaryLine(
        leading: label,
        text: _formatFriendlyDate(deadline),
        useBullet: false,
      ),
    ];
  }

  List<_SummaryLine> _buildAssignmentScheduleLines(_SubjectPlanInfo plan) {
    final String assignmentNumber = plan.coveredAssignmentsController.text.trim();
    final DateTime? deadline = plan.deadlineFor('assignment');

    final String numberPart = assignmentNumber.isEmpty ? '—' : assignmentNumber;
    final String deadlinePart = deadline == null ? '—' : _formatFriendlyDate(deadline);
    final String display = 'Number $numberPart   Deadline $deadlinePart';

    final List<_SummaryLine> lines = [];
    if (assignmentNumber.isNotEmpty || deadline != null) {
      lines.add(_SummaryLine(text: display, useBullet: false));
    }

    final List<String> plannedNotes = _extractLines(plan.plannedAssignmentsController.text);
    if (plannedNotes.isNotEmpty) {
      lines.add(
        _SummaryLine(
          text: _summarizeScheduleNotes(plannedNotes),
          useBullet: false,
        ),
      );
    }

    return lines;
  }

  List<_SummaryLine> _buildQuizScheduleLines(_SubjectPlanInfo plan) {
    final String quizNumber = plan.coveredQuizzesController.text.trim();
    final DateTime? deadline = plan.deadlineFor('quiz');

    final String numberPart = quizNumber.isEmpty ? '—' : quizNumber;
    final String deadlinePart = deadline == null ? '—' : _formatFriendlyDate(deadline);
    final String display = 'Number $numberPart   Deadline $deadlinePart';

    final List<_SummaryLine> lines = [];
    if (quizNumber.isNotEmpty || deadline != null) {
      lines.add(_SummaryLine(text: display, useBullet: false));
    }

    final List<String> plannedNotes = _extractLines(plan.plannedQuizzesController.text);
    if (plannedNotes.isNotEmpty) {
      lines.add(
        _SummaryLine(
          text: _summarizeScheduleNotes(plannedNotes),
          useBullet: false,
        ),
      );
    }

    return lines;
  }

  String _summarizeScheduleNotes(List<String> notes) {
    final filtered = notes.map((note) => note.trim()).where((note) => note.isNotEmpty).toList();
    if (filtered.isEmpty) {
      return '...';
    }

    final snippets = filtered.map(_shorthandNote).toList(growable: false);
    if (snippets.length == 1) {
      return snippets.single;
    }
    if (snippets.length == 2) {
      return snippets.join(', ');
    }
    return '${snippets.take(2).join(', ')} +${snippets.length - 2} more';
  }

  String _summarizeNoteLine(String note) {
    final words = note.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) {
      return '...';
    }
    if (words.length <= 5) {
      return words.join(' ');
    }
    return '${words.take(5).join(' ')}...';
  }

  String _shorthandNote(String note) {
    final words = note.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) {
      return '...';
    }
    if (words.length <= 2) {
      return words.join(' ');
    }
    return '${words.take(2).join(' ')}...';
  }

  Future<DateTime?> _pickDeadline(BuildContext context, DateTime? initial) async {
    final DateTime today = DateTime.now();
    final initialDate = initial ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 5),
    );
    return picked == null ? null : DateTime(picked.year, picked.month, picked.day);
  }

  @override
  void initState() {
    super.initState();
    _ensurePlanAlignment();
  }

  @override
  void didUpdateWidget(covariant SchemeTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAdminView != widget.isAdminView ||
        oldWidget.adminAssignments.length != widget.adminAssignments.length ||
        oldWidget.scheme.length != widget.scheme.length) {
      _ensurePlanAlignment();
    }
  }

  void _ensurePlanAlignment() {
    if (!_isAdminView) {
      if (_plans.isNotEmpty) {
        for (final plan in _plans) {
          plan.dispose();
        }
        _plans.clear();
      }
      return;
    }

    final target = _targetPlanCount;
    if (_plans.length > target) {
      for (var i = target; i < _plans.length; i++) {
        _plans[i].dispose();
      }
      _plans.removeRange(target, _plans.length);
    } else if (_plans.length < target) {
      _plans.addAll(List.generate(target - _plans.length, (_) => _SubjectPlanInfo()));
    }

    if (_isAdminView) {
      final signature = widget.adminAssignments
          .map((assignment) =>
              '${assignment.classId ?? 'x'}-${assignment.subjectIdInt ?? assignment.subjectId}')
          .join('|');
      if (signature != _assignmentsSignature) {
        _assignmentsSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _loadAllPlannerData();
        });
      }
    }
  }

  void _loadAllPlannerData() {
    for (var index = 0; index < _plans.length; index++) {
      _loadPlannerForAssignment(index);
    }
  }

  Future<void> _loadPlannerForAssignment(int index) async {
    if (!mounted || !_isAdminView) {
      return;
    }
    if (index >= widget.adminAssignments.length) {
      return;
    }

    final assignment = widget.adminAssignments[index];
    final plan = _plans[index];
    final int? classId = assignment.classId;
    final int? subjectId = assignment.subjectIdInt ?? int.tryParse(assignment.subjectId);

    setState(() {
      plan.beginLoad();
    });

    if (classId == null || subjectId == null) {
      setState(() {
        plan.setLoadError('Missing class or subject identifiers.');
        plan.applyPlannerResponse(null, const []);
      });
      return;
    }

    try {
      final response = await ApiService.getPlanner(
        classId: classId,
        subjectId: subjectId,
      );
      final Map<String, dynamic>? planData =
          response['plan'] is Map<String, dynamic> ? response['plan'] as Map<String, dynamic> : null;
      final List<dynamic> rawItems = response['items'] is List ? response['items'] as List : const [];
      setState(() {
        plan.applyPlannerResponse(planData, rawItems);
        plan.finishLoad();
      });
    } catch (e) {
      setState(() {
        plan.setLoadError(e.toString());
      });
    }
  }

  @override
  void dispose() {
    for (final plan in _plans) {
      plan.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdminView) {
      return _buildStandardScheme(context);
    }

    if (widget.adminAssignments.isEmpty) {
      return const _EmptyState(
        icon: Icons.info_outline,
        title: 'No assigned subjects',
        subtitle: 'You do not have any subjects to plan yet.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: widget.adminAssignments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final assignment = widget.adminAssignments[index];
        final plan = _plans[index];
        return _buildAdminSubjectCard(context, assignment, plan, index);
      },
    );
  }

  Widget _buildStandardScheme(BuildContext context) {
    if (widget.scheme.isEmpty) {
      return const _EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No scheme available',
        subtitle: 'Your course outlines will appear here once shared.',
      );
    }

    final horizontalPadding = ResponsiveHelper.responsiveValue(
      context,
      mobile: 16,
      tablet: 24,
      desktop: 32,
      largeDesktop: 48,
    );

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 24),
      itemCount: widget.scheme.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final item = widget.scheme[index];
        final theme = Theme.of(context);
        final mutedStyle = GoogleFonts.inter(
          fontSize: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        );

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.subjectName,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                if (item.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(item.description.trim(), style: mutedStyle),
                ],
                if (item.learningOutcomes.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Learning Outcomes',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  ...item.learningOutcomes
                      .where((outcome) => outcome.trim().isNotEmpty)
                      .map((outcome) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildBulletLine(context, outcome.trim()),
                          )),
                ],
                if (item.assessmentWeights.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Assessment Breakdown',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: item.assessmentWeights
                        .where((weight) => weight.component.trim().isNotEmpty)
                        .map(
                          (weight) => Chip(
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                            label: Text(
                              '${weight.component.trim()} • ${weight.weight.toStringAsFixed(
                                    weight.weight == weight.weight.roundToDouble() ? 0 : 1,
                                  )}%',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (item.resources.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Resources',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: item.resources
                        .where((resource) =>
                            resource.label.trim().isNotEmpty || resource.url.trim().isNotEmpty)
                        .map(
                          (resource) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text.rich(
                              TextSpan(
                                style: GoogleFonts.inter(fontSize: 13),
                                children: [
                                  if (resource.label.trim().isNotEmpty)
                                    TextSpan(
                                      text: resource.label.trim(),
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                    ),
                                  if (resource.url.trim().isNotEmpty) ...[
                                    if (resource.label.trim().isNotEmpty)
                                      const TextSpan(text: '  •  '),
                                    TextSpan(
                                      text: resource.url.trim(),
                                      style: GoogleFonts.inter(color: theme.colorScheme.primary),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBulletLine(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminSubjectCard(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
    int index,
  ) {
    final theme = Theme.of(context);
    final subjectName = (assignment.subjectName?.trim().isNotEmpty ?? false)
        ? assignment.subjectName!.trim()
        : assignment.subjectId;
    final classLabel = assignment.className?.trim().isNotEmpty == true ? assignment.className!.trim() : null;
    final scheduleItems = [
      _SummaryItem(title: 'Covered Syllabus', controller: plan.coveredSyllabusController),
      _SummaryItem(
        title: 'Assignments',
        controller: plan.coveredAssignmentsController,
        extraLinesBuilder: () => const <_SummaryLine>[],
        includeBaseLines: false,
      ),
      _SummaryItem(
        title: 'Quizzes',
        controller: plan.coveredQuizzesController,
        extraLinesBuilder: () => const <_SummaryLine>[],
        includeBaseLines: false,
      ),
    ];
    final plannedItems = [
      _SummaryItem(
        title: 'Syllabus',
        controller: plan.plannedSyllabusController,
        extraLinesBuilder: () => _buildSyllabusScheduleLines(plan),
        onTap: plan.scheduledDates.isEmpty ? null : () => _showScheduleDetailsDialog(context, plan),
      ),
      _SummaryItem(
        title: 'Assignments',
        controller: plan.plannedAssignmentsController,
        extraLinesBuilder: () => _buildAssignmentScheduleLines(plan),
        includeBaseLines: false,
        onTap: () => _showAssignmentDetailsDialog(context, plan),
      ),
      _SummaryItem(
        title: 'Quizzes',
        controller: plan.plannedQuizzesController,
        extraLinesBuilder: () => _buildQuizScheduleLines(plan),
        includeBaseLines: false,
        onTap: () => _showQuizDetailsDialog(context, plan),
      ),
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectName,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
                      ),
                      if (classLabel != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          classLabel,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final updated = await _showProgressDialog(context, assignment, plan, index);
                    if (updated == true) {
                      await _loadPlannerForAssignment(index);
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Update Progress'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (plan.isLoading)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: const [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 12),
                    Text('Loading planner data...'),
                  ],
                ),
              )
            else if (plan.loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        plan.loadError!,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _buildSectionHeader(context, 'History'),
            const SizedBox(height: 12),
            _buildSummaryRow(context, scheduleItems),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Scheduled'),
            const SizedBox(height: 12),
            _buildSummaryRow(context, plannedItems),
            const SizedBox(height: 24),
            _buildBottomActions(context, assignment, plan, index),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
    int index,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttons = [
          ElevatedButton.icon(
            onPressed: () async {
              final updated = await _showPlanDialog(context, assignment, plan, index);
              if (updated == true) {
                await _loadPlannerForAssignment(index);
              }
            },
            icon: const Icon(Icons.calendar_month),
            label: const Text('Plan Schedule'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final updated = await _showAssignmentDialog(context, assignment, plan, index);
              if (updated == true) {
                await _loadPlannerForAssignment(index);
              }
            },
            icon: const Icon(Icons.assignment_outlined),
            label: const Text('Assignment'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final updated = await _showQuizDialog(context, assignment, plan, index);
              if (updated == true) {
                await _loadPlannerForAssignment(index);
              }
            },
            icon: const Icon(Icons.quiz_outlined),
            label: const Text('Quiz'),
          ),
        ];

        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i != 0) const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: buttons[i]),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i != 0) const SizedBox(width: 16),
              Expanded(child: buttons[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, List<_SummaryItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final children = items
            .map((item) => _buildSummaryTile(context, item))
            .toList(growable: false);
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i != 0) const SizedBox(height: 12),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i != 0) const SizedBox(width: 16),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }

  String _joinLines(List<String> lines) {
    return lines.join('\n');
  }

  String _mergeLines(String existingText, List<String> newLines) {
    final List<String> merged = [];
    for (final line in _extractLines(existingText)) {
      if (!merged.contains(line)) {
        merged.add(line);
      }
    }
    for (final line in newLines) {
      if (!merged.contains(line)) {
        merged.add(line);
      }
    }
    return _joinLines(merged);
  }

  Future<bool?> _showProgressDialog(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
    int index,
  ) async {
    final snapshot = plan.snapshot();
    final String originalText = plan.plannedSyllabusController.text;
    final editingController = TextEditingController(text: originalText);
    bool isEditing = false;
    bool isSaving = false;
    String? saveError;

    final originalLines = _extractLines(originalText);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            child: StatefulBuilder(
              builder: (context, setLocalState) {
                final editedLines = _extractLines(editingController.text);
                final removedLines = originalLines
                    .where((line) => !editedLines.contains(line))
                    .toList();
                final hasContent = editedLines.isNotEmpty;
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Update Progress',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        assignment.subjectName ?? assignment.subjectId,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: _buildSectionHeader(context, 'Scheduled Syllabus')),
                          TextButton.icon(
                            onPressed: () {
                              setLocalState(() {
                                isEditing = !isEditing;
                              });
                              if (!isEditing) {
                                FocusScope.of(dialogContext).unfocus();
                              }
                            },
                            icon: Icon(isEditing ? Icons.check : Icons.edit),
                            label: Text(isEditing ? 'Done' : (hasContent ? 'Edit' : 'Add')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (!hasContent && !isEditing)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'No syllabus added yet.',
                            style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                          ),
                        )
                      else if (!isEditing)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).dividerColor),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final line in editedLines) ...[
                                _buildBulletLine(context, line),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        )
                      else
                        TextField(
                          controller: editingController,
                          minLines: 6,
                          maxLines: 12,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(context, 'Progress Summary'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _buildSummaryChip(
                            context,
                            'Will be Covered',
                            editedLines,
                          ),
                          _buildSummaryChip(
                            context,
                            'Will remain Scheduled',
                            removedLines,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (saveError != null) ...[
                        Text(
                          saveError!,
                          style: GoogleFonts.inter(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              FocusScope.of(dialogContext).unfocus();
                              plan.restore(snapshot);
                              setState(() {});
                              Navigator.of(dialogContext).pop(false);
                            },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    FocusScope.of(dialogContext).unfocus();
                                    setLocalState(() {
                                      isSaving = true;
                                      saveError = null;
                                    });

                                    final bool edited = editingController.text != originalText;
                                    final currentLines = editedLines;
                                    final currentRemoved = removedLines;

                                    if (!edited) {
                                      if (originalLines.isNotEmpty) {
                                        plan.coveredSyllabusController.text = _mergeLines(
                                          plan.coveredSyllabusController.text,
                                          originalLines,
                                        );
                                      }
                                      plan.plannedSyllabusController.clear();
                                    } else {
                                      if (currentLines.isNotEmpty) {
                                        plan.coveredSyllabusController.text = _mergeLines(
                                          plan.coveredSyllabusController.text,
                                          currentLines,
                                        );
                                      }
                                      if (currentRemoved.isEmpty) {
                                        plan.plannedSyllabusController.clear();
                                      } else {
                                        plan.plannedSyllabusController.text = _joinLines(currentRemoved);
                                      }
                                    }

                                    final error = await _persistPlannerChanges(assignment, plan);
                                    if (!dialogContext.mounted) {
                                      return;
                                    }
                                    if (error == null) {
                                      Navigator.of(dialogContext).pop(true);
                                    } else {
                                      setLocalState(() {
                                        isSaving = false;
                                        saveError = error;
                                      });
                                    }
                                  },
                            child: const Text('Save'),
                          ),
                          const SizedBox(width: 12),
                          if (isSaving)
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    editingController.dispose();

    if (result != true) {
      plan.restore(snapshot);
    }

    return result;
  }

  Widget _buildSummaryChip(BuildContext context, String label, List<String> lines) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            Text(
              'No items',
              style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines) ...[
                  _buildBulletLine(context, line),
                  const SizedBox(height: 6),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryTile(BuildContext context, _SummaryItem item) {
    final theme = Theme.of(context);
    final List<_SummaryLine> baseLines = _extractLines(item.controller.text)
        .map((line) => _SummaryLine(text: line))
        .toList(growable: false);
    final List<_SummaryLine> extraLines = item.extraLinesBuilder?.call() ?? const <_SummaryLine>[];
    final bool skipBaseLines = !item.includeBaseLines ||
        ((item.title == 'Syllabus' || item.title == 'Assignments') && extraLines.isNotEmpty);
    final List<_SummaryLine> lines = [
      ...extraLines,
      if (!skipBaseLines) ...baseLines,
    ];
    final tile = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          if (lines.isEmpty)
            Text(
              'No details added yet.',
              style: GoogleFonts.inter(fontSize: 14),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines) ...[
                  if (!line.useBullet)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        line.leading != null && line.leading!.isNotEmpty
                            ? '${line.leading!}  ${line.text}'.trim()
                            : line.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 14),
                      ),
                    )
                  else if (line.leading != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 152,
                          child: Text(
                            line.leading!,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            line.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 14),
                          ),
                        ),
                      ],
                    )
                  else
                    _buildBulletLine(context, line.text),
                ],
              ],
            ),
        ],
      ),
    );

    if (item.onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        child: tile,
      );
    }

    return tile;
  }

  Future<void> _showScheduleDetailsDialog(BuildContext context, _SubjectPlanInfo plan) async {
    final List<DateTime> dates = plan.scheduledDates;
    final DateTime? startDate = dates.isNotEmpty
        ? dates.first
        : plan.singleDate ?? plan.range?.start;
    final DateTime? endDate = dates.isNotEmpty
        ? dates.last
        : plan.singleDate ?? plan.range?.end;

    final List<String> noteSegments = dates
        .map((date) => plan.controllerForDate(date).text.trim())
        .where((note) => note.isNotEmpty)
        .toList(growable: true);

    if (noteSegments.isEmpty) {
      noteSegments.addAll(
        _extractLines(plan.plannedSyllabusController.text)
            .where((line) => line.isNotEmpty),
      );
    }

    final String notesBody = noteSegments.isEmpty
        ? 'No notes added yet.'
        : noteSegments.join('\n\n');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Syllabus Schedule Details',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    plan.frequency != null && plan.frequency!.isNotEmpty
                        ? '${plan.frequency} planner'
                        : 'Planner overview',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (startDate != null || endDate != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        () {
                          if (startDate != null && endDate != null) {
                            return '${_formatFriendlyDate(startDate)} → ${_formatFriendlyDate(endDate)}';
                          }
                          final DateTime date = startDate ?? endDate!;
                          return _formatFriendlyDate(date);
                        }(),
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        notesBody,
                        style: GoogleFonts.inter(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAssignmentDetailsDialog(BuildContext context, _SubjectPlanInfo plan) async {
    final String assignmentNumber = plan.coveredAssignmentsController.text.trim();
    final DateTime? deadline = plan.deadlineFor('assignment');
    final List<String> plannedNotes = _extractLines(plan.plannedAssignmentsController.text);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final String deadlineLabel = deadline != null ? _formatFriendlyDate(deadline) : 'Not set';
        final String numberLabel = assignmentNumber.isEmpty ? 'Not set' : assignmentNumber;
        final String notesBody = plannedNotes.isEmpty
            ? 'No planned assignment notes added yet.'
            : plannedNotes.join('\n\n');

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assignment Details',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Planner overview',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assignment number: $numberLabel',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Deadline: $deadlineLabel',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        notesBody,
                        style: GoogleFonts.inter(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuizDetailsDialog(BuildContext context, _SubjectPlanInfo plan) async {
    final String quizNumber = plan.coveredQuizzesController.text.trim();
    final DateTime? deadline = plan.deadlineFor('quiz');
    final List<String> plannedNotes = _extractLines(plan.plannedQuizzesController.text);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final String deadlineLabel = deadline != null ? _formatFriendlyDate(deadline) : 'Not set';
        final String numberLabel = quizNumber.isEmpty ? 'Not set' : quizNumber;
        final String notesBody = plannedNotes.isEmpty
            ? 'No planned quiz notes added yet.'
            : plannedNotes.join('\n\n');

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quiz Details',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Planner overview',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quiz number: $numberLabel',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Deadline: $deadlineLabel',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        notesBody,
                        style: GoogleFonts.inter(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showPlanDialog(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
    int index,
  ) async {
    final snapshot = plan.snapshot();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isSaving = false;
        String? saveError;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            child: StatefulBuilder(
              builder: (context, setLocalState) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Plan Schedule',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        assignment.subjectName ?? assignment.subjectId,
                        style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: const ['Daily','Weekly','Monthly','Custom'].contains(plan.frequency)
                            ? plan.frequency
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Schedule',
                          hintText: 'Select one',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                          DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                          DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                          DropdownMenuItem(value: 'Custom', child: Text('Custom')),
                        ],
                        onChanged: (value) async {
                          await _handleFrequencyChanged(dialogContext, index, value);
                          setLocalState(() {});
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(context, 'Add New Schedule'),
                      const SizedBox(height: 12),
                      _buildSummaryInputs([
                        _SummaryItem(
                          title: 'Syllabus Plan',
                          controller: plan.plannedSyllabusController,
                        ),
                      ]),
                      const SizedBox(height: 28),
                      if (saveError != null) ...[
                        Text(
                          saveError!,
                          style: GoogleFonts.inter(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              FocusScope.of(dialogContext).unfocus();
                              plan.restore(snapshot);
                              setState(() {});
                              Navigator.of(dialogContext).pop(false);
                            },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    FocusScope.of(dialogContext).unfocus();
                                    setLocalState(() {
                                      isSaving = true;
                                      saveError = null;
                                    });
                                    final error = await _persistPlannerChanges(assignment, plan);
                                    if (!dialogContext.mounted) {
                                      return;
                                    }
                                    if (error == null) {
                                      Navigator.of(dialogContext).pop(true);
                                    } else {
                                      setLocalState(() {
                                        isSaving = false;
                                        saveError = error;
                                      });
                                    }
                                  },
                            child: const Text('Save'),
                          ),
                          const SizedBox(width: 12),
                          if (isSaving)
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showAssignmentDialog(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
    int index,
  ) {
    return _showPlannerNotesDialog(
      context,
      assignment,
      plan,
      title: 'Assignments',
      numberLabel: 'Assignment Number',
      numberController: plan.coveredAssignmentsController,
      notesLabel: 'Planned Assignments',
      notesController: plan.plannedAssignmentsController,
    );
  }

  Future<bool?> _showQuizDialog(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
    int index,
  ) {
    return _showPlannerNotesDialog(
      context,
      assignment,
      plan,
      title: 'Quizzes',
      numberLabel: 'Quiz Number',
      numberController: plan.coveredQuizzesController,
      notesLabel: 'Planned Quizzes',
      notesController: plan.plannedQuizzesController,
    );
  }

  Future<bool?> _showPlannerNotesDialog(
    BuildContext context,
    _AdminAssignment assignment,
    _SubjectPlanInfo plan, {
    required String title,
    required String numberLabel,
    required TextEditingController numberController,
    required String notesLabel,
    required TextEditingController notesController,
  }) async {
    final snapshot = plan.snapshot();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isSaving = false;
        String? saveError;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: StatefulBuilder(
              builder: (context, setLocalState) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$title Notes',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        assignment.subjectName ?? assignment.subjectId,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: numberController,
                              decoration: InputDecoration(
                                labelText: numberLabel,
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (title == 'Assignments')
                            _DeadlineButton(
                              date: plan.deadlineFor('assignment'),
                              formatDate: _formatFriendlyDate,
                              onPressed: () async {
                                final selected = await _pickDeadline(dialogContext, plan.deadlineFor('assignment'));
                                if (selected != null || plan.deadlineFor('assignment') != null) {
                                  plan.setDeadline('assignment', selected);
                                  setLocalState(() {});
                                }
                              },
                            ),
                          if (title == 'Quizzes')
                            _DeadlineButton(
                              date: plan.deadlineFor('quiz'),
                              formatDate: _formatFriendlyDate,
                              onPressed: () async {
                                final selected = await _pickDeadline(dialogContext, plan.deadlineFor('quiz'));
                                if (selected != null || plan.deadlineFor('quiz') != null) {
                                  plan.setDeadline('quiz', selected);
                                  setLocalState(() {});
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: notesLabel,
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (saveError != null) ...[
                        Text(
                          saveError!,
                          style: GoogleFonts.inter(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              FocusScope.of(dialogContext).unfocus();
                              plan.restore(snapshot);
                              setState(() {});
                              Navigator.of(dialogContext).pop(false);
                            },
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    FocusScope.of(dialogContext).unfocus();
                                    setLocalState(() {
                                      isSaving = true;
                                      saveError = null;
                                    });
                                    final error = await _persistPlannerChanges(assignment, plan);
                                    if (!dialogContext.mounted) {
                                      return;
                                    }
                                    if (error == null) {
                                      Navigator.of(dialogContext).pop(true);
                                    } else {
                                      setLocalState(() {
                                        isSaving = false;
                                        saveError = error;
                                      });
                                    }
                                  },
                            child: const Text('Save'),
                          ),
                          const SizedBox(width: 12),
                          if (isSaving)
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryInputs(List<_SummaryItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 720;
        final fields = items
            .map(
              (item) => TextField(
                controller: item.controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: item.title,
                  border: const OutlineInputBorder(),
                ),
              ),
            )
            .toList(growable: false);

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i != 0) const SizedBox(height: 12),
                fields[i],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i != 0) const SizedBox(width: 16),
              Expanded(child: fields[i]),
            ],
          ],
        );
      },
    );
  }

  Future<void> _handleFrequencyChanged(BuildContext context, int index, String? value) async {
    if (value == null) {
      return;
    }
    final plan = _plans[index];

    if (value == 'Daily') {
      final nextDayRaw = DateTime.now().add(const Duration(days: 1));
      final nextDay = DateTime(nextDayRaw.year, nextDayRaw.month, nextDayRaw.day);
      setState(() {
        plan.frequency = value;
        plan.singleDate = nextDay;
        plan.range = null;
        plan.setDates([nextDay]);
      });
      return;
    }

    final DateTime today = DateTime.now();
    final DateTime defaultEnd = value == 'Weekly'
        ? today.add(const Duration(days: 6))
        : today.add(const Duration(days: 29));
    final initialRange = plan.range ?? DateTimeRange(start: today, end: defaultEnd);

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
      helpText: value == 'Weekly' ? 'Select week range' : 'Select month range',
    );

    if (picked != null) {
      final List<DateTime> dates = [];
      DateTime cursor = picked.start;
      while (!cursor.isAfter(picked.end)) {
        dates.add(DateTime(cursor.year, cursor.month, cursor.day));
        cursor = cursor.add(const Duration(days: 1));
      }

      setState(() {
        plan.frequency = value;
        plan.range = picked;
        plan.singleDate = null;
        plan.setDates(dates);
      });
    } else {
      // Force rebuild to revert dropdown visual selection if user cancels
      setState(() {});
    }
  }

  Future<String?> _persistPlannerChanges(
    _AdminAssignment assignment,
    _SubjectPlanInfo plan,
  ) async {
    final int? classId = assignment.classId;
    final int? subjectId = assignment.subjectIdInt ?? int.tryParse(assignment.subjectId);
    if (classId == null || subjectId == null) {
      return 'Missing class or subject identifiers for this assignment.';
    }

    int? planId = plan.planId;

    try {
      final response = await ApiService.savePlannerPlan(
        planId: planId,
        classId: classId,
        subjectId: subjectId,
        frequency: plan.frequency,
        singleDate: plan.singleDate != null ? _formatIsoDate(plan.singleDate!) : null,
        rangeStart: plan.range?.start != null ? _formatIsoDate(plan.range!.start) : null,
        rangeEnd: plan.range?.end != null ? _formatIsoDate(plan.range!.end) : null,
      );

      if (response['success'] != true) {
        return (response['error'] ?? 'Failed to save planner plan').toString();
      }

      final resolvedPlanId = _parseNullableInt(response['plan_id']);
      if (resolvedPlanId == null) {
        return 'Planner plan saved but no plan_id returned by server.';
      }
      plan.planId = resolvedPlanId;
      planId = resolvedPlanId;

      final drafts = plan.buildItemDrafts();
      final sessions = plan.scheduledDates
          .map((date) => {
                'session_date': _formatIsoDate(date),
                'notes': plan.controllerForDate(date).text.trim(),
              })
          .toList();

      for (final draft in drafts) {
        final hasContent = draft.description.isNotEmpty;

        if (!hasContent && draft.itemId == null) {
          continue;
        }

        if (!hasContent && draft.itemId != null) {
          try {
            final deleteResponse = await ApiService.deletePlannerItem(id: draft.itemId!);
            if (deleteResponse['success'] == true) {
              plan.updateItemId(draft.itemType, draft.status, draft.itemId!);
            } else if (deleteResponse['error'] != null) {
              return deleteResponse['error'].toString();
            }
          } catch (e) {
            return e.toString();
          }
          continue;
        }

        final bool isScheduled = draft.status == 'scheduled';
        final String normalizedStatus = _normalizePlannerStatus(draft.status);
        final String? scheduledFor = isScheduled && plan.scheduledDates.isNotEmpty
            ? _formatIsoDate(plan.scheduledDates.first)
            : null;
        final String? scheduledUntil = isScheduled && plan.scheduledDates.isNotEmpty
            ? _formatIsoDate(plan.scheduledDates.last)
            : null;

        try {
          final itemResponse = await ApiService.savePlannerItem(
            id: draft.itemId,
            planId: planId,
            itemType: draft.itemType,
            status: normalizedStatus,
            description: draft.description,
            scheduledFor: scheduledFor,
            scheduledUntil: scheduledUntil,
            sessions: isScheduled ? sessions : null,
          );

          if (itemResponse['success'] == true) {
            final savedId = _parseNullableInt(itemResponse['item_id']);
            if (savedId != null) {
              plan.updateItemId(draft.itemType, normalizedStatus, savedId);
            }
          } else {
            return (itemResponse['error'] ?? 'Failed to save planner item').toString();
          }
        } catch (e) {
          return e.toString();
        }
      }

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static int? _parseNullableInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _formatIsoDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _SubjectPlanInfo {
  int? planId;
  String? frequency;
  DateTimeRange? range;
  DateTime? singleDate;
  final TextEditingController coveredSyllabusController = TextEditingController();
  final TextEditingController coveredAssignmentsController = TextEditingController();
  final TextEditingController coveredQuizzesController = TextEditingController();
  final TextEditingController plannedSyllabusController = TextEditingController();
  final TextEditingController plannedAssignmentsController = TextEditingController();
  final TextEditingController plannedQuizzesController = TextEditingController();
  final Map<String, DateTime?> _deadlines = {
    'assignment': null,
    'quiz': null,
  };
  List<DateTime> _scheduledDates = [];
  final Map<String, TextEditingController> _dateControllers = {};
  final Map<String, int> _itemIds = {};
  bool isLoading = false;
  String? loadError;

  List<DateTime> get scheduledDates => List.unmodifiable(_scheduledDates);

  TextEditingController controllerForDate(DateTime date) {
    final key = _normalizeKey(date);
    return _dateControllers.putIfAbsent(key, () => TextEditingController());
  }

  void beginLoad() {
    isLoading = true;
    loadError = null;
  }

  void finishLoad() {
    isLoading = false;
  }

  void setLoadError(String message) {
    loadError = message;
    isLoading = false;
  }

  void updateItemId(String itemType, String status, int id) {
    _itemIds[_itemKey(itemType, status)] = id;
  }

  int? existingItemId(String itemType, String status) {
    return _itemIds[_itemKey(itemType, status)];
  }

  void applyPlannerResponse(Map<String, dynamic>? planData, List<dynamic> rawItems) {
    final objectId = planData?['id'];
    planId = _parseInt(objectId);
    final freq = planData?['frequency']?.toString();
    frequency = freq?.isNotEmpty == true ? freq : null;

    singleDate = _tryParseDate(planData?['single_date']);
    final rangeStart = _tryParseDate(planData?['range_start']);
    final rangeEnd = _tryParseDate(planData?['range_end']);
    if (rangeStart != null && rangeEnd != null && !rangeStart.isAfter(rangeEnd)) {
      range = DateTimeRange(start: rangeStart, end: rangeEnd);
    } else {
      range = null;
    }

    // Persist plan-level deadlines if present
    final DateTime? assignmentDeadline = _tryParseDate(planData?['assignment_deadline']);
    final DateTime? quizDeadline = _tryParseDate(planData?['quiz_deadline']);
    _deadlines['assignment'] = assignmentDeadline;
    _deadlines['quiz'] = quizDeadline;

    final List<DateTime> sessionDates = [];
    final Map<DateTime, List<String>> sessionNotes = {};
    _itemIds.clear();
    final Map<String, List<String>> textLookup = {};

    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final itemType = raw['item_type']?.toString();
      final status = _normalizePlannerStatus(raw['status']?.toString());
      if (itemType == null) {
        continue;
      }
      final key = _itemKey(itemType, status);
      final idValue = raw['id'];
      final parsedId = _parseInt(idValue);
      if (parsedId != null) {
        _itemIds[key] = parsedId;
      }
      final description = (raw['description'] ?? raw['title'] ?? '').toString().trim();
      if (description.isNotEmpty) {
        textLookup.putIfAbsent(key, () => []).add(description);
      }

      final sessions = raw['sessions'];
      if (sessions is List) {
        for (final session in sessions) {
          final sessionDateRaw = session is Map<String, dynamic> ? session['session_date'] : null;
          final parsed = _tryParseDate(sessionDateRaw);
          if (parsed != null) {
            sessionDates.add(parsed);
            final noteRaw = session is Map<String, dynamic> ? session['notes'] : null;
            final note = noteRaw?.toString().trim();
            if (note != null && note.isNotEmpty) {
              sessionNotes.putIfAbsent(parsed, () => []).add(note);
            }
          }
        }
      }
    }

    coveredSyllabusController.text = _joinTexts(textLookup[_itemKey('syllabus', 'covered')]);
    coveredAssignmentsController.text = _joinTexts(textLookup[_itemKey('assignment', 'covered')]);
    coveredQuizzesController.text = _joinTexts(textLookup[_itemKey('quiz', 'covered')]);
    plannedSyllabusController.text = _joinTexts(textLookup[_itemKey('syllabus', 'scheduled')]);
    plannedAssignmentsController.text = _joinTexts(textLookup[_itemKey('assignment', 'scheduled')]);
    plannedQuizzesController.text = _joinTexts(textLookup[_itemKey('quiz', 'scheduled')]);

    if (sessionDates.isNotEmpty) {
      setDates(sessionDates);
    } else if (singleDate != null) {
      setDates([singleDate!]);
    } else if (range != null) {
      final List<DateTime> dates = [];
      DateTime cursor = range!.start;
      while (!cursor.isAfter(range!.end)) {
        dates.add(DateTime(cursor.year, cursor.month, cursor.day));
        cursor = cursor.add(const Duration(days: 1));
      }
      setDates(dates);
    } else {
      setDates(const []);
    }

    for (final entry in sessionNotes.entries) {
      if (_scheduledDates.contains(entry.key)) {
        controllerForDate(entry.key).text = entry.value.join('\n');
      }
    }
  }

  List<_PlannerItemDraft> buildItemDrafts() {
    return [
      _PlannerItemDraft(
        itemType: 'syllabus',
        status: 'covered',
        description: coveredSyllabusController.text.trim(),
        itemId: existingItemId('syllabus', 'covered'),
      ),
      _PlannerItemDraft(
        itemType: 'assignment',
        status: 'covered',
        description: coveredAssignmentsController.text.trim(),
        itemId: existingItemId('assignment', 'covered'),
      ),
      _PlannerItemDraft(
        itemType: 'quiz',
        status: 'covered',
        description: coveredQuizzesController.text.trim(),
        itemId: existingItemId('quiz', 'covered'),
      ),
      _PlannerItemDraft(
        itemType: 'syllabus',
        status: 'scheduled',
        description: plannedSyllabusController.text.trim(),
        itemId: existingItemId('syllabus', 'scheduled'),
      ),
      _PlannerItemDraft(
        itemType: 'assignment',
        status: 'scheduled',
        description: plannedAssignmentsController.text.trim(),
        itemId: existingItemId('assignment', 'scheduled'),
      ),
      _PlannerItemDraft(
        itemType: 'quiz',
        status: 'scheduled',
        description: plannedQuizzesController.text.trim(),
        itemId: existingItemId('quiz', 'scheduled'),
      ),
    ];
  }

  DateTime? deadlineFor(String itemType) => _deadlines[itemType];

  void setDeadline(String itemType, DateTime? date) {
    _deadlines[itemType] = date;
  }

  static String _joinTexts(List<String>? values) {
    if (values == null || values.isEmpty) {
      return '';
    }
    return values.join('\n');
  }

  static DateTime? _tryParseDate(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final str = value.toString().trim();
    if (str.isEmpty) {
      return null;
    }
    DateTime? parsed;
    try {
      parsed = DateTime.parse(str);
    } catch (_) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static String _itemKey(String itemType, String status) => '${itemType.toLowerCase()}::${status.toLowerCase()}';

  void setDates(List<DateTime> dates) {
    final normalized = dates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toList()
      ..sort();

    final currentDates = _scheduledDates.toSet();
    final normalizedSet = normalized.toSet();

    final toRemove = currentDates.difference(normalizedSet);
    for (final date in toRemove) {
      final key = _normalizeKey(date);
      _dateControllers.remove(key)?.dispose();
    }

    for (final date in normalizedSet) {
      final key = _normalizeKey(date);
      _dateControllers.putIfAbsent(key, () => TextEditingController());
    }

    _scheduledDates = normalized;
  }

  void dispose() {
    coveredSyllabusController.dispose();
    coveredAssignmentsController.dispose();
    coveredQuizzesController.dispose();
    plannedSyllabusController.dispose();
    plannedAssignmentsController.dispose();
    plannedQuizzesController.dispose();
    for (final controller in _dateControllers.values) {
      controller.dispose();
    }
  }

  String _normalizeKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  _SubjectPlanSnapshot snapshot() {
    final Map<DateTime, String> dateTexts = {};
    for (final date in _scheduledDates) {
      dateTexts[date] = controllerForDate(date).text;
    }
    return _SubjectPlanSnapshot(
      planId: planId,
      frequency: frequency,
      range: range,
      singleDate: singleDate,
      scheduledDates: List<DateTime>.from(_scheduledDates),
      dateTexts: dateTexts,
      coveredSyllabus: coveredSyllabusController.text,
      coveredAssignments: coveredAssignmentsController.text,
      coveredQuizzes: coveredQuizzesController.text,
      plannedSyllabus: plannedSyllabusController.text,
      plannedAssignments: plannedAssignmentsController.text,
      plannedQuizzes: plannedQuizzesController.text,
      itemIds: Map<String, int>.from(_itemIds),
      deadlines: Map<String, DateTime?>.from(_deadlines),
    );
  }

  void restore(_SubjectPlanSnapshot snapshot) {
    planId = snapshot.planId;
    frequency = snapshot.frequency;
    range = snapshot.range;
    singleDate = snapshot.singleDate;
    setDates(snapshot.scheduledDates);
    for (final entry in snapshot.dateTexts.entries) {
      controllerForDate(entry.key).text = entry.value;
    }
    coveredSyllabusController.text = snapshot.coveredSyllabus;
    coveredAssignmentsController.text = snapshot.coveredAssignments;
    coveredQuizzesController.text = snapshot.coveredQuizzes;
    plannedSyllabusController.text = snapshot.plannedSyllabus;
    plannedAssignmentsController.text = snapshot.plannedAssignments;
    plannedQuizzesController.text = snapshot.plannedQuizzes;
    _itemIds
      ..clear()
      ..addAll(snapshot.itemIds);
    _deadlines
      ..clear()
      ..addAll(snapshot.deadlines);
  }
}

class _SubjectPlanSnapshot {
  _SubjectPlanSnapshot({
    required this.planId,
    required this.frequency,
    required this.range,
    required this.singleDate,
    required this.scheduledDates,
    required this.dateTexts,
    required this.coveredSyllabus,
    required this.coveredAssignments,
    required this.coveredQuizzes,
    required this.plannedSyllabus,
    required this.plannedAssignments,
    required this.plannedQuizzes,
    required this.itemIds,
    required this.deadlines,
  });

  final int? planId;
  final String? frequency;
  final DateTimeRange? range;
  final DateTime? singleDate;
  final List<DateTime> scheduledDates;
  final Map<DateTime, String> dateTexts;
  final String coveredSyllabus;
  final String coveredAssignments;
  final String coveredQuizzes;
  final String plannedSyllabus;
  final String plannedAssignments;
  final String plannedQuizzes;
  final Map<String, int> itemIds;
  final Map<String, DateTime?> deadlines;
}

class _PlannerItemDraft {
  _PlannerItemDraft({
    required this.itemType,
    required this.status,
    required this.description,
    this.itemId,
  });

  final String itemType;
  final String status;
  final String description;
  final int? itemId;
}

class HistoryTabView extends StatelessWidget {
  const HistoryTabView({
    super.key,
    required this.history,
    this.showAdminAnalytics = false,
    this.studentSearchController,
    this.onStudentSearch,
    this.onStudentSelected,
    this.selectedStudentAnalytics,
    this.searchError,
    this.availableStudents = const [],
  });

  final List<EnrollmentHistoryItem> history;
  final bool showAdminAnalytics;
  final TextEditingController? studentSearchController;
  final VoidCallback? onStudentSearch;
  final ValueChanged<StudentAnalytics>? onStudentSelected;
  final StudentAnalytics? selectedStudentAnalytics;
  final String? searchError;
  final List<StudentAnalytics> availableStudents;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = EdgeInsets.fromLTRB(
          ResponsiveHelper.responsiveValue(context, mobile: 16, tablet: 24, desktop: 32, largeDesktop: 48),
          12,
          ResponsiveHelper.responsiveValue(context, mobile: 16, tablet: 24, desktop: 32, largeDesktop: 48),
          24,
        );

        final content = <Widget>[
          if (showAdminAnalytics)
            _AdminHistoryAnalytics(
              controller: studentSearchController,
              onSearch: onStudentSearch,
              onStudentSelected: onStudentSelected,
              selectedAnalytics: selectedStudentAnalytics,
              searchError: searchError,
              availableStudents: availableStudents,
            ),
          if (history.isEmpty)
            const _EmptyState(
              icon: Icons.timeline,
              title: 'No history yet',
              subtitle: 'Your academic journey will appear here once terms close.',
            )
          else
            ...List.generate(history.length, (index) {
              final entry = history[index];
              return Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
                child: _TimelineEntry(
                  history: entry,
                  isLast: index == history.length - 1,
                ),
              );
            }),
        ];

        return ListView(
          padding: padding,
          children: content,
        );
      },
    );
  }
}

class _AdminHistoryAnalytics extends StatelessWidget {
  const _AdminHistoryAnalytics({
    this.controller,
    this.onSearch,
    this.onStudentSelected,
    this.selectedAnalytics,
    this.searchError,
    this.availableStudents = const [],
  });

  final TextEditingController? controller;
  final VoidCallback? onSearch;
  final ValueChanged<StudentAnalytics>? onStudentSelected;
  final StudentAnalytics? selectedAnalytics;
  final String? searchError;
  final List<StudentAnalytics> availableStudents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analytics = selectedAnalytics;

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student Insights',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Search student by name',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => onSearch?.call(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: onSearch,
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
                  ),
                ),
              ],
            ),
            if (searchError != null) ...[
              const SizedBox(height: 8),
              Text(
                searchError!,
                style: GoogleFonts.inter(color: theme.colorScheme.error, fontSize: 13),
              ),
            ],
            if (availableStudents.isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: availableStudents
                      .map(
                        (student) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: selectedAnalytics == student,
                            label: Text(student.studentName),
                            onSelected: (_) => onStudentSelected?.call(student),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (analytics == null)
              _buildPlaceholder(theme)
            else ...[
              _buildAttendanceCard(theme, analytics),
              const SizedBox(height: 20),
              _buildAcademicCard(theme, analytics),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insights_outlined, size: 36),
          const SizedBox(height: 12),
          Text(
            'Search a student to view analytics',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Attendance and academic statistics will appear here once you select a student.',
            style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(ThemeData theme, StudentAnalytics analytics) {
    final attendance = analytics.attendance;
    final double total = attendance.total <= 0 ? 1.0 : attendance.total;
    final sections = [
      _buildPieSection(theme, 'Present', attendance.present.toDouble(), total, theme.colorScheme.primary),
      _buildPieSection(theme, 'Absent', attendance.absent.toDouble(), total, const Color(0xFFDC2626)),
      _buildPieSection(theme, 'Late', attendance.late.toDouble(), total, const Color(0xFFF59E0B)),
      _buildPieSection(theme, 'Excused', attendance.excused.toDouble(), total, const Color(0xFF6366F1)),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance Snapshot',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isVertical = constraints.maxWidth < 720;
              return Flex(
                direction: isVertical ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 220,
                    width: isVertical ? double.infinity : 240,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: isVertical ? 50 : 60,
                        sections: sections,
                      ),
                    ),
                  ),
                  SizedBox(width: isVertical ? 0 : 24, height: isVertical ? 16 : 0),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.4),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Scrollbar(
                        child: ListView.separated(
                          primary: false,
                          shrinkWrap: true,
                          itemCount: attendance.details.length,
                          separatorBuilder: (_, __) => const Divider(height: 16),
                          itemBuilder: (context, index) {
                            final detail = attendance.details[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.label,
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  detail.value,
                                  style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  PieChartSectionData _buildPieSection(
    ThemeData theme,
    String label,
    double value,
    double total,
    Color color,
  ) {
    final percentage = total <= 0 ? 0 : (value / total * 100);
    return PieChartSectionData(
      color: color,
      value: value,
      radius: 70,
      title: value <= 0 ? '' : '${percentage.toStringAsFixed(1)}%',
      titleStyle: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      badgeWidget: value <= 0
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 3)),
                ],
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ),
      badgePositionPercentageOffset: 1.2,
    );
  }

  Widget _buildAcademicCard(ThemeData theme, StudentAnalytics analytics) {
    final academics = analytics.academics;
    final metrics = academics.metrics;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isVertical = constraints.maxWidth < 720;
          return Flex(
            direction: isVertical ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Academic Performance (${academics.yearLabel})',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    if (academics.highlights.isEmpty)
                      Text(
                        'No academic highlights shared for this student.',
                        style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                      )
                    else
                      ...academics.highlights.map(
                        (highlight) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(top: 6, right: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  highlight,
                                  style: GoogleFonts.inter(fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: isVertical ? 0 : 24, height: isVertical ? 20 : 0),
              Expanded(
                child: SizedBox(
                  height: 260,
                  child: BarChart(
                    BarChartData(
                      gridData: FlGridData(show: true, horizontalInterval: 20, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: 20)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= metrics.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  metrics[index].label,
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(metrics.length, (index) {
                        final metric = metrics[index];
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: metric.obtained,
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                              width: 26,
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: metric.total,
                                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SubjectPerformanceCard extends StatelessWidget {
  const SubjectPerformanceCard({
    super.key,
    required this.subject,
    this.isAdminView = false,
    this.adminAssignment,
    this.onComponentTap,
  });

  final SubjectMarkBreakdown subject;
  final bool isAdminView;
  final _AdminAssignment? adminAssignment;
  final void Function(SubjectMarkBreakdown subject, AssessmentComponent component, _AdminAssignment assignment)? onComponentTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = subject.accent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? accent.withValues(alpha: 0.22) : accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_stories, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.subjectName,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    if (isAdminView && adminAssignment?.className != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          adminAssignment!.className!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    if (subject.teacherName != null && subject.teacherName!.isNotEmpty)
                      Text(
                        subject.teacherName!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${subject.overallPercentage.toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  Text(
                    'Overall',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: subject.components.map((component) {
              final compColor = component.accent ?? accent;
              final isDarkChip = theme.brightness == Brightness.dark;
              final canHandleAdminTap = isAdminView && adminAssignment != null && onComponentTap != null;

              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    component.type,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: compColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${component.obtained.toStringAsFixed(0)} / ${component.total.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ],
              );

              final chip = Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDarkChip
                      ? compColor.withValues(alpha: 0.22)
                      : compColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: content,
              );

              return InkWell(
                onTap: () {
                  if (canHandleAdminTap) {
                    onComponentTap!(subject, component, adminAssignment!);
                  } else {
                    _showComponentDialog(context, subject, component);
                  }
                },
                borderRadius: BorderRadius.circular(14),
                child: chip,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showComponentDialog(
    BuildContext context,
    SubjectMarkBreakdown subject,
    AssessmentComponent component,
  ) {
    final theme = Theme.of(context);
    final accentColor = component.accent ?? subject.accent;
    final remark = component.remark?.trim();
    final String? dateText = component.takenAt != null ? _formatDate(component.takenAt!) : null;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Widget buildRow(String label, String value) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  value,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  component.type.characters.first.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      component.type,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subject.subjectName,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildRow('Score', '${_formatScore(component.obtained)} / ${_formatScore(component.total)}'),
                buildRow('Percentage', '${component.percentage.toStringAsFixed(1)}%'),
                if (dateText != null) buildRow('Taken on', dateText),
                if (remark != null && remark.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Remark',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                if (remark != null && remark.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      remark,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatScore(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthIndex = (date.month - 1).clamp(0, 11);
    return '${months[monthIndex]} ${date.day}, ${date.year}';
  }
}

class _AdminMarksDialog extends StatefulWidget {
  const _AdminMarksDialog({
    required this.subject,
    required this.component,
    required this.assignment,
    required this.className,
    this.classId,
    this.subjectId,
    required this.onSuccess,
  });

  final SubjectMarkBreakdown subject;
  final AssessmentComponent component;
  final _AdminAssignment assignment;
  final String className;
  final int? classId;
  final int? subjectId;
  final VoidCallback onSuccess;

  @override
  State<_AdminMarksDialog> createState() => _AdminMarksDialogState();
}

class _AdminMarksDialogState extends State<_AdminMarksDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final TextEditingController _totalController;
  final List<_StudentMarkEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _totalController = TextEditingController(text: widget.component.total.toStringAsFixed(widget.component.total == widget.component.total.roundToDouble() ? 0 : 2));
    _loadRoster();
  }

  Future<void> _loadRoster() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final students = await ApiService.getStudentsInClass(widget.className);
      _entries
        ..clear()
        ..addAll(students.map((row) => _StudentMarkEntry.fromMap(row)));
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _submit() async {
    if (_saving) return;

    final total = double.tryParse(_totalController.text.trim());
    if (total == null || total <= 0) {
      _showInlineMessage('Please enter a valid total marks value.');
      return;
    }

    final missing = _entries.where((entry) => entry.controller.text.trim().isEmpty).toList();
    if (missing.isNotEmpty) {
      _showInlineMessage('Enter marks for all students before saving.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final entries = _entries.map((entry) => entry.toPayload()).toList();
      final payloadTotal = total.round();
      final kind = _mapComponentTypeToKind(widget.component.type);

      if (kind == 'first_term') {
        await ApiService.upsertFirstTermMarks(
          classId: widget.classId,
          subjectId: widget.subjectId,
          className: widget.className,
          subjectName: widget.subject.subjectName,
          totalMarks: payloadTotal,
          entries: entries,
        );
      } else if (kind == 'final_term') {
        await ApiService.upsertFinalTermMarks(
          classId: widget.classId,
          subjectId: widget.subjectId,
          className: widget.className,
          subjectName: widget.subject.subjectName,
          totalMarks: payloadTotal,
          entries: entries,
        );
      } else {
        await ApiService.upsertStudentMarks(
          classId: widget.classId,
          subjectId: widget.subjectId,
          className: widget.className,
          subjectName: widget.subject.subjectName,
          kind: kind,
          number: 1,
          totalMarks: payloadTotal,
          entries: entries,
        );
      }

      widget.onSuccess();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  void _showInlineMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.controller.dispose();
    }
    _totalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.component.accent ?? widget.subject.accent;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.component.type.characters.first.toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter ${widget.component.type} Marks',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.subject.subjectName} • ${widget.className}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadRoster)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _totalController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Total Marks',
                                hintText: 'e.g. 50',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(widget.component.type, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: Scrollbar(
                          child: ListView.separated(
                            itemCount: _entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 16),
                            itemBuilder: (context, index) {
                              final entry = _entries[index];
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.name,
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                        ),
                                        if (entry.rollNumber != null && entry.rollNumber!.isNotEmpty)
                                          Text(
                                            entry.rollNumber!,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: TextFormField(
                                      controller: entry.controller,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Obtained',
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }

  String _mapComponentTypeToKind(String type) {
    final normalized = type.trim().toLowerCase();
    if (normalized.contains('quiz')) return 'quiz';
    if (normalized.contains('assignment')) return 'assignment';
    if (normalized.contains('first')) return 'first_term';
    if (normalized.contains('mid')) return 'first_term';
    if (normalized.contains('final')) return 'final_term';
    if (normalized.contains('lab')) return 'lab';
    return normalized.replaceAll(' ', '_');
  }
}

class _StudentMarkEntry {
  _StudentMarkEntry({
    required this.userId,
    required this.name,
    this.rollNumber,
    double? existingMarks,
  }) : controller = TextEditingController(
          text: existingMarks == null
              ? ''
              : (existingMarks == existingMarks.roundToDouble()
                  ? existingMarks.toStringAsFixed(0)
                  : existingMarks.toStringAsFixed(2)),
        );

  final int userId;
  final String name;
  final String? rollNumber;
  final TextEditingController controller;

  Map<String, dynamic> toPayload() {
    final raw = controller.text.trim();
    final obtained = double.tryParse(raw) ?? 0;
    return {
      'student_user_id': userId,
      'obtained_marks': obtained,
    };
  }

  static _StudentMarkEntry fromMap(Map<String, dynamic> row) {
    int? userId;
    final rawId = row['user_id'] ?? row['student_user_id'] ?? row['id'];
    if (rawId is int) {
      userId = rawId;
    } else if (rawId is String) {
      userId = int.tryParse(rawId);
    }
    if (userId == null) {
      throw Exception('Invalid student data: missing user_id.');
    }

    final existingMarks = row['obtained_marks'];
    double? obtained;
    if (existingMarks is num) {
      obtained = existingMarks.toDouble();
    } else if (existingMarks is String) {
      obtained = double.tryParse(existingMarks);
    }

    return _StudentMarkEntry(
      userId: userId,
      name: (row['name'] ?? row['student_name'] ?? 'Student').toString(),
      rollNumber: (row['roll_number'] ?? row['registration_no'])?.toString(),
      existingMarks: obtained,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 42, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load students',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _AdminAssignment {
  const _AdminAssignment({
    required this.subjectId,
    this.subjectIdInt,
    this.classId,
    this.subjectName,
    this.className,
  });

  final String subjectId;
  final int? subjectIdInt;
  final int? classId;
  final String? subjectName;
  final String? className;

  String get _normalizedSubjectId => _normalizeKey(subjectId);
  String? get _normalizedSubjectName => subjectName == null || subjectName!.trim().isEmpty ? null : _normalizeKey(subjectName!);
  String? get classNameKey => className == null || className!.trim().isEmpty ? null : _normalizeKey(className!);

  bool matchesKey(String key) {
    final normalized = _normalizeKey(key);
    if (normalized.isEmpty) return false;
    if (_normalizedSubjectId.isNotEmpty) {
      if (normalized == _normalizedSubjectId) return true;
      if (_normalizedSubjectId.startsWith(normalized) || normalized.startsWith(_normalizedSubjectId)) {
        return true;
      }
    }
    if (_normalizedSubjectName != null) {
      final name = _normalizedSubjectName!;
      if (normalized == name) return true;
      if (name.contains(normalized) || normalized.contains(name)) {
        return true;
      }
    }
    if (classNameKey != null && classNameKey!.contains(normalized)) {
      return true;
    }
    return false;
  }

  bool matchesSubject(SubjectMarkBreakdown subject) {
    final subjectKey = _subjectLookupKey(subject);
    if (matchesKey(subjectKey)) {
      return true;
    }

    final subjectNameKey = _normalizeKey(subject.subjectName);
    if (matchesKey(subjectNameKey)) {
      return true;
    }

    final subjectTokens = _tokenize(subjectNameKey);
    final assignmentTokens =
        _normalizedSubjectName != null ? _tokenize(_normalizedSubjectName!) : const <String>{};
    if (assignmentTokens.isNotEmpty) {
      final overlap = assignmentTokens.intersection(subjectTokens);
      if (overlap.isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  static _AdminAssignment? tryParse(Map<String, dynamic> map) {
    final dynamic rawSubjectId = map['subject_id'] ?? map['subjectId'] ?? map['subjectid'] ?? map['id'] ?? map['course_id'] ?? map['courseId'];
    final String rawSubjectName =
        (map['subject_name'] ?? map['subject'] ?? map['name'] ?? map['course_name'] ?? '').toString();
    final String rawSubjectCode =
        (map['subject_code'] ?? map['subjectCode'] ?? map['code'] ?? map['course_code'] ?? '').toString();
    final dynamic rawClassId = map['class_id'] ?? map['classId'];
    final String rawClassName = (map['class_name'] ?? map['className'] ?? map['class'] ?? '').toString();

    String subjectId = '';
    int? subjectIdInt;

    final dynamic subjectIdCandidate = rawSubjectId ?? (rawSubjectCode.trim().isNotEmpty ? rawSubjectCode : null);

    if (subjectIdCandidate is int) {
      subjectIdInt = subjectIdCandidate;
      subjectId = subjectIdCandidate.toString();
    } else if (subjectIdCandidate is String) {
      subjectId = subjectIdCandidate.trim();
      subjectIdInt = int.tryParse(subjectId);
    }

    final String trimmedSubjectName = rawSubjectName.trim();
    if (subjectId.isEmpty && trimmedSubjectName.isNotEmpty) {
      subjectId = trimmedSubjectName;
      subjectIdInt ??= int.tryParse(subjectId);
    }

    if (subjectId.isEmpty) {
      return null;
    }

    int? classId;
    if (rawClassId is int) {
      classId = rawClassId;
    } else if (rawClassId is String) {
      classId = int.tryParse(rawClassId.trim());
    }

    final String trimmedClassName = rawClassName.trim();

    return _AdminAssignment(
      subjectId: subjectId,
      subjectIdInt: subjectIdInt,
      classId: classId,
      subjectName: trimmedSubjectName.isEmpty ? null : trimmedSubjectName,
      className: trimmedClassName.isEmpty ? null : trimmedClassName,
    );
  }
}

String _normalizeKey(String value) => value.trim().toLowerCase();

Set<String> _tokenize(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  final tokens = cleaned
      .split(RegExp(r'\s+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toSet();
  return tokens;
}

class TermSummaryPanel extends StatelessWidget {
  const TermSummaryPanel({super.key, required this.term});

  final AcademicTerm term;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Term Overview', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _SummaryRow(label: 'Overall Percentage', value: '${term.overallPercentage.toStringAsFixed(1)}%'),
            _SummaryRow(label: 'GPA', value: term.gpa.toStringAsFixed(2)),
            _SummaryRow(
              label: 'Duration',
              value: '${_format(term.startDate)} - ${_format(term.endDate)}',
            ),
          ],
        ),
      ),
    );
  }

  String _format(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[(date.month - 1).clamp(0, 11)]} ${date.day}, ${date.year}';
  }
}

class UpcomingAssessmentsCard extends StatelessWidget {
  const UpcomingAssessmentsCard({super.key, required this.assessments});

  final List<String> assessments;

  @override
  Widget build(BuildContext context) {
    if (assessments.isEmpty) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Upcoming Assessments', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Text(
                'No upcoming assessments scheduled.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming Assessments', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...assessments.map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
          Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13))),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.history, required this.isLast});

  final EnrollmentHistoryItem history;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 110,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(history.academicYear, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                const SizedBox(height: 6),
                Text(history.className, style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Roll: ${history.rollNumber}', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: history.termSummaries.map((summary) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(summary.termName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 6),
                          Text('Percentage: ${summary.percentage.toStringAsFixed(1)}%\nGPA: ${summary.gpa.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12)),
                          if (summary.remarks != null && summary.remarks!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(summary.remarks!, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.primary)),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TermSelector extends StatelessWidget {
  const _TermSelector({required this.terms, required this.selected, required this.onChanged});

  final List<AcademicTerm> terms;
  final String selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            decoration: InputDecoration(
              labelText: 'Select Term',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            items: terms
                .map(
                  (term) => DropdownMenuItem(
                    value: term.id,
                    child: Text(term.name),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Refresh',
          onPressed: () {},
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
