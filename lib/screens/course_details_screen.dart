import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../utils/responsive_helper.dart';
import 'home.dart';

class CourseDetailsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onOpenLectures;
  final VoidCallback? onOpenAttendance;
  // Passed-in course data
  final String courseTitle;
  final String? className;
  final String? subjectName;
  final String? teacherName;
  final Color accentColor;
  final bool isAdmin; // Admin-only controls
  // Identifiers to wire backend
  final String? level; // Education level: EarlyYears | Primary | Secondary
  final int? classId;
  final int? subjectId;

  const CourseDetailsScreen({
    super.key,
    this.onBack,
    this.onOpenLectures,
    this.onOpenAttendance,
    required this.courseTitle,
    this.className,
    this.subjectName,
    this.teacherName,
    this.accentColor = const Color(0xFF8B5CF6),
    this.isAdmin = false,
    this.level,
    this.classId,
    this.subjectId,
  });

  @override
  State<CourseDetailsScreen> createState() => _CourseDetailsScreenState();
}

class _CourseDetailsScreenState extends State<CourseDetailsScreen> {
  // Local UI state (can be wired to backend later)
  String? _upcomingLectureDateTime; // e.g., 2025-09-01 09:00 AM
  String? _nextQuizDateTime; // e.g., 2025-09-05 10:00 AM
  String? _nextQuizTopic; // Local-only: topic/name for upcoming quiz
  int? _plannedQuizNumber; // Local-only: planned upcoming quiz number from dialog
  String? _nextAssignmentLink; // URL
  String? _nextAssignmentDeadline; // MySQL datetime
  int? _nextAssignmentNumber; // New: next assignment number to be finalized upfront
  int _totalLectures = 0;
  // Each lecture: { 'number': '1', 'name': 'Intro', 'link': 'https://...' }
  final List<Map<String, String>> _lectures = [];
  // Backend MySQL datetime strings (YYYY-MM-DD HH:MM:SS)
  String? _upcomingLectureAt;
  String? _nextQuizAt;
  String? _lastQuizTakenAt; // MySQL datetime
  int? _lastQuizNumber;
  String? _lastAssignmentTakenAt; // MySQL datetime
  int? _lastAssignmentNumber;
  final List<Timer> _assignmentTimers = [];
  // Summary box controllers
  final TextEditingController _todayTopicsCtrl = TextEditingController();
  final TextEditingController _reviseTopicsCtrl = TextEditingController();
  bool _loadingSummary = false;
  // Editing state for summary box
  bool _editingEnabled = false; // Admin fields disabled until Edit is pressed
  DateTime? _lastSummaryUpdatedAt; // Tracks updated_at from last saved entry
  
  // File upload state
  File? _selectedFile;
  String? _selectedFileName;
  List<int>? _selectedFileBytes;
  bool _uploadingFile = false;
  int? _resolvedClassId;
  int? _resolvedSubjectId;

  int? get _classIdEff => widget.classId ?? _resolvedClassId;
  int? get _subjectIdEff => widget.subjectId ?? _resolvedSubjectId;

  bool get _withinEditWindow {
    if (_lastSummaryUpdatedAt == null) return true; // no prior entry => allow editing
    final diff = DateTime.now().difference(_lastSummaryUpdatedAt!);
    return diff.inMinutes < 12 * 60; // 12 hours
  }

  Future<void> _ensureIdentifiers() async {
    // Attempt to resolve class/subject IDs if they are not provided
    if ((widget.classId != null && widget.subjectId != null)) {
      _dlog('IDs already provided by widget: classId=${widget.classId}, subjectId=${widget.subjectId}');
      return;
    }
    final className = widget.className?.trim();
    final subjectName = widget.subjectName?.trim();
    if (className == null || className.isEmpty || subjectName == null || subjectName.isEmpty) {
      _dlog('Cannot resolve IDs: className or subjectName is empty. className=${className ?? 'null'}, subjectName=${subjectName ?? 'null'}');
      return;
    }
    final level = _detectLevelFromClassName(className);
    if (level == null) {
      _dlog('Could not detect level from className=$className; skipping ID resolve');
      return;
    }
    try {
      _dlog('Resolving IDs for level=$level, className=$className, subjectName=$subjectName');
      final classes = await ApiService.getClasses(level);
      final subjects = await ApiService.getSubjects(level);

      String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r"\s+"), " ");
      String squash(String s) => s.replaceAll(RegExp(r"\s+"), "");

      Map<String, dynamic> findBestMatch(List<Map<String, dynamic>> list, List<String> keys, String target) {
        final t1 = norm(target);
        final t2 = squash(t1);
        for (final m in list) {
          final name = (m[keys.firstWhere((k) => m.containsKey(k), orElse: () => keys.first)] ?? '').toString();
          final n1 = norm(name);
          if (n1 == t1) return m;
        }
        for (final m in list) {
          final name = (m[keys.firstWhere((k) => m.containsKey(k), orElse: () => keys.first)] ?? '').toString();
          if (squash(norm(name)) == t2) return m;
        }
        for (final m in list) {
          final name = (m[keys.firstWhere((k) => m.containsKey(k), orElse: () => keys.first)] ?? '').toString().toLowerCase();
          if (name.contains(t1) || t1.contains(name)) return m;
        }
        return const {};
      }

      final cls = findBestMatch(
        List<Map<String, dynamic>>.from(classes),
        const ['name'],
        className,
      );
      final sub = findBestMatch(
        List<Map<String, dynamic>>.from(subjects),
        const ['name', 'subject_name'],
        subjectName,
      );

