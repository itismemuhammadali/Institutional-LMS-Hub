import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/vertical_nav_bar.dart';
import 'home.dart';

class TermAssessmentsScreen extends StatefulWidget {
  final int? classId;
  final int? subjectId;
  final String? className;
  final String? subjectName;

  const TermAssessmentsScreen({
    super.key,
    this.classId,
    this.subjectId,
    this.className,
    this.subjectName,
  });

  @override
  State<TermAssessmentsScreen> createState() => _TermAssessmentsScreenState();
}

class _TermAssessmentsScreenState extends State<TermAssessmentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final int _selectedNavIndex = 11; // Academic Records entry
  bool _isNavExpanded = false;

  final TextEditingController _totalMarksController = TextEditingController();
  final Map<int, TextEditingController> _markControllers = {};

  List<Map<String, dynamic>> _studentRows = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _loadData();
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _totalMarksController.dispose();
    for (final controller in _markControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _currentTerm => _tabController.index == 0 ? 'first' : 'final';

  String get _currentTermTitle => _currentTerm == 'first' ? 'First Term' : 'Final Term';

  Future<void> _loadData() async {
    if ((widget.className ?? '').isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Class information is required to load students.';
        _studentRows = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final roster = await _fetchRoster(widget.className!);
      final marks = await _fetchTermMarks();
      final merged = _mergeRosterWithMarks(roster, marks);
      _prepareControllers(merged, marks);
      setState(() {
        _studentRows = merged;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
        _studentRows = const [];
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRoster(String className) async {
    return ApiService.getStudentsInClass(className);
  }

  Future<List<Map<String, dynamic>>> _fetchTermMarks() {
    if (_currentTerm == 'first') {
      return ApiService.getStudentFirstTermMarks(classId: widget.classId);
    }
    return ApiService.getStudentFinalTermMarks(classId: widget.classId);
  }

  void _prepareControllers(
    List<Map<String, dynamic>> merged,
    List<Map<String, dynamic>> marks,
  ) {
    for (final controller in _markControllers.values) {
      controller.dispose();
    }
    _markControllers.clear();

    String? detectedTotal;
    if (_currentTerm == 'first') {
      detectedTotal = _initialTotalMarksValue(marks);
    } else {
      detectedTotal = _initialTotalMarksValue(marks);
    }
    _totalMarksController.text = detectedTotal ?? '100';

    for (final row in merged) {
      final id = _parseStudentId(row['student_user_id'] ?? row['user_id'] ?? row['id']);
      if (id == null) continue;
      final obtained = row['obtained_marks'];
      _markControllers[id] = TextEditingController(
        text: obtained == null ? '' : obtained.toString(),
      );
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

    merged.sort((a, b) {
      final rollA = (a['roll_number'] ?? a['roll_no'] ?? '').toString();
      final rollB = (b['roll_number'] ?? b['roll_no'] ?? '').toString();
      return rollA.compareTo(rollB);
    });

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

  Future<void> _saveMarks() async {
    final total = int.tryParse(_totalMarksController.text.trim());
    if (total == null || total <= 0) {
      _showSnack('Enter a valid total marks value.');
      return;
    }

    final entries = <Map<String, dynamic>>[];
    for (final row in _studentRows) {
      final id = _parseStudentId(row['student_user_id'] ?? row['user_id'] ?? row['id']);
      if (id == null) continue;
      final ctrl = _markControllers[id];
      if (ctrl == null) continue;
      final raw = ctrl.text.trim();
      if (raw.isEmpty) continue;
      final obtained = double.tryParse(raw);
      if (obtained == null) {
        _showSnack('Marks for ${row['name'] ?? 'student'} must be a number.');
        return;
      }
      entries.add({
        'student_user_id': id,
        'obtained_marks': obtained,
      });
    }

    if (entries.isEmpty) {
      _showSnack('Enter marks for at least one student.');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      Map<String, dynamic> response;
      if (_currentTerm == 'first') {
        response = await ApiService.upsertFirstTermMarks(
          classId: widget.classId,
          subjectId: widget.subjectId,
          className: widget.className,
          subjectName: widget.subjectName,
          totalMarks: total,
          entries: entries,
        );
      } else {
        response = await ApiService.upsertFinalTermMarks(
          classId: widget.classId,
          subjectId: widget.subjectId,
          className: widget.className,
          subjectName: widget.subjectName,
          totalMarks: total,
          entries: entries,
        );
      }

      if (response['success'] == true) {
        _showSnack('$_currentTermTitle marks saved for ${entries.length} students.');
        await _loadData();
      } else {
        final message = response['error'] ?? 'Failed to save marks.';
        _showSnack(message.toString());
      }
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);

    if (isMobile) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme: theme, isMobile: isMobile),
              if (_hasClassOrSubject)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 24,
                    vertical: 12,
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      if ((widget.className ?? '').isNotEmpty)
                        _buildInfoChip('Class: ${widget.className!}', theme),
                      if ((widget.subjectName ?? '').isNotEmpty)
                        _buildInfoChip('Subject: ${widget.subjectName!}', theme),
                    ],
                  ),
                ),
              Expanded(child: _buildMainCard(theme: theme, isMobile: isMobile)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VerticalNavBar(
              selectedIndex: _selectedNavIndex,
              onItemSelected: _handleNavSelection,
              isExpanded: _isNavExpanded,
              onToggleExpanded: (expanded) {
                setState(() => _isNavExpanded = expanded);
              },
              showAddStudent: false,
              showCourses: true,
              showCourseAssignment: false,
              showAdminDues: false,
              showStudentDues: true,
              showTakeAttendance: false,
              showGenerateTicket: false,
              showAcademicRecords: true,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme: theme, isMobile: false),
                  if (_hasClassOrSubject)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          if ((widget.className ?? '').isNotEmpty)
                            _buildInfoChip('Class: ${widget.className!}', theme),
                          if ((widget.subjectName ?? '').isNotEmpty)
                            _buildInfoChip('Subject: ${widget.subjectName!}', theme),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: _buildMainCard(theme: theme, isMobile: false),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildMainCard({required ThemeData theme, required bool isMobile}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        boxShadow: ResponsiveHelper.getElevation(context, level: 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 16 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_currentTermTitle Marks',
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: isMobile ? 160 : 180,
                      child: TextField(
                        controller: _totalMarksController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Total Marks',
                          hintText: 'e.g. 100',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_saving) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: _saveMarks,
                        icon: const Icon(Icons.save),
                        label: const Text('Save Marks'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 14, color: theme.colorScheme.error),
                          ),
                        ),
                      )
                    : _studentRows.isEmpty
                        ? Center(
                            child: Text(
                              'No students found for this class.',
                              style: GoogleFonts.inter(fontSize: 14),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              isMobile ? 16 : 24,
                              isMobile ? 12 : 16,
                              isMobile ? 16 : 24,
                              isMobile ? 20 : 28,
                            ),
                            itemBuilder: (context, index) {
                              final row = _studentRows[index];
                              final id = _parseStudentId(row['student_user_id'] ?? row['user_id'] ?? row['id']);
                              if (id == null) {
                                return const SizedBox.shrink();
                              }
                              final ctrl = _markControllers[id]!;
                              final name = (row['student_name'] ?? row['name'] ?? 'Student').toString();
                              final email = row['student_email'] ?? row['email'];
                              final roll = (row['roll_number'] ?? row['roll_no'] ?? '').toString();

                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                                ),
                                child: Row(
                                  children: [
                                    if (roll.isNotEmpty)
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          roll,
                                          style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    if (roll.isNotEmpty) const SizedBox(width: 16) else const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: theme.textTheme.bodyLarge?.color,
                                            ),
                                          ),
                                          if (email != null)
                                            Text(
                                              email.toString(),
                                              style: GoogleFonts.inter(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 110,
                                      child: TextField(
                                        controller: ctrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: InputDecoration(
                                          labelText: 'Marks',
                                          suffixText: '/${_totalMarksController.text}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemCount: _studentRows.length,
                          ),
          ),
        ],
      ),
    );
  }

  bool get _hasClassOrSubject => (widget.className ?? '').isNotEmpty || (widget.subjectName ?? '').isNotEmpty;

  Widget _buildInfoChip(String label, ThemeData theme) {
    return Chip(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      label: Text(
        label,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _buildHeader({required ThemeData theme, required bool isMobile}) {
    final isFirstTerm = _tabController.index == 0;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primary,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  final popped = await Navigator.of(context).maybePop();
                  if (!popped && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Term Assessments',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentTermTitle,
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: isMobile ? 13 : 14,
                      ),
                    ),
                  ],
                ),
              ),
              _HeaderTabButton(
                label: 'First Term',
                icon: Icons.assignment_outlined,
                selected: isFirstTerm,
                onTap: () => _tabController.animateTo(0),
              ),
              const SizedBox(width: 8),
              _HeaderTabButton(
                label: 'Finals',
                icon: Icons.emoji_events_outlined,
                selected: !isFirstTerm,
                onTap: () => _tabController.animateTo(1),
              ),
            ],
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
          color: selected ? Colors.white : Colors.white.withOpacity(0.12),
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
