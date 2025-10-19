import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
class TeacherAttendanceScreen extends StatefulWidget {
  const TeacherAttendanceScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _loadingStudents = false;
  bool _loadingClasses = false;
  bool _loadingHistory = false;
  bool _saving = false;
  String? _error;

  // Selected class display name (e.g., 'Class 4')
  String? _selectedClassName;

  // classes: simple list of display names (from assignments or static)
  List<String> _classes = [];

  // students: [{ id, name, roll_no, status }]
  List<Map<String, dynamic>> _students = [];

  // Teacher mode: list teachers instead of students for a class
  bool _teacherMode = false;
  bool _loadingTeachers = false;
  List<Map<String, dynamic>> _teachers = [];
  bool _isSuperAdmin = false;

  // previous history entries: [{ attendance_date, entries, present_count, ... }]
  List<Map<String, dynamic>> _history = [];

  final List<String> _statuses = const ['present', 'absent', 'leave'];
  final TextEditingController _remarksController = TextEditingController();

  // Accent palette similar to Courses screen
  final List<Color> _palette = const [
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFFEF4444),
  ];
  Color _colorFor(int i) => _palette[i % _palette.length];

  Widget _statusSelector({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    Widget buildBtn(String key, Color color) {
      final selected = value == key;
      return InkWell(
        onTap: () => onChanged(key),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? color : Colors.white.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                key[0].toUpperCase() + key.substring(1),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? const Color(0xFF1E3A8A) : const Color(0xFF1E3A8A).withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: selected ? color : Colors.white.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        buildBtn('present', const Color(0xFF10B981)),
        buildBtn('absent', const Color(0xFFEF4444)),
        buildBtn('leave', const Color(0xFFF59E0B)),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadClasses();
  }

  Future<void> _loadUserRole() async {
    try {
      final me = await ApiService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _isSuperAdmin = (me?['is_super_admin'] == 1 || me?['is_super_admin'] == '1');
      });
    } catch (_) {
      // ignore soft errors
    }
  }

  Widget _buildClassAttendancePane(bool isDark, Color onSurface) {
    return Column(
      children: [
        // Previous attendance history
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text('Previous attendance', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (_loadingHistory) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        SizedBox(
          height: 110,
          child: _history.isEmpty && !_loadingHistory
              ? Center(child: Text('No previous records', style: GoogleFonts.inter(color: onSurface.withValues(alpha: 0.7), fontSize: 12)))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final h = _history[index];
                    final date = (h['attendance_date'] ?? '').toString();
                    final present = (h['present_count'] ?? 0).toString();
                    final absent = (h['absent_count'] ?? 0).toString();
                    final leave = (h['leave_count'] ?? 0).toString();
                    return InkWell(
                      onTap: () => _loadAttendanceForDate(date),
                      child: Container(
                        width: 170,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(date, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text('P: $present  A: $absent  L: $leave', style: GoogleFonts.inter(fontSize: 12, color: onSurface.withValues(alpha: 0.8))),
                            const Spacer(),
                            Text('Tap to load', style: GoogleFonts.inter(fontSize: 11, color: onSurface.withValues(alpha: 0.7))),
                          ],
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemCount: _history.length,
                ),
        ),
        const SizedBox(height: 12),
        // Students pane
        Expanded(child: _buildStudentsPane(isDark, onSurface)),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final res = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (res != null) {
      setState(() => _selectedDate = res);
    }
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadClasses() async {
    setState(() {
      _loadingClasses = true;
      _error = null;
      _classes = [];
    });
    try {
      // Try to derive teacher's classes from assignments endpoint.
      // Fallback: show common classes if API doesn't include teacher filter.
      final assignments = await ApiService.getAssignments();
      final names = <String>{};
      for (final a in assignments) {
        final cname = (a['class_name'] ?? a['class'] ?? '').toString();
        if (cname.isNotEmpty) names.add(cname);
      }
      // If nothing came back, add a sensible default
      if (names.isEmpty) {
        names.addAll(['Class 4']);
      }
      setState(() => _classes = names.toList()..sort());
    } catch (e) {
      setState(() => _error = 'Failed to load classes: ${e.toString()}');
    } finally {
      setState(() => _loadingClasses = false);
    }
  }

  Future<void> _loadStudents(String className) async {
    setState(() {
      _selectedClassName = className;
      _loadingStudents = true;
      _error = null;
      _students = [];
    });
    try {
      final list = await ApiService.getStudentsInClass(className);
      setState(() {
        _students = list
            .map((e) => {
                  'id': e['user_id'] ?? e['id'] ?? e['student_user_id'],
                  'name': (e['name'] ?? e['student_name'] ?? 'Student').toString(),
                  'roll': (e['roll_number'] ?? e['roll_no'] ?? '').toString(),
                  'status': 'present',
                })
            .toList();
      });
      await _loadHistory();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loadingStudents = false);
    }
  }

  Future<void> _loadHistory() async {
    final cname = _selectedClassName;
    if (cname == null || cname.isEmpty) return;
    setState(() {
      _loadingHistory = true;
    });
    try {
      final hist = await ApiService.getClassAttendanceHistory(className: cname, limit: 30);
      setState(() => _history = hist);
    } catch (e) {
      // Don't block UI; show soft error
      setState(() => _error = 'Failed history: ${e.toString()}');
    } finally {
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadAttendanceForDate(String yyyyMmDd) async {
    final cname = _selectedClassName;
    if (cname == null) return;
    setState(() => _error = null);
    try {
      final entries = await ApiService.getClassAttendance(className: cname, date: yyyyMmDd);
      // Build a map student_user_id -> status
      final byId = <int, String>{};
      for (final e in entries) {
        final sid = e['student_user_id'];
        final st = (e['status'] ?? 'present').toString();
        if (sid is int) {
          byId[sid] = st;
        } else if (sid is String) {
          final p = int.tryParse(sid);
          if (p != null) {
            byId[p] = st;
          }
        }
      }
      setState(() {
        _selectedDate = DateTime.parse(yyyyMmDd);
        for (var i = 0; i < _students.length; i++) {
          final sid = _students[i]['id'];
          int? id;
          if (sid is int) {
            id = sid;
          } else if (sid is String) {
            id = int.tryParse(sid);
          }
          if (id != null && byId.containsKey(id)) {
            _students[i]['status'] = byId[id];
          }
        }
      });
    } catch (e) {
      setState(() => _error = 'Failed to load previous: ${e.toString()}');
    }
  }

  Future<void> _saveAttendance() async {
    // If in teacher mode, save teacher attendance here
    if (_teacherMode) {
      if (_teachers.isEmpty) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      final date = _fmt(_selectedDate);
      try {
        for (final t in _teachers) {
          final rawId = t['id'];
          final status = (t['status'] ?? 'present').toString();
          int? uid;
          if (rawId is int) {
            uid = rawId;
          } else if (rawId is String) {
            uid = int.tryParse(rawId);
          }
          if (uid != null) {
            await ApiService.upsertAttendanceRecord(userId: uid, date: date, status: status);
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Teachers attendance saved'), backgroundColor: Color(0xFF10B981)),
        );
      } catch (e) {
        setState(() => _error = 'Failed to save: ${e.toString()}');
      } finally {
        setState(() => _saving = false);
      }
      return;
    }

    if (_students.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final date = _fmt(_selectedDate);
    try {
      // Build batch entries
      final entries = <Map<String, dynamic>>[];
      for (final s in _students) {
        final rawId = s['id'];
        int? sid = rawId is int ? rawId : (rawId is String ? int.tryParse(rawId) : null);
        final status = (s['status'] ?? 'present').toString();
        if (sid != null) {
          entries.add({'student_user_id': sid, 'status': status});
        }
      }
      if (entries.isNotEmpty) {
        await ApiService.recordClassAttendance(className: _selectedClassName!, date: date, entries: entries);
      }
      // TODO: Persist remarks once backend endpoint is available (e.g., class_attendance remarks/diary)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance saved successfully'), backgroundColor: Color(0xFF10B981)),
      );
      await _loadHistory();
    } catch (e) {
      setState(() => _error = 'Failed to save: ${e.toString()}');
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    // If inside a sub-state (teacher mode or a selected class), exit that first
    if (_teacherMode || _selectedClassName != null) {
      setState(() {
        _teacherMode = false;
        _teachers = [];
        _selectedClassName = null;
        _students = [];
      });
      return false; // do not pop the route
    }
    return true; // allow route pop
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bool isWide = MediaQuery.of(context).size.width >= 768;

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: isWide
            ? AppBar(
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.transparent
                    : const Color(0xFF1E3A8A),
                elevation: 0,
                title: Text(
                  'Attendance',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.white,
                  ),
                ),
                // Only show back button on desktop devices (768px and above)
                leading: isWide
                    ? IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.white,
                        ),
                        onPressed: () async {
                          final allowPop = await _handleBack();
                          if (!mounted) return;
                          if (allowPop) {
                            if (widget.onBack != null) {
                              widget.onBack!.call();
                            } else if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                            }
                          }
                        },
                      )
                    : null,
                automaticallyImplyLeading: isWide,
              )
            : null,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month),
                      label: Text(_fmt(_selectedDate)),
                    ),
                    const SizedBox(width: 12),
                    if (_selectedClassName != null)
                      Chip(
                        label: Text(_selectedClassName!),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: () {
                          setState(() {
                            _selectedClassName = null;
                            _students = [];
                          });
                        },
                      ),
                    if (_teacherMode) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: const Text('Teachers'),
                        deleteIcon: const Icon(Icons.close),
                        onDeleted: () {
                          setState(() {
                            _teacherMode = false;
                            _teachers = [];
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(_error!, style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _selectedClassName == null && !_teacherMode
                    ? _buildClassesPane(onSurface)
                    : (_teacherMode
                        ? _buildTeachersPane(isDark, onSurface)
                        : _buildClassAttendancePane(isDark, onSurface)),
              ),
              const SizedBox(height: 10),
              if (_selectedClassName != null || _teacherMode) ...[
                Text('Remarks (topics taught, notes)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                TextField(
                  controller: _remarksController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g., Chapter 3: Fractions; 2 students were late',
                    hintStyle: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF60A5FA).withValues(alpha: 0.6)
                          : const Color(0xFF6B7280),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF1E3A8A),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF60A5FA).withValues(alpha: 0.5)
                            : const Color(0xFF1E3A8A).withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF1E3A8A),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                  ),
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: (_saving) ? null : _saveAttendance,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Attendance'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassesPane(Color onSurface) {
    if (_loadingClasses) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_classes.isEmpty && !_isSuperAdmin) {
      return Center(
        child: Text('No classes assigned', style: GoogleFonts.inter(color: onSurface.withValues(alpha: 0.8))),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final double spacing = constraints.maxWidth < 500 ? 8 : 12;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final int perRow = (() {
          final w = constraints.maxWidth;
          if (w < 420) return 2; // small phones
          if (w < 700) return 3; // large phones
          if (w < 1000) return 4; // tablets
          return 5; // desktop
        })();
        final double tileW = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;

        Widget buildTeachersTile() {
          const accent = Color(0xFF06B6D4);
          return SizedBox(
            width: tileW,
            child: InkWell(
              onTap: _loadingTeachers ? null : _enterTeacherMode,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFE7E0DE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.4) : const Color(0xFFD9D2D0),
                  ),
                  boxShadow: isDark
                      ? const []
                      : [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.groups, color: accent, size: 12),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Teachers Attendance',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF1E3A8A).withValues(alpha: 0.6),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget buildClassTile(String cname, int index) {
          final accent = _colorFor(index);
          return SizedBox(
            width: tileW,
            child: InkWell(
              onTap: _loadingStudents ? null : () => _loadStudents(cname),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFE7E0DE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.4) : const Color(0xFFD9D2D0),
                  ),
                  boxShadow: isDark
                      ? const []
                      : [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.book, color: accent, size: 12),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cname,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF1E3A8A).withValues(alpha: 0.6),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSuperAdmin) ...[
                Text(
                  'Teacher Attendance',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [buildTeachersTile()],
                ),
                const SizedBox(height: 20),
              ],
              Text(
                'Student Attendance',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                ),
              ),
              const SizedBox(height: 10),
              if (_classes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE7E0DE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFD9D2D0),
                    ),
                  ),
                  child: Text(
                    'No classes assigned',
                    style: GoogleFonts.inter(color: isDark ? Colors.white70 : const Color(0xFF1E3A8A).withValues(alpha: 0.75)),
                  ),
                )
              else
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (int i = 0; i < _classes.length; i++) buildClassTile(_classes[i], i),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _enterTeacherMode() async {
    setState(() {
      _teacherMode = true;
      _loadingTeachers = true;
      _error = null;
      _teachers = [];
      _selectedClassName = null; // ensure class mode off
    });
    try {
      final list = await ApiService.getTeachers();
      setState(() {
        _teachers = list
            .map((e) => {
                  'id': e['user_id'] ?? e['id'],
                  'name': (e['name'] ?? e['full_name'] ?? 'Teacher').toString(),
                  'status': 'present',
                })
            .toList();
      });
    } catch (e) {
      setState(() => _error = 'Failed to load teachers: ${e.toString()}');
    } finally {
      setState(() => _loadingTeachers = false);
    }
  }

  Widget _buildTeachersPane(bool isDark, Color onSurface) {
    if (_loadingTeachers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_teachers.isEmpty) {
      return Center(
        child: Text('No teachers found', style: GoogleFonts.inter(color: onSurface.withValues(alpha: 0.8))),
      );
    }
    return ListView.separated(
      itemCount: _teachers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final t = _teachers[index];
        final status = (t['status'] ?? 'present') as String;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE7E0DE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFD9D2D0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t['name']?.toString() ?? 'Teacher',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _statusSelector(
                    value: _statuses.contains(status) ? status : 'present',
                    onChanged: (v) => setState(() => _teachers[index]['status'] = v),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentsPane(bool isDark, Color onSurface) {
    if (_loadingStudents) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_students.isEmpty) {
      return Center(
        child: Text('No students found', style: GoogleFonts.inter(color: onSurface.withValues(alpha: 0.8))),
      );
    }
    return ListView.separated(
      itemCount: _students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = _students[index];
        final status = (s['status'] ?? 'present') as String;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE7E0DE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFD9D2D0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['name']?.toString() ?? 'Student',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if ((s['roll'] as String).isNotEmpty)
                      Text(
                        'Roll: ${s['roll']}',
                        style: GoogleFonts.inter(fontSize: 11, color: onSurface.withValues(alpha: 0.75)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _statusSelector(
                    value: _statuses.contains(status) ? status : 'present',
                    onChanged: (v) => setState(() => _students[index]['status'] = v),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
