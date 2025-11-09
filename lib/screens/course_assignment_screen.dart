import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'home.dart';

class CourseAssignmentScreen extends StatefulWidget {
  const CourseAssignmentScreen({super.key});

  // Global key to access the state from parent (Home) for mobile save action
  static final GlobalKey<CourseAssignmentScreenState> globalKey =
      GlobalKey<CourseAssignmentScreenState>();

  @override
  State<CourseAssignmentScreen> createState() => CourseAssignmentScreenState();
}

class CourseAssignmentScreenState extends State<CourseAssignmentScreen> {
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _accentBlue = Color(0xFF60A5FA);
  static const Color _lightShell = Color(0xFFE7E0DE);
  static const Color _lightSurface = Color(0xFFF7F5F4);

  String? _selectedTeacher;
  String? _selectedLevel;
  String? _selectedClass;
  final List<String> _selectedCourses = [];
  bool _makeClassTeacher = false;
  String? _currentClassTeacherOf; // existing class if any

  final TextEditingController _teacherController = TextEditingController();
  final TextEditingController _classController = TextEditingController();
  bool _suspendTeacherTextListener = false;
  bool _suspendClassTextListener = false;

  // Loading and error states
  bool _isLoading = true;
  String? _errorMessage;
  bool _classesLoading = false; // loading specific to classes/subjects
  bool _coursesLoading = false; // loading specific to class subjects

  // Dynamically loaded data
  List<Teacher> _teachers = [];
  final Map<String, List<String>> _educationLevels = {
    'Early Years': ['Playgroup', 'Nursery', 'Prep', 'KG', 'Montessori'],
    'Primary': [
      'Class 1',
      'Class 2',
      'Class 3',
      'Class 4',
      'Class 5',
      'Class 6',
      'Class 7'
    ],
    'Secondary': ['Class 8', 'Class 9', 'Class 10'],
  };

  // Loaded classes and subjects from backend
  List<String> _fetchedClasses = [];
  List<Course> _availableCourses = [];
  final Map<String, _AssignmentMeta> _assignmentsBySubject = {};
  final Set<String> _subjectsAssignedToOtherTeachers = {};

  List<String> get _availableClasses {
    if (_selectedLevel == null) return [];
    return _fetchedClasses;
  }

