import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/calendar_widget.dart';
import '../widgets/vertical_nav_bar.dart';
import '../widgets/sidebar_chat_widget.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'course_details_screen.dart';
import 'courses_screen.dart';
import 'academic_dashboard_screen.dart';
import 'profile_screen.dart';
import 'dues_screen.dart';
import '../screens/course_assignment_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/add_new_user_screen.dart';
import 'admin_dues_screen.dart';
import 'dart:developer' show log;
import 'dart:convert';
import 'teacher_attendance_screen.dart';
import 'generate_ticket_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key, this.initialIndex = 1});

  final int initialIndex;

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  int _selectedNavIndex = 1;
  bool _isNavExpanded = false;
  bool _showCourseDetails = false; // New state for course details
  bool _showLectures = false; // New state for lectures tab
  bool _showAttendance = false; // New state for attendance tab
  bool _showChatSidebar = false; // New state for chat sidebar
  Map<String, dynamic>? _selectedCourse; // Selected course data
  Color? _selectedCourseColor; // Selected course accent color
  Offset _chatButtonPosition = const Offset(20, 100); // Position for draggable chat button
  bool _isChatFullscreen = false; // Track fullscreen state
  
  // Uniform height for dashboard cards (Event, Add New Student, Take Attendance)
  static const double _dashCardHeight = 140;
  
  // Attendance summary state
  bool _attendanceLoading = false;
  String? _termStartDate;
  double _percPresent = 0;
  double _percAbsent = 0;
  double _percLeave = 0;
  int _countPresent = 0;
  int _countAbsent = 0;
  int _countLeave = 0;
  int _countTotal = 0;
  String? _attendanceError;
  
  // User data from API
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _userProfile;
  bool _profileLoading = false;
  String? _profilePictureUrl;

  // Upcoming event (from server calendar: user events or holidays)
  String? _upcomingEventTitle;
  DateTime? _upcomingEventDate;
  String? _upcomingEventDesc;

  // Notices state
  bool _noticesLoading = false;
  List<Map<String, dynamic>> _notices = const [];
  String? _noticesError;
  
  // Calendar events for notice board
  List<Map<String, dynamic>> _calendarEvents = const [];

  // Courses (teacher-assigned) state
  bool _coursesLoading = false;
  List<Map<String, dynamic>> _myCourses = const [];
  String? _coursesError;

  // Student dashboard totals
  // Pending Assignments and Upcoming Quizzes counts
  int? _pendingAssignmentsCount;
  int? _upcomingQuizzesCount;
  bool _studentTotalsLoading = false;

  bool get _canAddEvents {
    // Only backend Admins (teacher-admin and superadmin) can add events
    final role = (_currentUser?['role'] ?? _userProfile?['role'] ?? '')
        .toString()
        .toLowerCase();
    return role == 'admin';
  }

  void _openAcademicRecords() {
    setState(() {
      _selectedNavIndex = 11;
      _showCourseDetails = false;
      _showLectures = false;
      _showAttendance = false;
      if (ResponsiveHelper.isMobile(context)) {
        _isNavExpanded = false;
      }
    });
  }

  Widget _buildAcademicRecordsBox() {
    const Color accent = Color(0xFF2563EB);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _openAcademicRecords,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? accent.withValues(alpha: 0.1)
                : const Color(0xFFE7E0DE),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? accent.withValues(alpha: 0.3)
                  : const Color(0xFFD9D2D0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).brightness == Brightness.dark
                    ? accent.withValues(alpha: 0.2)
                    : accent.withValues(alpha: 0.15),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          constraints:
              BoxConstraints(minHeight: _dashCardHeight, maxHeight: _dashCardHeight),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.insights, color: accent, size: 28),
                        SizedBox(width: 8),
                      ],
                    ),
                    Text(
                      'Academic Records',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'View results & history',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadMyCourses() async {
    setState(() {
      _coursesLoading = true;
      _coursesError = null;
    });
    try {
      // Choose endpoint based on role
      final user = await ApiService.getCurrentUser();
      final role = (user?['role'] ?? '').toString().toLowerCase();
      final bool isStudent = role == 'student';
      List<Map<String, dynamic>> items;
      if (isStudent) {
        items = const [];
        final userId = await ApiService.getCurrentUserId();
        if (userId != null) {
          final profile = await ApiService.getUserProfile(userId);
          final className = (profile?['class'] ?? '').toString();
          final level = _inferLevelForClass(className);

          if (className.isNotEmpty && level != null) {
            try {
              final subjects = await ApiService.getClassSubjects(
                level: level,
                className: className,
              );
              items = subjects
                  .map((s) => {
                        'name': (s['name'] ?? '').toString(),
                        'subject_name': (s['name'] ?? '').toString(),
                        'class_name': className,
                        'subject_id': s['subject_id'] ?? s['id'],
                        'class_id': s['class_id'],
                      })
                  .toList();

              final subjectNames = items
                  .map((m) => (m['subject_name'] ?? m['name'] ?? '').toString())
                  .where((s) => s.isNotEmpty)
                  .toList();
              _loadStudentTotals(className: className, subjects: subjectNames);
            } catch (err) {
              items = const [];
              _coursesError = err.toString();
            }
          }
        }
      } else {
        // Teachers/Admins continue to use their own courses endpoint
        items = await ApiService.getMyCourses();
      }
      if (!mounted) return;
      setState(() {
        // Normalize title for UI: prefer 'name' else fallback to 'subject_name'
        _myCourses = items.map((m) {
          final map = Map<String, dynamic>.from(m);
          if ((map['name'] == null || map['name'].toString().trim().isEmpty) &&
              (map['subject_name'] != null)) {
            map['name'] = map['subject_name'];
          }
          return map;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _coursesError = e.toString();
        _myCourses = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _coursesLoading = false;
        });
      }
    }
  }

  // Compute student dashboard totals by aggregating course summaries per subject
  Future<void> _loadStudentTotals({
    required String className,
    required List<String> subjects,
  }) async {
    if (!mounted) return;
    setState(() {
      _studentTotalsLoading = true;
      _pendingAssignmentsCount = null;
      _upcomingQuizzesCount = null;
    });
    try {
      final level = _inferLevelForClass(className);
      int pendingAssignments = 0;
      int upcomingQuizzes = 0;

      // Today (date only) for comparison
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final subject in subjects) {
        try {
          final meta = await ApiService.getCourseSummary(
            level: level,
            className: className,
            subjectName: subject,
          );
          if (meta == null || meta.isEmpty) continue;

          final String? assignmentDeadlineStr = (meta['next_assignment_deadline'] ?? meta['nextAssignmentDeadline'])?.toString();
          if (assignmentDeadlineStr != null && assignmentDeadlineStr.trim().isNotEmpty) {
            DateTime? dt;
            try { dt = DateTime.parse(assignmentDeadlineStr); } catch (_) {}
            if (dt != null) {
              final dueDate = DateTime(dt.year, dt.month, dt.day);
              if (!dueDate.isBefore(today)) {
                pendingAssignments += 1;
              }
            }
          }

          final String? nextQuizAtStr = (meta['next_quiz_at'] ?? meta['nextQuizAt'])?.toString();
          if (nextQuizAtStr != null && nextQuizAtStr.trim().isNotEmpty) {
            DateTime? dt;
            try { dt = DateTime.parse(nextQuizAtStr); } catch (_) {}
            if (dt != null && dt.isAfter(now)) {
              upcomingQuizzes += 1;
            }
          }
        } catch (_) {
          // Ignore per-subject failures; continue aggregation
        }
      }

      if (!mounted) return;
      setState(() {
        _pendingAssignmentsCount = pendingAssignments;
        _upcomingQuizzesCount = upcomingQuizzes;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingAssignmentsCount = 0;
        _upcomingQuizzesCount = 0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _studentTotalsLoading = false;
        });
      }
    }
  }

  bool get _canAddNotices {
    final role = (_currentUser?['role'] ?? _userProfile?['role'] ?? '')
        .toString()
        .toLowerCase();
    return role == 'teacher' || role == 'principal' || role == 'admin';
  }

  Future<void> _loadAttendanceSummary() async {
    setState(() {
      _attendanceLoading = true;
      _attendanceError = null;
    });
    try {
      final res = await ApiService.getAttendanceSummary();
      if (!mounted) return;
      setState(() {
        _termStartDate = (res['term_start_date'] as String?);
        final p = res['percentages'] as Map<String, dynamic>?;
        _percPresent = ((p?['present'] ?? 0) as num).toDouble();
        _percAbsent  = ((p?['absent']  ?? 0) as num).toDouble();
        _percLeave   = ((p?['leave']   ?? 0) as num).toDouble();
        _countPresent = (res['present'] ?? 0) as int;
        _countAbsent  = (res['absent']  ?? 0) as int;
        _countLeave   = (res['leave']   ?? 0) as int;
        _countTotal   = (res['total']   ?? 0) as int;
        _attendanceError = null;
      });

      // Fallback: if summary shows zero total, compute from detailed records
      if ((_countTotal == 0) && mounted) {
        try {
          final userId = await ApiService.getCurrentUserId();
          if (userId != null) {
            final items = await ApiService.getUserAttendance(userId);
            int p = 0, a = 0, l = 0;
            for (final it in items) {
              final st = (it['status'] ?? '').toString().toLowerCase().trim();
              if (st == 'present') {
                p++;
              } else if (st == 'absent') a++; else if (st == 'leave') l++;
            }
            final tot = p + a + l;
            if (tot > 0 && mounted) {
              setState(() {
                _countPresent = p;
                _countAbsent = a;
                _countLeave = l;
                _countTotal = tot;
                _percPresent = double.parse(((p * 100.0) / tot).toStringAsFixed(1));
                _percAbsent = double.parse(((a * 100.0) / tot).toStringAsFixed(1));
                _percLeave = double.parse(((l * 100.0) / tot).toStringAsFixed(1));
              });
            }
          }
        } catch (_) {
          // ignore and keep original zeros
        }
      }
    } catch (e) {
      if (!mounted) return;
      // Keep silent but reset values
      setState(() {
        _termStartDate = null;
        _percPresent = _percAbsent = _percLeave = 0;
        _countPresent = _countAbsent = _countLeave = _countTotal = 0;
        _attendanceError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _attendanceLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedNavIndex = widget.initialIndex;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
    
    print('🚀 [INIT] ===== APP INITIALIZING =====');
    log('🚀 [INIT] ===== APP INITIALIZING =====');
    print('🚀 [INIT] InitState method called successfully!');
    log('🚀 [INIT] InitState method called successfully!');
    print('🚀 [INIT] About to initialize app...');
    log('🚀 [INIT] About to initialize app...');
    
    // Load user data from API
      print('🚀 [INIT] Calling _loadUserData...');
      log('🚀 [INIT] Calling _loadUserData...');
    _loadUserData();
    
    // Load upcoming calendar event from backend
    print('🚀 [INIT] Calling _loadUpcomingEvent...');
    log('🚀 [INIT] Calling _loadUpcomingEvent...');
    _loadUpcomingEvent();
    
    // Load attendance summary for pie chart
    print('🚀 [INIT] Calling _loadAttendanceSummary...');
    log('🚀 [INIT] Calling _loadAttendanceSummary...');
    _loadAttendanceSummary();
    
    // Check if user is superadmin and load tickets
    print('🚀 [INIT] Calling _checkUserAndLoadData...');
    log('🚀 [INIT] Calling _checkUserAndLoadData...');
    _checkUserAndLoadData();
    
    // Load notices
    print('🚀 [INIT] Calling _loadNotices...');
    log('🚀 [INIT] Calling _loadNotices...');
    _loadNotices();
    
    // Load assigned courses (if teacher)
    print('🚀 [INIT] Calling _loadMyCourses...');
    log('🚀 [INIT] Calling _loadMyCourses...');
    _loadMyCourses();
    
    print('🚀 [INIT] ===== APP INITIALIZATION COMPLETED =====');
    log('🚀 [INIT] ===== APP INITIALIZATION COMPLETED =====');
    print('🚀 [INIT] App initialization completed successfully!');
    log('🚀 [INIT] App initialization completed successfully!');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    print('🔄 [LIFECYCLE] didChangeDependencies called, selectedNavIndex: $_selectedNavIndex');
    log('🔄 [LIFECYCLE] didChangeDependencies called, selectedNavIndex: $_selectedNavIndex');
    print('🔄 [LIFECYCLE] didChangeDependencies method called successfully!');
    log('🔄 [LIFECYCLE] didChangeDependencies method called successfully!');
    print('🔄 [LIFECYCLE] About to check if profile screen is selected...');
    log('🔄 [LIFECYCLE] About to check if profile screen is selected...');
    print('🔄 [LIFECYCLE] About to start profile screen check process...');
    log('🔄 [LIFECYCLE] About to start profile screen check process...');
    // Refresh profile picture when returning from profile screen
    if (_selectedNavIndex == 4) {
      print('🔄 [LIFECYCLE] Profile screen detected, refreshing profile picture...');
      log('🔄 [LIFECYCLE] Profile screen detected, refreshing profile picture...');
      print('🔄 [LIFECYCLE] About to start profile picture refresh process...');
      log('🔄 [LIFECYCLE] About to start profile picture refresh process...');
      _refreshProfilePictureOnReturn();
    }
    print('🔄 [LIFECYCLE] didChangeDependencies completed successfully!');
    log('🔄 [LIFECYCLE] didChangeDependencies completed successfully!');
  }

  @override
  void didUpdateWidget(StudentDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    print('🔄 [LIFECYCLE] didUpdateWidget called, selectedNavIndex: $_selectedNavIndex');
    log('🔄 [LIFECYCLE] didUpdateWidget called, selectedNavIndex: $_selectedNavIndex');
    print('🔄 [LIFECYCLE] didUpdateWidget method called successfully!');
    log('🔄 [LIFECYCLE] didUpdateWidget method called successfully!');
    print('🔄 [LIFECYCLE] About to check if profile screen is selected in didUpdateWidget...');
    log('🔄 [LIFECYCLE] About to check if profile screen is selected in didUpdateWidget...');
    print('🔄 [LIFECYCLE] About to start profile screen check process in didUpdateWidget...');
    log('🔄 [LIFECYCLE] About to start profile screen check process in didUpdateWidget...');
    // Refresh profile picture when returning from profile screen
    if (_selectedNavIndex == 4) {
      print('🔄 [LIFECYCLE] Profile screen detected in didUpdateWidget, refreshing profile picture...');
      log('🔄 [LIFECYCLE] Profile screen detected in didUpdateWidget, refreshing profile picture...');
      print('🔄 [LIFECYCLE] About to start profile picture refresh process in didUpdateWidget...');
      log('🔄 [LIFECYCLE] About to start profile picture refresh process in didUpdateWidget...');
      _refreshProfilePictureOnReturn();
    }
    print('🔄 [LIFECYCLE] didUpdateWidget completed successfully!');
    log('🔄 [LIFECYCLE] didUpdateWidget completed successfully!');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('🔄 [LIFECYCLE] didChangeAppLifecycleState called, state: $state');
    log('🔄 [LIFECYCLE] didChangeAppLifecycleState called, state: $state');
    print('🔄 [LIFECYCLE] didChangeAppLifecycleState method called successfully!');
    log('🔄 [LIFECYCLE] didChangeAppLifecycleState method called successfully!');
    print('🔄 [LIFECYCLE] About to check if app is resumed...');
    log('🔄 [LIFECYCLE] About to check if app is resumed...');
    print('🔄 [LIFECYCLE] About to start app lifecycle check process...');
    log('🔄 [LIFECYCLE] About to start app lifecycle check process...');
    // Refresh profile picture when app becomes active
    if (state == AppLifecycleState.resumed) {
      print('🔄 [LIFECYCLE] App resumed, refreshing profile picture...');
      log('🔄 [LIFECYCLE] App resumed, refreshing profile picture...');
      print('🔄 [LIFECYCLE] About to start profile picture refresh process...');
      log('🔄 [LIFECYCLE] About to start profile picture refresh process...');
      _refreshProfilePicture();
    }
    print('🔄 [LIFECYCLE] didChangeAppLifecycleState completed successfully!');
    log('🔄 [LIFECYCLE] didChangeAppLifecycleState completed successfully!');
  }

  Future<void> _loadNotices() async {
    setState(() {
      _noticesLoading = true;
      _noticesError = null;
    });
    try {
      // Load regular notices
      final items = await ApiService.listNotices(limit: 10);
      
      // Load calendar events for current month
      final now = DateTime.now();
      final calendarResult = await ApiService.getCalendarMonth(now.year, now.month);
      
      // Extract upcoming events from calendar data
      final upcomingEvents = <Map<String, dynamic>>[];
      print('Notice Board: Full API response: $calendarResult');
      
      // Process events from the same structure as calendar widget
      // First check for user events in multiple possible locations
      List evs = [];
      if (calendarResult['events'] != null) {
        evs = calendarResult['events'] as List;
      } else if (calendarResult['data'] != null && calendarResult['data']['events'] != null) {
        evs = calendarResult['data']['events'] as List;
      } else if (calendarResult['calendar_events'] != null) {
        evs = calendarResult['calendar_events'] as List;
      }
      
      print('Notice Board: Found ${evs.length} user events: $evs');
      
      for (final event in evs) {
        final dateStr = event['date'] as String?;
        if (dateStr == null) continue;
        
        try {
          final eventDate = DateTime.parse(dateStr);
          // Include events from the past 7 days and all future events
          if (eventDate.isAfter(now.subtract(const Duration(days: 7)))) {
            print('Notice Board: Adding user event: ${event['title']} on $dateStr');
            upcomingEvents.add({
              'title': '📅 ${(event['title'] ?? event['name'] ?? '').toString()}',
              'created_at': dateStr,
              'type': 'calendar_event',
              'event_date': eventDate,
              'description': (event['description'] ?? event['details'] ?? event['body'] ?? '')?.toString(),
            });
          }
        } catch (e) {
          print('Notice Board: Error parsing event date $dateStr: $e');
        }
      }
      
      // Also check days for holidays/titles
      if (calendarResult['days'] != null) {
        final List days = calendarResult['days'] as List;
        for (final day in days) {
          final dateStr = day['date'] as String?;
          if (dateStr == null) continue;
          
          final isHoliday = (day['is_holiday'] ?? 0) == 1;
          final title = (day['title'] ?? '') as String;
          
          if (isHoliday || title.isNotEmpty) {
            try {
              final dayDate = DateTime.parse(dateStr);
              if (dayDate.isAfter(now.subtract(const Duration(days: 7)))) {
                print('Notice Board: Adding holiday/title: ${title.isNotEmpty ? title : 'Holiday'} on $dateStr');
                upcomingEvents.add({
                  'title': '📅 ${title.isNotEmpty ? title : 'Holiday'}',
                  'created_at': dateStr,
                  'type': 'calendar_event',
                  'event_date': dayDate,
                  'description': (day['description'] ?? day['details'] ?? '')?.toString(),
                });
              }
            } catch (e) {
              print('Notice Board: Error parsing day date $dateStr: $e');
            }
          }
        }
      }
      print('Notice Board: Total upcoming events found: ${upcomingEvents.length}');
      
      if (!mounted) return;
      setState(() {
        _notices = items;
        _calendarEvents = upcomingEvents;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _noticesError = e.toString();
        _notices = const [];
        _calendarEvents = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _noticesLoading = false;
        });
      }
    }
  }
  
  Future<void> _loadUserData() async {
    try {
      print('🔄 [PROFILE PICTURE] Starting user data load...');
      log('🔄 [PROFILE PICTURE] Starting user data load...');
      
      if (mounted) {
        setState(() {
          _profileLoading = true;
        });
      }

      print('🔄 [PROFILE PICTURE] Getting current user...');
      log('🔄 [PROFILE PICTURE] Getting current user...');
      final user = await ApiService.getCurrentUser();
      if (user != null && mounted) {
        print('✅ [PROFILE PICTURE] Current user loaded: ${user['name']} (ID: ${user['id']})');
        log('✅ [PROFILE PICTURE] Current user loaded: ${user['name']} (ID: ${user['id']})');
        setState(() {
          _currentUser = user;
        });
      } else {
        print('❌ [PROFILE PICTURE] Failed to load current user');
        log('❌ [PROFILE PICTURE] Failed to load current user');
      }

      // Prefer reliable ID helper
      print('🔄 [PROFILE PICTURE] Getting user ID...');
      log('🔄 [PROFILE PICTURE] Getting user ID...');
      int? userId = await ApiService.getCurrentUserId();
      if (userId == null) {
        print('⚠️ [PROFILE PICTURE] getCurrentUserId returned null, trying user data...');
        log('⚠️ [PROFILE PICTURE] getCurrentUserId returned null, trying user data...');
        final raw = user?['id'];
        if (raw is int) {
          userId = raw;
          print('✅ [PROFILE PICTURE] User ID from user data: $userId');
          log('✅ [PROFILE PICTURE] User ID from user data: $userId');
        } else if (raw is String) {
          userId = int.tryParse(raw);
          print('✅ [PROFILE PICTURE] User ID parsed from string: $userId');
          log('✅ [PROFILE PICTURE] User ID parsed from string: $userId');
        }
      } else {
        print('✅ [PROFILE PICTURE] User ID from getCurrentUserId: $userId');
        log('✅ [PROFILE PICTURE] User ID from getCurrentUserId: $userId');
      }

      if (userId != null) {
        print('🔄 [PROFILE PICTURE] Loading user profile for ID: $userId...');
        log('🔄 [PROFILE PICTURE] Loading user profile for ID: $userId...');
        final profile = await ApiService.getUserProfile(userId);
        if (mounted) {
          print('✅ [PROFILE PICTURE] User profile loaded: ${profile?.keys.toList()}');
          log('✅ [PROFILE PICTURE] User profile loaded: ${profile?.keys.toList()}');
          setState(() {
            _userProfile = profile;
          });
        }
        
        // Load profile picture URL after profile is loaded
        print('🔄 [PROFILE PICTURE] Starting profile picture load...');
        log('🔄 [PROFILE PICTURE] Starting profile picture load...');
        print('🔄 [PROFILE PICTURE] About to call _loadProfilePicture with userId: $userId');
        log('🔄 [PROFILE PICTURE] About to call _loadProfilePicture with userId: $userId');
        print('🔄 [PROFILE PICTURE] Calling _loadProfilePicture method...');
        log('🔄 [PROFILE PICTURE] Calling _loadProfilePicture method...');
        print('🔄 [PROFILE PICTURE] About to await _loadProfilePicture...');
        log('🔄 [PROFILE PICTURE] About to await _loadProfilePicture...');
        await _loadProfilePicture(userId);
        print('🔄 [PROFILE PICTURE] _loadProfilePicture completed');
        log('🔄 [PROFILE PICTURE] _loadProfilePicture completed');
        print('🔄 [PROFILE PICTURE] Profile picture loading in user data completed!');
        log('🔄 [PROFILE PICTURE] Profile picture loading in user data completed!');
        print('🔄 [PROFILE PICTURE] User data profile picture loading successful!');
        log('🔄 [PROFILE PICTURE] User data profile picture loading successful!');
      } else {
        print('❌ [PROFILE PICTURE] Error loading user data: Missing userId');
        log('❌ [PROFILE PICTURE] Error loading user data: Missing userId');
      }
    } catch (e) {
      print('❌ [PROFILE PICTURE] Error loading user data: $e');
      log('❌ [PROFILE PICTURE] Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
        print('✅ [PROFILE PICTURE] User data loading completed');
        log('✅ [PROFILE PICTURE] User data loading completed');
      }
    }
  }

  Future<void> _loadProfilePicture(int userId) async {
    try {
      print('🖼️ [PROFILE PICTURE] ===== STARTING PROFILE PICTURE LOAD =====');
      log('🖼️ [PROFILE PICTURE] ===== STARTING PROFILE PICTURE LOAD =====');
      print('🖼️ [PROFILE PICTURE] User ID: $userId');
      log('🖼️ [PROFILE PICTURE] User ID: $userId');
      print('🖼️ [PROFILE PICTURE] Current _profilePictureUrl: $_profilePictureUrl');
      log('🖼️ [PROFILE PICTURE] Current _profilePictureUrl: $_profilePictureUrl');
      print('🖼️ [PROFILE PICTURE] Method called successfully!');
      log('🖼️ [PROFILE PICTURE] Method called successfully!');
      print('🖼️ [PROFILE PICTURE] _loadProfilePicture method entry point reached!');
      log('🖼️ [PROFILE PICTURE] _loadProfilePicture method entry point reached!');
      print('🖼️ [PROFILE PICTURE] About to start profile picture loading process...');
      log('🖼️ [PROFILE PICTURE] About to start profile picture loading process...');
      
      // First check if profile picture URL is in the profile data
      String? profilePictureUrl;
      
      print('🖼️ [PROFILE PICTURE] Checking profile data...');
      log('🖼️ [PROFILE PICTURE] Checking profile data...');
      print('🖼️ [PROFILE PICTURE] About to check _userProfile...');
      log('🖼️ [PROFILE PICTURE] About to check _userProfile...');
      print('🖼️ [PROFILE PICTURE] About to start profile data check...');
      log('🖼️ [PROFILE PICTURE] About to start profile data check...');
      
      if (_userProfile != null) {
        print('🖼️ [PROFILE PICTURE] Profile data available: ${_userProfile!.keys.toList()}');
        log('🖼️ [PROFILE PICTURE] Profile data available: ${_userProfile!.keys.toList()}');
        print('🖼️ [PROFILE PICTURE] Full profile data: $_userProfile');
        log('🖼️ [PROFILE PICTURE] Full profile data: $_userProfile');
        
        // Check common field names for profile picture URL
        profilePictureUrl = _userProfile!['profile_picture_url'] ?? 
                           _userProfile!['avatar_url'] ?? 
                           _userProfile!['profile_image_url'] ??
                           _userProfile!['picture_url'];
        print('🖼️ [PROFILE PICTURE] Profile picture URL from profile data: $profilePictureUrl');
        log('🖼️ [PROFILE PICTURE] Profile picture URL from profile data: $profilePictureUrl');
        print('🖼️ [PROFILE PICTURE] Profile data check completed!');
        log('🖼️ [PROFILE PICTURE] Profile data check completed!');
        print('🖼️ [PROFILE PICTURE] Profile data check successful!');
        log('🖼️ [PROFILE PICTURE] Profile data check successful!');
      } else {
        print('⚠️ [PROFILE PICTURE] No profile data available');
        log('⚠️ [PROFILE PICTURE] No profile data available');
        print('⚠️ [PROFILE PICTURE] Profile data check completed with no data!');
        log('⚠️ [PROFILE PICTURE] Profile data check completed with no data!');
        print('⚠️ [PROFILE PICTURE] Profile data check failed!');
        log('⚠️ [PROFILE PICTURE] Profile data check failed!');
      }
      
      // If not found in profile data, fetch it separately
      print('🖼️ [PROFILE PICTURE] Checking if URL is null or empty...');
      log('🖼️ [PROFILE PICTURE] Checking if URL is null or empty...');
      print('🖼️ [PROFILE PICTURE] profilePictureUrl: $profilePictureUrl');
      log('🖼️ [PROFILE PICTURE] profilePictureUrl: $profilePictureUrl');
      print('🖼️ [PROFILE PICTURE] profilePictureUrl is null: ${profilePictureUrl == null}');
      log('🖼️ [PROFILE PICTURE] profilePictureUrl is null: ${profilePictureUrl == null}');
      print('🖼️ [PROFILE PICTURE] profilePictureUrl is empty: ${profilePictureUrl?.isEmpty ?? true}');
      log('🖼️ [PROFILE PICTURE] profilePictureUrl is empty: ${profilePictureUrl?.isEmpty ?? true}');
      
      if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
        print('🔄 [PROFILE PICTURE] No URL in profile data, fetching from API...');
        log('🔄 [PROFILE PICTURE] No URL in profile data, fetching from API...');
        print('🔄 [PROFILE PICTURE] Calling ApiService.getUserProfilePictureUrl($userId)...');
        log('🔄 [PROFILE PICTURE] Calling ApiService.getUserProfilePictureUrl($userId)...');
        print('🔄 [PROFILE PICTURE] About to make API call...');
        log('🔄 [PROFILE PICTURE] About to make API call...');
        print('🔄 [PROFILE PICTURE] About to start API call process...');
        log('🔄 [PROFILE PICTURE] About to start API call process...');
        
        try {
          profilePictureUrl = await ApiService.getUserProfilePictureUrl(userId);
          print('✅ [PROFILE PICTURE] API call completed');
          log('✅ [PROFILE PICTURE] API call completed');
          print('🖼️ [PROFILE PICTURE] Profile picture URL from API: $profilePictureUrl');
          log('🖼️ [PROFILE PICTURE] Profile picture URL from API: $profilePictureUrl');
          print('✅ [PROFILE PICTURE] API call successful!');
          log('✅ [PROFILE PICTURE] API call successful!');
          print('✅ [PROFILE PICTURE] API call process completed successfully!');
          log('✅ [PROFILE PICTURE] API call process completed successfully!');
        } catch (apiError) {
          print('❌ [PROFILE PICTURE] API call failed: $apiError');
          log('❌ [PROFILE PICTURE] API call failed: $apiError');
          print('❌ [PROFILE PICTURE] API call error handled!');
          log('❌ [PROFILE PICTURE] API call error handled!');
          print('❌ [PROFILE PICTURE] API call process failed!');
          log('❌ [PROFILE PICTURE] API call process failed!');
          profilePictureUrl = null;
        }
      } else {
        print('✅ [PROFILE PICTURE] Found URL in profile data, skipping API call');
        log('✅ [PROFILE PICTURE] Found URL in profile data, skipping API call');
        print('✅ [PROFILE PICTURE] API call skipped successfully!');
        log('✅ [PROFILE PICTURE] API call skipped successfully!');
        print('✅ [PROFILE PICTURE] API call process skipped successfully!');
        log('✅ [PROFILE PICTURE] API call process skipped successfully!');
      }
      
      print('🖼️ [PROFILE PICTURE] Final profile picture URL: $profilePictureUrl');
      log('🖼️ [PROFILE PICTURE] Final profile picture URL: $profilePictureUrl');
      print('🖼️ [PROFILE PICTURE] URL is empty: ${profilePictureUrl?.isEmpty ?? true}');
      log('🖼️ [PROFILE PICTURE] URL is empty: ${profilePictureUrl?.isEmpty ?? true}');
      print('🖼️ [PROFILE PICTURE] URL is null: ${profilePictureUrl == null}');
      log('🖼️ [PROFILE PICTURE] URL is null: ${profilePictureUrl == null}');
      
      print('🖼️ [PROFILE PICTURE] Checking if widget is mounted...');
      log('🖼️ [PROFILE PICTURE] Checking if widget is mounted...');
      print('🖼️ [PROFILE PICTURE] Widget mounted: $mounted');
      log('🖼️ [PROFILE PICTURE] Widget mounted: $mounted');
      print('🖼️ [PROFILE PICTURE] About to check mounted state...');
      log('🖼️ [PROFILE PICTURE] About to check mounted state...');
      print('🖼️ [PROFILE PICTURE] About to start mounted state check...');
      log('🖼️ [PROFILE PICTURE] About to start mounted state check...');
      
      if (mounted) {
        print('🔄 [PROFILE PICTURE] Setting state with URL: $profilePictureUrl');
        log('🔄 [PROFILE PICTURE] Setting state with URL: $profilePictureUrl');
        print('🔄 [PROFILE PICTURE] About to call setState...');
        log('🔄 [PROFILE PICTURE] About to call setState...');
        print('🔄 [PROFILE PICTURE] About to start setState process...');
        log('🔄 [PROFILE PICTURE] About to start setState process...');
        setState(() {
          // Add cache-busting query to ensure latest image is fetched
          if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
            final ts = DateTime.now().millisecondsSinceEpoch;
            // If URL already has query params, append with &; else use ?
            final separator = profilePictureUrl.contains('?') ? '&' : '?';
            _profilePictureUrl = '$profilePictureUrl${separator}t=$ts';
          } else {
            _profilePictureUrl = profilePictureUrl;
          }
        });
        print('✅ [PROFILE PICTURE] State updated. New _profilePictureUrl: $_profilePictureUrl');
        log('✅ [PROFILE PICTURE] State updated. New _profilePictureUrl: $_profilePictureUrl');
        print('✅ [PROFILE PICTURE] setState completed successfully!');
        log('✅ [PROFILE PICTURE] setState completed successfully!');
        print('✅ [PROFILE PICTURE] setState process completed successfully!');
        log('✅ [PROFILE PICTURE] setState process completed successfully!');
        
        // Test if the URL is accessible
        print('🖼️ [PROFILE PICTURE] Testing URL accessibility...');
        log('🖼️ [PROFILE PICTURE] Testing URL accessibility...');
        print('🖼️ [PROFILE PICTURE] profilePictureUrl for testing: $profilePictureUrl');
        log('🖼️ [PROFILE PICTURE] profilePictureUrl for testing: $profilePictureUrl');
        print('🖼️ [PROFILE PICTURE] profilePictureUrl is null for testing: ${profilePictureUrl == null}');
        log('🖼️ [PROFILE PICTURE] profilePictureUrl is null for testing: ${profilePictureUrl == null}');
        print('🖼️ [PROFILE PICTURE] profilePictureUrl is empty for testing: ${profilePictureUrl?.isEmpty ?? true}');
        log('🖼️ [PROFILE PICTURE] profilePictureUrl is empty for testing: ${profilePictureUrl?.isEmpty ?? true}');
        print('🖼️ [PROFILE PICTURE] About to test URL accessibility...');
        log('🖼️ [PROFILE PICTURE] About to test URL accessibility...');
        print('🖼️ [PROFILE PICTURE] About to start URL testing process...');
        log('🖼️ [PROFILE PICTURE] About to start URL testing process...');
        
        if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
          print('🔍 [PROFILE PICTURE] Testing URL accessibility...');
          log('🔍 [PROFILE PICTURE] Testing URL accessibility...');
          try {
            final uri = Uri.parse(profilePictureUrl);
            print('✅ [PROFILE PICTURE] URL parsed successfully: $uri');
            log('✅ [PROFILE PICTURE] URL parsed successfully: $uri');
            print('🔍 [PROFILE PICTURE] URL scheme: ${uri.scheme}');
            log('🔍 [PROFILE PICTURE] URL scheme: ${uri.scheme}');
            print('🔍 [PROFILE PICTURE] URL host: ${uri.host}');
            log('🔍 [PROFILE PICTURE] URL host: ${uri.host}');
            print('🔍 [PROFILE PICTURE] URL path: ${uri.path}');
            log('🔍 [PROFILE PICTURE] URL path: ${uri.path}');
            print('✅ [PROFILE PICTURE] URL testing completed successfully!');
            log('✅ [PROFILE PICTURE] URL testing completed successfully!');
            print('✅ [PROFILE PICTURE] URL testing process completed successfully!');
            log('✅ [PROFILE PICTURE] URL testing process completed successfully!');
          } catch (e) {
            print('❌ [PROFILE PICTURE] Error parsing profile picture URL: $e');
            log('❌ [PROFILE PICTURE] Error parsing profile picture URL: $e');
            print('❌ [PROFILE PICTURE] URL testing failed!');
            log('❌ [PROFILE PICTURE] URL testing failed!');
            print('❌ [PROFILE PICTURE] URL testing process failed!');
            log('❌ [PROFILE PICTURE] URL testing process failed!');
          }
        } else {
          print('⚠️ [PROFILE PICTURE] No valid URL to test');
          log('⚠️ [PROFILE PICTURE] No valid URL to test');
          print('⚠️ [PROFILE PICTURE] URL testing skipped!');
          log('⚠️ [PROFILE PICTURE] URL testing skipped!');
          print('⚠️ [PROFILE PICTURE] URL testing process skipped!');
          log('⚠️ [PROFILE PICTURE] URL testing process skipped!');
        }
      } else {
        print('⚠️ [PROFILE PICTURE] Widget not mounted, skipping state update');
        log('⚠️ [PROFILE PICTURE] Widget not mounted, skipping state update');
        print('⚠️ [PROFILE PICTURE] State update skipped!');
        log('⚠️ [PROFILE PICTURE] State update skipped!');
        print('⚠️ [PROFILE PICTURE] State update process skipped!');
        log('⚠️ [PROFILE PICTURE] State update process skipped!');
      }
      
      print('🖼️ [PROFILE PICTURE] ===== PROFILE PICTURE LOAD COMPLETED =====');
      log('🖼️ [PROFILE PICTURE] ===== PROFILE PICTURE LOAD COMPLETED =====');
      print('🖼️ [PROFILE PICTURE] Profile picture loading method completed successfully!');
      log('🖼️ [PROFILE PICTURE] Profile picture loading method completed successfully!');
      print('🖼️ [PROFILE PICTURE] Profile picture loading process completed successfully!');
      log('🖼️ [PROFILE PICTURE] Profile picture loading process completed successfully!');
    } catch (e) {
      print('❌ [PROFILE PICTURE] Error loading profile picture: $e');
      log('❌ [PROFILE PICTURE] Error loading profile picture: $e');
      print('❌ [PROFILE PICTURE] Stack trace: ${StackTrace.current}');
      log('❌ [PROFILE PICTURE] Stack trace: ${StackTrace.current}');
      print('❌ [PROFILE PICTURE] Profile picture loading method failed!');
      log('❌ [PROFILE PICTURE] Profile picture loading method failed!');
      print('❌ [PROFILE PICTURE] Profile picture loading process failed!');
      log('❌ [PROFILE PICTURE] Profile picture loading process failed!');
    }
  }

  Future<void> _onCalendarUpdated() async {
    await _loadUpcomingEvent();
    await _loadNotices();
  }

  Future<void> _loadUpcomingEvent() async {
    try {
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);

      Future<Map<String, dynamic>?> findInMonth(int year, int month) async {
        final data = await ApiService.getCalendarMonth(year, month);
        final List items = [];

        // Holidays/titled days
        List daysList = [];
        if (data['days'] != null) {
          daysList = data['days'] as List;
        } else if (data['data'] != null && data['data']['days'] != null) {
          daysList = data['data']['days'] as List;
        }
        for (final d in daysList) {
          final dateStr = d['date'] as String?;
          if (dateStr == null) continue;
          final title = (d['title'] ?? '').toString();
          final isHoliday = (d['is_holiday'] ?? 0) == 1;
          if (title.isEmpty && !isHoliday) continue;
          final dt = DateTime.parse(dateStr);
          final dayKey = DateTime(dt.year, dt.month, dt.day);
          if (dayKey.isBefore(today)) continue;
          items.add({
            'date': dayKey,
            'title': title.isNotEmpty ? title : 'Holiday',
            'description': (d['description'] ?? d['details'] ?? '')?.toString(),
          });
        }

        // User events
        List evs = [];
        if (data['events'] != null) {
          evs = data['events'] as List;
        } else if (data['data'] != null && data['data']['events'] != null) {
          evs = data['data']['events'] as List;
        } else if (data['calendar_events'] != null) {
          evs = data['calendar_events'] as List;
        }
        for (final e in evs) {
          final dateStr = e['date'] as String?;
          if (dateStr == null) continue;
          final dt = DateTime.parse(dateStr);
          final dayKey = DateTime(dt.year, dt.month, dt.day);
          if (dayKey.isBefore(today)) continue;
          final title = (e['title'] ?? e['name'] ?? '').toString();
          if (title.isEmpty) continue;
          items.add({
            'date': dayKey,
            'title': title,
            'description': (e['description'] ?? e['details'] ?? e['body'] ?? '')?.toString(),
          });
        }

        if (items.isEmpty) return null;
        items.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
        return items.first as Map<String, dynamic>;
      }

      // Try current month, then next month
      final foundCurrent = await findInMonth(today.year, today.month);
      final nextMonthDate = DateTime(today.year, today.month + 1, 1);
      final foundNext = foundCurrent ?? await findInMonth(nextMonthDate.year, nextMonthDate.month);

      if (!mounted) return;
      setState(() {
        _upcomingEventDate = foundNext != null ? foundNext['date'] as DateTime : null;
        _upcomingEventTitle = foundNext != null ? foundNext['title'] as String : null;
        _upcomingEventDesc = foundNext != null ? (foundNext['description'] as String?) : null;
      });
    } catch (e) {
      // Silent fail to keep home rendering
      if (!mounted) return;
      setState(() {
        _upcomingEventDate = null;
        _upcomingEventTitle = null;
        _upcomingEventDesc = null;
      });
    }
  }

  String _formatDayMonth(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  // Build a display label for the student's class from profile data
  // Example: "9 (Computer)" if batch/stream exists, otherwise just "9"
  String _classLabel() {
    final cls = (_userProfile?['class'] ?? '').toString().trim();
    final batch = (_userProfile?['batch'] ?? '').toString().trim();
    if (cls.isEmpty) return 'Class';
    if (batch.isEmpty) return cls;
    return '$cls ($batch)';
  }

  // Course color palette helpers
  final List<Color> _coursePalette = const [
    Color(0xFF1E3A8A),
    Color(0xFF1E3A8A),
    Color(0xFF1E3A8A),
    Color(0xFF1E3A8A),
    Color(0xFF1E3A8A),
  ];
  Color _courseColor(int index) => _coursePalette[index % _coursePalette.length];

  String _courseTitle(Map<String, dynamic> m) {
    final name = (m['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final subject = (m['subject_name'] ?? '').toString().trim();
    if (subject.isNotEmpty) return subject;
    return 'Course';
  }

  // Infer education level from class name to help backend resolve by names
  // Returns one of: 'EarlyYears', 'Primary', 'Secondary', or null if unknown
  String? _inferLevelForClass(String? raw) {
    if (raw == null) return null;
    final c = raw.trim();
    if (c.isEmpty) return null;
    // If contains a digit, treat numerically
    final match = RegExp(r"\d+").firstMatch(c);
    if (match != null) {
      final n = int.tryParse(match.group(0)!);
      if (n != null) {
        if (n >= 8) return 'Secondary';
        if (n >= 1) return 'Primary';
      }
    }
    // Early Years common labels
    final s = c.toLowerCase();
    const early = {
      'montessori', 'nursery', 'prep', 'kg', 'k.g', 'playgroup', 'play group',
      'kindergarten', 'pre-school', 'preschool'
    };
    if (early.contains(s)) return 'EarlyYears';
    return null;
  }

  Widget _buildAttendanceScreen() {
    // Placeholder list reflecting an attendance detail list
    final items = [
      {
        'date': '01/01/2025, 09:00 AM',
        'class': 'Subject Name',
        'topic': 'Topic Name',
        'present': true,
      },
      {
        'date': '02/01/2025, 09:00 AM',
        'class': 'Subject Name',
        'topic': 'Topic Name',
        'present': false,
      },
      {
        'date': '03/01/2025, 09:00 AM',
        'class': 'Subject Name',
        'topic': 'Topic Name',
        'present': true,
      },
    ];

    Color statusColor(bool present) => present ? const Color(0xFF1E3A8A) : const Color(0xFF1E3A8A);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0),
        child: Padding(
          padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showAttendance = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFF1E3A8A),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Attendance',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final it = items[index];
          final present = it['present'] as bool;
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE7E0DE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (Theme.of(context).brightness == Brightness.dark)
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFFD9D2D0),
                  width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor(present).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor(present), width: 1),
                  ),
                  child: Icon(
                    present ? Icons.check : Icons.close,
                    size: 20,
                    color: statusColor(present),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it['date'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        it['class'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        it['topic'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor(present).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor(present), width: 1),
                  ),
                  child: Text(
                    present ? 'Present' : 'Absent',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor(present),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAttendanceDetailsDialog() async {
    // Determine the current user ID (works for both students and admins)
    final userId = await ApiService.getCurrentUserId();
    if (userId == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Attendance Details'),
          content: const Text('Unable to determine current user.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    // Loading indicator while fetching
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> items = const [];
    String? error;
    try {
      items = await ApiService.getUserAttendance(userId);
      // Sort by date descending if possible
      items.sort((a, b) {
        final sa = (a['date'] ?? '').toString();
        final sb = (b['date'] ?? '').toString();
        DateTime? da, db;
        try { da = DateTime.parse(sa); } catch (_) {}
        try { db = DateTime.parse(sb); } catch (_) {}
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) Navigator.of(context).pop(); // close loader
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Attendance Details'),
          content: SizedBox(
            width: 480,
            height: 420,
            child: error != null
                ? SingleChildScrollView(child: Text(error))
                : (items.isEmpty
                    ? const Center(child: Text('No attendance records found.'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Counts row
                          Row(
                            children: [
                              _buildCountChip('Present: $_countPresent', const Color(0xFF1E3A8A)),
                              const SizedBox(width: 8),
                              _buildCountChip('Absent: $_countAbsent', const Color(0xFF1E3A8A)),
                              const SizedBox(width: 8),
                              _buildCountChip('Leave: $_countLeave', const Color(0xFF1E3A8A)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 12),
                              itemBuilder: (context, index) {
                                final it = items[index];
                                final dateStr = (it['date'] ?? '').toString();
                                final statusRaw = (it['status'] ?? '').toString().toLowerCase();
                                final remarks = (it['remarks'] ?? it['note'] ?? '').toString();

                                Color statusColor;
                                String statusLabel;
                                switch (statusRaw) {
                                  case 'present':
                                    statusColor = const Color(0xFF1E3A8A);
                                    statusLabel = 'Present';
                                    break;
                                  case 'absent':
                                    statusColor = const Color(0xFF1E3A8A);
                                    statusLabel = 'Absent';
                                    break;
                                  case 'leave':
                                    statusColor = const Color(0xFF1E3A8A);
                                    statusLabel = 'Leave';
                                    break;
                                  default:
                                    statusColor = Theme.of(context).colorScheme.primary;
                                    statusLabel = statusRaw.isEmpty ? 'Unknown' : statusRaw;
                                }

                                String prettyDate = dateStr;
                                try {
                                  final d = DateTime.parse(dateStr);
                                  prettyDate = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                                } catch (_) {}

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            prettyDate,
                                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                          if (remarks.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              remarks,
                                              style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: statusColor, width: 1),
                                      ),
                                      child: Text(
                                        statusLabel,
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      )),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          ResponsiveHelper.isMobile(context) 
              ? _buildMobileLayout()
              : _buildDesktopLayout(),
          if (!_showChatSidebar) _buildDraggableChatButton(),
        ],
      ),
    );
  }

  Widget _buildDraggableChatButton() {
    return Positioned(
      left: _chatButtonPosition.dx,
      top: _chatButtonPosition.dy,
      child: Draggable(
        feedback: _buildChatButton(isDragging: true),
        childWhenDragging: Container(), // Hide original when dragging
        onDragEnd: (details) {
          setState(() {
            // Keep button within screen bounds
            final screenSize = MediaQuery.of(context).size;
            _chatButtonPosition = Offset(
              details.offset.dx.clamp(0, screenSize.width - 140), // Account for button width
              details.offset.dy.clamp(0, screenSize.height - 60), // Account for button height
            );
          });
        },
        child: _buildChatButton(),
      ),
    );
  }

  Widget _buildChatButton({bool isDragging = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: isDragging ? null : () {
        // Add a small haptic feedback for better UX
        // HapticFeedback.lightImpact(); // Uncomment if you want haptic feedback
        _showChatPopupAtButton();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat,
              color: isDark ? Colors.black : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Chat Assistant',
              style: TextStyle(
                color: isDark ? Colors.black : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatPopupAtButton() {
    setState(() {
      _isChatFullscreen = false; // Reset to normal size when opening
    });
    
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final isMobile = ResponsiveHelper.isMobile(context);
            final screenSize = MediaQuery.of(context).size;
            final buttonHeight = 48.0;
            
            // Dynamic sizing based on fullscreen state
            final popupWidth = _isChatFullscreen 
                ? screenSize.width * 0.95 
                : (isMobile ? screenSize.width * 0.85 : 400.0);
            final popupHeight = _isChatFullscreen 
                ? screenSize.height * 0.95 
                : (isMobile ? screenSize.height * 0.7 : 500.0);
            
            // Calculate position
            double left = _isChatFullscreen 
                ? (screenSize.width - popupWidth) / 2 
                : _chatButtonPosition.dx;
            double top = _isChatFullscreen 
                ? (screenSize.height - popupHeight) / 2 
                : _chatButtonPosition.dy + buttonHeight + 10;
            
            // Adjust if popup would go off screen (only for normal size)
            if (!_isChatFullscreen) {
              if (left + popupWidth > screenSize.width) {
                left = screenSize.width - popupWidth - 20;
              }
              if (top + popupHeight > screenSize.height) {
                top = _chatButtonPosition.dy - popupHeight - 10;
              }
              if (top < 0) {
                top = 20;
              }
            }
            
            // Scale animation
            final scaleAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.elasticOut,
            ));
            
            final fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ));
            
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: ScaleTransition(
                    scale: scaleAnimation,
                    alignment: Alignment.topLeft,
                    child: FadeTransition(
                      opacity: fadeAnimation,
                      child: Container(
                        width: popupWidth,
                        height: popupHeight,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0B0F14) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Custom header with fullscreen toggle
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.chat,
                                      color: isDark ? Colors.black : Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Chat Assistant',
                                    style: TextStyle(
                                      color: isDark ? Colors.black : Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Fullscreen toggle button
                                  IconButton(
                                    icon: Icon(
                                      _isChatFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: isDark ? Colors.black : Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isChatFullscreen = !_isChatFullscreen;
                                      });
                                      setDialogState(() {});
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close,
                                        color: isDark ? Colors.black : Colors.white, size: 20),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ],
                              ),
                            ),
                            // Chat content
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: SidebarChatWidget(
                                  onClose: () => Navigator.of(context).pop(),
                                  showHeader: false, // Hide header since we have custom one
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    return Stack(
      children: [
        // Main content
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Mobile app bar
                _buildMobileAppBar(),
                // Content
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _buildCurrentScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Mobile drawer overlay
        if (_isNavExpanded)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => setState(() => _isNavExpanded = false),
              child: Container(
                width: ResponsiveHelper.screenWidth(context),
                color: Colors.black54,
                child: GestureDetector(
                  onTap: () {}, // Prevent closing when tapping drawer
                  child: VerticalNavBar(
                    selectedIndex: _selectedNavIndex,
                    onItemSelected: _handleNavSelection,
                    isExpanded: _isNavExpanded,
                    onToggleExpanded: (expanded) {
            setState(() => _isNavExpanded = expanded);
          },
          showAddStudent: _isSuperAdminUser(),
                    showCourses: _currentUser == null || 
                                !(_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'),
                    showCourseAssignment: _currentUser != null && 
                                         (_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'),
                    showAdminDues: _currentUser != null && 
                                 (_currentUser!['is_super_admin'] == 1 || 
                                  _currentUser!['is_super_admin'] == '1'),
                    showStudentDues: _currentUser == null || !(
                      (_currentUser!['role']?.toString().toLowerCase() == 'admin') ||
                      _currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'
                    ),
                    showTakeAttendance: _currentUser != null && (
                      _currentUser!['role']?.toString().toLowerCase() == 'admin' ||
                      _currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'
                    ),
                    showAcademicRecords: _canAccessAcademicRecords(),
                    showGenerateTicket: _currentUser != null && (
                      _currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1' ||
                      _currentUser!['role']?.toString().toLowerCase() == 'student'
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Chat sidebar overlay
        if (_showChatSidebar)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showChatSidebar = false),
              child: Container(
                color: Colors.black54,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {}, // Prevent closing when tapping sidebar
                    child: SidebarChatWidget(
                      onClose: () => setState(() => _showChatSidebar = false),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Vertical Navigation
        VerticalNavBar(
          selectedIndex: _selectedNavIndex,
          onItemSelected: _handleNavSelection,
          isExpanded: _isNavExpanded,
          onToggleExpanded: (expanded) {
            setState(() {
              _isNavExpanded = expanded;
            });
          },
          // Show Manage Members only to superadmins
          showAddStudent: _isSuperAdminUser(),
          showCourses: _currentUser == null || 
                      !(_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'),
          showCourseAssignment: _currentUser != null && 
                               (_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'),
          showAdminDues: _currentUser != null && 
                       (_currentUser!['is_super_admin'] == 1 || 
                        _currentUser!['is_super_admin'] == '1'),
          showStudentDues: _currentUser == null || !(
            (_currentUser!['role']?.toString().toLowerCase() == 'admin') ||
            _currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'
          ),
          showTakeAttendance: _currentUser != null && (
            _currentUser!['role']?.toString().toLowerCase() == 'admin' ||
            _currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'
          ),
          showAcademicRecords: _canAccessAcademicRecords(),
          showGenerateTicket: _currentUser != null && (
            _currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1' ||
            _currentUser!['role']?.toString().toLowerCase() == 'student'
          ),
        ),
        
        // Main Content Area
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: _buildCurrentScreen(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentScreen() {
    // If course details is active, show it regardless of nav index
    if (_showCourseDetails) {
      return _buildCourseDetailsScreen();
    }
    // If lectures is active, show it regardless of nav index
    if (_showLectures) {
      return _buildLecturesScreen();
    }
    // If attendance is active, show it regardless of nav index
    if (_showAttendance) {
      return _buildAttendanceScreen();
    }
    
    switch (_selectedNavIndex) {
      case 0: // Dashboard
      case 1: // Home - Same as Dashboard
        return _buildHomeScreen();
      case 2: // Courses
        return _buildCoursesScreen();
      case 3: // Dues
        return _buildDuesScreen();
      case 4: // Profile
        return _buildProfileScreen();
      case 5: // Settings
        return SettingsScreen(
          onBack: () {
            setState(() {
              _selectedNavIndex = 1; // Home
              _showCourseDetails = false;
              _showLectures = false;
              _showAttendance = false;
            });
          },
        );
      case 7: // Course Assignment
        return CourseAssignmentScreen(key: CourseAssignmentScreen.globalKey);
      case 8: // Admin Dues
        return AdminDuesScreen();
      case 9: // Take Attendance
        return TeacherAttendanceScreen(
          onBack: () {
            setState(() {
              _selectedNavIndex = 1; // Home
              _showCourseDetails = false;
              _showLectures = false;
              _showAttendance = false;
            });
          },
        );
      case 10: // Generate Ticket
        return GenerateTicketScreen(
          key: GenerateTicketScreen.globalKey,
          onBack: () {
            setState(() {
              _selectedNavIndex = 1; // Home
              _showCourseDetails = false;
              _showLectures = false;
              _showAttendance = false;
            });
          },
        );
      case 11: // Academic Records
        return const AcademicDashboardScreen();
      default:
        return _buildHomeScreen();
    }
  }

  String _getCurrentScreenName() {
    if (_showCourseDetails) return 'Course Details';
    if (_showLectures) return 'Lectures';
    if (_showAttendance) return 'Attendance';
    
    switch (_selectedNavIndex) {
      case 0: return 'Menu';
      case 1: return 'Dashboard';
      case 2: return 'Courses';
      case 3: return 'Dues';
      case 4: return 'Profile';
      case 5: return 'Settings';
      case 7: return 'Assign Courses';
      case 8: return 'Admin Dues';
      case 9: return 'Take Attendance';
      case 10: return 'Generate Ticket';
      case 11: return 'Academic Records';
      default: return 'Dashboard';
    }
  }

  Widget _buildMobileAppBar() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color barColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: barColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _isNavExpanded = true),
            icon: const Icon(
              Icons.menu,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          if (_selectedNavIndex != 10)
            Expanded(
              child: Text(
                _getCurrentScreenName(),
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          else
            Expanded(
              child: Text(
                'Tickets',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          if (_selectedNavIndex == 7) ...[
            const SizedBox(width: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final double w = MediaQuery.of(context).size.width;
                // Use icon-only on very small widths to avoid overflow
                if (w < 360) {
                  return IconButton(
                    icon: const Icon(Icons.save, color: Colors.white, size: 22),
                    tooltip: 'Save',
                    onPressed: () {
                      CourseAssignmentScreen.globalKey.currentState?.saveAssignments();
                    },
                  );
                }
                return TextButton.icon(
                  onPressed: () {
                    CourseAssignmentScreen.globalKey.currentState?.saveAssignments();
                  },
                  icon: const Icon(Icons.save, color: Colors.white, size: 20),
                  label: Text(
                    'Save',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                );
              },
            ),
          ]
          else if (_selectedNavIndex == 10) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
              tooltip: 'Refresh',
              onPressed: () {
                GenerateTicketScreen.globalKey.currentState?.refreshTickets();
              },
            ),
          ],
        ],
      ),
    );
  }

  void _handleNavSelection(int index) {
    if (index == 6) {
      final bool isSuperAdmin = _isSuperAdminUser();
      if (!isSuperAdmin) return; // block non-superadmin
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddNewUserScreen(
            showAddStudent: true,
            showCourses: false,
            showCourseAssignment: true,
            showAdminDues: true,
            showStudentDues: false,
          ),
        ),
      );
      return;
    }

    if (index == 11) {
      _openAcademicRecords();
      return;
    }
    
    // If navigating to profile screen, refresh profile picture
    if (index == 4) {
      _refreshProfilePicture();
    }
    
    setState(() {
      _selectedNavIndex = index;
      _showCourseDetails = false;
      _showLectures = false;
      _showAttendance = false;
    });
  }

  Future<void> _refreshProfilePictureOnReturn() async {
    print('🔄 [REFRESH] ===== REFRESHING PROFILE PICTURE ON RETURN =====');
    log('🔄 [REFRESH] ===== REFRESHING PROFILE PICTURE ON RETURN =====');
    print('🔄 [REFRESH] Refresh method called successfully!');
    log('🔄 [REFRESH] Refresh method called successfully!');
    print('🔄 [REFRESH] About to refresh profile picture on return...');
    log('🔄 [REFRESH] About to refresh profile picture on return...');
    print('🔄 [REFRESH] About to start profile picture refresh process...');
    log('🔄 [REFRESH] About to start profile picture refresh process...');
    
    // Small delay to ensure profile screen has loaded
    await Future.delayed(const Duration(milliseconds: 100));
    print('🔄 [REFRESH] Delay completed, getting user ID...');
    log('🔄 [REFRESH] Delay completed, getting user ID...');
    
    // Refresh profile picture when returning from profile screen
    final userId = await ApiService.getCurrentUserId();
    if (userId != null) {
      print('🔄 [REFRESH] User ID found: $userId, loading profile picture...');
      log('🔄 [REFRESH] User ID found: $userId, loading profile picture...');
      await _loadProfilePicture(userId);
    } else {
      print('❌ [REFRESH] No user ID found for refresh');
      log('❌ [REFRESH] No user ID found for refresh');
    }
    
    print('🔄 [REFRESH] ===== REFRESH ON RETURN COMPLETED =====');
    log('🔄 [REFRESH] ===== REFRESH ON RETURN COMPLETED =====');
    print('🔄 [REFRESH] Refresh on return method completed successfully!');
    log('🔄 [REFRESH] Refresh on return method completed successfully!');
  }

  Future<void> _refreshProfilePicture() async {
    print('🔄 [REFRESH] ===== MANUAL PROFILE PICTURE REFRESH =====');
    log('🔄 [REFRESH] ===== MANUAL PROFILE PICTURE REFRESH =====');
    print('🔄 [REFRESH] Manual refresh method called successfully!');
    log('🔄 [REFRESH] Manual refresh method called successfully!');
    print('🔄 [REFRESH] About to refresh profile picture manually...');
    log('🔄 [REFRESH] About to refresh profile picture manually...');
    print('🔄 [REFRESH] About to start manual profile picture refresh process...');
    log('🔄 [REFRESH] About to start manual profile picture refresh process...');
    
    final userId = await ApiService.getCurrentUserId();
    if (userId != null) {
      print('🔄 [REFRESH] User ID found: $userId, loading profile picture...');
      log('🔄 [REFRESH] User ID found: $userId, loading profile picture...');
      await _loadProfilePicture(userId);
    } else {
      print('❌ [REFRESH] No user ID found for manual refresh');
      log('❌ [REFRESH] No user ID found for manual refresh');
    }
    
    print('🔄 [REFRESH] ===== MANUAL REFRESH COMPLETED =====');
    log('🔄 [REFRESH] ===== MANUAL REFRESH COMPLETED =====');
    print('🔄 [REFRESH] Manual refresh method completed successfully!');
    log('🔄 [REFRESH] Manual refresh method completed successfully!');
  }

  Future<void> _testProfilePictureAPI() async {
    try {
      print('🧪 [TEST] ===== TESTING PROFILE PICTURE API =====');
      log('🧪 [TEST] ===== TESTING PROFILE PICTURE API =====');
      print('🧪 [TEST] Test method called successfully!');
      log('🧪 [TEST] Test method called successfully!');
      print('🧪 [TEST] About to test profile picture API...');
      log('🧪 [TEST] About to test profile picture API...');
      print('🧪 [TEST] About to start profile picture API testing process...');
      log('🧪 [TEST] About to start profile picture API testing process...');
      print('🧪 [TEST] About to begin profile picture API testing process...');
      log('🧪 [TEST] About to begin profile picture API testing process...');
      
      final userId = await ApiService.getCurrentUserId();
      if (userId != null) {
        print('🧪 [TEST] User ID: $userId');
        log('🧪 [TEST] User ID: $userId');
        print('🧪 [TEST] Calling ApiService.getUserProfilePictureUrl($userId)...');
        log('🧪 [TEST] Calling ApiService.getUserProfilePictureUrl($userId)...');
        print('🧪 [TEST] About to make API call...');
        log('🧪 [TEST] About to make API call...');
        
        final url = await ApiService.getUserProfilePictureUrl(userId);
        print('🧪 [TEST] API call completed');
        log('🧪 [TEST] API call completed');
        print('🧪 [TEST] Test result - Profile picture URL: $url');
        log('🧪 [TEST] Test result - Profile picture URL: $url');
        print('🧪 [TEST] URL is null: ${url == null}');
        log('🧪 [TEST] URL is null: ${url == null}');
        print('🧪 [TEST] URL is empty: ${url?.isEmpty ?? true}');
        log('🧪 [TEST] URL is empty: ${url?.isEmpty ?? true}');
        print('🧪 [TEST] API call successful!');
        log('🧪 [TEST] API call successful!');
        print('🧪 [TEST] API call process completed successfully!');
        log('🧪 [TEST] API call process completed successfully!');
        
        if (url != null && url.isNotEmpty) {
          print('✅ [TEST] Profile picture found!');
          log('✅ [TEST] Profile picture found!');
          print('✅ [TEST] Showing success snackbar...');
          log('✅ [TEST] Showing success snackbar...');
          print('✅ [TEST] About to show success snackbar...');
          log('✅ [TEST] About to show success snackbar...');
          print('✅ [TEST] About to start success snackbar process...');
          log('✅ [TEST] About to start success snackbar process...');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Profile picture found: $url', style: GoogleFonts.inter()),
              backgroundColor: const Color(0xFF1E3A8A),
            ),
          );
          print('✅ [TEST] Success snackbar shown!');
          log('✅ [TEST] Success snackbar shown!');
          print('✅ [TEST] Success snackbar process completed!');
          log('✅ [TEST] Success snackbar process completed!');
        } else {
          print('⚠️ [TEST] No profile picture found');
          log('⚠️ [TEST] No profile picture found');
          print('⚠️ [TEST] Showing warning snackbar...');
          log('⚠️ [TEST] Showing warning snackbar...');
          print('⚠️ [TEST] About to show warning snackbar...');
          log('⚠️ [TEST] About to show warning snackbar...');
          print('⚠️ [TEST] About to start warning snackbar process...');
          log('⚠️ [TEST] About to start warning snackbar process...');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No profile picture found', style: GoogleFonts.inter()),
              backgroundColor: const Color(0xFF1E3A8A),
            ),
          );
          print('⚠️ [TEST] Warning snackbar shown!');
          log('⚠️ [TEST] Warning snackbar shown!');
          print('⚠️ [TEST] Warning snackbar process completed!');
          log('⚠️ [TEST] Warning snackbar process completed!');
        }
      } else {
        print('❌ [TEST] No user ID available');
        log('❌ [TEST] No user ID available');
        print('❌ [TEST] Showing error snackbar...');
        log('❌ [TEST] Showing error snackbar...');
        print('❌ [TEST] About to show error snackbar...');
        log('❌ [TEST] About to show error snackbar...');
        print('❌ [TEST] About to start error snackbar process...');
        log('❌ [TEST] About to start error snackbar process...');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No user ID available', style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF1E3A8A),
          ),
        );
        print('❌ [TEST] Error snackbar shown!');
        log('❌ [TEST] Error snackbar shown!');
        print('❌ [TEST] Error snackbar process completed!');
        log('❌ [TEST] Error snackbar process completed!');
      }
      
      print('🧪 [TEST] ===== TEST COMPLETED =====');
      log('🧪 [TEST] ===== TEST COMPLETED =====');
      print('🧪 [TEST] Test method completed successfully!');
      log('🧪 [TEST] Test method completed successfully!');
    } catch (e) {
      print('❌ [TEST] Error testing profile picture API: $e');
      log('❌ [TEST] Error testing profile picture API: $e');
      print('❌ [TEST] Stack trace: ${StackTrace.current}');
      log('❌ [TEST] Stack trace: ${StackTrace.current}');
      print('❌ [TEST] Showing error snackbar...');
      log('❌ [TEST] Showing error snackbar...');
      print('❌ [TEST] About to show error snackbar...');
      log('❌ [TEST] About to show error snackbar...');
      print('❌ [TEST] About to start error snackbar process...');
      log('❌ [TEST] About to start error snackbar process...');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFF1E3A8A),
        ),
      );
      print('❌ [TEST] Error snackbar shown!');
      log('❌ [TEST] Error snackbar shown!');
      print('❌ [TEST] Error snackbar process completed!');
      log('❌ [TEST] Error snackbar process completed!');
      print('❌ [TEST] Test method failed!');
      log('❌ [TEST] Test method failed!');
      print('❌ [TEST] Test method process failed!');
      log('❌ [TEST] Test method process failed!');
    }
  }

  bool _isTeacherAdmin() {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    final isSuperAdmin = _currentUser?['is_super_admin'] == 1 || _currentUser?['is_super_admin'] == '1';
    final classTeacherOf = (_userProfile?['class_teacher_of'] ?? '').toString().trim();
    final isTeacherAdmin = role == 'admin' && !isSuperAdmin && classTeacherOf.isNotEmpty;
    return isTeacherAdmin;
  }

  bool _shouldShowAddUserActions() {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    if (role != 'admin') return false;
    if (_isTeacherAdmin()) return false;
    return true;
  }

  bool _isSuperAdminUser() {
    return _currentUser?['is_super_admin'] == 1 || _currentUser?['is_super_admin'] == '1';
  }

  bool _canAccessAcademicRecords() {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    final isSuperAdmin = _currentUser?['is_super_admin'] == 1 || _currentUser?['is_super_admin'] == '1';
    return role == 'student' || role == 'admin' || isSuperAdmin;
  }

  Widget _buildAttendanceCalendarSection() {
    if (ResponsiveHelper.isMobile(context)) {
      // Stack vertically on mobile
      return Column(
        children: [
          _buildAttendancePieChart(),
          const SizedBox(height: 20),
          CalendarWidget(
            canAddEvents: _canAddEvents,
            onEventsChanged: _onCalendarUpdated,
            canDeleteEvents: () {
              final canDelete = _currentUser != null && (_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1');
              print('🔐 CalendarWidget canDeleteEvents: $canDelete (user: ${_currentUser?['name']}, is_super_admin: ${_currentUser?['is_super_admin']})');
              return canDelete;
            }(),
          ),
        ],
      );
    } else {
      // Side by side on tablet/desktop
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: ResponsiveHelper.isTablet(context) ? 1 : 1,
            child: _buildAttendancePieChart(),
          ),
          SizedBox(
            width: ResponsiveHelper.responsiveValue(
              context,
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          Expanded(
            flex: ResponsiveHelper.isTablet(context) ? 2 : 2,
            child: CalendarWidget(
              canAddEvents: _canAddEvents,
              onEventsChanged: _onCalendarUpdated,
              canDeleteEvents: () {
              final canDelete = _currentUser != null && (_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1');
              print('🔐 CalendarWidget canDeleteEvents: $canDelete (user: ${_currentUser?['name']}, is_super_admin: ${_currentUser?['is_super_admin']})');
              return canDelete;
            }(),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      padding: ResponsiveHelper.isMobile(context) ? EdgeInsets.zero : ResponsiveHelper.getContentPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name Section with Profile Picture (with padding on mobile)
          ResponsiveHelper.isMobile(context) 
            ? Padding(
                padding: ResponsiveHelper.getContentPadding(context),
                child: _buildNameSection(),
              )
            : _buildNameSection(),
          SizedBox(
            height: ResponsiveHelper.getSpacing(context, size: 'lg'),
          ),
          
          // Three Boxes: Event, Quizzes, Pending Assignment (full width on mobile)
          _buildThreeBoxesSection(),
          SizedBox(
            height: ResponsiveHelper.getSpacing(context, size: 'lg'),
          ),
          
          // Attendance and Calendar Section (responsive layout)
          ResponsiveHelper.isMobile(context) 
            ? Padding(
                padding: ResponsiveHelper.getContentPadding(context),
                child: _buildAttendanceCalendarSection(),
              )
            : _buildAttendanceCalendarSection(),
          SizedBox(
            height: ResponsiveHelper.getSpacing(context, size: 'lg'),
          ),
          
          // 5. Notice Board (moved above courses)
          ResponsiveHelper.isMobile(context) 
            ? Padding(
                padding: ResponsiveHelper.getContentPadding(context),
                child: _buildBottomNoticeBoard(),
              )
            : _buildBottomNoticeBoard(),
          SizedBox(
            height: ResponsiveHelper.getSpacing(context, size: 'xl'),
          ),
          
          // 6. Courses Section with Enrolled Courses (hidden for Super Admin)
          if (!(_currentUser?['is_super_admin'] == 1 || _currentUser?['is_super_admin'] == '1'))
            _buildCoursesSection(),
        ],
      ),
    );
  }

  Widget _buildCoursesScreen() {
    return CoursesScreen(
      onViewDetails: (course) {
        setState(() {
          _selectedCourse = {
            'name': course.name,
            'class_name': course.className,
            'subject_name': course.subjectName,
            'teacher_name': '',
            'class_id': course.classId,
            'subject_id': course.subjectId,
          };
          _selectedCourseColor = course.color;
          _showCourseDetails = true;
        });
      },
    );
  }

  Widget _buildDuesScreen() {
    return DuesScreen();
  }

  Widget _buildProfileScreen() {
    print('🖼️ [PROFILE SCREEN] Building profile screen with callback');
    log('🖼️ [PROFILE SCREEN] Building profile screen with callback');
    print('🖼️ [PROFILE SCREEN] Profile screen building method called successfully!');
    log('🖼️ [PROFILE SCREEN] Profile screen building method called successfully!');
    print('🖼️ [PROFILE SCREEN] About to build profile screen...');
    log('🖼️ [PROFILE SCREEN] About to build profile screen...');
    print('🖼️ [PROFILE SCREEN] About to start profile screen building process...');
    log('🖼️ [PROFILE SCREEN] About to start profile screen building process...');
    
    return ProfileScreen(
      onProfileUpdated: () async {
        print('🖼️ [PROFILE SCREEN] Profile updated callback triggered');
        log('🖼️ [PROFILE SCREEN] Profile updated callback triggered');
        print('🖼️ [PROFILE SCREEN] Profile updated callback method called successfully!');
        log('🖼️ [PROFILE SCREEN] Profile updated callback method called successfully!');
        print('🖼️ [PROFILE SCREEN] About to refresh profile picture...');
        log('🖼️ [PROFILE SCREEN] About to refresh profile picture...');
        print('🖼️ [PROFILE SCREEN] About to start profile picture refresh process...');
        log('🖼️ [PROFILE SCREEN] About to start profile picture refresh process...');
        // Refresh profile picture when profile is updated
        await _refreshProfilePicture();
        print('🖼️ [PROFILE SCREEN] Profile picture refresh completed!');
        log('🖼️ [PROFILE SCREEN] Profile picture refresh completed!');
        print('🖼️ [PROFILE SCREEN] Profile picture refresh process completed!');
        log('🖼️ [PROFILE SCREEN] Profile picture refresh process completed!');
      },
    );
  }

  Widget _buildCourseDetailsScreen() {
    // Safely extract IDs from the selected course for backend fetches
    final dynamic cls = _selectedCourse?['class_id'];
    final dynamic subj = _selectedCourse?['subject_id'];
    final int? classId = cls is int ? cls : int.tryParse(cls?.toString() ?? '');
    final int? subjectId = subj is int ? subj : int.tryParse(subj?.toString() ?? '');

    return CourseDetailsScreen(
      courseTitle: (_selectedCourse?['name'] ?? 'Course Details').toString(),
      className: (_selectedCourse?['class_name'] ?? '').toString(),
      subjectName: (_selectedCourse?['subject_name'] ?? '').toString(),
      teacherName: (_selectedCourse?['teacher_name'] ?? '').toString(),
      accentColor: _selectedCourseColor ?? const Color(0xFF1E3A8A),
      level: _inferLevelForClass((_selectedCourse?['class_name'] ?? '').toString()),
      isAdmin: (
        ((_currentUser?['role'] ?? _userProfile?['role'] ?? '')
                .toString()
                .toLowerCase() ==
            'admin') &&
        !(_currentUser?['is_super_admin'] == 1 ||
          _currentUser?['is_super_admin'] == '1')
      ),
      classId: classId,
      subjectId: subjectId,
    );
  }

  Widget _buildLecturesScreen() {
    // Simple placeholder list of lectures with a trailing Link button
    final lectures = [
      {'number': 'Lecture 1', 'title': 'Topic Name', 'link': 'https://example.com/lec1'},
      {'number': 'Lecture 2', 'title': 'Topic Name', 'link': 'https://example.com/lec2'},
      {'number': 'Lecture 3', 'title': 'Topic Name', 'link': 'https://example.com/lec3'},
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0),
        child: Padding(
          padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showLectures = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFF1E3A8A),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Lectures',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: lectures.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = lectures[index];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (Theme.of(context).brightness == Brightness.dark)
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFE7E0DE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (Theme.of(context).brightness == Brightness.dark)
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFD9D2D0),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['number'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['title'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Placeholder: in future we can open/download link
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link action coming soon')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Link',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfilePicture({required double size}) {
    print('🖼️ [WIDGET] ===== BUILDING PROFILE PICTURE WIDGET =====');
    print('🖼️ [WIDGET] Size: $size');
    print('🖼️ [WIDGET] Current _profilePictureUrl: $_profilePictureUrl');
    print('🖼️ [WIDGET] URL is null: ${_profilePictureUrl == null}');
    print('🖼️ [WIDGET] URL is empty: ${_profilePictureUrl?.isEmpty ?? true}');
    print('🖼️ [WIDGET] Will show image: ${_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty}');
    print('🖼️ [WIDGET] Widget building method called successfully!');
    print('🖼️ [WIDGET] About to build profile picture widget...');
    print('🖼️ [WIDGET] About to start widget building process...');
    log('🖼️ [WIDGET] ===== BUILDING PROFILE PICTURE WIDGET =====');
    log('🖼️ [WIDGET] Size: $size');
    log('🖼️ [WIDGET] Current _profilePictureUrl: $_profilePictureUrl');
    log('🖼️ [WIDGET] URL is null: ${_profilePictureUrl == null}');
    log('🖼️ [WIDGET] URL is empty: ${_profilePictureUrl?.isEmpty ?? true}');
    log('🖼️ [WIDGET] Will show image: ${_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty}');
    log('🖼️ [WIDGET] Widget building method called successfully!');
    log('🖼️ [WIDGET] About to build profile picture widget...');
    log('🖼️ [WIDGET] About to start widget building process...');
    
    return GestureDetector(
      onTap: () {
        print('🖼️ [WIDGET] Profile picture tapped - navigating to profile screen');
        log('🖼️ [WIDGET] Profile picture tapped - navigating to profile screen');
        // Refresh profile picture before navigating
        _refreshProfilePicture();
        setState(() {
          _selectedNavIndex = 4; // Navigate to Profile screen
        });
      },
      onLongPress: () async {
        // Long press to test profile picture API
        print('🖼️ [WIDGET] Long press detected - testing profile picture API...');
        log('🖼️ [WIDGET] Long press detected - testing profile picture API...');
        await _testProfilePictureAPI();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1E3A8A), Color(0xFF1E3A8A)],
          ),
          borderRadius: BorderRadius.circular(size / 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E3A8A).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: _profilePictureUrl != null && _profilePictureUrl!.isNotEmpty
              ? Builder(
                  builder: (context) {
                    print('🖼️ [WIDGET] Building Image.network with URL: $_profilePictureUrl');
                    log('🖼️ [WIDGET] Building Image.network with URL: $_profilePictureUrl');
                    print('🖼️ [WIDGET] About to create Image.network widget');
                    log('🖼️ [WIDGET] About to create Image.network widget');
                    print('🖼️ [WIDGET] Image.network builder called successfully!');
                    log('🖼️ [WIDGET] Image.network builder called successfully!');
                    print('🖼️ [WIDGET] About to start Image.network creation process...');
                    log('🖼️ [WIDGET] About to start Image.network creation process...');
                    return Image.network(
                      _profilePictureUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        print('❌ [WIDGET] Error loading profile picture: $error');
                        log('❌ [WIDGET] Error loading profile picture: $error');
                        print('❌ [WIDGET] Stack trace: $stackTrace');
                        log('❌ [WIDGET] Stack trace: $stackTrace');
                        print('❌ [WIDGET] Error builder called successfully!');
                        log('❌ [WIDGET] Error builder called successfully!');
                        print('❌ [WIDGET] Error builder process completed!');
                        log('❌ [WIDGET] Error builder process completed!');
                        return const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 28,
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          print('✅ [WIDGET] Profile picture loaded successfully');
                          log('✅ [WIDGET] Profile picture loaded successfully');
                          print('✅ [WIDGET] Loading builder completed successfully!');
                          log('✅ [WIDGET] Loading builder completed successfully!');
                          print('✅ [WIDGET] Loading builder process completed!');
                          log('✅ [WIDGET] Loading builder process completed!');
                          return child;
                        }
                        print('🔄 [WIDGET] Loading profile picture... ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes}');
                        log('🔄 [WIDGET] Loading profile picture... ${loadingProgress.cumulativeBytesLoaded}/${loadingProgress.expectedTotalBytes}');
                        print('🔄 [WIDGET] Loading builder called successfully!');
                        log('🔄 [WIDGET] Loading builder called successfully!');
                        print('🔄 [WIDGET] Loading builder process in progress!');
                        log('🔄 [WIDGET] Loading builder process in progress!');
                        return const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 28,
                        );
                      },
                    );
                  },
                )
              : Builder(
                  builder: (context) {
                    print('🖼️ [WIDGET] No profile picture URL, showing default icon');
                    log('🖼️ [WIDGET] No profile picture URL, showing default icon');
                    print('🖼️ [WIDGET] About to create default icon widget');
                    log('🖼️ [WIDGET] About to create default icon widget');
                    print('🖼️ [WIDGET] Default icon builder called successfully!');
                    log('🖼️ [WIDGET] Default icon builder called successfully!');
                    print('🖼️ [WIDGET] Default icon builder process completed!');
                    log('🖼️ [WIDGET] Default icon builder process completed!');
                    return const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 28,
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildNameSection() {
    print('🏠 [NAME SECTION] Building name section...');
    print('🏠 [NAME SECTION] Current user: $_currentUser');
    print('🏠 [NAME SECTION] User profile: $_userProfile');
    print('🏠 [NAME SECTION] Profile picture URL: $_profilePictureUrl');
    print('🏠 [NAME SECTION] Name section building method called successfully!');
    print('🏠 [NAME SECTION] About to build name section...');
    print('🏠 [NAME SECTION] About to start name section building process...');
    log('🏠 [NAME SECTION] Building name section...');
    log('🏠 [NAME SECTION] Current user: $_currentUser');
    log('🏠 [NAME SECTION] User profile: $_userProfile');
    log('🏠 [NAME SECTION] Profile picture URL: $_profilePictureUrl');
    log('🏠 [NAME SECTION] Name section building method called successfully!');
    log('🏠 [NAME SECTION] About to build name section...');
    log('🏠 [NAME SECTION] About to start name section building process...');
    final role = (_currentUser?['role'] ?? _userProfile?['role'] ?? '').toString().toLowerCase();
    final isAdmin = role == 'admin';
    final isSuperAdmin = (_currentUser?['is_super_admin'] == 1 || _currentUser?['is_super_admin'] == '1');
    final isAdminLike = isAdmin || isSuperAdmin;
    final regNo = ((_userProfile != null ? _userProfile!['registration_no'] : null) ?? '').toString();
    final classTeacherOf = ((_userProfile != null ? _userProfile!['class_teacher_of'] : null) ?? '').toString();
    // Prepare safe display values for student details
    final rollSafe = ((_userProfile?['roll_number'] ?? '').toString().trim());
    final classSafe = _classLabel();

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                  const Color(0xFF1E3A8A).withValues(alpha: 0.15),
                ],
              )
            : null,
        color: isDark ? null : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFD9D2D0),
          width: 1,
        ),
      ),
      child: ResponsiveHelper.isMobile(context) 
        ? Column(
            children: [
              Row(
                children: [
            Builder(
              builder: (context) {
                print('🏠 [NAME SECTION] Building profile picture for mobile...');
                print('🏠 [NAME SECTION] Profile picture URL in mobile: $_profilePictureUrl');
                print('🏠 [NAME SECTION] Mobile profile picture builder called successfully!');
                print('🏠 [NAME SECTION] About to build mobile profile picture...');
                print('🏠 [NAME SECTION] About to start mobile profile picture building process...');
                log('🏠 [NAME SECTION] Building profile picture for mobile...');
                log('🏠 [NAME SECTION] Profile picture URL in mobile: $_profilePictureUrl');
                log('🏠 [NAME SECTION] Mobile profile picture builder called successfully!');
                log('🏠 [NAME SECTION] About to build mobile profile picture...');
                log('🏠 [NAME SECTION] About to start mobile profile picture building process...');
                return _buildProfilePicture(size: 60);
              },
            ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentUser?['name'] ?? 'Name',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isAdminLike) ...[
                Text(
                  'Registration No: ${regNo.isNotEmpty ? regNo : 'N/A'}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (isAdmin)
                  Text(
                    'Class Teacher of: ${classTeacherOf.isNotEmpty ? classTeacherOf : 'N/A'}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ] else ...[
                Text(
                  'Roll No: ${_profileLoading ? 'Loading...' : (rollSafe.isNotEmpty ? rollSafe : 'N/A')}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Class: ${_profileLoading ? 'Loading...' : (classSafe == 'Class' ? 'N/A' : classSafe)}',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              // Mobile actions row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedNavIndex = 4;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF1E3A8A)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushNamed('/settings');
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF1E3A8A)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      try {
                        await ApiService.logout();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Logout error: ${e.toString()}',
                                style: GoogleFonts.inter(),
                              ),
                              backgroundColor: const Color(0xFF1E3A8A),
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.logout,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          )
        :         Row(
            children: [
            Builder(
              builder: (context) {
                print('🏠 [NAME SECTION] Building profile picture for desktop...');
                print('🏠 [NAME SECTION] Profile picture URL in desktop: $_profilePictureUrl');
                print('🏠 [NAME SECTION] Desktop profile picture builder called successfully!');
                print('🏠 [NAME SECTION] About to build desktop profile picture...');
                print('🏠 [NAME SECTION] About to start desktop profile picture building process...');
                log('🏠 [NAME SECTION] Building profile picture for desktop...');
                log('🏠 [NAME SECTION] Profile picture URL in desktop: $_profilePictureUrl');
                log('🏠 [NAME SECTION] Desktop profile picture builder called successfully!');
                log('🏠 [NAME SECTION] About to build desktop profile picture...');
                log('🏠 [NAME SECTION] About to start desktop profile picture building process...');
                return _buildProfilePicture(size: 70);
              },
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentUser?['name'] ?? 'Name',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (isAdminLike) ...[
                      Text(
                        'Registration No: ${regNo.isNotEmpty ? regNo : 'N/A'}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      if (isAdmin)
                        Text(
                          'Class Teacher of: ${classTeacherOf.isNotEmpty ? classTeacherOf : 'N/A'}',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                    ] else ...[
                      Text(
                        'Roll No: ${_profileLoading ? 'Loading...' : (rollSafe.isNotEmpty ? rollSafe : 'N/A')}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      Text(
                        'Class: ${_profileLoading ? 'Loading...' : (classSafe == 'Class' ? 'N/A' : classSafe)}',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Desktop actions row
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedNavIndex = 4;
                      });
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF1E3A8A)],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushNamed('/settings');
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF1E3A8A)],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.settings,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      try {
                        await ApiService.logout();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Logout error: ${e.toString()}',
                                style: GoogleFonts.inter(),
                              ),
                              backgroundColor: const Color(0xFF1E3A8A),
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.logout,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
    );
  }

  Widget _buildThreeBoxesSection() {
    final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
    final isTeacherOrPrincipal = role == 'teacher' || role == 'principal' || role == 'admin';
    
    final bool isSuperAdmin = _isSuperAdminUser();
    final bool isStudent = role == 'student';
    return ResponsiveHelper.isMobile(context)
        ? SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMobileInfoBox(
                  'Event',
                  _upcomingEventTitle != null && _upcomingEventDate != null
                      ? (_upcomingEventDesc != null && _upcomingEventDesc!.trim().isNotEmpty
                          ? '${_formatDayMonth(_upcomingEventDate!)}: $_upcomingEventTitle — $_upcomingEventDesc'
                          : '${_formatDayMonth(_upcomingEventDate!)}: $_upcomingEventTitle')
                      : 'No upcoming events',
                  const Color(0xFF1E3A8A),
                  Icons.event,
                ),
                if (isSuperAdmin) ...[
                  _buildMobileAddNewStudentBox(),
                  _buildMobileTakeAttendanceBox(),
                ] else if (isStudent) ...[
                  _buildMobileInfoBox(
                    'Assignments',
                    _studentTotalsLoading
                        ? 'Loading...'
                        : ((_pendingAssignmentsCount ?? 0) > 0
                            ? '$_pendingAssignmentsCount pending assignments'
                            : 'No pending assignments'),
                    const Color(0xFF1E3A8A),
                    Icons.assignment,
                  ),
                  _buildMobileInfoBox(
                    'Quizzes',
                    _studentTotalsLoading
                        ? 'Loading...'
                        : ((_upcomingQuizzesCount ?? 0) > 0
                            ? '$_upcomingQuizzesCount upcoming quizzes'
                            : 'No upcoming quizzes'),
                    const Color(0xFF1E3A8A),
                    Icons.quiz,
                  ),
                  _buildMobileAcademicRecordsBox(),
                ] else ...[
                  // Admin-like (non-superadmin): show only Take Attendance after Event
                  _buildMobileTakeAttendanceBox(),
                ],
              ],
            ),
          )
        : Row(
            children: [
              Expanded(
                child: _buildInfoBox(
                  'Event',
                  _upcomingEventTitle != null && _upcomingEventDate != null
                      ? (_upcomingEventDesc != null && _upcomingEventDesc!.trim().isNotEmpty
                          ? '${_formatDayMonth(_upcomingEventDate!)}: $_upcomingEventTitle — $_upcomingEventDesc'
                          : '${_formatDayMonth(_upcomingEventDate!)}: $_upcomingEventTitle')
                      : 'No upcoming events',
                  const Color(0xFF1E3A8A),
                  Icons.event,
                ),
              ),
              SizedBox(width: ResponsiveHelper.getSpacing(context, size: 'medium')),
              if (isSuperAdmin) ...[
                Expanded(
                  child: _buildAddNewStudentBox(),
                ),
                SizedBox(width: ResponsiveHelper.getSpacing(context, size: 'medium')),
                Expanded(
                  child: _buildTakeAttendanceBox(),
                ),
              ] else if (isStudent) ...[
                Expanded(
                  child: _buildInfoBox(
                    'Assignments',
                    _studentTotalsLoading
                        ? 'Loading...'
                        : ((_pendingAssignmentsCount ?? 0) > 0
                            ? '$_pendingAssignmentsCount pending assignments'
                            : 'No pending assignments'),
                    const Color(0xFF1E3A8A),
                    Icons.assignment,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.getSpacing(context, size: 'medium')),
                Expanded(
                  child: _buildInfoBox(
                    'Quizzes',
                    _studentTotalsLoading
                        ? 'Loading...'
                        : ((_upcomingQuizzesCount ?? 0) > 0
                            ? '$_upcomingQuizzesCount upcoming quizzes'
                            : 'No upcoming quizzes'),
                    const Color(0xFF1E3A8A),
                    Icons.quiz,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.getSpacing(context, size: 'medium')),
                Expanded(
                  child: _buildAcademicRecordsBox(),
                ),
              ] else ...[
                // Admin-like (non-superadmin): Only Event + enlarged Take Attendance
                Expanded(
                  child: _buildTakeAttendanceBox(),
                ),
              ],
            ],
          );
  }

  Widget _buildAddNewStudentBox() {
    const Color accent = Color(0xFF1E3A8A);
    return Container(
      padding: EdgeInsets.all(
        ResponsiveHelper.getSpacing(context, size: 'medium'),
      ),
      decoration: BoxDecoration(
        color: (Theme.of(context).brightness == Brightness.dark)
            ? accent.withValues(alpha: 0.1)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.responsiveValue(
            context,
            mobile: 16,
            tablet: 18,
            desktop: 20,
          ),
        ),
        border: Border.all(
          color: (Theme.of(context).brightness == Brightness.dark)
              ? accent.withValues(alpha: 0.3)
              : const Color(0xFFD9D2D0),
          width: 1.5,
        ),
        boxShadow: ResponsiveHelper.getElevation(context, level: 2),
      ),
      constraints: BoxConstraints(minHeight: _dashCardHeight, maxHeight: _dashCardHeight),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: const [
                    Icon(Icons.person_add, color: accent, size: 28),
                    SizedBox(width: 8),
                  ],
                ),
                Text(
                  'Add New Users',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create a new user account',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddNewUserScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              'Add',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTakeAttendanceBox() {
    const Color accent = Color(0xFF1E3A8A);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? accent.withValues(alpha: 0.1)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? accent.withValues(alpha: 0.3)
              : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? accent.withValues(alpha: 0.2)
                : accent.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      constraints: BoxConstraints(minHeight: _dashCardHeight, maxHeight: _dashCardHeight),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: const [
                    Icon(Icons.how_to_reg, color: accent, size: 28),
                    SizedBox(width: 8),
                  ],
                ),
                Text(
                  'Take Attendance',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mark student attendance',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedNavIndex = 9; // Take Attendance tab
                _showCourseDetails = false;
                _showLectures = false;
                _showAttendance = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              'Take',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // List to store recent tickets for display in the ticket overview box
  List<Map<String, dynamic>> _recentTickets = [];
  bool _ticketsLoading = false;
  

  // Load recent tickets for the ticket overview box
  Future<void> _loadRecentTickets() async {
    if (!mounted) return;
    setState(() => _ticketsLoading = true);
    try {
      final tickets = await ApiService.listTickets();
      if (mounted) {
        setState(() {
          _recentTickets = tickets.take(3).toList(); // Take only the 3 most recent tickets
          _ticketsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recentTickets = [];
          _ticketsLoading = false;
        });
      }
    }
  }


  // Method to check if user is superadmin and load tickets if they are
  Future<void> _checkUserAndLoadData() async {
    final user = await ApiService.getCurrentUser();
    if (user != null && (user['is_super_admin'] == 1 || user['is_super_admin'] == '1')) {
      _loadRecentTickets();
    }
  }

  Widget _buildTicketOverviewBox() {
    const Color accent = Color(0xFF1E3A8A);
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNavIndex = 10; // Generate Ticket screen
        });
      },
      child: Container(
        width: double.infinity,
        height: 440,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? accent.withValues(alpha: 0.15)
              : const Color(0xFFE7E0DE),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? accent.withValues(alpha: 1.0)
                : const Color(0xFFD9D2D0),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.15,
              ),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ticket Overview',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh, color: accent),
                  onPressed: _loadRecentTickets,
                  tooltip: 'Refresh tickets',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_ticketsLoading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: accent),
                ),
              )
            else if (_recentTickets.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent Tickets',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _recentTickets.length,
                        itemBuilder: (context, index) {
                          final ticket = _recentTickets[index];
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: accent.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: ListTile(
                              title: Text(
                                '#${ticket['id']} - ${ticket['level1']} (${ticket['level2']})',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                ticket['content'].toString().length > 50
                                    ? '${ticket['content'].toString().substring(0, 50)}...'
                                    : ticket['content'].toString(),
                                style: GoogleFonts.inter(fontSize: 12),
                              ),
                              trailing: Chip(
                                label: Text(
                                  ticket['status'] ?? 'New',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                backgroundColor: _getStatusColor(ticket['status']),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.confirmation_number_outlined,
                        size: 64,
                        color: accent,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Recent Tickets',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create and manage support tickets',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                        textAlign: TextAlign.center,
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

  
  // Helper method to get color based on ticket status
  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }

  Widget _buildInfoBox(String title, String subtitle, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? color.withValues(alpha: 0.1)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? color.withValues(alpha: 0.3)
              : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? color.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      constraints: BoxConstraints(minHeight: _dashCardHeight, maxHeight: _dashCardHeight),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).brightness == Brightness.dark
                  ? color
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileInfoBox(String title, String subtitle, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? color.withValues(alpha: 0.1)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? color.withValues(alpha: 0.3)
              : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? color.withValues(alpha: 0.2)
                : color.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      constraints: BoxConstraints(minHeight: _dashCardHeight),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).brightness == Brightness.dark
                  ? color
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileAcademicRecordsBox() {
    const Color accent = Color(0xFF2563EB);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _openAcademicRecords,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? accent.withValues(alpha: 0.1) : const Color(0xFFE7E0DE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? accent.withValues(alpha: 0.3) : const Color(0xFFD9D2D0),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? accent.withValues(alpha: 0.2) : accent.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: BoxConstraints(minHeight: _dashCardHeight),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.insights, color: accent, size: 28),
                          SizedBox(width: 8),
                        ],
                      ),
                      Text(
                        'Academic Records',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'View results & history',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileAddNewStudentBox() {
    const Color accent = Color(0xFF1E3A8A);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: (Theme.of(context).brightness == Brightness.dark)
            ? accent.withValues(alpha: 0.1)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (Theme.of(context).brightness == Brightness.dark)
              ? accent.withValues(alpha: 0.3)
              : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      constraints: BoxConstraints(minHeight: _dashCardHeight),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: const [
                    Icon(Icons.person_add, color: accent, size: 28),
                    SizedBox(width: 8),
                  ],
                ),
                Text(
                  'Add New Users',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create a new user account',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddNewUserScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              'Add',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTakeAttendanceBox() {
    const Color accent = Color(0xFF1E3A8A);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? accent.withValues(alpha: 0.1)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? accent.withValues(alpha: 0.3)
              : const Color(0xFFD9D2D0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark
                ? accent.withValues(alpha: 0.2)
                : accent.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      constraints: BoxConstraints(minHeight: _dashCardHeight),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: const [
                    Icon(Icons.how_to_reg, color: accent, size: 28),
                    SizedBox(width: 8),
                  ],
                ),
                Text(
                  'Take Attendance',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mark student attendance',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedNavIndex = 9; // Take Attendance tab
                _showCourseDetails = false;
                _showLectures = false;
                _showAttendance = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(
              'Take',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAttendancePieChart() {
    // For superadmin users, show ticket overview box instead of attendance
    if (_currentUser != null && (_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1')) {
      return _buildTicketOverviewBox();
    }
    const Color accentBlue = Color(0xFF1E3A8A);
    const Color lightCard = Color(0xFFE7E0DE);
    const Color lightBorder = Color(0xFFD9D2D0);
    const Color presentColor = Color(0xFF16A34A);
    const Color absentColor = Color(0xFFDC2626);
    const Color leaveColor = Color(0xFF2563EB);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _openAttendanceDetailsDialog,
      child: Container(
      width: double.infinity,
      height: 440,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)
              : lightBorder,
          width: 1.5,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: accentBlue.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (_termStartDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'From: $_termStartDate to Today',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: _attendanceLoading
                  ? const CircularProgressIndicator(color: accentBlue)
                  : (() {
                      if (_attendanceError != null && _attendanceError!.isNotEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accentBlue.withValues(alpha: isDark ? 0.25 : 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: accentBlue.withValues(alpha: 0.35), width: 1),
                          ),
                          child: Text(
                            _attendanceError!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: accentBlue, fontSize: 12),
                          ),
                        );
                      }
                      final sum = _percPresent + _percAbsent + _percLeave;
                      if (sum <= 0) {
                        return Text(
                          'No attendance data yet',
                          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85)),
                        );
                      }
                      return SizedBox(
                        width: 200,
                        height: 200,
                        child: PieChart(
                          PieChartData(
                            sections: [
                              PieChartSectionData(
                                color: presentColor,
                                value: _percPresent,
                                title: '${_percPresent.toStringAsFixed(0)}%',
                                radius: 85,
                                titleStyle: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              PieChartSectionData(
                                color: absentColor,
                                value: _percAbsent,
                                radius: 85,
                                title: _percAbsent > 0 ? '${_percAbsent.toStringAsFixed(0)}%' : '',
                                titleStyle: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              PieChartSectionData(
                                color: leaveColor,
                                value: _percLeave,
                                radius: 85,
                                title: _percLeave > 0 ? '${_percLeave.toStringAsFixed(0)}%' : '',
                                titleStyle: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                            centerSpaceRadius: 55,
                            sectionsSpace: 2,
                          ),
                        ),
                      );
                    })(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('Present', presentColor),
              _buildLegendItem('Absent', absentColor),
              _buildLegendItem('Leave', leaveColor),
            ],
          ),
          const SizedBox(height: 12),
          // Counts chips removed; tap the box to view detailed day-by-day records
        ],
      ),
    ),
  );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildCoursesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: ResponsiveHelper.isMobile(context) 
            ? ResponsiveHelper.getContentPadding(context)
            : EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Courses',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedNavIndex = 2; // Navigate to Courses screen
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                ),
                child: Text(
                  'View all',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_coursesLoading)
          ResponsiveHelper.isMobile(context)
            ? Column(
                children: [
                  _buildMobileCourseBox('Loading...', _courseColor(0)),
                  _buildMobileCourseBox('Loading...', _courseColor(1)),
                  _buildMobileCourseBox('Loading...', _courseColor(2)),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _buildCourseBox('Loading...', _courseColor(0))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCourseBox('Loading...', _courseColor(1))),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCourseBox('Loading...', _courseColor(2))),
                ],
              )
        else if (_coursesError != null)
          Padding(
            padding: ResponsiveHelper.isMobile(context) 
              ? ResponsiveHelper.getContentPadding(context)
              : EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 1),
              ),
              child: Text(
                _coursesError ?? 'Failed to load courses',
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          )
        else if (_myCourses.isEmpty)
          Padding(
            padding: ResponsiveHelper.isMobile(context) 
              ? ResponsiveHelper.getContentPadding(context)
              : EdgeInsets.zero,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
              ),
              child: Text(
                'No assigned courses',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
              ),
            ),
          )
        else
          ResponsiveHelper.isMobile(context)
            ? Column(
                children: [
                  for (int i = 0; i < _myCourses.length; i++)
                    _buildMobileCourseBox(
                      _courseTitle(_myCourses[i]),
                      _courseColor(i),
                      course: _myCourses[i],
                    ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  // Determine columns based on width; aim for min ~180px per card
                  int cols = (w / 200).floor().clamp(1, 4);
                  final spacing = w < 500 ? 12.0 : 16.0;
                  final boxW = ((w - spacing * (cols - 1)) / cols).clamp(160.0, 320.0);
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (int i = 0; i < _myCourses.length; i++)
                        SizedBox(
                          width: boxW,
                          child: _buildCourseBox(
                            _courseTitle(_myCourses[i]),
                            _courseColor(i),
                            course: _myCourses[i],
                          ),
                        ),
                    ],
                  );
                },
              ),
      ],
    );
  }

  Widget _buildMobileCourseBox(String title, Color color, {Map<String, dynamic>? course}) {
    // Get lecture count for this course
    int lectureCount = 0;
    if (course != null) {
      lectureCount = _getCourseLectureCount(course);
    }

    return GestureDetector(
      onTap: () {
        if (course != null) {
          // If student and course has lectures, show lecture dialog
          final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
          if (role == 'student' && lectureCount > 0) {
            _showStudentLecturesDialog(course);
          } else {
            // Otherwise show course details
            setState(() {
              _selectedCourse = course;
              _selectedCourseColor = color;
              _showCourseDetails = true;
            });
          }
        }
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: (Theme.of(context).brightness == Brightness.dark)
              ? color.withValues(alpha: 0.1)
              : const Color(0xFFE7E0DE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (Theme.of(context).brightness == Brightness.dark)
                ? color.withValues(alpha: 0.3)
                : const Color(0xFFD9D2D0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        constraints: BoxConstraints(minHeight: _dashCardHeight),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.school,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (course != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            color: color,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$lectureCount lectures',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Lectures',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getCourseLectureCount(Map<String, dynamic> course) {
    // Get available lectures count (only lectures with links)
    final lecturesJson = course['lectures_json'];
    if (lecturesJson == null || lecturesJson.toString().isEmpty) {
      return 0;
    }
    
    try {
      final parsed = jsonDecode(lecturesJson.toString());
      if (parsed is List) {
        // Count only lectures that have non-empty links
        return parsed.where((lecture) {
          final link = lecture['link']?.toString() ?? '';
          return link.isNotEmpty;
        }).length;
      }
    } catch (e) {
      print('[DEBUG] Error parsing lectures JSON in home screen: $e');
    }
    
    return 0;
  }

  void _showStudentLecturesDialog(Map<String, dynamic> course) {
    final lecturesJson = course['lectures_json'];
    if (lecturesJson == null || lecturesJson.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No lectures available')),
      );
      return;
    }

    List<Map<String, dynamic>> lectures = [];
    try {
      final parsed = jsonDecode(lecturesJson.toString());
      if (parsed is List) {
        lectures = parsed.where((lecture) {
          final link = lecture['link']?.toString() ?? '';
          return link.isNotEmpty;
        }).map<Map<String, dynamic>>((e) => {
          'number': (e['number'] ?? '').toString(),
          'name': (e['name'] ?? '').toString(),
          'link': (e['link'] ?? '').toString(),
        }).toList();
      }
    } catch (e) {
      print('[DEBUG] Error parsing lectures in dialog: $e');
    }

    if (lectures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No lectures with links available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${course['subject_name'] ?? 'Course'} Lectures'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: lectures.length,
            itemBuilder: (context, index) {
              final lecture = lectures[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  child: Text(
                    lecture['number'],
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                title: Text(lecture['name']),
                subtitle: Text(lecture['link']),
                trailing: ElevatedButton(
                  onPressed: () => _openLectureLink(lecture['link']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Open',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                onTap: () => _openLectureLink(lecture['link']),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLectureLink(String url) async {
    if (url.isEmpty) return;
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open link: $url')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  Widget _buildCourseBox(String title, Color color, {Map<String, dynamic>? course}) {
    // Get lecture count for this course
    int lectureCount = 0;
    if (course != null) {
      lectureCount = _getCourseLectureCount(course);
    }

    return GestureDetector(
      onTap: () {
        if (course != null) {
          // If student and course has lectures, show lecture dialog
          final role = (_currentUser?['role'] ?? '').toString().toLowerCase();
          if (role == 'student' && lectureCount > 0) {
            _showStudentLecturesDialog(course);
          } else {
            // Otherwise show course details
            setState(() {
              _selectedCourse = course;
              _selectedCourseColor = color;
              _showCourseDetails = true;
            });
          }
        }
      },
      child: Container(
        height: 140, // Increased height to accommodate lecture info
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (Theme.of(context).brightness == Brightness.dark)
              ? color.withValues(alpha: 0.1)
              : const Color(0xFFE7E0DE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (Theme.of(context).brightness == Brightness.dark)
                ? color.withValues(alpha: 0.3)
                : const Color(0xFFD9D2D0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.school,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // Lecture count display
            if (course != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      color: color,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$lectureCount lectures',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
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

  Widget _buildBottomNoticeBoard() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color accentBlue = Color(0xFF1E3A8A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E3A8A).withValues(alpha: 0.15)
            : const Color(0xFFE7E0DE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFD9D2D0),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Notice Board',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : accentBlue,
                ),
              ),
              if (_canAddNotices)
                ElevatedButton.icon(
                  onPressed: _showAddNoticeDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    'Add Notice',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_noticesLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1E3A8A)),
                    ),
                    const SizedBox(width: 10),
                    Text('Loading notices...', style: GoogleFonts.inter(color: Colors.white)),
                  ],
                ),
              ),
            )
          else if (_noticesError != null)
            Text(
              _noticesError!,
              style: GoogleFonts.inter(color: accentBlue),
            )
          else if (_notices.isEmpty && _calendarEvents.isEmpty)
            Text(
              'No notices or events yet',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white.withValues(alpha: 0.9) : accentBlue.withValues(alpha: 0.85),
              ),
            )
          else
            Column(
              children: [
                // Display calendar events first
                for (int i = 0; i < _calendarEvents.length; i++) ...[
                  _buildNoticeItem(
                    (_calendarEvents[i]['title'] ?? '').toString(),
                    _formatEventTime(_calendarEvents[i]['event_date'] as DateTime),
                    isEvent: true,
                    subtitle: (_calendarEvents[i]['description'] ?? '')?.toString(),
                  ),
                  if (i < _calendarEvents.length - 1 || _notices.isNotEmpty) const SizedBox(height: 14),
                ],
                // Then display regular notices
                for (int i = 0; i < _notices.length; i++) ...[
                  _buildNoticeItem(
                    (_notices[i]['title'] ?? '').toString(),
                    _formatNoticeTime((_notices[i]['created_at'] ?? '').toString()),
                  ),
                  if (i < _notices.length - 1) const SizedBox(height: 14),
                ]
              ],
            ),
        ],
      ),
    );
  }

  String _formatNoticeTime(String createdAt) {
    // Expecting MySQL timestamp 'YYYY-MM-DD HH:MM:SS'
    try {
      if (createdAt.isEmpty) return '';
      final dt = DateTime.parse(createdAt.replaceFirst(' ', 'T'));
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return createdAt;
    }
  }

  String _formatEventTime(DateTime eventDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(eventDate.year, eventDate.month, eventDate.day);
    
    if (eventDay == today) {
      return 'Today';
    } else if (eventDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else {
      return '${eventDate.day.toString().padLeft(2, '0')}/${eventDate.month.toString().padLeft(2, '0')}/${eventDate.year}';
    }
  }

  void _showAddNoticeDialog() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        bool submitting = false;
        final navigator = Navigator.of(ctx);
        final messenger = ScaffoldMessenger.of(ctx);
        return StatefulBuilder(
          builder: (context, setSt) {
            return AlertDialog(
              backgroundColor: Theme.of(ctx).colorScheme.surface,
              title: Text(
                'Add Notice',
                style: GoogleFonts.inter(
                  color: Theme.of(ctx).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Body (optional)'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => navigator.pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Title is required', style: GoogleFonts.inter())),
                            );
                            return;
                          }
                          setSt(() => submitting = true);
                          try {
                            await ApiService.createNotice(title: title, body: bodyCtrl.text.trim().isEmpty ? null : bodyCtrl.text.trim());
                            if (!mounted) return;
                            navigator.pop();
                            await _loadNotices();
                            messenger.showSnackBar(SnackBar(content: Text('Notice added', style: GoogleFonts.inter())));
                          } catch (e) {
                            setSt(() => submitting = false);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(backgroundColor: const Color(0xFF1E3A8A), content: Text('Failed: $e', style: GoogleFonts.inter())),
                            );
                          }
                        },
                  child: submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCountChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
      ),
    );
  }

  Widget _buildNoticeItem(String title, String time, {bool isEvent = false, String? subtitle}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isEvent ? const Color(0xFF1E3A8A) : const Color(0xFF1E3A8A),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(
          time,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}


