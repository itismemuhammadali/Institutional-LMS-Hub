import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/responsive_helper.dart';
import '../services/api_service.dart';
import 'home.dart';
import 'course_details_screen.dart';

class Course {
  final String name;
  final Color color;
  final String? className;
  final String? subjectName;
  final int? classId;
  final int? subjectId;
  
  const Course({
    required this.name,
    required this.color,
    this.className,
    this.subjectName,
    this.classId,
    this.subjectId,
  });

  static Course fromApi(Map<String, dynamic> m, Color color) {
    return Course(
      name: ((m['name'] ?? m['subject_name'] ?? 'Course')).toString(),
      color: color,
      className: (m['class_name'] ?? '') as String?,
      subjectName: (m['subject_name'] ?? '') as String?,
      classId: (m['class_id'] is int)
          ? m['class_id'] as int
          : int.tryParse((m['class_id'] ?? '').toString()),
      subjectId: (m['subject_id'] is int)
          ? m['subject_id'] as int
          : int.tryParse((m['subject_id'] ?? '').toString()),
    );
  }
}

class CoursesScreen extends StatefulWidget {
  final void Function(Course course)? onViewDetails;
  const CoursesScreen({super.key, this.onViewDetails});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  bool _loading = false;
  String? _error;
  List<Course> _courses = const [];