      final int? classId = (cls['id'] is int) ? cls['id'] as int : int.tryParse((cls['id'] ?? '').toString());
      final int? subjectId = (sub['id'] is int) ? sub['id'] as int : int.tryParse((sub['id'] ?? '').toString());
      _dlog('Match results -> classMatch=${cls['name'] ?? ''}, subjectMatch=${sub['name'] ?? sub['subject_name'] ?? ''}');
      if (mounted) {
        setState(() {
          _resolvedClassId = classId;
          _resolvedSubjectId = subjectId;
        });
      }
      _dlog('Resolved IDs: classId=${classId?.toString() ?? 'null'}, subjectId=${subjectId?.toString() ?? 'null'}');
    } catch (e) {
      _dlog('Failed to resolve IDs: $e');
    }
  }

  String? _detectLevelFromClassName(String className) {
    bool isSecondaryClass(String c) {
      final digits = RegExp(r"\d+").firstMatch(c)?.group(0);
      if (digits == null) return false;
      final n = int.tryParse(digits);
      if (n == null) return false;
      return n >= 8 && n <= 10;
    }

    bool isPrimaryMidClass(String c) {
      final digits = RegExp(r"\d+").firstMatch(c)?.group(0);
      if (digits == null) return false;
      final n = int.tryParse(digits);
      if (n == null) return false;
      return n >= 4 && n <= 7;
    }

    bool isLowerPrimaryClass(String c) {
      final digits = RegExp(r"\d+").firstMatch(c)?.group(0);
      if (digits == null) return false;
      final n = int.tryParse(digits);
      if (n == null) return false;
      return n >= 1 && n <= 3;
    }

    final lc = className.toLowerCase();
    final isEarlyYears = lc.contains('montessori') || lc.contains('nursery') || lc.contains('prep') || lc == 'kg' || lc.contains('kg') || lc.contains('playgroup') || lc.contains('earlyyears') || lc.contains('early years');
    if (isEarlyYears) return 'EarlyYears';
    if (isLowerPrimaryClass(className)) return 'Primary';
    if (isPrimaryMidClass(className)) return 'Primary';
    if (isSecondaryClass(className)) return 'Secondary';
    return null;
  }

  void _dlog(String message) {
    // Centralized debug logger so we can filter easily
    // ignore: avoid_print
    print('[CourseDetails][${DateTime.now().toIso8601String()}] $message');
  }

  Future<void> _openStudentAssignmentDialog() async {
    // Show upcoming assignment + previous assignments (fetched from backend)
    final List<Map<String, dynamic>> history = [];
    bool loading = true;
    String? error;

    if (widget.classId != null && widget.subjectId != null) {
      try {
        final uid = await ApiService.getCurrentUserId();
        // ignore: avoid_print
        print('[AssignHistory] Fetching with classId=${widget.classId}, subjectId=${widget.subjectId}, userId=$uid');
        final res = await ApiService.getStudentAssignmentHistory(
          classId: widget.classId!,
          subjectId: widget.subjectId!,
          userId: uid,
        );
        history.addAll(res);
        // Fallback: include last-known meta if server returned empty
        if (history.isEmpty && (_lastAssignmentTakenAt != null || _lastAssignmentNumber != null)) {
          history.add({
            'number': _lastAssignmentNumber,
            'taken_at': _lastAssignmentTakenAt,
          });
        }
        // ignore: avoid_print
        print('[AssignHistory] Received ${history.length} entries');
      } catch (e) {
        error = e.toString();
        // ignore: avoid_print
        print('[AssignHistory][Error] $error');
      }
    } else {
      error = 'Missing class/subject context to fetch assignment history.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing class/subject identifiers. Cannot load assignment history.')),
        );
      }
    }
    loading = false;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const lightCard = Color(0xFFE7E0DE);
        const lightBorder = Color(0xFFD9D2D0);
        final Color primaryText = isLight ? theme.colorScheme.onSurface : Colors.white;
        final Color secondaryText = isLight
            ? theme.colorScheme.onSurface.withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.85);
        return AlertDialog(
          backgroundColor: isLight ? lightCard : const Color(0xFF0B1222),
          title: Text(
            'Assignment Details',
            style: GoogleFonts.inter(
              color: isLight ? primaryBlue : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Upcoming section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLight ? lightCard : const Color(0xFFEC4899).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLight ? lightBorder : const Color(0xFFEC4899).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upcoming Assignment',
                        style: GoogleFonts.inter(
                          color: isLight ? primaryBlue : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (_nextAssignmentDeadline != null && _nextAssignmentDeadline!.isNotEmpty)
                            ? _displayFromMysql(_nextAssignmentDeadline!)
                            : 'Not announced',
                        style: GoogleFonts.inter(
                          color: secondaryText,
                        ),
                      ),
                      if (_nextAssignmentNumber != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Assignment #$_nextAssignmentNumber',
                          style: GoogleFonts.inter(
                            color: secondaryText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (_nextAssignmentLink != null && _nextAssignmentLink!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _nextAssignmentLink!,
                          style: GoogleFonts.inter(
                            color: isLight
                                ? primaryBlue.withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Previous Assignments',
                  style: GoogleFonts.inter(
                    color: isLight ? primaryBlue : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                else if (error != null)
                  Text(error, style: GoogleFonts.inter(color: Colors.redAccent))
                else if (history.isEmpty)
                  Text(
                    'No assignments recorded yet.',
                    style: GoogleFonts.inter(color: secondaryText),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final h = history[index];
                        final numTxt = (h['number'] ?? '').toString();
                        final total = (h['total_marks'] ?? '').toString();
                        final obtained = (h['obtained_marks'] ?? '').toString();
                        final when = (h['taken_at'] ?? h['updated_at'] ?? '').toString();
                        final whenDisp = when.isEmpty ? '' : _displayFromMysql(when);
                        final topic = (h['topic'] ?? '').toString();
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isLight ? lightCard : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEC4899).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFEC4899)),
                                ),
                                child: Text('Assignment #$numTxt', style: GoogleFonts.inter(color: const Color(0xFFEC4899), fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (obtained.isNotEmpty || total.isNotEmpty)
                                      Text(
                                        '${obtained.isEmpty ? '-' : obtained} / ${total.isEmpty ? '-' : total}',
                                        style: GoogleFonts.inter(
                                          color: isLight ? primaryBlue : Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    if (topic.isNotEmpty)
                                      Text(
                                        topic,
                                        style: GoogleFonts.inter(
                                          color: secondaryText,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (whenDisp.isNotEmpty)
                                Text(
                                  whenDisp,
                                  style: GoogleFonts.inter(
                                    color: isLight
                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                                        : Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Future<void> _openStudentQuizDialog() async {
    // Students view-only: show upcoming and previous quiz history
    final List<Map<String, dynamic>> history = [];
    bool loading = true;
    String? error;
    // Fire request only if IDs are available
    if (widget.classId != null && widget.subjectId != null) {
      try {
        final uid = await ApiService.getCurrentUserId();
        // Prefer explicit userId to avoid any JWT/session mismatch
        // Debug: Log parameters used for fetching quiz history
        // ignore: avoid_print
        print('[QuizHistory] Fetching with classId=${widget.classId}, subjectId=${widget.subjectId}, userId=$uid');
        final res = await ApiService.getStudentQuizHistory(
          classId: widget.classId!,
          subjectId: widget.subjectId!,
          userId: uid,
        );
        history.addAll(res);
        // ignore: avoid_print
        print('[QuizHistory] Received ${history.length} entries');
      } catch (e) {
        error = e.toString();
        // ignore: avoid_print
        print('[QuizHistory][Error] $error');
      }
    } else {
      error = 'Missing class/subject context to fetch quiz history.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing class/subject identifiers. Cannot load quiz history.')),
        );
      }
    }
    loading = false;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const lightCard = Color(0xFFE7E0DE);
        const lightBorder = Color(0xFFD9D2D0);
        final Color secondaryText = isLight
            ? theme.colorScheme.onSurface.withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.85);
        return AlertDialog(
          backgroundColor: isLight ? lightCard : const Color(0xFF0B1222),
          title: Text(
            'Quiz Details',
            style: GoogleFonts.inter(
              color: isLight ? primaryBlue : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Upcoming section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isLight ? lightCard : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isLight ? lightBorder : const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upcoming Quiz',
                        style: GoogleFonts.inter(
                          color: isLight ? primaryBlue : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (_nextQuizAt != null && _nextQuizAt!.isNotEmpty)
                            ? _displayFromMysql(_nextQuizAt!)
                            : 'Not announced',
                        style: GoogleFonts.inter(color: secondaryText),
                      ),
                      if (_nextQuizTopic != null && _nextQuizTopic!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _nextQuizTopic!,
                          style: GoogleFonts.inter(color: secondaryText, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Previous Quizzes',
                  style: GoogleFonts.inter(
                    color: isLight ? primaryBlue : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (loading)
                  const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                else if (error != null)
                  Text(error, style: GoogleFonts.inter(color: Colors.redAccent))
                else if (history.isEmpty)
                  Text('No quizzes recorded yet.', style: GoogleFonts.inter(color: secondaryText))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final h = history[index];
                        final numTxt = (h['number'] ?? '').toString();
                        final total = (h['total_marks'] ?? '').toString();
                        final obtained = (h['obtained_marks'] ?? '').toString();
                        final when = (h['taken_at'] ?? h['updated_at'] ?? '').toString();
                        final whenDisp = when.isEmpty ? '' : _displayFromMysql(when);
                        final topic = (h['topic'] ?? '').toString();
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isLight ? lightCard : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFF59E0B)),
                                ),
                                child: Text('Quiz #$numTxt', style: GoogleFonts.inter(color: const Color(0xFFF59E0B), fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$obtained / $total',
                                      style: GoogleFonts.inter(
                                        color: isLight ? primaryBlue : Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (topic.isNotEmpty)
                                      Text(
                                        topic,
                                        style: GoogleFonts.inter(color: secondaryText, fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              if (whenDisp.isNotEmpty)
                                Text(
                                  whenDisp,
                                  style: GoogleFonts.inter(
                                    color: isLight
                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                                        : Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _promptForQuizDetails({
    String? initialTopic,
    int? initialNumber,
    String? initialWhenMysql,
  }) async {
    final topicCtrl = TextEditingController(text: initialTopic ?? '');
    final numberCtrl = TextEditingController(text: initialNumber?.toString() ?? '');
    String? mysqlWhen = initialWhenMysql;
    String whenDisplay = '';
    if (mysqlWhen != null && mysqlWhen.isNotEmpty) {
      whenDisplay = _displayFromMysql(mysqlWhen);
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const surface = Color(0xFFFAFAF7);
        const lightCard = Colors.white;
        const lightBorder = Color(0xFFE5E7EB);
        final titleColor = isLight ? primaryBlue : Colors.white;
        final bodyColor = isLight ? primaryBlue : Colors.white;
        final secondaryColor = isLight ? const Color(0xFF374151) : Colors.white.withValues(alpha: 0.7);

        OutlineInputBorder buildBorder(Color color) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color),
            );

        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: isLight ? surface : const Color(0xFF0B1222),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Quiz Details', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Topic / Lecture Name', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: topicCtrl,
                      style: TextStyle(color: bodyColor),
                      decoration: InputDecoration(
                        hintText: 'e.g. Algebra - Quadratic Equations',
                        hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
                        filled: true,
                        fillColor: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
                        enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                        focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                      ),
                      keyboardType: TextInputType.text,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    Text('Quiz Number', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: numberCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: bodyColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. 1',
                          hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
                          filled: true,
                          fillColor: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
                          enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                          focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Quiz Date & Time', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              whenDisplay.isEmpty ? 'DD/MM/YY, 00:00 AM/PM' : whenDisplay,
                              style: GoogleFonts.inter(color: secondaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.event),
                          label: const Text('Pick'),
                          onPressed: () async {
                            await _pickDateTime((dt, disp) async {
                              setLocal(() {
                                mysqlWhen = _toMysql(dt);
                                whenDisplay = disp;
                              });
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: isLight ? primaryBlue : Colors.white,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () {
                    final t = topicCtrl.text.trim();
                    final n = int.tryParse(numberCtrl.text.trim());
                    if (n == null || n <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid quiz number.')));
                      return;
                    }
                    if (mysqlWhen == null || mysqlWhen!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a quiz date/time.')));
                      return;
                    }
                    Navigator.pop(context, {
                      'topic': t.isEmpty ? null : t,
                      'number': n,
                      'when': mysqlWhen,
                      'whenDisplay': whenDisplay,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openQuizMenuOrDialog() async {
    // If not set yet, open details dialog directly
    if ((_nextQuizAt == null || _nextQuizAt!.isEmpty)) {
      final res = await _promptForQuizDetails(
        initialTopic: _nextQuizTopic,
        initialNumber: null,
        initialWhenMysql: _nextQuizAt,
      );
      if (res != null) {
        setState(() {
          _nextQuizTopic = res['topic'] as String?;
          _nextQuizDateTime = res['whenDisplay'] as String?;
          _nextQuizAt = res['when'] as String?;
          _plannedQuizNumber = res['number'] as int?;
        });
        await _saveSummary();
      }
      return;
    }

    // Otherwise, show Edit/Add Next options
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1222),
        title: Text('Quiz Options', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Edit Current Quiz'),
              textColor: Colors.white,
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              title: const Text('Add Next Quiz'),
              textColor: Colors.white,
              onTap: () => Navigator.pop(context, 'next'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'edit') {
      final res = await _promptForQuizDetails(
        initialTopic: _nextQuizTopic,
        initialNumber: _plannedQuizNumber,
        initialWhenMysql: _nextQuizAt,
      );
      if (res != null) {
        setState(() {
          _nextQuizTopic = res['topic'] as String?;
          _nextQuizDateTime = res['whenDisplay'] as String?;
          _nextQuizAt = res['when'] as String?;
          _plannedQuizNumber = res['number'] as int?;
        });
        await _saveSummary();
      }
    } else if (choice == 'next') {
      final res = await _promptForQuizDetails();
      if (res != null) {
        setState(() {
          _nextQuizTopic = res['topic'] as String?;
          _nextQuizDateTime = res['whenDisplay'] as String?;
          _nextQuizAt = res['when'] as String?;
          _plannedQuizNumber = res['number'] as int?;
        });
        await _saveSummary();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _ensureIdentifiers();
  }

  int _getAvailableLecturesCount() {
    // Only count lectures that have links added by teachers
    return _lectures.where((lecture) => 
      lecture['link'] != null && lecture['link']!.trim().isNotEmpty
    ).length;
  }

  Future<void> _openStudentLecturesDialog() async {
    // Show only lectures that have links added by teachers
    final availableLectures = _lectures.where((lecture) => 
      lecture['link'] != null && lecture['link']!.trim().isNotEmpty
    ).toList();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final onSurface = theme.colorScheme.onSurface;
        final secondaryText = theme.textTheme.bodyMedium?.color?.withOpacity(0.65) ?? const Color(0xFF6B7280);

        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Available Lectures',
            style: GoogleFonts.inter(color: onSurface, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (availableLectures.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
                    ),
                    child: Text(
                      'No lectures available yet. Your teacher will add lecture links here.',
                      style: GoogleFonts.inter(color: secondaryText),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: availableLectures.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final lecture = availableLectures[index];
                        final lectureNumber = lecture['number'] ?? '${index + 1}';
                        final lectureName = lecture['name'] ?? 'Lecture $lectureNumber';
                        final lectureLink = lecture['link'] ?? '';

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: widget.accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: widget.accentColor.withOpacity(0.6)),
                                ),
                                child: Text(
                                  'Lecture #$lectureNumber',
                                  style: GoogleFonts.inter(
                                    color: widget.accentColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lectureName,
                                      style: GoogleFonts.inter(
                                        color: onSurface,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Click to open lecture',
                                      style: GoogleFonts.inter(
                                        color: secondaryText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _openLectureLink(lectureLink),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.accentColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Open',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showAssignmentOptionsDialog(BuildContext context) {
    // Ensure we attempt resolving IDs if they aren't available yet (hot reload won't re-run initState)
    if (_classIdEff == null || _subjectIdEff == null) {
      _dlog('IDs missing on dialog open; invoking resolver');
      // Fire and forget; results will update state and future actions will have IDs
      _ensureIdentifiers();
    }
    _dlog('Opening Assignment Options Dialog with ids: classId=${_classIdEff?.toString() ?? 'null'}, subjectId=${_subjectIdEff?.toString() ?? 'null'}, nextAssignmentNumber=${_nextAssignmentNumber?.toString() ?? 'null'}, nextAssignmentDeadline=${_nextAssignmentDeadline ?? 'null'}, nextAssignmentLink=${_nextAssignmentLink ?? 'null'}');
    final TextEditingController linkController = TextEditingController(text: _nextAssignmentLink ?? '');
    
    showDialog(
      context: context,
      barrierDismissible: true,
            builder: (context) {
        final theme = Theme.of(context);
        final onSurface = theme.colorScheme.onSurface;
        final secondaryText = theme.textTheme.bodyMedium?.color?.withOpacity(0.65) ?? const Color(0xFF6B7280);

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          child: Container(
            width: 480,
            constraints: const BoxConstraints(maxHeight: 600),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.dividerColor.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor.withOpacity(0.2)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.assignment_turned_in,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assignment Portal',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'View instructions and submit your work',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close,
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_nextAssignmentLink != null && _nextAssignmentLink!.isNotEmpty) ...[
                          // Assignment Instructions Card
                          Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.description,
                                          color: theme.colorScheme.primary,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Assignment Instructions',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Review the assignment requirements before submitting',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _openAssignmentLink();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.colorScheme.primary,
                                        foregroundColor: theme.colorScheme.onPrimary,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.open_in_new, size: 18),
                                      label: Text(
                                        'View Assignment',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Submit Solution Card
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.secondary.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.secondary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.link,
                                        color: theme.colorScheme.secondary,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Submit Solution Link',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Share your completed assignment via Google Drive, GitHub, or any public link',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: secondaryText,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
                                  ),
                                  child: TextField(
                                    controller: linkController,
                                    style: GoogleFonts.inter(color: onSurface),
                                    decoration: InputDecoration(
                                      hintText: 'Paste your assignment URL here...',
                                      hintStyle: GoogleFonts.inter(
                                        color: secondaryText,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.all(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      final newLink = linkController.text.trim();
                                      if (newLink.isNotEmpty) {
                                        _submitAssignmentLink(newLink);
                                        Navigator.pop(context);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.colorScheme.secondary,
                                      foregroundColor: theme.colorScheme.onSecondary,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.send, size: 18),
                                    label: Text(
                                      'Submit Solution',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Upload File Card
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.tertiary.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.tertiary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.cloud_upload,
                                        color: theme.colorScheme.tertiary,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Upload Solution File',
                                      style: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Upload your assignment as PDF, Word document, or other supported format',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: secondaryText,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (_selectedFileName != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.tertiary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.colorScheme.tertiary.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.description,
                                          color: theme.colorScheme.tertiary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _selectedFileName!,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              color: onSurface,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _selectedFile = null;
                                              _selectedFileName = null;
                                              _selectedFileBytes = null;
                                            });
                                          },
                                          icon: Icon(
                                            Icons.close,
                                            color: secondaryText,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _uploadingFile ? null : () => _uploadAssignmentFile(),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.colorScheme.tertiary,
                                          foregroundColor: theme.colorScheme.onTertiary,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.attach_file, size: 18),
                                        label: Text(
                                          _selectedFileName != null ? 'Change File' : 'Choose File',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: (_uploadingFile || _selectedFileName == null) ? null : () => _performFileUpload(),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.colorScheme.secondary,
                                          foregroundColor: theme.colorScheme.onSecondary,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                        icon: _uploadingFile
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : const Icon(Icons.upload, size: 18),
                                        label: Text(
                                          _uploadingFile ? 'Uploading...' : 'Upload File',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
      },
    );
  }

  void _submitAssignmentLink(String assignmentLink) {
    // TODO: Implement assignment submission to database/API
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Assignment submitted successfully: $assignmentLink'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _uploadAssignmentFile() async {
    try {
      _dlog('Launching file picker. kIsWeb=$kIsWeb');
      // Pick a file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );

      if (result != null) {
        final picked = result.files.single;
        _dlog('File picked: name=${picked.name}, size=${picked.size}, bytes_null=${picked.bytes == null}, path=${picked.path ?? 'null'}');
        setState(() {
          _selectedFileName = result.files.single.name;
          _selectedFileBytes = result.files.single.bytes;
          
          // Only try to access file path on non-web platforms
          if (!kIsWeb) {
            try {
              if (result.files.single.path != null) {
                _selectedFile = File(result.files.single.path!);
              }
            } catch (e) {
              _selectedFile = null;
            }
          } else {
            _selectedFile = null; // Web doesn't support file paths
          }
        });
        _dlog('After setState: _selectedFileName=${_selectedFileName ?? 'null'}, hasBytes=${_selectedFileBytes?.isNotEmpty ?? false}, filePath=${_selectedFile?.path ?? 'null'}');

        // Show file selected confirmation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File selected: $_selectedFileName'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _dlog('Error selecting file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _performFileUpload() async {
    if (_selectedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No file selected'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _uploadingFile = true;
    });

    try {
      // Get assignment details for upload
      if (_classIdEff == null || _subjectIdEff == null) {
        _dlog('IDs missing at upload time; attempting resolver now...');
        await _ensureIdentifiers();
      }
      if (_classIdEff == null || _subjectIdEff == null) {
        _dlog('Cannot upload: classId=${_classIdEff?.toString() ?? 'null'}, subjectId=${_subjectIdEff?.toString() ?? 'null'}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Missing class/subject identifiers. Cannot upload.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final classId = _classIdEff!;
      final subjectId = _subjectIdEff!;
      final assignmentNumber = _nextAssignmentNumber ?? 1;

      _dlog('Preparing upload. classId=$classId, subjectId=$subjectId, assignmentNumber=$assignmentNumber');
      _dlog('Selected file state before upload: name=${_selectedFileName ?? 'null'}, hasBytes=${_selectedFileBytes?.isNotEmpty ?? false}, filePath=${_selectedFile?.path ?? 'null'}');

      Map<String, dynamic> result;
      
      // Use bytes for web, file path for mobile/desktop
      if (_selectedFileBytes != null) {
        // Web platform - use bytes
        _dlog('Uploading via bytes API');
        result = await ApiService.submitAssignmentBytes(
          classId: classId,
          subjectId: subjectId,
          assignmentNumber: assignmentNumber,
          fileName: _selectedFileName!,
          fileBytes: _selectedFileBytes!,
        );
      } else if (_selectedFile != null) {
        // Mobile/Desktop platform - use file path
        _dlog('Uploading via file path API');
        result = await ApiService.submitAssignmentFile(
          classId: classId,
          subjectId: subjectId,
          assignmentNumber: assignmentNumber,
          filePath: _selectedFile!.path,
        );
      } else {
        _dlog('Upload aborted: no file data available');
        throw Exception('No file data available');
      }

      _dlog('Upload response: $result');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Assignment uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Clear selected file after successful upload
      setState(() {
        _selectedFile = null;
        _selectedFileName = null;
        _selectedFileBytes = null;
      });

    } catch (e) {
      _dlog('Upload failed with error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingFile = false;
        });
      }
    }
  }

  Future<void> _openLectureLink(String url) async {
    if (url.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No lecture link available.')),
        );
      }
      return;
    }
    
    try {
      final uri = Uri.parse(url.trim());
      if (!await canLaunchUrl(uri)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open lecture link: $url')),
          );
        }
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open lecture link: ${e.toString()}')),
        );
      }
    }
  }

  // ignore: unused_element
  Future<int?> _promptForAssignmentNumber({int? initial}) async {
    final numberCtrl = TextEditingController(text: (initial ?? '').toString());
    return showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B1222),
          title: Text('Finalize Assignment Number', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: numberCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Assignment Number',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
              onPressed: () {
                final n = int.tryParse(numberCtrl.text.trim());
                if (n == null || n <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid assignment number.')));
                  return;
                }
                Navigator.pop(context, n);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _markAssignmentTaken() async {
    if (!widget.isAdmin) return;
    // Use the finalized next assignment number from the dialog
    final number = _nextAssignmentNumber;
    if (number == null || number <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set assignment link, deadline, and number first.')));
      }
      return;
    }

    final now = DateTime.now();
    try {
      final res = await ApiService.saveCourseSummary(
        classId: widget.classId,
        subjectId: widget.subjectId,
        level: widget.level,
        className: widget.classId == null ? widget.className : null,
        subjectName: widget.subjectId == null ? widget.subjectName : null,
        todayTopics: _todayTopicsCtrl.text.trim().isEmpty ? null : _todayTopicsCtrl.text.trim(),
        reviseTopics: _reviseTopicsCtrl.text.trim().isEmpty ? null : _reviseTopicsCtrl.text.trim(),
        upcomingLectureAt: _upcomingLectureAt,
        nextQuizAt: _nextQuizAt,
        nextAssignmentUrl: (_nextAssignmentLink == null || _nextAssignmentLink!.trim().isEmpty)
            ? null
            : _nextAssignmentLink!.trim(),
        nextAssignmentDeadline: _nextAssignmentDeadline,
        totalLectures: _totalLectures,
        lecturesJson: _lectures.isEmpty ? null : jsonEncode(_lectures),
        lastAssignmentTakenAt: _toMysql(now),
        lastAssignmentNumber: number,
      );
      if (res['success'] == true) {
        setState(() {
          _lastAssignmentTakenAt = _toMysql(now);
          _lastAssignmentNumber = number;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked assignment as taken.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to mark: ${e.toString()}')));
      }
    }
  }

  Future<void> _openAssignmentLink() async {
    final url = _nextAssignmentLink?.trim();
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No assignment link available.')),
        );
      }
      return;
    }
    try {
      final uri = Uri.parse(url);
      if (!await canLaunchUrl(uri)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open link: $url')),
          );
        }
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open link: ${e.toString()}')),
        );
      }
    }
  }

  void _setupAssignmentReminders() {
    if (!widget.isAdmin) return;
    for (final t in _assignmentTimers) {
      t.cancel();
    }
    _assignmentTimers.clear();

    final deadline = _parseMysql(_nextAssignmentDeadline);
    if (deadline == null) return;
    final now = DateTime.now();
    final intervals = <Duration>[
      const Duration(hours: 24),
      const Duration(hours: 12),
      const Duration(hours: 1),
      const Duration(minutes: 15),
      const Duration(minutes: 2),
    ];
    for (final d in intervals) {
      final triggerAt = deadline.subtract(d);
      if (triggerAt.isAfter(now)) {
        final delay = triggerAt.difference(now);
        _assignmentTimers.add(Timer(delay, () {
          if (!mounted) return;
          final mins = d.inMinutes;
          String label;
          if (d.inHours >= 1) {
            label = '${d.inHours}h';
          } else {
            label = '${mins}m';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reminder: Assignment deadline in $label')),
          );
        }));
      }
    }
  }

  Future<Map<String, dynamic>?> _promptForAssignmentLinkAndDeadline(BuildContext context) async {
    final linkCtrl = TextEditingController(text: _nextAssignmentLink ?? '');
    final numberCtrl = TextEditingController(text: _nextAssignmentNumber?.toString() ?? '');
    // DateTime? pickedDt; // removed unused variable
    String? mysqlDeadline = _nextAssignmentDeadline?.isNotEmpty == true ? _nextAssignmentDeadline : null;
    String displayDeadline = '';
    if (_nextAssignmentDeadline != null && _nextAssignmentDeadline!.isNotEmpty) {
      displayDeadline = _displayFromMysql(_nextAssignmentDeadline!);
    }
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const surface = Color(0xFFFAFAF7);
        const lightCard = Colors.white;
        const lightBorder = Color(0xFFE5E7EB);
        final titleColor = isLight ? primaryBlue : Colors.white;
        final bodyColor = isLight ? primaryBlue : Colors.white;
        final secondaryColor = isLight ? const Color(0xFF374151) : Colors.white.withValues(alpha: 0.7);

        OutlineInputBorder buildBorder(Color color) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color),
            );

        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: isLight ? surface : const Color(0xFF0B1222),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Assignment Link', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: linkCtrl,
                      style: TextStyle(color: bodyColor),
                      decoration: InputDecoration(
                        hintText: 'https://... ',
                        hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
                        filled: true,
                        fillColor: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
                        enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                        focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                      ),
                      keyboardType: TextInputType.url,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    Text('Assignment Number', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: numberCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: bodyColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. 1',
                          hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
                          filled: true,
                          fillColor: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
                          enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                          focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Assignment Deadline', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              displayDeadline.isEmpty ? 'Pick date & time' : displayDeadline,
                              style: GoogleFonts.inter(color: secondaryColor),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await _pickDateTime((dt, formatted) {
                              mysqlDeadline = _toMysql(dt);
                              setLocal(() => displayDeadline = formatted);
                            });
                          },
                          icon: const Icon(Icons.event),
                          label: const Text('Pick'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: isLight ? primaryBlue : Colors.white,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () {
                    final link = linkCtrl.text.trim();
                    final n = int.tryParse(numberCtrl.text.trim());
                    if (n == null || n <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid assignment number.')));
                      return;
                    }
                    Navigator.pop(context, {
                      'link': link.isEmpty ? null : link,
                      'deadline': mysqlDeadline,
                      'number': n,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openMarksDialog(String kind) async {
    if (!widget.isAdmin) return;

    // Require class name to fetch roster
    if ((widget.className ?? '').isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Class is not set for this course.')),
        );
      }
      return;
    }

    // Load real roster
    List<Map<String, dynamic>> students = [];
    try {
      final roster = await ApiService.getStudentsInClass(widget.className!);
      students = roster
          .map((e) => {
                'id': e['user_id'] ?? e['id'] ?? e['student_user_id'],
                'roll': (e['roll_number'] ?? e['roll_no'] ?? '').toString(),
                'name': (e['name'] ?? e['student_name'] ?? 'Student').toString(),
                'marks': '',
              })
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load students: ${e.toString()}')),
        );
      }
      return;
    }

    final totalCtrl = TextEditingController(text: '100');
    final numberCtrl = TextEditingController(text: '1');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const surface = Color(0xFFFAFAF7);
        const lightCard = Colors.white;
        const lightBorder = Color(0xFFE5E7EB);
        final titleColor = isLight ? primaryBlue : Colors.white;
        final bodyColor = isLight ? primaryBlue : Colors.white;
        final secondaryColor = isLight ? primaryBlue : Colors.white.withValues(alpha: 0.75);
        final fieldFillColor = isLight ? primaryBlue.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.05);

        OutlineInputBorder buildBorder(Color color) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color),
            );

        Color accentColor(String kind) => kind == 'Quiz' ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

        return StatefulBuilder(
          builder: (context, setLocal) {
            // Compute a responsive content height to avoid bottom overflow
            final vh = MediaQuery.of(context).size.height;
            double contentHeight = vh * 0.7; // target 70% of viewport height
            if (contentHeight < 420) contentHeight = 420;
            if (contentHeight > 560) contentHeight = 560;

            return AlertDialog(
              backgroundColor: isLight ? surface : const Color(0xFF0B1222),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor(kind).withValues(alpha: isLight ? 0.12 : 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accentColor(kind)),
                    ),
                    child: Text(
                      '$kind Marks',
                      style: GoogleFonts.inter(
                        color: accentColor(kind),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Enter $kind marks for students',
                      style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 640,
                height: contentHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quiz/Assignment Number input
                    Row(
                      children: [
                        Text('$kind Number', style: GoogleFonts.inter(color: secondaryColor, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: numberCtrl,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: bodyColor),
                            decoration: InputDecoration(
                              hintText: 'e.g. 1',
                              hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
                              filled: true,
                              fillColor: fieldFillColor,
                              enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                              focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Total Marks', style: GoogleFonts.inter(color: secondaryColor, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: totalCtrl,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: bodyColor),
                            decoration: InputDecoration(
                              hintText: 'e.g. 100',
                              hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
                              filled: true,
                              fillColor: fieldFillColor,
                              enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                              focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                            ),
                            onChanged: (_) => setLocal(() {}),
                          ),
                        ),
                        const Spacer(),
                        Text('Students', style: GoogleFonts.inter(color: secondaryColor.withOpacity(0.85), fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: students.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final s = students[index];
                          final marksCtrl = TextEditingController(text: s['marks']);
                          Future<void> onCheck() async {
                            final number = int.tryParse(numberCtrl.text.trim());
                            if (number == null || number <= 0) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Enter a valid number first.')),
                                );
                              }
                              return;
                            }
                            if (_classIdEff == null || _subjectIdEff == null) {
                              // Try to resolve quickly
                              await _ensureIdentifiers();
                            }
                            if (_classIdEff == null || _subjectIdEff == null) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Class/Subject IDs are missing.')),
                                );
                              }
                              return;
                            }
                            try {
                              final list = await ApiService.getAssignmentSubmissions(
                                classId: _classIdEff,
                                subjectId: _subjectIdEff,
                                assignmentNumber: number,
                              );
                              final sid = (s['id'] is int) ? s['id'] as int : int.tryParse((s['id'] ?? '').toString());
                              final mine = list.where((e) => (e['student_id']?.toString() ?? '') == (sid?.toString() ?? '')).toList();
                              if (mine.isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('No submission found for ${s['name']}')),
                                  );
                                }
                                return;
                              }
                              final sub = mine.first;
                              final type = (sub['submission_type'] ?? '').toString();
                              final fileName = (sub['file_name'] ?? '').toString();
                              if (context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) {
                                    final innerTheme = Theme.of(context);
                                    final innerIsLight = innerTheme.brightness == Brightness.light;
                                    final innerTitle = innerIsLight ? primaryBlue : Colors.white;
                                    final innerBody = innerIsLight ? primaryBlue : Colors.white70;
                                    return AlertDialog(
                                      backgroundColor: innerIsLight ? surface : const Color(0xFF0B1222),
                                      surfaceTintColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                      title: Text('Submission Found', style: GoogleFonts.inter(color: innerTitle, fontWeight: FontWeight.w700)),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Student: ${s['name']}', style: GoogleFonts.inter(color: innerBody)),
                                          const SizedBox(height: 6),
                                          Text('Type: $type', style: GoogleFonts.inter(color: innerBody)),
                                          const SizedBox(height: 6),
                                          Text('Value: $fileName', style: GoogleFonts.inter(color: innerBody), maxLines: 2, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                      actions: [
                                        if (type == 'link')
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              _openLectureLink(fileName);
                                            },
                                            style: TextButton.styleFrom(foregroundColor: innerIsLight ? primaryBlue : Colors.white),
                                            child: const Text('Open Link'),
                                          ),
                                        if (type == 'file')
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              final subId = sub['id']?.toString();
                                              if (subId != null && subId.isNotEmpty) {
                                                final url = '${ApiService.baseUrl}?endpoint=download_assignment&submission_id=$subId';
                                                _openLectureLink(url);
                                              }
                                            },
                                            style: TextButton.styleFrom(foregroundColor: innerIsLight ? primaryBlue : Colors.white),
                                            child: const Text('Open'),
                                          ),
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(),
                                          style: TextButton.styleFrom(foregroundColor: innerIsLight ? primaryBlue : Colors.white),
                                          child: const Text('Close'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Check failed: ${e.toString()}')),
                                );
                              }
                            }
                          }
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isLight ? lightCard : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isLight ? primaryBlue.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(s['roll'], style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(s['name'], style: GoogleFonts.inter(color: bodyColor, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 12),
                                if (kind != 'Quiz') ...[
                                  SizedBox(
                                    height: 36,
                                    child: OutlinedButton.icon(
                                      onPressed: onCheck,
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: isLight ? primaryBlue.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.2)),
                                        foregroundColor: isLight ? primaryBlue : Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                      ),
                                      icon: const Icon(Icons.search, size: 16),
                                      label: const Text('Check', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ] else
                                  const SizedBox(width: 12),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: marksCtrl,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: bodyColor),
                                    decoration: InputDecoration(
                                      labelText: 'Marks',
                                      labelStyle: TextStyle(color: secondaryColor.withOpacity(0.7)),
                                      suffixText: '/${totalCtrl.text}',
                                      suffixStyle: TextStyle(color: secondaryColor.withOpacity(0.7)),
                                      filled: true,
                                      fillColor: fieldFillColor,
                                      enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                                      focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                                    ),
                                    onChanged: (v) => s['marks'] = v,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: isLight ? primaryBlue : Colors.white,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor(kind),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () async {
                    final total = int.tryParse(totalCtrl.text.trim());
                    final number = int.tryParse(numberCtrl.text.trim());
                    if (total == null || total <= 0 || number == null || number <= 0) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter valid total and number.')),
                        );
                      }
                      return;
                    }
                    // Build entries
                    final entries = <Map<String, dynamic>>[];
                    for (final s in students) {
                      final raw = (s['marks'] ?? '').toString().trim();
                      if (raw.isEmpty) continue; // skip empty inputs
                      final obtained = double.tryParse(raw);
                      if (obtained == null) continue;
                      final sidRaw = s['id'];
                      int? sid;
                      if (sidRaw is int) {
                        sid = sidRaw;
                      } else if (sidRaw is String) sid = int.tryParse(sidRaw);
                      if (sid == null) continue;
                      final capped = obtained > total ? total.toDouble() : obtained;
                      entries.add({'student_user_id': sid, 'obtained_marks': capped});
                    }
                    if (entries.isEmpty) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter at least one mark.')),
                        );
                      }
                      return;
                    }
                    try {
                      final res = await ApiService.upsertStudentMarks(
                        className: widget.className,
                        subjectName: widget.subjectName,
                        level: widget.level,
                        kind: kind.toLowerCase(),
                        number: number,
                        totalMarks: total,
                        entries: entries,
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (res['success'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$kind #$number saved for ${entries.length} students.')),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to save: ${res['error'] ?? 'Unknown error'}')),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Save failed: ${e.toString()}')),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF1E3A8A);
    final bool isMobile = ResponsiveHelper.isMobile(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isMobile
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(64.0),
              child: Container(
                height: 64,
                width: double.infinity,
                color: primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const StudentDashboard()),
                        );
                      },
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Course Details',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                _buildBackHeader(context),
                const SizedBox(height: 20),
              ],
              // Course Information and Grades Section
              _buildCourseHeader(),
            const SizedBox(height: 30),

            // Diary Box (above class details)
            _buildDiaryBox(),
            const SizedBox(height: 30),

            // Attendance Box (students only)
            if (!widget.isAdmin) ...[
              _buildAttendanceBox(),
              const SizedBox(height: 30),
            ],

              // Upcoming Events Section
              _buildUpcomingEvents(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _todayTopicsCtrl.dispose();
    _reviseTopicsCtrl.dispose();
    for (final t in _assignmentTimers) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _loadSummary() async {
    // Need either IDs or names to fetch meta; if not available, skip
    if ((widget.classId == null || widget.subjectId == null) &&
        ((widget.className == null || widget.className!.isEmpty) ||
         (widget.subjectName == null || widget.subjectName!.isEmpty))) {
      return;
    }
    setState(() { _loadingSummary = true; });
    try {
      final meta = await ApiService.getCourseSummary(
        classId: widget.classId,
        subjectId: widget.subjectId,
        level: widget.level, // pass level for names path (backend requires it with class/subject names)
        className: widget.classId == null ? widget.className : null,
        subjectName: widget.subjectId == null ? widget.subjectName : null,
      );
      if (meta != null) {
        _todayTopicsCtrl.text = (meta['today_topics'] ?? '') as String;
        _reviseTopicsCtrl.text = (meta['revise_topics'] ?? '') as String;
        // Load meta extras
        _upcomingLectureAt = (meta['upcoming_lecture_at'] ?? '') as String;
        _nextQuizAt = (meta['next_quiz_at'] ?? '') as String;
        _nextQuizTopic = (meta['next_quiz_topic'] ?? '') as String;
        _nextAssignmentLink = (meta['next_assignment_url'] ?? '') as String;
        _nextAssignmentDeadline = (meta['next_assignment_deadline'] ?? '') as String;
        _lastQuizTakenAt = (meta['last_quiz_taken_at'] ?? '') as String;
        final lqn = meta['last_quiz_number'];
        _lastQuizNumber = lqn == null ? null : int.tryParse(lqn.toString());
        _lastAssignmentTakenAt = (meta['last_assignment_taken_at'] ?? '') as String;
        final lan = meta['last_assignment_number'];
        _lastAssignmentNumber = lan == null ? null : int.tryParse(lan.toString());
        final nan = meta['next_assignment_number'];
        _nextAssignmentNumber = nan == null ? null : int.tryParse(nan.toString());
        _totalLectures = int.tryParse((meta['total_lectures'] ?? '0').toString()) ?? 0;
        final lj = meta['lectures_json'];
        
        // Debug logging for data loading
        print('[DEBUG] Loading lecture data from database:');
        print('[DEBUG] Total lectures from DB: $_totalLectures');
        print('[DEBUG] Lectures JSON from DB: $lj');
        
        if (lj is String && lj.isNotEmpty) {
          try {
            final parsed = json.decode(lj);
            if (parsed is List) {
              _lectures
                ..clear()
                ..addAll(parsed.map<Map<String, String>>((e) => {
                      'number': (e['number'] ?? '').toString(),
                      'name': (e['name'] ?? '').toString(),
                      'link': (e['link'] ?? '').toString(),
                    }));
              print('[DEBUG] Loaded ${_lectures.length} lectures from database');
              print('[DEBUG] Lectures with links: ${_getAvailableLecturesCount()}');
            }
          } catch (e) {
            print('[DEBUG] Error parsing lectures JSON: $e');
          }
        } else {
          print('[DEBUG] No lectures JSON data found in database');
        }
        // Prepare display strings from MySQL datetimes
        if (_upcomingLectureAt != null && _upcomingLectureAt!.isNotEmpty) {
          _upcomingLectureDateTime = _displayFromMysql(_upcomingLectureAt!);
        }
        if (_nextQuizAt != null && _nextQuizAt!.isNotEmpty) {
          _nextQuizDateTime = _displayFromMysql(_nextQuizAt!);
        }
        // Track last summary update time and set initial editing state
        final updatedAtStr = (meta['updated_at'] ?? '') as String;
        _lastSummaryUpdatedAt = _parseMysql(updatedAtStr);
        // If no previous entry, allow editing by default; otherwise locked until Edit
        _editingEnabled = _lastSummaryUpdatedAt == null;
        // Set up in-app reminders for assignment deadline (admin only)
        _setupAssignmentReminders();
      }
    } catch (_) {
      // ignore errors silently for now; UI remains editable
    } finally {
      if (mounted) setState(() { _loadingSummary = false; });
    }
  }

  Future<void> _saveSummary() async {
    if (!widget.isAdmin) return;
    try {
      // Debug logging
      print('[DEBUG] Saving lecture data to database:');
      print('[DEBUG] Total lectures: $_totalLectures');
      print('[DEBUG] Lectures count: ${_lectures.length}');
      print('[DEBUG] Lectures data: $_lectures');
      print('[DEBUG] Lectures JSON: ${_lectures.isEmpty ? 'null' : jsonEncode(_lectures)}');
      
      final res = await ApiService.saveCourseSummary(
        classId: widget.classId,
        subjectId: widget.subjectId,
        level: widget.level, // ensure backend can resolve when using names
        className: widget.classId == null ? widget.className : null,
        subjectName: widget.subjectId == null ? widget.subjectName : null,
        todayTopics: _todayTopicsCtrl.text.trim().isEmpty ? null : _todayTopicsCtrl.text.trim(),
        reviseTopics: _reviseTopicsCtrl.text.trim().isEmpty ? null : _reviseTopicsCtrl.text.trim(),
        upcomingLectureAt: _upcomingLectureAt,
        nextQuizAt: _nextQuizAt,
        nextQuizTopic: (_nextQuizTopic == null || _nextQuizTopic!.trim().isEmpty) ? null : _nextQuizTopic!.trim(),
        nextAssignmentUrl: _nextAssignmentLink,
        totalLectures: _totalLectures,
        lecturesJson: _lectures.isEmpty ? null : jsonEncode(_lectures),
      );
      if (res['success'] == true) {
        print('[DEBUG] Database save successful: $res');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Summary saved')),
          );
        }
        setState(() {
          _lastSummaryUpdatedAt = DateTime.now();
          _editingEnabled = false; // lock again after save
        });
      } else {
        print('[DEBUG] Database save failed: $res');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _saveSummaryWithDeadline() async {
    if (!widget.isAdmin) return;
    try {
      final res = await ApiService.saveCourseSummary(
        classId: widget.classId,
        subjectId: widget.subjectId,
        level: widget.level,
        className: widget.classId == null ? widget.className : null,
        subjectName: widget.subjectId == null ? widget.subjectName : null,
        todayTopics: _todayTopicsCtrl.text.trim().isEmpty ? null : _todayTopicsCtrl.text.trim(),
        reviseTopics: _reviseTopicsCtrl.text.trim().isEmpty ? null : _reviseTopicsCtrl.text.trim(),
        upcomingLectureAt: _upcomingLectureAt,
        nextQuizAt: _nextQuizAt,
        nextQuizTopic: (_nextQuizTopic == null || _nextQuizTopic!.trim().isEmpty) ? null : _nextQuizTopic!.trim(),
        nextAssignmentUrl: _nextAssignmentLink,
        nextAssignmentDeadline: _nextAssignmentDeadline,
        nextAssignmentNumber: _nextAssignmentNumber,
        totalLectures: _totalLectures,
        lecturesJson: _lectures.isEmpty ? null : jsonEncode(_lectures),
      );
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Assignment link and deadline saved')),
          );
        }
        _setupAssignmentReminders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${e.toString()}')),
        );
      }
    }
  }

  // Helpers
  Future<void> _pickDateTime(void Function(DateTime dt, String formatted) onPicked) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      builder: (context, child) {
        final lightScheme = const ColorScheme.light(
          primary: Color(0xFF1E3A8A),
          secondary: Color(0xFF1E3A8A),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          surface: Color(0xFFFAFAF7),
          onSurface: Color(0xFF1E3A8A),
        );
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: lightScheme,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: lightScheme.primary),
            ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
      builder: (context, child) {
        final lightScheme = const ColorScheme.light(
          primary: Color(0xFF1E3A8A),
          secondary: Color(0xFF1E3A8A),
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          surface: Color(0xFFFAFAF7),
          onSurface: Color(0xFF1E3A8A),
        );
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: lightScheme,
            timePickerTheme: const TimePickerThemeData(
              helpTextStyle: TextStyle(color: Color(0xFF1E3A8A)),
              backgroundColor: Colors.white,
              dialHandColor: Color(0xFF1E3A8A),
              dialBackgroundColor: Color(0xFFFAFAF7),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: lightScheme.primary),
            ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final formatted = _formatDateTime(dt);
    onPicked(dt, formatted);
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final yy = two(dt.year % 100);
    final mm = two(dt.month);
    final dd = two(dt.day);
    int hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = two(dt.minute);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$dd/$mm/$yy, ${two(hour)}:$min $ampm';
  }

  String _toMysql(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:00';
  }

  String _displayFromMysql(String mysql) {
    try {
      final dt = DateTime.parse(mysql.replaceFirst(' ', 'T'));
      return _formatDateTime(dt);
    } catch (_) {
      return mysql;
    }
  }

  DateTime? _parseMysql(String? mysql) {
    if (mysql == null || mysql.isEmpty) return null;
    try {
      return DateTime.parse(mysql.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }

  Future<void> _markQuizTaken() async {
    if (!widget.isAdmin) return;
    // No popup: decide quiz number automatically
    final int picked = _plannedQuizNumber ?? (_lastQuizNumber != null ? _lastQuizNumber! + 1 : 1);
    final now = DateTime.now();
    try {
      final res = await ApiService.saveCourseSummary(
        classId: widget.classId,
        subjectId: widget.subjectId,
        level: widget.level,
        className: widget.classId == null ? widget.className : null,
        subjectName: widget.subjectId == null ? widget.subjectName : null,
        todayTopics: _todayTopicsCtrl.text.trim(),
        reviseTopics: _reviseTopicsCtrl.text.trim(),
        upcomingLectureAt: _upcomingLectureAt,
        nextQuizAt: _nextQuizAt,
        nextAssignmentUrl: _nextAssignmentLink,
        nextAssignmentDeadline: _nextAssignmentDeadline,
        totalLectures: _totalLectures,
        lecturesJson: _lectures.isEmpty ? null : jsonEncode(_lectures),
        lastQuizTakenAt: _toMysql(now),
        lastQuizNumber: picked,
      );
      if (res['success'] == true) {
        setState(() {
          _lastQuizTakenAt = _toMysql(now);
          _lastQuizNumber = picked;
          _plannedQuizNumber = null; // clear planned number after marking
        });
        // No popup; a subtle toast is fine
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Marked quiz #$picked as taken.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to mark: ${e.toString()}')));
      }
    }
  }

  Future<String?> _promptForUrl(BuildContext context, {required String title}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const surface = Color(0xFFFAFAF7);
        const lightCard = Colors.white;
        const lightBorder = Color(0xFFE5E7EB);
        final titleColor = isLight ? primaryBlue : Colors.white;
        final bodyColor = isLight ? primaryBlue : Colors.white;
        final secondaryColor = isLight ? const Color(0xFF374151) : Colors.white.withValues(alpha: 0.7);

        OutlineInputBorder border(Color color) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color),
            );

        return AlertDialog(
          backgroundColor: isLight ? surface : const Color(0xFF0B1222),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: bodyColor),
            decoration: InputDecoration(
              hintText: 'https://... ',
              hintStyle: TextStyle(color: secondaryColor.withOpacity(0.6)),
              filled: true,
              fillColor: isLight ? lightCard : Colors.white.withValues(alpha: 0.05),
              enabledBorder: border(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
              focusedBorder: border(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: isLight ? primaryBlue : Colors.white,
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: () {
                final val = controller.text.trim();
                Navigator.pop(context, val.isEmpty ? null : val);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openLecturesManager() async {
    // Work on a temporary list then commit on Save
    List<Map<String, String>> tempLectures = _lectures.map((e) => {...e}).toList();
    int tempTotal = _totalLectures;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        const surface = Color(0xFFFAFAF7);
        const lightCard = Colors.white;
        const lightBorder = Color(0xFFE5E7EB);
        final titleColor = isLight ? primaryBlue : Colors.white;
        final bodyColor = isLight ? primaryBlue : Colors.white;
        final secondaryColor = isLight ? primaryBlue : Colors.white.withValues(alpha: 0.75);
        final fieldFillColor = isLight ? primaryBlue.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.05);

        OutlineInputBorder buildBorder(Color color) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color),
            );

        return StatefulBuilder(
          builder: (context, setLocal) {
            void ensureSize() {
              while (tempLectures.length < tempTotal) {
                final nextNum = (tempLectures.length + 1).toString();
                tempLectures.add({'number': nextNum, 'name': 'Lecture $nextNum', 'link': ''});
              }
              while (tempLectures.length > tempTotal && tempLectures.isNotEmpty) {
                tempLectures.removeLast();
              }
            }
            ensureSize();
            return AlertDialog(
              backgroundColor: isLight ? surface : const Color(0xFF0B1222),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Manage Lectures', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Total lectures control
                    Row(
                      children: [
                        Text('Total Lectures', style: GoogleFonts.inter(color: secondaryColor, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => setLocal(() { if (tempTotal > 0) tempTotal--; }),
                          icon: Icon(Icons.remove, color: bodyColor),
                        ),
                        Text('$tempTotal', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                        IconButton(
                          onPressed: () => setLocal(() { tempTotal++; }),
                          icon: Icon(Icons.add, color: bodyColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          itemCount: tempLectures.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final lec = tempLectures[index];
                            final nameController = TextEditingController(text: lec['name'] ?? '');
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isLight ? lightCard : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                children: [
                                  Text('#${lec['number']}', style: GoogleFonts.inter(color: titleColor, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: nameController,
                                      onChanged: (v) => lec['name'] = v,
                                      style: TextStyle(color: isLight ? primaryBlue : bodyColor),
                                      decoration: InputDecoration(
                                        labelText: 'Lecture name',
                                        suffixStyle: TextStyle(color: secondaryColor.withOpacity(0.7)),
                                      filled: true,
                                      fillColor: fieldFillColor,
                                        enabledBorder: buildBorder(isLight ? lightBorder : Colors.white.withValues(alpha: 0.2)),
                                        focusedBorder: buildBorder(isLight ? primaryBlue : const Color(0xFF8B5CF6)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  TextButton(
                                    onPressed: () async {
                                      final link = await _promptForUrl(context, title: 'Lecture ${lec['number']} Link');
                                      if (link != null) setLocal(() => lec['link'] = link);
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                                      textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                                    ),
                                    child: Text((lec['link'] ?? '').isEmpty ? 'Link' : 'Change'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: isLight ? primaryBlue : Colors.white,
                    textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Close'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isLight ? const Color(0xFF10B981) : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () async {
                    setState(() {
                      _totalLectures = tempTotal;
                      _lectures
                        ..clear()
                        ..addAll(tempLectures);
                    });
                    Navigator.pop(context);
                    // Save to database immediately after updating local state
                    print('[DEBUG] About to save lectures after dialog close');
                    await _saveSummary();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lectures saved: ${_getAvailableLecturesCount()} with links')),
                      );
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
  }

  Widget _buildBackHeader(BuildContext context) {
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final Color accent = widget.accentColor;
    final Color textColor = isLight
        ? Theme.of(context).colorScheme.onSurface
        : Colors.white;
    return Row(
      children: [
        GestureDetector(
          onTap: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isLight ? accent.withValues(alpha: 0.12) : accent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withValues(alpha: isLight ? 0.3 : 0.5),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.arrow_back,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          'Course Details',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildCourseHeader() {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final bool isMobile = ResponsiveHelper.isMobile(context);
    // Compute whether to show the "Mark Quiz Taken" button inline in the Next Quiz box
    final now = DateTime.now();
    final quizAt = _parseMysql(_nextQuizAt);
    final lastTakenAt = _parseMysql(_lastQuizTakenAt);
    final showTakenTop = widget.isAdmin && quizAt != null && (now.isAfter(quizAt) || now.isAtSameMomentAs(quizAt)) && (lastTakenAt == null || lastTakenAt.isBefore(quizAt));

    final upcomingBox = _buildInfoBox(
      value: (_upcomingLectureDateTime ?? (widget.isAdmin ? '—' : '00/00/00, 00:00 AM/PM')),
      label: widget.isAdmin ? 'Upcoming Lecture' : 'Next Class',
      color: const Color(0xFFEF4444),
      onTap: widget.isAdmin
          ? () => _pickDateTime((dt, v) async {
                setState(() {
                  _upcomingLectureDateTime = v;
                  _upcomingLectureAt = _toMysql(dt);
                });
                await _saveSummary();
              })
          : null,
    );

    final quizBox = _buildInfoBox(
      value: (_nextQuizDateTime ?? (widget.isAdmin ? '—' : '00/00/00, 00:00 AM/PM')),
      label: 'Quiz Details',
      color: const Color(0xFFF59E0B),
      onTap: widget.isAdmin ? _openQuizMenuOrDialog : null,
      extra: widget.isAdmin
          ? (showTakenTop
              ? SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton(
                    onPressed: _markQuizTaken,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Mark Quiz Taken'),
                  ),
                )
              : ((_lastQuizTakenAt != null && _lastQuizTakenAt!.isNotEmpty)
                  ? Text(
                      'Taken #${_lastQuizNumber ?? ''} on ${_displayFromMysql(_lastQuizTakenAt!)}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                    )
                  : null))
          : ((_nextQuizTopic != null && _nextQuizTopic!.isNotEmpty)
              ? Text(
                  _nextQuizTopic!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
                )
              : null),
    );

    final assignmentBox = _buildInfoBox(
      value: (_nextAssignmentDeadline != null && _nextAssignmentDeadline!.isNotEmpty)
          ? _displayFromMysql(_nextAssignmentDeadline!)
          : (widget.isAdmin ? '—' : '00/00/00, 00:00 AM/PM'),
      label: 'Next Assignment',
      color: const Color(0xFF10B981),
      onTap: widget.isAdmin
          ? () async {
              final hasCurrent = (_nextAssignmentDeadline != null && _nextAssignmentDeadline!.isNotEmpty) ||
                  (_nextAssignmentLink != null && _nextAssignmentLink!.isNotEmpty);
              if (!hasCurrent) {
                final res = await _promptForAssignmentLinkAndDeadline(context);
                if (res != null) {
                  setState(() {
                    _nextAssignmentLink = res['link'];
                    _nextAssignmentDeadline = res['deadline'];
                    _nextAssignmentNumber = res['number'] as int?;
                  });
                  await _saveSummaryWithDeadline();
                }
                return;
              }
              final choice = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF0B1222),
                  title: Text('Assignment Options', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('Edit Current Assignment'),
                        textColor: Colors.white,
                        onTap: () => Navigator.pop(context, 'edit'),
                      ),
                      ListTile(
                        title: const Text('Add Next Assignment'),
                        textColor: Colors.white,
                        onTap: () => Navigator.pop(context, 'next'),
                      ),
                    ],
                  ),
                ),
              );
              if (choice == null) return;
              if (choice == 'edit') {
                final res = await _promptForAssignmentLinkAndDeadline(context);
                if (res != null) {
                  setState(() {
                    _nextAssignmentLink = res['link'];
                    _nextAssignmentDeadline = res['deadline'];
                    _nextAssignmentNumber = res['number'] as int?;
                  });
                  await _saveSummaryWithDeadline();
                }
              } else if (choice == 'next') {
                final res = await _promptForAssignmentLinkAndDeadline(context);
                if (res != null) {
                  setState(() {
                    _nextAssignmentLink = res['link'];
                    _nextAssignmentDeadline = res['deadline'];
                    _nextAssignmentNumber = res['number'] as int?;
                  });
                  await _saveSummaryWithDeadline();
                }
              }
            }
          : null,
      extra: () {
        final now = DateTime.now();
        final assignAt = _parseMysql(_nextAssignmentDeadline);
        final lastAssignTaken = _parseMysql(_lastAssignmentTakenAt);
        final showMarkBtn = widget.isAdmin && assignAt != null && (now.isAfter(assignAt) || now.isAtSameMomentAs(assignAt)) && (lastAssignTaken == null || lastAssignTaken.isBefore(assignAt));

        String statusLine = '';
        if (_lastAssignmentTakenAt != null && _lastAssignmentTakenAt!.isNotEmpty) {
          final takenDisp = _displayFromMysql(_lastAssignmentTakenAt!);
          final numText = _lastAssignmentNumber != null ? '#$_lastAssignmentNumber' : '';
          statusLine = 'Taken $numText on $takenDisp';
        }

        if (!showMarkBtn && statusLine.isEmpty) return null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (statusLine.isNotEmpty)
              Text(
                statusLine,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
              ),
            if (showMarkBtn) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton(
                  onPressed: _markAssignmentTaken,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Mark Assignment Taken'),
                ),
              ),
            ],
          ],
        );
      }(),
    );

    final lecturesBox = _buildInfoBox(
      value: widget.isAdmin ? 'Lectures' : (_getAvailableLecturesCount().toString()),
      label: widget.isAdmin ? 'Manage' : 'Lectures',
      color: widget.accentColor,
      onTap: widget.isAdmin ? _openLecturesManager : _openStudentLecturesDialog,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isLight ? lightCard : null,
        gradient: isLight
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.accentColor.withValues(alpha: 0.2),
                  const Color(0xFFEC4899).withValues(alpha: 0.15),
                ],
              ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Course Title Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: isLight ? lightCard : widget.accentColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isLight ? primaryBlue : widget.accentColor, width: 2),
            ),
            child: Text(
              widget.courseTitle,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isLight ? primaryBlue : Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),

          // Teacher Information
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (widget.teacherName != null && widget.teacherName!.isNotEmpty)
                          ? widget.teacherName!
                          : 'Teacher Name',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isLight ? primaryBlue : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.className == null || (widget.className ?? '').isEmpty ? 'Class' : (widget.className ?? ''),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isLight
                            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEF4444), width: 2),
                ),
                child: const Icon(
                  Icons.sentiment_dissatisfied,
                  color: Color(0xFFEF4444),
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Four Info Boxes (repurposed as per requirement)
          Builder(
            builder: (context) {
              if (isMobile) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: upcomingBox),
                        const SizedBox(width: 8),
                        Expanded(child: quizBox),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: assignmentBox),
                        const SizedBox(width: 8),
                        Expanded(child: lecturesBox),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: upcomingBox),
                  const SizedBox(width: 8),
                  Expanded(child: quizBox),
                  const SizedBox(width: 8),
                  Expanded(child: assignmentBox),
                  const SizedBox(width: 8),
                  Expanded(child: lecturesBox),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox({
    required String value,
    required String label,
    required Color color,
    VoidCallback? onTap,
    Widget? extra,
  }) {
    final box = Container(
      height: extra != null ? 120 : 80,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          if (extra != null) ...[
            const SizedBox(height: 8),
            extra,
          ],
        ],
      ),
    );
    return onTap == null
        ? box
        : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: box);
  }

  Widget _buildAttendanceBox() {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isLight ? lightCard : const Color(0xFF10B981).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isLight ? lightBorder : const Color(0xFF10B981), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '📊 Attendance',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isLight ? primaryBlue : Colors.white,
                ),
              ),
              if (widget.isAdmin)
                TextButton(
                  onPressed: () {
                    if (widget.onOpenAttendance != null) {
                      widget.onOpenAttendance!();
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: isLight ? primaryBlue : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    'View All',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isLight ? primaryBlue : Colors.white,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 20),
          _buildAttendanceEntry(
            '00/00/0000, 00:00 AM/PM',
            'Subject Name',
            'Topic Name',
            true,
          ),
          const SizedBox(height: 16),
          _buildAttendanceEntry(
            '00/00/0000, 00:00 AM/PM',
            'Subject Name',
            'Topic Name',
            false,
          ),
        ],
      ),
    );
  }


  Widget _buildAttendanceEntry(
    String date,
    String className,
    String topic,
    bool isPresent,
  ) {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? lightCard : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isLight ? primaryBlue : Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  className,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isLight
                        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  topic,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isLight
                        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                        : Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  isPresent
                      ? (isLight
                          ? const Color(0xFF10B981).withValues(alpha: 0.18)
                          : const Color(0xFF10B981).withValues(alpha: 0.2))
                      : (isLight
                          ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                          : const Color(0xFFEF4444).withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    isPresent
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                width: 1,
              ),
            ),
            child: Text(
              isPresent ? 'Present' : 'Absent',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color:
                    isPresent
                        ? (isLight ? const Color(0xFF05603A) : const Color(0xFF10B981))
                        : (isLight ? const Color(0xFFB42318) : const Color(0xFFEF4444)),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDiaryBox() {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isLight ? lightCard : const Color(0xFFEC4899).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isLight ? lightBorder : const Color(0xFFEC4899), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📋 Summary',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isLight ? primaryBlue : Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          if (_loadingSummary)
            const Center(child: CircularProgressIndicator())
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLight ? lightCard : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Topics:',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isLight ? primaryBlue : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.isAdmin)
                    TextField(
                      controller: _todayTopicsCtrl,
                      minLines: 2,
                      maxLines: 6,
                      enabled: _editingEnabled,
                      readOnly: !_editingEnabled,
                      style: TextStyle(color: isLight ? Colors.black87 : Colors.white),
                      decoration: InputDecoration(
                        hintText: '• Topic Name 1\n• Topic Name 2',
                        hintStyle: TextStyle(color: isLight ? Colors.black54 : Colors.white.withValues(alpha: 0.6)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.2))),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: isLight ? primaryBlue : const Color(0xFF8B5CF6))),
                        disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.1))),
                      ),
                    )
                  else
                    Text(
                      _todayTopicsCtrl.text.isEmpty ? '—' : _todayTopicsCtrl.text,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isLight ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Revision:',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isLight ? primaryBlue : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.isAdmin)
                    TextField(
                      controller: _reviseTopicsCtrl,
                      minLines: 2,
                      maxLines: 6,
                      enabled: _editingEnabled,
                      readOnly: !_editingEnabled,
                      style: TextStyle(color: isLight ? Colors.black87 : Colors.white),
                      decoration: InputDecoration(
                        hintText: '• Review Topic 1\n• Review Topic 2',
                        hintStyle: TextStyle(color: isLight ? Colors.black54 : Colors.white.withValues(alpha: 0.6)),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.2))),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: isLight ? primaryBlue : const Color(0xFF8B5CF6))),
                        disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.1))),
                      ),
                    )
                  else
                    Text(
                      _reviseTopicsCtrl.text.isEmpty ? '—' : _reviseTopicsCtrl.text,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: isLight ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.9),
                        height: 1.4,
                      ),
                    ),
                  if (widget.isAdmin)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_lastSummaryUpdatedAt != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                _withinEditWindow
                                    ? 'Edit allowed until: ${_displayFromMysql(_toMysql(_lastSummaryUpdatedAt!.add(const Duration(hours: 12))))}'
                                    : 'Edit window expired (last updated: ${_displayFromMysql(_toMysql(_lastSummaryUpdatedAt!))})',
                                style: GoogleFonts.inter(color: isLight ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.7), fontSize: 12),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: !_editingEnabled && _withinEditWindow
                                    ? () {
                                        setState(() { _editingEnabled = true; });
                                      }
                                    : null,
                                icon: const Icon(Icons.edit),
                                label: const Text('Edit'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isLight ? primaryBlue : Colors.white,
                                  side: BorderSide(color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.3)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _editingEnabled ? _saveSummary : null,
                                icon: const Icon(Icons.save),
                                label: const Text('Save'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B5CF6),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }




  Widget _buildUpcomingEvents() {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final bool isMobile = ResponsiveHelper.isMobile(context);

    Widget buildCard({
      required IconData icon,
      required Color accent,
      required String title,
      required List<Widget> body,
      VoidCallback? onTap,
    }) {
      final card = Container(
        padding: EdgeInsets.all(isMobile ? 18 : 24),
        decoration: BoxDecoration(
          color: isLight ? lightCard : accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isLight ? lightBorder : accent.withValues(alpha: 0.45), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isLight ? 0.04 : 0.18),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: isMobile ? 20 : 22),
                ),
                SizedBox(width: isMobile ? 12 : 14),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: isLight ? primaryBlue : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isMobile ? 14 : 20),
            ...body,
          ],
        ),
      );

      if (onTap == null) return card;

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: card,
      );
    }

    final quizBody = <Widget>[
      Text(
        widget.isAdmin
            ? 'Chapter Name, Topic Name'
            : ((_nextQuizTopic != null && _nextQuizTopic!.isNotEmpty)
                ? _nextQuizTopic!
                : 'Chapter Name, Topic Name'),
        style: GoogleFonts.inter(
          fontSize: isMobile ? 14 : 16,
          color: isLight
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.9),
        ),
      ),
      if (!widget.isAdmin && _nextQuizAt != null && _nextQuizAt!.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          _displayFromMysql(_nextQuizAt!),
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isLight
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                : Colors.white70,
          ),
        ),
      ],
      if (widget.isAdmin) ...[
        SizedBox(height: isMobile ? 12 : 16),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: () => _openMarksDialog('Quiz'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Enter Quiz Marks'),
          ),
        ),
      ],
    ];

    final assignmentBody = <Widget>[
      Text(
        'Chapter Name, Topic Name',
        style: GoogleFonts.inter(
          fontSize: isMobile ? 14 : 16,
          color: isLight
              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.9),
        ),
      ),
      if (!widget.isAdmin && _nextAssignmentDeadline != null && _nextAssignmentDeadline!.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          _displayFromMysql(_nextAssignmentDeadline!),
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isLight
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                : Colors.white70,
          ),
        ),
      ],
      if (widget.isAdmin) ...[
        SizedBox(height: isMobile ? 12 : 16),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: () => _openMarksDialog('Assignment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Enter Assignment Marks'),
          ),
        ),
      ] else ...[
        SizedBox(height: isMobile ? 12 : 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showAssignmentOptionsDialog(context),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Submit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openStudentAssignmentDialog,
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('Details'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isLight ? primaryBlue : Colors.white,
                  side: BorderSide(color: isLight ? primaryBlue.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.35)),
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
        if (_nextAssignmentLink != null && _nextAssignmentLink!.isNotEmpty) ...[
          SizedBox(height: isMobile ? 10 : 14),
          ElevatedButton.icon(
            onPressed: () => _openLectureLink(_nextAssignmentLink!),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open Assignment Link'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 38),
            ),
          ),
        ],
      ],
    ];

    final quizTitle = widget.isAdmin ? 'Enter Quiz Marks' : 'Quiz Details';

    final assignmentTitle = widget.isAdmin
        ? 'Enter Assignment Marks'
        : '${_nextAssignmentNumber != null ? 'Assignment #$_nextAssignmentNumber' : 'Assignment'} '
            'Due '
            '${(_nextAssignmentDeadline != null && _nextAssignmentDeadline!.isNotEmpty) ? _displayFromMysql(_nextAssignmentDeadline!) : 'Not announced'}';

    final quizCard = buildCard(
      icon: Icons.quiz,
      accent: const Color(0xFF8B5CF6),
      title: quizTitle,
      body: quizBody,
      onTap: widget.isAdmin ? null : _openStudentQuizDialog,
    );

    final assignmentCard = buildCard(
      icon: Icons.assignment,
      accent: const Color(0xFF10B981),
      title: assignmentTitle,
      body: assignmentBody,
      onTap: widget.isAdmin ? null : () => _showAssignmentOptionsDialog(context),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          quizCard,
          const SizedBox(height: 16),
          assignmentCard,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: quizCard),
        const SizedBox(width: 20),
        Expanded(child: assignmentCard),
      ],
    );
  }

}