  // Public method to trigger save from parent (Home mobile header)
  void saveAssignments() {
    _saveAssignments();
  }

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _teacherController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final rows = await ApiService.getTeachers();
      setState(() {
        _teachers = rows
            .map((e) => Teacher(
                  id: (e['id'] ?? '').toString(),
                  name: e['name'] ?? 'Unknown',
                  email: e['email'] ?? '',
                ))
            .toList();
        _isLoading = false;

        final selected = _teacherById(_selectedTeacher);
        if (selected != null) {
          _setTeacherControllerText(selected.name);
        } else {
          if (_selectedTeacher != null) {
            _selectedTeacher = null;
            _makeClassTeacher = false;
            _currentClassTeacherOf = null;
            _selectedCourses.clear();
          }
          _clearTeacherController();
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load teachers: $e';
      });
    }
  }

  Future<void> _loadExistingClassTeacher(String teacherId) async {
    try {
      final profile = await ApiService.getUserProfile(int.parse(teacherId));
      setState(() {
        _currentClassTeacherOf =
            profile != null ? (profile['class_teacher_of']?.toString()) : null;
      });
    } catch (e) {
      // Non-blocking: just clear known state
      setState(() {
        _currentClassTeacherOf = null;
      });
    }
  }

  Teacher? _teacherById(String? id) {
    if (id == null) return null;
    for (final teacher in _teachers) {
      if (teacher.id == id) {
        return teacher;
      }
    }
    return null;
  }

  void _setTeacherControllerText(String text) {
    _suspendTeacherTextListener = true;
    _teacherController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _clearTeacherController() {
    if (_teacherController.text.isEmpty) return;
    _suspendTeacherTextListener = true;
    _teacherController.clear();
  }

  void _setClassControllerText(String text) {
    _suspendClassTextListener = true;
    _classController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _clearClassController() {
    if (_classController.text.isEmpty) return;
    _suspendClassTextListener = true;
    _classController.clear();
  }

  Future<void> _loadClassesForLevel(String level) async {
    try {
      setState(() {
        _classesLoading = true;
      });
      final classes = await ApiService.getClasses(level);
      setState(() {
        _fetchedClasses =
            classes.map((c) => (c['name'] ?? '').toString()).toList();

        if (_selectedClass != null && !_fetchedClasses.contains(_selectedClass)) {
          _selectedClass = null;
          _selectedCourses.clear();
          _availableCourses = [];
          _makeClassTeacher = false;
        }
      });

      if (_selectedClass != null) {
        _setClassControllerText(_selectedClass!);
      } else {
        _clearClassController();
      }
    } catch (e) {
      _showError('Failed to load classes: $e');
    } finally {
      if (mounted) {
        setState(() {
          _classesLoading = false;
        });
      }
    }
  }

  Future<void> _loadCoursesForClass(String level, String className) async {
    try {
      setState(() {
        _coursesLoading = true;
        _availableCourses = [];
        _selectedCourses.clear();
      });

      final results = await Future.wait([
        ApiService.getClassSubjects(level: level, className: className),
        ApiService.getAssignments(level: level, className: className),
      ]);

      final subjects = List<Map<String, dynamic>>.from(results[0] as List);
      final assignments = List<Map<String, dynamic>>.from(results[1] as List);

      final courses = subjects
          .map((s) => Course(
                id: (s['subject_id'] ?? s['id'] ?? '').toString(),
                name: (s['name'] ?? '').toString(),
                code: (s['code'] ?? s['name'] ?? '').toString(),
                credits: 0,
              ))
          .toList();

      final assignmentsBySubject = <String, _AssignmentMeta>{};
      final subjectsForSelectedTeacher = <String>{};
      final subjectsAssignedToOthers = <String>{};

      for (final assignment in assignments) {
        final subjectId = _normalizeId(
          assignment['subject_id'] ?? assignment['subjectId'],
        );
        if (subjectId == null) continue;

        final teacherId = _normalizeId(
          assignment['teacher_user_id'] ?? assignment['teacherId'],
        );
        final assignmentId = _normalizeId(assignment['id']);
        final teacherNameRaw =
            assignment['teacher_name'] ?? assignment['teacherName'];

        assignmentsBySubject[subjectId] = _AssignmentMeta(
          assignmentId: assignmentId,
          teacherId: teacherId,
          teacherName: teacherNameRaw == null
              ? null
              : teacherNameRaw.toString().trim().isEmpty
                  ? null
                  : teacherNameRaw.toString(),
        );

        if (teacherId != null && teacherId.isNotEmpty) {
          if (_selectedTeacher != null && teacherId == _selectedTeacher) {
            subjectsForSelectedTeacher.add(subjectId);
          } else {
            subjectsAssignedToOthers.add(subjectId);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _availableCourses = courses;
        _assignmentsBySubject
          ..clear()
          ..addAll(assignmentsBySubject);
        _subjectsAssignedToOtherTeachers
          ..clear()
          ..addAll(subjectsAssignedToOthers);
        _selectedCourses
          ..clear()
          ..addAll(subjectsForSelectedTeacher);
      });
    } catch (e) {
      _showError('Failed to load class subjects: $e');
    } finally {
      if (mounted) {
        setState(() {
          _coursesLoading = false;
        });
      }
    }
  }

  String? _normalizeId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.toString();
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 768;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isWide ? _buildAppBar() : null,
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E293B)
              : const Color(0xFF1E3A8A),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // Only show back button on desktop devices (768px and above)
          leading: MediaQuery.of(context).size.width >= 768
              ? IconButton(
                  onPressed: () async {
                    final popped = await Navigator.of(context).maybePop();
                    if (!popped && context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const StudentDashboard()),
                      );
                    }
                  },
                  icon: Icon(
                    Icons.arrow_back,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.white,
                  ),
                )
              : null,
          automaticallyImplyLeading: MediaQuery.of(context).size.width >= 768,
          title: Text(
            'Course Assignment',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.white,
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _saveAssignments,
              icon: Icon(
                Icons.save,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFF60A5FA),
              ),
              label: Text(
                'Save Changes',
                style: GoogleFonts.inter(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF8B5CF6)
                      : const Color(0xFF60A5FA),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Show loading state
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Show error state
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error Loading Data',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadTeachers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double? panelHeightAfterPadding(double verticalPadding) {
          if (!constraints.maxHeight.isFinite) return null;
          final value = constraints.maxHeight - verticalPadding;
          return value > 0 ? value : null;
        }

        final w = constraints.maxWidth;
        // Breakpoints: >=1200 desktop 2-column; 800-1199 tablet 2-column tighter; <800 phone stacked
        if (w >= 1200) {
          final panelHeight = panelHeightAfterPadding(48);
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: _buildSelectionPanel(minHeight: panelHeight),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: _buildAssignmentPanel(minHeight: panelHeight),
                ),
              ],
            ),
          );
        } else if (w >= 800) {
          final panelHeight = panelHeightAfterPadding(32);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildSelectionPanel(minHeight: panelHeight),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildAssignmentPanel(minHeight: panelHeight),
                ),
              ],
            ),
          );
        } else {
          // Phone: stack panels and use tighter padding
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              children: [
                _buildSelectionPanel(),
                const SizedBox(height: 12),
                _buildAssignmentPanel(),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSelectionPanel({double? minHeight}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        minHeight: minHeight ?? 300,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : _lightShell,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : _primaryBlue.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: _primaryBlue.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Selection Panel',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : _primaryBlue,
              ),
            ),
            const SizedBox(height: 24),

            // Teacher Selection
            _buildTeacherSelection(),
            const SizedBox(height: 24),

            // Education Level Selection
            _buildLevelSelection(),
            const SizedBox(height: 24),

            // Class Selection
            _buildClassSelection(),
            const SizedBox(height: 24),

            if (_selectedTeacher != null &&
                _selectedLevel != null &&
                _selectedClass != null)
              _buildClassTeacherToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSelection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Teacher',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark
                ? Colors.white.withValues(alpha: 0.9)
                : _primaryBlue,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : _lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : _primaryBlue.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: TypeAheadField<Teacher>(
            controller: _teacherController,
            hideOnEmpty: true,
            debounceDuration: const Duration(milliseconds: 200),
            suggestionsCallback: (pattern) {
              final query = pattern.trim().toLowerCase();
              Iterable<Teacher> source = _teachers;
              if (query.isNotEmpty) {
                source = source.where((teacher) {
                  final name = teacher.name.toLowerCase();
                  final email = teacher.email.toLowerCase();
                  return name.contains(query) || email.contains(query);
                });
              }
              return source.take(10).toList();
            },
            decorationBuilder: (context, child) => Material(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              shadowColor: Colors.black.withValues(alpha: 0.2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            ),
            itemBuilder: (context, teacher) {
              return ListTile(
                dense: true,
                title: Text(
                  teacher.name,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : _primaryBlue,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: teacher.email.isNotEmpty
                    ? Text(
                        teacher.email,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.6)
                              : _primaryBlue.withValues(alpha: 0.6),
                        ),
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
              );
            },
            emptyBuilder: (context) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _teachers.isEmpty
                    ? 'No teachers available'
                    : 'No teacher found',
                style: GoogleFonts.inter(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : _primaryBlue.withValues(alpha: 0.6),
                ),
              ),
            ),
            onSelected: (teacher) {
              _setTeacherControllerText(teacher.name);
              setState(() {
                _selectedTeacher = teacher.id;
                _selectedCourses.clear();
                _makeClassTeacher = false;
                _currentClassTeacherOf = null;
              });
              _loadExistingClassTeacher(teacher.id);
              if (_selectedLevel != null && _selectedClass != null) {
                _loadCoursesForClass(_selectedLevel!, _selectedClass!);
              }
            },
            builder: (context, controller, focusNode) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: _teachers.isNotEmpty,
                style: GoogleFonts.inter(
                  color:
                      isDark ? Colors.white : _primaryBlue,
                  fontWeight: FontWeight.w500,
                ),
                onChanged: (value) {
                  if (_suspendTeacherTextListener) {
                    _suspendTeacherTextListener = false;
                    return;
                  }
                  if (_selectedTeacher != null) {
                    final selected = _teacherById(_selectedTeacher);
                    if (selected == null || selected.name != value) {
                      setState(() {
                        _selectedTeacher = null;
                        _makeClassTeacher = false;
                        _currentClassTeacherOf = null;
                        _selectedCourses.clear();
                      });
                    }
                  }
                },
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: _teachers.isEmpty
                      ? 'No teachers available'
                      : 'Search teacher by name...',
                  hintStyle: GoogleFonts.inter(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : _primaryBlue.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : _primaryBlue.withValues(alpha: 0.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLevelSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Education Level',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.9)
                : _primaryBlue,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0F172A)
                : _lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : _primaryBlue.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedLevel,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            isExpanded: true,
            dropdownColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E293B)
                : Colors.white,
            style: GoogleFonts.inter(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : _primaryBlue,
            ),
            hint: Text(
              'Choose education level...',
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.6)
                    : _primaryBlue.withValues(alpha: 0.5),
              ),
            ),
            items: _educationLevels.keys.map((level) {
              return DropdownMenuItem<String>(
                value: level,
                child: Text(
                  level,
                  style: GoogleFonts.inter(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : _primaryBlue,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) async {
              setState(() {
                _selectedLevel = value;
                _selectedClass = null;
                _selectedCourses.clear();
                _fetchedClasses = [];
                _availableCourses = [];
                _coursesLoading = false;
              });
              _clearClassController();
              if (value != null) {
                await _loadClassesForLevel(value);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClassSelection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Class',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.9)
                : const Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _selectedLevel == null
                ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                    : _lightSurface.withValues(alpha: 0.65))
                : (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0F172A)
                    : _lightSurface),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : _primaryBlue.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: TypeAheadField<String>(
            controller: _classController,
            hideOnEmpty: true,
            debounceDuration: const Duration(milliseconds: 150),
            suggestionsCallback: (pattern) {
              if (_selectedLevel == null || _classesLoading) {
                return const <String>[];
              }
              final query = pattern.trim().toLowerCase();
              Iterable<String> source = _availableClasses;
              if (query.isNotEmpty) {
                source = source.where((className) =>
                    className.toLowerCase().contains(query));
              }
              return source.take(20).toList();
            },
            decorationBuilder: (context, child) => Material(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              shadowColor: Colors.black.withValues(alpha: 0.2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            ),
            itemBuilder: (context, className) {
              return ListTile(
                dense: true,
                title: Text(
                  className,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : _primaryBlue,
                  ),
                ),
              );
            },
            emptyBuilder: (context) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _selectedLevel == null
                    ? 'Select education level first'
                    : (_classesLoading
                        ? 'Loading classes...'
                        : _availableClasses.isEmpty
                            ? 'No classes available'
                            : 'No class found'),
                style: GoogleFonts.inter(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : _primaryBlue.withValues(alpha: 0.6),
                ),
              ),
            ),
            onSelected: (className) {
              _setClassControllerText(className);
              setState(() {
                _selectedClass = className;
              });
              if (_selectedLevel != null) {
                _loadCoursesForClass(_selectedLevel!, className);
              }
            },
            builder: (context, controller, focusNode) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: _selectedLevel == null,
                style: GoogleFonts.inter(
                  color:
                      isDark ? Colors.white : _primaryBlue,
                  fontWeight: FontWeight.w500,
                ),
                onTap: () {
                  if (_selectedLevel != null &&
                      !_classesLoading &&
                      _availableClasses.isEmpty) {
                    _loadClassesForLevel(_selectedLevel!);
                  }
                },
                onChanged: (value) {
                  if (_suspendClassTextListener) {
                    _suspendClassTextListener = false;
                    return;
                  }
                  if (_selectedClass != null) {
                    if (value != _selectedClass) {
                      setState(() {
                        _selectedClass = null;
                        _selectedCourses.clear();
                        _availableCourses = [];
                        _makeClassTeacher = false;
                      });
                    }
                  }
                },
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: _selectedLevel == null
                      ? 'Select education level first...'
                      : (_classesLoading
                          ? 'Loading classes...'
                          : 'Search class by name...'),
                  hintStyle: GoogleFonts.inter(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : _primaryBlue.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : _primaryBlue.withValues(alpha: 0.4),
                  ),
                  suffixIcon: _classesLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAssignmentPanel({double? minHeight}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: BoxConstraints(
        minHeight: minHeight ?? 300,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : _lightShell,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : _primaryBlue.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: _primaryBlue.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: hidden on mobile to avoid duplicate second line beneath the mobile app bar
            if (MediaQuery.of(context).size.width >= 768)
              Row(
                children: [
                  Text(
                    'Course Assignment',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color:
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : _primaryBlue,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedTeacher != null && _selectedClass != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _accentBlue.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_teachers.firstWhere((t) => t.id == _selectedTeacher, orElse: () => Teacher(id: '', name: 'Unknown', email: '')).name} → $_selectedLevel → $_selectedClass',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _accentBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              )
            else
            // On mobile, show only the summary chip (if available) and drop the title line
            if (_selectedTeacher != null && _selectedClass != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accentBlue.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_teachers.firstWhere((t) => t.id == _selectedTeacher, orElse: () => Teacher(id: '', name: 'Unknown', email: '')).name} → $_selectedLevel → $_selectedClass',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _accentBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),

            if (_selectedTeacher == null ||
                _selectedLevel == null ||
                _selectedClass == null)
              _buildEmptyState()
            else ...[
              // Removed Flexible inside scrollable to prevent overflow exceptions on small screens
              Container(
                constraints: const BoxConstraints(
                  minHeight: 200,
                  maxHeight: 400,
                ),
                child: _buildCourseGrid(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildClassTeacherToggle() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color backgroundColor =
        isDark ? const Color(0xFF0F172A) : _lightSurface;
    final Color borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : _primaryBlue.withValues(alpha: 0.18);
    final Color primaryTextColor = isDark ? Colors.white : _primaryBlue;
    final Color secondaryTextColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : _primaryBlue.withValues(alpha: 0.7);
    final note =
        _currentClassTeacherOf != null && _currentClassTeacherOf!.isNotEmpty
            ? 'Currently class teacher of: $_currentClassTeacherOf'
            : 'Not currently a class teacher';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Make Class Teacher',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note,
                  style: GoogleFonts.inter(
                      color: secondaryTextColor, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _makeClassTeacher,
            activeThumbColor: _primaryBlue,
            activeTrackColor: _primaryBlue.withValues(alpha: 0.35),
            onChanged: (val) async {
              if (!val) {
                setState(() => _makeClassTeacher = false);
                return;
              }
              // Enforce single class-teacher per teacher
              if (_currentClassTeacherOf != null &&
                  _currentClassTeacherOf!.isNotEmpty &&
                  _currentClassTeacherOf != _selectedClass) {
                final ok = await _confirmOverrideClassTeacher(
                  _currentClassTeacherOf!,
                  _selectedClass!,
                );
                if (!ok) return;
              }
              setState(() => _makeClassTeacher = true);
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmOverrideClassTeacher(
      String currentClass, String newClass) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: Text('Change Class Teacher',
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            content: Text(
              'This teacher is already the class teacher of "$currentClass".\n\nMake them the class teacher of "$newClass" instead? This will replace the previous assignment.',
              style:
                  GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel',
                    style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.8))),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('Replace',
                    style: GoogleFonts.inter(color: const Color(0xFF8B5CF6))),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildEmptyState() {
    return SizedBox(
      height: 300, // Fixed height to prevent layout issues
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.3)
                  : const Color(0xFF1E3A8A).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Teacher, Level and Class',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.7)
                    : _primaryBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a teacher, education level, and class to assign courses',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.5)
                    : _primaryBlue.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseGrid() {
    if (_coursesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_availableCourses.isEmpty) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Text(
          'No subjects available for this class. Link subjects first, then assign them to teachers.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark
                ? Colors.white.withValues(alpha: 0.7)
                : const Color(0xFF1E3A8A).withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        // Determine columns based on width with minimum card width ~220px
        int cols = (w / 220).floor().clamp(1, 4);
        final spacing = w < 500 ? 12.0 : 16.0;
        final aspect = w < 500 ? 1.2 : 1.5;
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspect,
          ),
          itemCount: _availableCourses.length,
          itemBuilder: (context, index) {
            final course = _availableCourses[index];
            final isSelected = _selectedCourses.contains(course.id);
            final meta = _assignmentsBySubject[course.id];
            final String? teacherName = meta?.teacherName;
            final bool assignedElsewhere = meta != null &&
                meta.teacherId != null &&
                meta.teacherId!.isNotEmpty &&
                _selectedTeacher != null &&
                meta.teacherId != _selectedTeacher &&
                !isSelected;
            final bool isSelectable = !assignedElsewhere;

            final Color baseBg;
            final Color borderColor;
            final Color titleColor;
            final Color subtitleColor;

            if (isSelected) {
              baseBg = _accentBlue.withValues(alpha: isDark ? 0.25 : 0.18);
              borderColor = _accentBlue;
              titleColor = isDark ? Colors.white : _primaryBlue;
              subtitleColor = isDark
                  ? Colors.white.withValues(alpha: 0.75)
                  : _primaryBlue.withValues(alpha: 0.7);
            } else if (assignedElsewhere) {
              baseBg = isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.6)
                  : _lightSurface.withValues(alpha: 0.65);
              borderColor = Colors.redAccent.withValues(alpha: 0.7);
              titleColor = Colors.redAccent;
              subtitleColor = Colors.redAccent.withValues(alpha: 0.7);
            } else {
              baseBg = isDark ? const Color(0xFF0F172A) : Colors.white;
              borderColor = isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : _primaryBlue.withValues(alpha: 0.18);
              titleColor = isDark ? Colors.white : _primaryBlue;
              subtitleColor = isDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : _primaryBlue.withValues(alpha: 0.6);
            }

            return GestureDetector(
              onTap: isSelectable
                  ? () {
                      setState(() {
                        if (isSelected) {
                          _selectedCourses.remove(course.id);
                        } else {
                          _selectedCourses.add(course.id);
                        }
                      });
                    }
                  : null,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.all(w < 500 ? 12 : 16),
                    decoration: BoxDecoration(
                      color: baseBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                course.name,
                                style: GoogleFonts.inter(
                                  fontSize: w < 500 ? 14 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: titleColor,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: _accentBlue,
                                size: 20,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          course.code,
                          style: GoogleFonts.inter(
                            fontSize: w < 500 ? 11 : 12,
                            color: subtitleColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Icon(
                              Icons.school,
                              size: 14,
                              color: subtitleColor.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                teacherName ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: w < 500 ? 11 : 12,
                                  color: subtitleColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (assignedElsewhere)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Tooltip(
                        message: teacherName == null || teacherName.isEmpty
                            ? 'Assigned to another teacher'
                            : 'Assigned to $teacherName',
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _saveAssignments() async {
    if (_selectedTeacher == null ||
        _selectedLevel == null ||
        _selectedClass == null ||
        _selectedCourses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select teacher, education level, class, and at least one course',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }
    final teacher = _teachers.firstWhere((t) => t.id == _selectedTeacher);
    final selectedCourseNames = _availableCourses
        .where((course) => _selectedCourses.contains(course.id))
        .map((course) => course.name)
        .toList();
    try {
      // If toggled, set class teacher for this teacher to the selected class
      if (_makeClassTeacher) {
        try {
          await ApiService.updateUserProfile(
            int.parse(_selectedTeacher!),
            {
              'class_teacher_of': _selectedClass,
            },
          );
          _currentClassTeacherOf = _selectedClass;
        } catch (e) {
          _showError('Failed to set class teacher: $e');
          return;
        }
      }
      final res = await ApiService.saveAssignments(
        teacherUserId: int.parse(_selectedTeacher!),
        level: _selectedLevel!,
        className: _selectedClass!,
        subjects: selectedCourseNames,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Assignments saved for ${teacher.name} (${_selectedLevel!} - ${_selectedClass!})',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _selectedTeacher = null;
          _selectedLevel = null;
          _selectedClass = null;
          _selectedCourses.clear();
          _fetchedClasses = [];
          _availableCourses = [];
        });
        _clearTeacherController();
        _clearClassController();
      } else {
        _showError(res['error'] ?? 'Failed to save assignments');
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to save assignments: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }
}

class Teacher {
  final String id;
  final String name;
  final String email;

  Teacher({
    required this.id,
    required this.name,
    required this.email,
  });
}

class Course {
  final String id;
  final String name;
  final String code;
  final int credits;

  Course({
    required this.id,
    required this.name,
    required this.code,
    required this.credits,
  });
}

class _AssignmentMeta {
  final String? assignmentId;
  final String? teacherId;
  final String? teacherName;

  const _AssignmentMeta({
    this.assignmentId,
    this.teacherId,
    this.teacherName,
  });
}