  final List<Color> _palette = const [
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF06B6D4),
    Color(0xFFEF4444),
  ];
  
  Color _colorFor(int i) => _palette[i % _palette.length];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      final currentUser = await ApiService.getCurrentUser();
      final role = (currentUser?['role'] ?? '').toString().toLowerCase();
      final bool isStudent = role == 'student';
      List<Map<String, dynamic>> list = const [];
      
      if (isStudent) {
        final userId = await ApiService.getCurrentUserId();
        if (userId != null) {
          final profile = await ApiService.getUserProfile(userId);
          final className = (profile?['class'] ?? '').toString();
          final level = _inferLevelForClass(className);

          if (className.isNotEmpty && level != null) {
            final subjects = await ApiService.getClassSubjects(
              level: level,
              className: className,
            );
            list = subjects
                .map((s) => {
                      'name': (s['name'] ?? '').toString(),
                      'subject_name': (s['name'] ?? '').toString(),
                      'class_name': className,
                      'subject_id': s['subject_id'] ?? s['id'],
                      'class_id': s['class_id'],
                    })
                .toList();
          }
        }
      } else {
        list = await ApiService.getMyCourses();
      }
      
      final mapped = <Course>[];
      for (int i = 0; i < list.length; i++) {
        mapped.add(Course.fromApi(list[i], _colorFor(i)));
      }
      
      if (!mounted) return;
      setState(() {
        _courses = mapped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String? _inferLevelForClass(String className) {
    final trimmed = className.trim();
    if (trimmed.isEmpty) return null;
    final digits = RegExp(r"\d+").firstMatch(trimmed)?.group(0);
    if (digits != null) {
      final value = int.tryParse(digits);
      if (value != null) {
        if (value >= 8) return 'Secondary';
        if (value >= 1) return 'Primary';
      }
    }
    final lower = trimmed.toLowerCase();
    const earlyYears = {
      'montessori',
      'nursery',
      'prep',
      'kg',
      'k.g',
      'playgroup',
      'play group',
      'kindergarten',
      'pre-school',
      'preschool',
    };
    if (earlyYears.contains(lower)) return 'EarlyYears';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final bool isMobile = ResponsiveHelper.isMobile(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          if (!isMobile)
            // Full-bleed header bar
            Container(
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
                    'My Courses',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          // Scrollable content with padding
          Expanded(
            child: SingleChildScrollView(
              padding: ResponsiveHelper.getContentPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Content states
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(left: 16, right: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLight ? lightCard : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5), width: 1),
                      ),
                      child: Text(
                        _error!,
                        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
                      ),
                    )
                  else if (_loading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF8B5CF6)),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Loading courses...',
                              style: GoogleFonts.inter(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_courses.isEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(left: 16, right: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isLight ? lightCard : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isLight ? lightBorder : Colors.white.withValues(alpha: 0.12), width: 1),
                      ),
                      child: Text(
                        'No courses assigned yet.',
                        style: GoogleFonts.inter(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final double width = constraints.maxWidth;
                        const double spacing = 16;
                        int columns = 1;

                        if (width >= ResponsiveHelper.mobileBreakpoint &&
                            width < ResponsiveHelper.tabletBreakpoint) {
                          columns = 2; // Tablets
                        } else if (width >= ResponsiveHelper.tabletBreakpoint &&
                            width < ResponsiveHelper.largeDesktopBreakpoint) {
                          columns = 3; // Laptops / standard desktops
                        } else if (width >= ResponsiveHelper.largeDesktopBreakpoint &&
                            width < ResponsiveHelper.ultraWideBreakpoint) {
                          columns = 4; // Large desktops
                        } else if (width >= ResponsiveHelper.ultraWideBreakpoint) {
                          columns = 5; // Ultra-wide displays
                        }

                        columns = columns.clamp(1, _courses.length);
                        final double itemWidth = columns == 1
                            ? width
                            : (width - spacing * (columns - 1)) / columns;

                        final rows = <Widget>[];
                        for (int start = 0; start < _courses.length; start += columns) {
                          final end = (start + columns).clamp(0, _courses.length);
                          final rowChildren = <Widget>[];

                          for (int i = start; i < end; i++) {
                            rowChildren.add(SizedBox(
                              width: itemWidth,
                              child: _buildCourseCard(_courses[i]),
                            ));
                            if (i < end - 1) {
                              rowChildren.add(const SizedBox(width: spacing));
                            }
                          }

                          rows.add(Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: rowChildren,
                          ));

                          if (end < _courses.length) {
                            rows.add(const SizedBox(height: spacing));
                          }
                        }

                        return Column(children: rows);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLecturesDialog(Course course) {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    final bool isMobileDialog = ResponsiveHelper.isMobile(context);
    final Size mediaSize = MediaQuery.of(context).size;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobileDialog ? 16 : 40,
          vertical: isMobileDialog ? 24 : 32,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 16,
        child: Container(
          width: isMobileDialog ? double.infinity : 480,
          constraints: BoxConstraints(
            maxWidth: isMobileDialog ? mediaSize.width : 520,
            maxHeight: isMobileDialog ? mediaSize.height * 0.85 : 600,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isLight ? lightCard : null,
            gradient: isLight
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1E293B),
                      const Color(0xFF0F172A),
                    ],
                  ),
            border: isLight ? Border.all(color: lightBorder, width: 1) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(isMobileDialog ? 16 : 24),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  color: isLight ? lightCard : null,
                  gradient: isLight
                      ? null
                      : LinearGradient(
                          colors: [
                            course.color.withValues(alpha: 0.2),
                            course.color.withValues(alpha: 0.1),
                          ],
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(isMobileDialog ? 10 : 12),
                      decoration: BoxDecoration(
                        color: course.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.play_circle_outline,
                        color: Colors.white,
                        size: isMobileDialog ? 22 : 24,
                      ),
                    ),
                    SizedBox(width: isMobileDialog ? 12 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${course.name} Lectures',
                            style: GoogleFonts.inter(
                              fontSize: isMobileDialog ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: isLight ? primaryBlue : Colors.white,
                            ),
                          ),
                          SizedBox(height: isMobileDialog ? 2 : 4),
                          Text(
                            'Access all available lectures',
                            style: GoogleFonts.inter(
                              fontSize: isMobileDialog ? 12 : 14,
                              color: isLight
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isMobileDialog ? 4 : 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: isLight
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isMobileDialog ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // No lectures available message
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isMobileDialog ? 16 : 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: isLight ? lightCard : null,
                          gradient: isLight
                              ? null
                              : LinearGradient(
                                  colors: [
                                    course.color.withValues(alpha: 0.1),
                                    course.color.withValues(alpha: 0.05),
                                  ],
                                ),
                          border: Border.all(
                            color: isLight ? lightBorder : course.color.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.video_library_outlined,
                              color: course.color,
                              size: isMobileDialog ? 40 : 48,
                            ),
                            SizedBox(height: isMobileDialog ? 12 : 16),
                            Text(
                              'No Lectures Available',
                              style: GoogleFonts.inter(
                                fontSize: isMobileDialog ? 16 : 18,
                                fontWeight: FontWeight.w600,
                                color: isLight ? primaryBlue : Colors.white,
                              ),
                            ),
                            SizedBox(height: isMobileDialog ? 6 : 8),
                            Text(
                              'Lectures for this course will appear here once they are uploaded by your teacher.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: isMobileDialog ? 12 : 14,
                                color: isLight
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7)
                                    : Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCourseDetails(Course course) {
    if (widget.onViewDetails != null) {
      widget.onViewDetails!(course);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CourseDetailsScreen(
          courseTitle: '${course.className} - ${course.subjectName}',
          className: course.className,
          subjectName: course.subjectName,
          teacherName: '',
          accentColor: const Color(0xFF8B5CF6),
          classId: course.classId,
          subjectId: course.subjectId,
        ),
      ),
    );
  }

  Widget _buildCourseCard(Course course) {
    const primaryBlue = Color(0xFF1E3A8A);
    const lightCard = Color(0xFFE7E0DE);
    const lightBorder = Color(0xFFD9D2D0);
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight ? lightCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? lightBorder : primaryBlue,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: course.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.book, color: course.color, size: 12),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  course.name,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Class/Subject line
          if ((course.className ?? '').isNotEmpty ||
              (course.subjectName ?? '').isNotEmpty)
            Row(
              children: [
                Icon(Icons.school, color: course.color, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [course.subjectName, course.className]
                        .where((e) => (e ?? '').isNotEmpty)
                        .join(' • '),
                    style: GoogleFonts.inter(fontSize: 12, color: primaryBlue.withValues(alpha: 0.7)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          // Buttons Row
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _showLecturesDialog(course),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: primaryBlue,
                    side: BorderSide(color: primaryBlue, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Lectures',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _openCourseDetails(course),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: primaryBlue,
                    side: BorderSide(color: primaryBlue, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Details',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
