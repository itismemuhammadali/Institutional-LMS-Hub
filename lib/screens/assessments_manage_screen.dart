  import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/vertical_nav_bar.dart';
import 'home.dart';

class AssessmentsManageScreen extends StatefulWidget {
  final String initialTab; // 'Quiz' | 'Assignment'
  final int? planId;
  final int? classId;
  final int? subjectId;
  final String? className;
  final String? subjectName;

  const AssessmentsManageScreen({
    super.key,
    required this.initialTab,
    this.planId,
    this.classId,
    this.subjectId,
    this.className,
    this.subjectName,
  });

  @override
  State<AssessmentsManageScreen> createState() => _AssessmentsManageScreenState();
}

class _AssessmentsManageScreenState extends State<AssessmentsManageScreen>
    with SingleTickerProviderStateMixin {
  String? _defaultSubjectName;
  late final TabController _tabController;

  final _quizTitleCtrl = TextEditingController();
  final _quizTopicCtrl = TextEditingController();
  DateTime? _quizWhen;

  final _assignTitleCtrl = TextEditingController();
  final _assignDescCtrl = TextEditingController();
  DateTime? _assignWhen;

  int _nextQuizNumber = 1;
  int _nextAssignmentNumber = 1;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _saving = false;
  Map<String, dynamic>? _currentUser;
  final int _selectedNavIndex = 2; // Highlight Courses in the sidebar
  bool _isNavExpanded = false;

  bool _assessmentsLoading = false;
  String? _assessmentsError;
  List<Map<String, dynamic>> _quizAssessments = [];
  List<Map<String, dynamic>> _assignmentAssessments = [];
  List<Map<String, dynamic>> _studentAssignmentSubmissions = [];
  final Set<int> _markingInProgress = <int>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.index = widget.initialTab == 'Assignment' ? 1 : 0;
    _tabController.addListener(() {
      if (mounted && !_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadCurrentUser();
    _loadAssessments();
    _ensureDefaultContext();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quizTitleCtrl.dispose();
    _quizTopicCtrl.dispose();
    _assignTitleCtrl.dispose();
    _assignDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final user = await ApiService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentUser = null;
      });
    }
  }

  Future<void> _ensureDefaultContext() async {
    if (widget.classId != null && widget.subjectId != null) return;
    final className = widget.className;
    if (className == null || className.isEmpty) return;
    try {
      final subjects = await ApiService.getSubjectsForStudentClass(className: className);
      if (!mounted || subjects.isEmpty) return;
      setState(() {
        _defaultSubjectName ??= subjects.first['name']?.toString();
      });
    } catch (_) {
      // best-effort only
    }
  }

  bool get _isSuperAdmin {
    final flag = _currentUser?['is_super_admin'];
    return flag == 1 || flag == '1';
  }

  bool get _isAdmin {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    return role == 'admin';
  }

  bool get _isStudent {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    return role == 'student';
  }

  bool get _canCreateAssessments => !_isStudent;

  bool get _canAccessAcademicRecords {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    if (_isSuperAdmin || _isAdmin) return true;
    return role == 'teacher' || role == 'principal';
  }

  void _handleNavSelection(int index) {
    setState(() => _isNavExpanded = false);
    if (index == _selectedNavIndex) return;
    _replaceWithDashboard(index);
  }

  void _replaceWithDashboard(int index) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => StudentDashboard(initialIndex: index),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  Widget _buildNavBar() {
    return VerticalNavBar(
      selectedIndex: _selectedNavIndex,
      onItemSelected: _handleNavSelection,
      isExpanded: _isNavExpanded,
      onToggleExpanded: (expanded) {
        setState(() => _isNavExpanded = expanded);
      },
      showAddStudent: _isSuperAdmin,
      showCourses: true,
      showCourseAssignment: _isSuperAdmin,
      showAdminDues: _isSuperAdmin || _isAdmin,
      showStudentDues: !_isAdmin && !_isSuperAdmin,
      showTakeAttendance: _isAdmin || _isSuperAdmin,
      showGenerateTicket: _isSuperAdmin || _isStudent,
      showAcademicRecords: _canAccessAcademicRecords,
    );
  }

  Future<void> _pickDateTime({required bool forQuiz}) async {
    final now = DateTime.now();
    if (_isStudent) return;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDate: now,
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (forQuiz) {
        _quizWhen = dt;
      } else {
        _assignWhen = dt;
      }
    });
  }

  Future<void> _saveQuiz() async {
    if (_isStudent) return;
    final classId = widget.classId;
    final subjectId = widget.subjectId;
    if (classId == null || subjectId == null) {
      _toast('Class and subject are required.');
      return;
    }
    if (_quizWhen == null) {
      _toast('Pick a date and time for the quiz.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.saveClassQuiz(
        classId: classId,
        subjectId: subjectId,
        title: _quizTitleCtrl.text.isEmpty ? null : _quizTitleCtrl.text,
        topic: _quizTopicCtrl.text.isEmpty ? null : _quizTopicCtrl.text,
        scheduledAt: _quizWhen!,
      );
      _toast('Quiz scheduled.');
      await _loadAssessments();
    } catch (e) {
      _toast('Failed to save quiz: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAssignment() async {
    final classId = widget.classId;
    final subjectId = widget.subjectId;
    if (classId == null || subjectId == null) {
      _toast('Class and subject are required.');
      return;
    }
    if (_assignWhen == null) {
      _toast('Pick a deadline date and time for the assignment.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService.saveClassAssignment(
        classId: classId,
        subjectId: subjectId,
        title: _assignTitleCtrl.text.isEmpty ? null : _assignTitleCtrl.text,
        description: _assignDescCtrl.text.isEmpty ? null : _assignDescCtrl.text,
        deadline: _assignWhen!,
      );
      _toast('Assignment scheduled.');
      await _loadAssessments();
    } catch (e) {
      _toast('Failed to save assignment: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadAssessments() async {
    final classId = widget.classId;
    final subjectId = widget.subjectId;

    if (classId == null || subjectId == null) {
      if (!mounted) return;
      setState(() {
        _assessmentsLoading = false;
        _assessmentsError = null;
        _quizAssessments = const [];
        _assignmentAssessments = const [];
      });
      return;
    }

    if (mounted) {
      setState(() {
        _assessmentsLoading = true;
        _assessmentsError = null;
      });
    }

    try {
      final result = await ApiService.getClassAssessments(classId: classId, subjectId: subjectId);
      final quizzes = _sortAssessments(_normalizeAssessments(result['quizzes']));
      final assignments = _sortAssessments(_normalizeAssessments(result['assignments']));
      final highestQuiz = quizzes.isEmpty ? 0 : _asInt(quizzes.last['number']);
      final highestAssignment = assignments.isEmpty ? 0 : _asInt(assignments.last['number']);

      if (!mounted) return;
      setState(() {
        _quizAssessments = quizzes;
        _assignmentAssessments = assignments;
        _nextQuizNumber = highestQuiz + 1;
        _nextAssignmentNumber = highestAssignment + 1;
        _assessmentsLoading = false;
        _assessmentsError = null;
      });

      if (_isStudent) {
        await _loadStudentSubmissions(classId: classId, subjectId: subjectId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assessmentsLoading = false;
        _assessmentsError = e.toString();
        _quizAssessments = const [];
        _assignmentAssessments = const [];
        _studentAssignmentSubmissions = const [];
      });
    }
  }

  Future<void> _loadStudentSubmissions({required int classId, required int subjectId}) async {
    try {
      final rows = await ApiService.getAssignmentSubmissions(
        classId: classId,
        subjectId: subjectId,
      );
      if (!mounted) return;
      setState(() {
        _studentAssignmentSubmissions = rows;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _studentAssignmentSubmissions = const []);
    }
  }

  List<Map<String, dynamic>> _normalizeAssessments(dynamic raw) {
    if (raw is List) {
      return raw
          .map<Map<String, dynamic>>((item) {
            if (item is Map<String, dynamic>) {
              return Map<String, dynamic>.from(item);
            }
            if (item is Map) {
              return item.map((key, value) => MapEntry(key.toString(), value));
            }
            return <String, dynamic>{};
          })
          .where((element) => element.isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> _sortAssessments(List<Map<String, dynamic>> source) {
    final list = List<Map<String, dynamic>>.from(source);
    list.sort((a, b) {
      final aDeadline = _parseDate(a['deadline']);
      final bDeadline = _parseDate(b['deadline']);
      if (aDeadline != null && bDeadline != null) {
        final cmp = aDeadline.compareTo(bDeadline);
        if (cmp != 0) return cmp;
      } else if (aDeadline != null) {
        return -1;
      } else if (bDeadline != null) {
        return 1;
      }

      final aNumber = _asInt(a['number']);
      final bNumber = _asInt(b['number']);
      return aNumber.compareTo(bNumber);
    });
    return list;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final str = value.toString();
    if (str.isEmpty) return null;
    return DateTime.tryParse(str);
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> get _filteredQuizAssessments => _filterAssessments(_quizAssessments);

  List<Map<String, dynamic>> get _filteredAssignmentAssessments => _filterAssessments(_assignmentAssessments);

  List<Map<String, dynamic>> _filterAssessments(List<Map<String, dynamic>> source) {
    final filtered = source.where((item) {
      final status = (item['status'] ?? '').toString().toLowerCase();
      final isOverdue = item['is_overdue'] == true;
      final graded = _asInt(item['graded_count']);
      final total = _asInt(item['student_count']);
      final needsMarks = status == 'covered' && (total == 0 || graded < total);
      return isOverdue || needsMarks;
    }).toList();

    if (filtered.isNotEmpty) {
      return _sortAssessments(filtered);
    }
    return _sortAssessments(source);
  }

  Widget _buildSideIndex(String number, Color accent) {
    return Container(
      width: 42,
      height: 140,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.5), width: 1.2),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            number,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssessmentCard({
    required BuildContext context,
    required String stepLabel,
    required Color accent,
    required String title,
    required List<Widget> actionButtons,
    required List<Widget> bodyChildren,
    List<Widget> bottomSections = const [],
  }) {
    final theme = Theme.of(context);
    final bool isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: isMobile ? 18 : 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: ResponsiveHelper.getElevation(context, level: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSideIndex(stepLabel, accent),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: isMobile ? 18 : 20,
                              fontWeight: FontWeight.w700,
                              color: theme.textTheme.titleLarge?.color,
                            ),
                          ),
                        ),
                        if (actionButtons.isNotEmpty)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: actionButtons,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ...bodyChildren,
                  ],
                ),
              ),
            ],
          ),
          if (bottomSections.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...bottomSections,
          ],
        ],
      ),
    );
  }

  Widget _quizTab() {
    const accent = Color(0xFFF59E0B);
    final dateStr = _quizWhen == null
        ? 'No date selected'
        : DateFormat('yyyy-MM-dd HH:mm').format(_quizWhen!);

    final List<Widget> actions = _canCreateAssessments
        ? <Widget>[
            FilledButton.icon(
              onPressed: _saving ? null : _saveQuiz,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Quiz'),
            ),
          ]
        : const [];

    final List<Widget> formFields = _canCreateAssessments
        ? <Widget>[
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickDateTime(forQuiz: true),
                  icon: const Icon(Icons.event),
                  label: const Text('Pick date & time'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dateStr,
                    style: GoogleFonts.inter(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _quizTitleCtrl,
              decoration: const InputDecoration(labelText: 'Quiz title (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quizTopicCtrl,
              decoration: const InputDecoration(labelText: 'Quiz topic (optional)'),
            ),
          ]
        : <Widget>[
            _buildReadOnlyNotice(
              accent: accent,
              title: 'Scheduled quizzes',
              subtitle: _quizAssessments.isEmpty
                  ? 'Your teacher has not posted any quizzes yet.'
                  : 'Review upcoming or past quizzes assigned to this class.',
            ),
          ];

    return _buildAssessmentCard(
      context: context,
      stepLabel: _formatStepLabel(_nextQuizNumber),
      accent: accent,
      title: 'Quiz Details',
      actionButtons: actions,
      bodyChildren: formFields,
      bottomSections: _buildAssessmentFooter(isQuiz: true),
    );
  }

  Widget _assignmentTab() {
    const accent = Color(0xFF10B981);
    final dateStr = _assignWhen == null
        ? 'No deadline selected'
        : DateFormat('yyyy-MM-dd HH:mm').format(_assignWhen!);
    return _buildAssessmentCard(
      context: context,
      stepLabel: _formatStepLabel(_nextAssignmentNumber),
      accent: accent,
      title: 'Assignment Details',
      actionButtons: _canCreateAssessments
          ? [
              FilledButton.icon(
                onPressed: _saving ? null : _saveAssignment,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Assignment'),
              ),
            ]
          : const [],
      bodyChildren: _canCreateAssessments
          ? [
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickDateTime(forQuiz: false),
                    icon: const Icon(Icons.event),
                    label: const Text('Pick deadline'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      dateStr,
                      style: GoogleFonts.inter(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _assignTitleCtrl,
                decoration: const InputDecoration(labelText: 'Assignment title (optional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _assignDescCtrl,
                decoration: const InputDecoration(labelText: 'Description / Link (optional)'),
              ),
            ]
          : [
              _buildReadOnlyNotice(
                accent: accent,
                title: 'Assignments',
                subtitle: _assignmentAssessments.isEmpty
                    ? 'No assignments have been posted yet.'
                    : 'Submit your work before the deadline listed below.',
              ),
            ],
      bottomSections: _buildAssessmentFooter(isQuiz: false),
    );
  }

  String _formatStepLabel(int number) {
    final safe = number <= 0 ? 1 : number;
    final asString = safe.toString();
    return asString.length == 1 ? '0$asString' : asString;
  }

  Widget _buildStatusContainer(Color accent, {required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }

  List<Widget> _buildAssessmentFooter({required bool isQuiz}) {
    final accent = isQuiz ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    if (widget.classId == null || widget.subjectId == null) {
      return [
        _buildStatusContainer(
          accent,
          child: Text(
            'Select a class and subject to manage ${isQuiz ? 'quizzes' : 'assignments'}.',
            style: GoogleFonts.inter(fontSize: 14),
          ),
        ),
      ];
    }

    if (_assessmentsLoading) {
      return [
        _buildStatusContainer(
          accent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)),
              SizedBox(width: 12),
              Text('Loading overdue assessments...'),
            ],
          ),
        ),
      ];
    }

    if (_assessmentsError != null) {
      return [
        _buildStatusContainer(
          accent,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Failed to load assessments. ${_assessmentsError!}',
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: _loadAssessments,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ];
    }

    final items = isQuiz ? _filteredQuizAssessments : _filteredAssignmentAssessments;
    if (_isStudent) {
      return [
        _buildStudentAssessmentList(
          accent: accent,
          isQuiz: isQuiz,
          items: items,
        ),
      ];
    }

    if (items.isEmpty) {
      return const <Widget>[];
    }

    return items
        .map<Widget>((item) => _buildOverdueCard(item, accent: accent, isQuiz: isQuiz))
        .toList();
  }

  Widget _buildReadOnlyNotice({required Color accent, required String title, required String subtitle}) {
    return _buildStatusContainer(
      accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: accent)),
          const SizedBox(height: 6),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStudentAssessmentList({
    required Color accent,
    required bool isQuiz,
    required List<Map<String, dynamic>> items,
  }) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return _buildStatusContainer(
        accent,
        child: Text(
          isQuiz
              ? 'No quizzes have been scheduled yet. Check back later.'
              : 'No assignments have been posted yet.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
      );
    }

    return _buildStatusContainer(
      accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...items.map<Widget>((item) {
            final number = item['number'];
            final deadline = _formatDeadline(item['deadline']);
            final title = isQuiz ? 'Quiz' : 'Assignment';
            final desc = (item['description'] ?? item['topic'] ?? '').toString();
            final status = (item['status'] ?? '').toString();
            final isSubmitted = !isQuiz && _studentAssignmentSubmissions.any(
              (row) => _asInt(row['assignment_number']) == _asInt(number),
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$title ${number ?? '—'}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: accent),
                      ),
                      const Spacer(),
                      Chip(
                        label: Text(status.isEmpty ? 'scheduled' : status),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Deadline: $deadline', style: GoogleFonts.inter(fontSize: 12)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(desc, style: GoogleFonts.inter(fontSize: 12)),
                  ],
                  if (!isQuiz)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildStudentAssignmentActions(number: number, accent: accent, submitted: isSubmitted),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStudentAssignmentActions({required dynamic number, required Color accent, required bool submitted}) {
    final submission = _studentAssignmentSubmissions.firstWhere(
      (row) => _asInt(row['assignment_number']) == _asInt(number),
      orElse: () => <String, dynamic>{},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (submitted)
          Text(
            'Submitted on: ${submission['submitted_at'] ?? '—'}',
            style: GoogleFonts.inter(fontSize: 12, color: accent.withValues(alpha: 0.9)),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: () => _promptStudentSubmission(number: number),
              icon: Icon(submitted ? Icons.edit : Icons.cloud_upload),
              label: Text(submitted ? 'Resubmit' : 'Upload'),
            ),
            OutlinedButton.icon(
              onPressed: () => _promptStudentSubmission(number: number, asLink: true),
              icon: const Icon(Icons.link),
              label: const Text('Submit Link'),
            ),
            if (submitted)
              TextButton.icon(
                onPressed: () => _openSubmission(submission),
                icon: const Icon(Icons.visibility),
                label: const Text('View'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _promptStudentSubmission({required dynamic number, bool asLink = false}) async {
    if (!_isStudent) return;
    final assignmentNumber = _asInt(number);
    if (assignmentNumber <= 0) {
      _toast('Invalid assignment to submit.');
      return;
    }

    if (asLink) {
      final controller = TextEditingController();
      final result = await showDialog<String?> (
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Submit assignment link'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Submission URL'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      );

      if (result == null || result.isEmpty) return;
      await _submitAssignmentLink(number: assignmentNumber, url: result);
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;

      if (file.bytes != null) {
        await _submitAssignmentBytes(number: assignmentNumber, name: file.name, bytes: file.bytes!);
      } else if (file.path != null) {
        await _submitAssignmentFile(number: assignmentNumber, path: file.path!);
      } else {
        _toast('Unable to read selected file.');
      }
    } catch (e) {
      _toast('File selection failed: $e');
    }
  }

  Future<void> _submitAssignmentLink({required int number, required String url}) async {
    if (widget.classId == null || widget.subjectId == null) {
      _toast('Missing class/subject details.');
      return;
    }
    try {
      await ApiService.submitAssignmentLink(
        classId: widget.classId!,
        subjectId: widget.subjectId!,
        assignmentNumber: number,
        linkUrl: url,
      );
      _toast('Assignment link submitted.');
      await _loadStudentSubmissions(classId: widget.classId!, subjectId: widget.subjectId!);
    } catch (e) {
      _toast('Failed to submit link: $e');
    }
  }

  Future<void> _submitAssignmentFile({required int number, required String path}) async {
    if (widget.classId == null || widget.subjectId == null) {
      _toast('Missing class/subject details.');
      return;
    }
    try {
      await ApiService.submitAssignmentFile(
        classId: widget.classId!,
        subjectId: widget.subjectId!,
        assignmentNumber: number,
        filePath: path,
      );
      _toast('Assignment uploaded successfully.');
      await _loadStudentSubmissions(classId: widget.classId!, subjectId: widget.subjectId!);
    } catch (e) {
      _toast('Upload failed: $e');
    }
  }

  Future<void> _submitAssignmentBytes({required int number, required String name, required List<int> bytes}) async {
    if (widget.classId == null || widget.subjectId == null) {
      _toast('Missing class/subject details.');
      return;
    }
    try {
      await ApiService.submitAssignmentBytes(
        classId: widget.classId!,
        subjectId: widget.subjectId!,
        assignmentNumber: number,
        fileName: name,
        fileBytes: bytes,
      );
      _toast('Assignment uploaded successfully.');
      await _loadStudentSubmissions(classId: widget.classId!, subjectId: widget.subjectId!);
    } catch (e) {
      _toast('Upload failed: $e');
    }
  }

  int? _parseStudentId(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final text = raw.toString();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  List<Map<String, dynamic>> _mergeRosterWithMarks(
    List<Map<String, dynamic>> roster,
    List<Map<String, dynamic>> marks,
  ) {
    final markMap = <int, Map<String, dynamic>>{};
    for (final row in marks) {
      final id = _parseStudentId(row['student_user_id'] ?? row['user_id'] ?? row['student_id'] ?? row['id']);
      if (id == null) continue;
      markMap[id] = Map<String, dynamic>.from(row);
    }

    final merged = <Map<String, dynamic>>[];
    for (final student in roster) {
      final id = _parseStudentId(student['student_user_id'] ?? student['user_id'] ?? student['id']);
      if (id == null) continue;
      final markRow = markMap.remove(id);
      final name = (student['student_name'] ?? student['name'] ?? markRow?['student_name'] ?? markRow?['name'] ?? 'Student').toString();
      final email = student['student_email'] ?? student['email'] ?? markRow?['student_email'] ?? markRow?['email'];
      final roll = (student['roll_number'] ?? student['roll_no'] ?? student['roll'] ?? '').toString();

      final mergedRow = <String, dynamic>{
        'student_user_id': id,
        'user_id': id,
        'student_id': id,
        'name': name,
        'student_name': name,
        'student_email': email,
        'email': email,
        'roll_number': roll,
        'roll_no': roll,
      };
      if (markRow != null) {
        mergedRow.addAll(markRow);
      }
      merged.add(mergedRow);
    }

    if (markMap.isNotEmpty) {
      merged.addAll(markMap.values);
    }

    return merged;
  }

  String? _initialTotalMarksValue(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final total = row['total_marks'];
      if (total != null) {
        final text = total.toString();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
  }

  Widget _buildOverdueCard(Map<String, dynamic> data, {required Color accent, required bool isQuiz}) {
    final theme = Theme.of(context);
    final status = (data['status'] ?? '').toString();
    final titleKind = isQuiz ? 'Quiz' : 'Assignment';
    final number = data['number'];
    final description = data['description'] ?? data['topic'];
    final deadline = data['deadline'];
    final studentCount = data['student_count'] ?? 0;
    final gradedCount = data['graded_count'] ?? 0;
    final isProcessing = _markingInProgress.contains(data['id']);
    final showEnterMarks = status == 'covered';

    return _buildStatusContainer(
      accent,
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
                      '$titleKind ${number ?? '—'}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Deadline: ${_formatDeadline(deadline)}',
                      style: GoogleFonts.inter(fontSize: 13, color: theme.textTheme.bodySmall?.color),
                    ),
                    if (description != null && description.toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description.toString(),
                        style: GoogleFonts.inter(fontSize: 13, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.9)),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Marks recorded: $gradedCount / $studentCount',
                      style: GoogleFonts.inter(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                children: [
                  if (!showEnterMarks)
                    ElevatedButton(
                      onPressed: isProcessing ? null : () => _handleMarkAsDone(data, isQuiz: isQuiz),
                      style: ElevatedButton.styleFrom(backgroundColor: accent),
                      child: isProcessing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Mark as Done'),
                    ),
                  if (showEnterMarks)
                    OutlinedButton(
                      onPressed: () => _openMarksDialog(data, isQuiz: isQuiz),
                      child: const Text('Enter Marks'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDeadline(dynamic value) {
    if (value == null) return '—';
    final raw = value.toString();
    DateTime? dt;
    try {
      dt = DateTime.tryParse(raw);
    } catch (_) {
      dt = null;
    }
    if (dt == null) {
      return raw;
    }
    return DateFormat('MMM d, yyyy • h:mm a').format(dt.toLocal());
  }

  Future<void> _handleMarkAsDone(Map<String, dynamic> assessment, {required bool isQuiz}) async {
    final classId = widget.classId;
    final subjectId = widget.subjectId;
    if (classId == null || subjectId == null) {
      _toast('Class and subject are required.');
      return;
    }
    final id = (assessment['id'] as int?) ?? -1;
    if (id < 0) {
      _toast('Invalid assessment reference.');
      return;
    }
    if (_markingInProgress.contains(id)) {
      return;
    }

    setState(() {
      _markingInProgress.add(id);
    });
    try {
      await ApiService.updateAssessmentCompletion(
        kind: isQuiz ? 'quiz' : 'assignment',
        classId: classId,
        subjectId: subjectId,
        planItemId: assessment['plan_item_id'] as int?,
        number: assessment['number'] as int?,
        status: 'covered',
        completedAt: DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      );
      await _loadAssessments();
      _toast('${isQuiz ? 'Quiz' : 'Assignment'} marked as done.');
    } catch (e) {
      _toast('Failed to mark as done: $e');
    } finally {
      if (mounted) {
        setState(() {
          _markingInProgress.remove(id);
        });
      }
    }
  }

  Future<void> _openMarksDialog(Map<String, dynamic> assessment, {required bool isQuiz}) async {
    final classId = widget.classId;
    final subjectId = widget.subjectId;
    if (classId == null || subjectId == null) {
      _toast('Class and subject are required to enter marks.');
      return;
    }
    final number = assessment['number'] as int?;
    if (number == null) {
      _toast('Assessment number is missing.');
      return;
    }

    try {
      final marks = await ApiService.getStudentMarks(
        classId: classId,
        subjectId: subjectId,
        kind: isQuiz ? 'quiz' : 'assignment',
        number: number,
      );

      Map<int, Map<String, dynamic>> submissionMap = {};
      if (!isQuiz) {
        final submissions = await ApiService.getAssignmentSubmissions(
          classId: classId,
          subjectId: subjectId,
          assignmentNumber: number,
        );
        submissionMap = {
          for (final entry in submissions)
            if ((entry['student_id'] ?? entry['student_user_id']) != null)
              int.parse((entry['student_id'] ?? entry['student_user_id']).toString()): entry,
        };
      }

      List<Map<String, dynamic>> roster = [];
      if ((widget.className ?? '').isNotEmpty) {
        try {
          roster = await ApiService.getStudentsInClass(widget.className!);
        } catch (e) {
          _toast('Unable to load class roster: $e');
        }
      }

      final studentRows = _mergeRosterWithMarks(roster, marks);

      final totalMarksValue = _initialTotalMarksValue(studentRows) ?? '';
      final totalController = TextEditingController(text: totalMarksValue);
      final controllers = <int, TextEditingController>{};
      for (final row in studentRows) {
        final id = _parseStudentId(row['student_user_id'] ?? row['user_id'] ?? row['id']);
        if (id == null) continue;
        final obtained = row['obtained_marks'];
        controllers[id] = TextEditingController(text: obtained == null ? '' : obtained.toString());
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text('${isQuiz ? 'Quiz' : 'Assignment'} ${number.toString()}'),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((assessment['description'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            assessment['description'].toString(),
                            style: GoogleFonts.inter(fontSize: 13),
                          ),
                        ),
                      TextField(
                        controller: totalController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        decoration: const InputDecoration(labelText: 'Total Marks'),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 360,
                        child: studentRows.isEmpty
                            ? Center(
                                child: Text(
                                  'No students found for this class.',
                                  style: GoogleFonts.inter(fontSize: 13),
                                ),
                              )
                            : ListView.separated(
                                itemBuilder: (context, index) {
                                  final row = studentRows[index];
                                  final studentId = _parseStudentId(row['student_user_id'] ?? row['user_id'] ?? row['id']);
                                  if (studentId == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final itemTheme = Theme.of(context);
                                  final name = (row['student_name'] ?? row['name'] ?? 'Student').toString();
                                  final email = row['student_email'] ?? row['email'];
                                  final roll = (row['roll_number'] ?? row['roll_no'] ?? row['roll'] ?? '').toString();
                                  final ctrl = controllers[studentId] ??= TextEditingController(
                                    text: row['obtained_marks'] == null ? '' : row['obtained_marks'].toString(),
                                  );
                                  final submission = submissionMap[studentId];

                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: roll.isEmpty
                                        ? null
                                        : Container(
                                            width: 44,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: itemTheme.colorScheme.primary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              roll,
                                              style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: itemTheme.colorScheme.primary),
                                            ),
                                          ),
                                    title: Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                                    subtitle: email != null
                                        ? Text(email.toString(), style: GoogleFonts.inter(fontSize: 12))
                                        : null,
                                    trailing: Wrap(
                                      spacing: 8,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (!isQuiz && submission != null)
                                          TextButton.icon(
                                            onPressed: () => _openSubmission(submission),
                                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                                            label: const Text('Check'),
                                          ),
                                        SizedBox(
                                          width: 86,
                                          child: TextField(
                                            controller: ctrl,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(labelText: 'Marks'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemCount: studentRows.length,
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final total = int.tryParse(totalController.text.trim());
                      if (total == null || total <= 0) {
                        _toast('Enter a valid total marks value.');
                        return;
                      }
                      final entries = <Map<String, dynamic>>[];
                      controllers.forEach((studentId, ctrl) {
                        final text = ctrl.text.trim();
                        if (text.isEmpty) return;
                        final value = double.tryParse(text);
                        if (value != null) {
                          entries.add({
                            'student_user_id': studentId,
                            'obtained_marks': value,
                          });
                        }
                      });

                      try {
                        await ApiService.upsertStudentMarks(
                          classId: classId,
                          subjectId: subjectId,
                          kind: isQuiz ? 'quiz' : 'assignment',
                          number: number,
                          totalMarks: total,
                          entries: entries,
                        );
                        if (context.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        await _loadAssessments();
                        _toast('Marks saved successfully.');
                      } catch (e) {
                        _toast('Failed to save marks: $e');
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      totalController.dispose();
      for (final controller in controllers.values) {
        controller.dispose();
      }
    } catch (e) {
      _toast('Unable to load marks: $e');
    }
  }

  Future<void> _openSubmission(Map<String, dynamic> submission) async {
    final submissionType = (submission['submission_type'] ?? '').toString();
    try {
      if (submissionType == 'link') {
        final link = submission['file_name']?.toString();
        if (link == null || link.isEmpty) {
          _toast('Submission link is unavailable.');
          return;
        }
        final uri = Uri.tryParse(link);
        if (uri == null) {
          _toast('Invalid submission link.');
          return;
        }
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          _toast('Could not open the submission link.');
        }
      } else {
        final submissionIdRaw = submission['id'] ?? submission['submission_id'];
        if (submissionIdRaw == null) {
          _toast('Submission file is unavailable.');
          return;
        }
        final submissionId = submissionIdRaw.toString();
        final downloadUrl = '${ApiService.baseUrl}?endpoint=download_assignment&submission_id=$submissionId';
        final uri = Uri.parse(downloadUrl);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          _toast('Could not launch the submission file.');
        }
      }
    } catch (e) {
      _toast('Failed to open submission: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isMobile = ResponsiveHelper.isMobile(context);
    final navWidth = ResponsiveHelper.getNavWidth(context, _isNavExpanded);
    final contentPadding = ResponsiveHelper.getContentPadding(context);

    final displaySubject =
        (widget.subjectName != null && widget.subjectName!.isNotEmpty) ? widget.subjectName : _defaultSubjectName;

    final List<String> contextChips = [
      if (widget.className != null && widget.className!.isNotEmpty)
        'Class: ${widget.className}',
      if (displaySubject != null) 'Subject: $displaySubject',
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: isMobile
          ? Drawer(
              child: SafeArea(
                child: _buildNavBar(),
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMobile)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: navWidth,
                curve: Curves.easeInOut,
                child: _buildNavBar(),
              ),
            Expanded(
              child: Container(
                color: theme.colorScheme.surface,
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderBar(context: context, theme: theme, isMobile: isMobile),
                    if (contextChips.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(contentPadding.left, 12, contentPadding.right, 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: contextChips
                              .map(
                                (label) => Chip(
                                  label: Text(label, style: GoogleFonts.inter(fontSize: 12)),
                                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: contentPadding.add(const EdgeInsets.only(top: 12)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                            boxShadow: ResponsiveHelper.getElevation(context, level: 1),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    SingleChildScrollView(
                                      padding: EdgeInsets.fromLTRB(
                                        isMobile ? 16 : 24,
                                        isMobile ? 16 : 24,
                                        isMobile ? 16 : 24,
                                        32,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          _quizTab(),
                                        ],
                                      ),
                                    ),
                                    SingleChildScrollView(
                                      padding: EdgeInsets.fromLTRB(
                                        isMobile ? 16 : 24,
                                        isMobile ? 16 : 24,
                                        isMobile ? 16 : 24,
                                        32,
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          _assignmentTab(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar({
    required BuildContext context,
    required ThemeData theme,
    required bool isMobile,
  }) {
    final bool isQuizSelected = _tabController.index == 0;
    final double horizontal = isMobile ? 16 : 24;

    return Container(
      width: double.infinity,
      color: theme.colorScheme.primary,
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: isMobile ? 10 : 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              final popped = await Navigator.of(context).maybePop();
              if (!popped && isMobile) {
                _scaffoldKey.currentState?.openDrawer();
              }
            },
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Manage Assessments',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: isMobile ? 16 : 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _HeaderTabButton(
            label: 'Quizzes',
            icon: Icons.quiz_outlined,
            selected: isQuizSelected,
            onTap: () => _tabController.animateTo(0),
          ),
          const SizedBox(width: 6),
          _HeaderTabButton(
            label: 'Assignments',
            icon: Icons.assignment_outlined,
            selected: !isQuizSelected,
            onTap: () => _tabController.animateTo(1),
          ),
        ],
      ),
    );
  }
}

class _HeaderTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _HeaderTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? Colors.white : Colors.white.withOpacity(0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? theme.colorScheme.primary : Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? theme.colorScheme.primary : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
