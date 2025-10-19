import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import 'home.dart';

class CourseAssignmentScreen extends StatefulWidget {
  const CourseAssignmentScreen({super.key});

  // Global key to access the state from parent (Home) for mobile save action
  static final GlobalKey<_CourseAssignmentScreenState> globalKey =
      GlobalKey<_CourseAssignmentScreenState>();

  @override
  State<CourseAssignmentScreen> createState() => _CourseAssignmentScreenState();
}

class _CourseAssignmentScreenState extends State<CourseAssignmentScreen> {
  // Sentinel values for placeholder dropdown entries (must never equal real class names)
  static const String _kPlaceholderLoad = '__tap_to_load__';
  static const String _kPlaceholderLoading = '__loading__';
  String? _selectedTeacher;
  String? _selectedLevel;
  String? _selectedClass;
  final List<String> _selectedCourses = [];
  bool _makeClassTeacher = false;
  String? _currentClassTeacherOf; // existing class if any

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

  Future<void> _loadClassesForLevel(String level) async {
    try {
      setState(() {
        _classesLoading = true;
      });
      final classes = await ApiService.getClasses(level);
      setState(() {
        _fetchedClasses =
            classes.map((c) => (c['name'] ?? '').toString()).toList();
      });
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
      final subjects = await ApiService.getClassSubjects(
        level: level,
        className: className,
      );
      setState(() {
        _availableCourses = subjects
            .map((s) => Course(
                  id: (s['subject_id'] ?? s['id'] ?? '').toString(),
                  name: (s['name'] ?? '').toString(),
                  code: (s['code'] ?? s['name'] ?? '').toString(),
                  credits: 0,
                ))
            .toList();
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
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF1E3A8A),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Teacher',
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
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFF1E3A8A).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedTeacher,
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
                  : const Color(0xFF1E3A8A),
            ),
            hint: Text(
              'Choose a teacher...',
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.6)
                    : const Color(0xFF6B7280),
              ),
            ),
            items: _teachers.isEmpty
                ? [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'No teachers available',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.6)
                              : const Color(0xFF6B7280),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ]
                : _teachers.map((teacher) {
                    return DropdownMenuItem<String>(
                      value: teacher.id,
                      child: Text(
                        teacher.name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : const Color(0xFF1E3A8A),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedTeacher = value;
                _selectedCourses.clear();
                _makeClassTeacher = false;
                _currentClassTeacherOf = null;
              });
              if (value != null) {
                _loadExistingClassTeacher(value);
              }
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
                : const Color(0xFF1E3A8A),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFF1E3A8A).withValues(alpha: 0.3),
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
                  : const Color(0xFF111827),
            ),
            hint: Text(
              'Choose education level...',
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.6)
                    : const Color(0xFF6B7280),
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
                        : const Color(0xFF1E3A8A),
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
    // Ensure the current value is valid w.r.t. items to avoid assertion
    final String? effectiveClassValue =
        (_availableClasses.contains(_selectedClass)) ? _selectedClass : null;
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
                    : const Color(0xFFF9FAFB).withValues(alpha: 0.5))
                : (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF9FAFB)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFF1E3A8A).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: effectiveClassValue,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            isExpanded: true,
            menuMaxHeight: 280,
            dropdownColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E293B)
                : Colors.white,
            style: GoogleFonts.inter(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF111827),
            ),
            hint: Text(
              _selectedLevel == null
                  ? 'Select education level first...'
                  : (_classesLoading
                      ? 'Loading classes...'
                      : (_availableClasses.isEmpty
                          ? 'Tap to load classes'
                          : 'Choose a class...')),
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.6)
                    : const Color(0xFF6B7280),
              ),
            ),
            items: (_availableClasses.isNotEmpty
                    ? _availableClasses.map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(
                            c,
                            style: GoogleFonts.inter(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFF1E3A8A),
                            ),
                          ),
                        ))
                    : (_selectedLevel != null
                        ? <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(
                              value: _classesLoading
                                  ? _kPlaceholderLoading
                                  : _kPlaceholderLoad,
                              child: Text(
                                _classesLoading
                                    ? 'Loading…'
                                    : 'Tap to load classes',
                                style: GoogleFonts.inter(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF1E3A8A),
                                ),
                              ),
                            ),
                          ]
                        : const <DropdownMenuItem<String>>[]))
                .toList(),
            onTap: () async {
              if (_selectedLevel != null &&
                  !_classesLoading &&
                  _availableClasses.isEmpty) {
                await _loadClassesForLevel(_selectedLevel!);
              }
            },
            onChanged: _selectedLevel == null
                ? null
                : (value) {
                    if (value == null) return;
                    if (value == _kPlaceholderLoad ||
                        value == _kPlaceholderLoading) {
                      // Reset selection to null to avoid assertion, and trigger loading
                      setState(() {
                        _selectedClass = null;
                      });
                      if (!_classesLoading && _availableClasses.isEmpty) {
                        _loadClassesForLevel(_selectedLevel!);
                      }
                      return;
                    }
                    setState(() {
                      _selectedClass = value;
                    });
                    if (value.isNotEmpty) {
                      _loadCoursesForClass(_selectedLevel!, value);
                    }
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
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF1E3A8A).withValues(alpha: 0.12),
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : const Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                  if (_selectedTeacher != null && _selectedClass != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_teachers.firstWhere((t) => t.id == _selectedTeacher, orElse: () => Teacher(id: '', name: 'Unknown', email: '')).name} → $_selectedLevel → $_selectedClass',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF8B5CF6),
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
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_teachers.firstWhere((t) => t.id == _selectedTeacher, orElse: () => Teacher(id: '', name: 'Unknown', email: '')).name} → $_selectedLevel → $_selectedClass',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF8B5CF6),
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
              _buildLevelInfo(),
              const SizedBox(height: 16),
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
    final note =
        _currentClassTeacherOf != null && _currentClassTeacherOf!.isNotEmpty
            ? 'Currently class teacher of: $_currentClassTeacherOf'
            : 'Not currently a class teacher';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note,
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _makeClassTeacher,
            activeThumbColor: const Color(0xFF8B5CF6),
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
                    : const Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a teacher, education level, and class to assign courses',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelInfo() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0F172A)
            : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFF1E3A8A).withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.school,
                color: const Color(0xFF8B5CF6),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Subjects linked to $_selectedClass',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_coursesLoading)
            const Center(child: CircularProgressIndicator())
          else if (_availableCourses.isEmpty)
            Text(
              'No subjects are currently linked to this class. Add subjects from the class setup screen.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.7),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableCourses.map((course) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    course.name,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF8B5CF6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
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

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedCourses.remove(course.id);
                  } else {
                    _selectedCourses.add(course.id);
                  }
                });
              },
              child: Container(
                padding: EdgeInsets.all(w < 500 ? 12 : 16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                      : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF8B5CF6)
                        : Colors.white.withValues(alpha: 0.1),
                    width: isSelected ? 2 : 1,
                  ),
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
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF8B5CF6),
                            size: 20,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      course.code,
                      style: GoogleFonts.inter(
                        fontSize: w < 500 ? 11 : 12,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.school,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '',
                          style: GoogleFonts.inter(
                            fontSize: w < 500 ? 11 : 12,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
