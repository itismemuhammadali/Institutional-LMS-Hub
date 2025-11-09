import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:developer' show log;

/// API Service class for handling all HTTP requests to the PHP backend
class ApiService {
  // Base URL for the API - automatically detect platform
  static String get baseUrl {
    // XAMPP/Apache mapping
    // - Web/Desktop/iOS simulator use localhost
    // - Android emulator uses 10.0.2.2 to reach host
    // - Physical devices use the LAN IP of the host machine
    if (kIsWeb) {
      return 'http://localhost/backend/api.php';
    }

    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2/backend/api.php';
      }
      if (Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux) {
        return 'http://localhost/backend/api.php';
      }
    } catch (_) {
      // Fallback if Platform is unavailable
    }
    // Physical devices on same Wi‑Fi: use your PC's LAN IP
    return 'http://192.168.18.30/backend/api.php';
  }

  static Future<Map<String, dynamic>> saveClassQuiz({
    required int classId,
    required int subjectId,
    String? title,
    String? topic,
    DateTime? scheduledAt,
    String status = 'scheduled',
    int? number,
    int? id,
    int? planItemId,
    int? teacherAssignmentId,
  }) async {
    try {
      final body = <String, dynamic>{
        'class_id': classId,
        'subject_id': subjectId,
        if (title != null) 'title': title,
        if (topic != null) 'topic': topic,
        if (scheduledAt != null) 'deadline': _formatDateTime(scheduledAt),
        'status': status,
        if (number != null) 'number': number,
        if (id != null) 'id': id,
        if (planItemId != null) 'plan_item_id': planItemId,
        if (teacherAssignmentId != null) 'teacher_assignment_id': teacherAssignmentId,
      };
      final response = await _makeRequest(
        'class_quiz_save',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save quiz: $e');
    }
  }

  static Future<Map<String, dynamic>> saveClassAssignment({
    required int classId,
    required int subjectId,
    String? title,
    String? description,
    DateTime? deadline,
    String status = 'scheduled',
    int? number,
    int? id,
    int? planItemId,
    int? teacherAssignmentId,
  }) async {
    try {
      final body = <String, dynamic>{
        'class_id': classId,
        'subject_id': subjectId,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (deadline != null) 'deadline': _formatDateTime(deadline),
        'status': status,
        if (number != null) 'number': number,
        if (id != null) 'id': id,
        if (planItemId != null) 'plan_item_id': planItemId,
        if (teacherAssignmentId != null) 'teacher_assignment_id': teacherAssignmentId,
      };
      final response = await _makeRequest(
        'class_assignment_save',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save assignment: $e');
    }
  }

  /// Fetch assessments for a class
  static Future<Map<String, dynamic>> getClassAssessments({
    required int classId,
    required int subjectId,
  }) async {
    try {
      final endpoint = 'class_assessments&class_id=$classId&subject_id=$subjectId';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return Map<String, dynamic>.from(result);
      }
      throw Exception(result['error'] ?? 'Failed to fetch assessments');
    } catch (e) {
      throw Exception('Failed to fetch assessments: $e');
    }
  }

  /// Update assessment completion/coverage status
  static Future<Map<String, dynamic>> updateAssessmentCompletion({
    required String kind, // 'assignment' | 'quiz'
    required int classId,
    required int subjectId,
    int? planItemId,
    int? number,
    String status = 'covered',
    String? completedAt,
  }) async {
    try {
      final body = <String, dynamic>{
        'kind': kind,
        'class_id': classId,
        'subject_id': subjectId,
        if (planItemId != null) 'plan_item_id': planItemId,
        if (number != null) 'number': number,
        'status': status,
        if (completedAt != null) 'completed_at': completedAt,
      };
      final response = await _makeRequest(
        'assessment_completion',
        method: 'PUT',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to update assessment completion: $e');
    }
  }

  static Future<Map<String, dynamic>> upsertFirstTermMarks({
    int? classId,
    int? subjectId,
    String? className,
    String? subjectName,
    String? examDate,
    String? remarks,
    required int totalMarks,
    required List<Map<String, dynamic>> entries,
  }) {
    return _postTermMarks(
      endpoint: 'student_first_term_marks_upsert',
      classId: classId,
      subjectId: subjectId,
      className: className,
      subjectName: subjectName,
      examDate: examDate,
      remarks: remarks,
      totalMarks: totalMarks,
      entries: entries,
    );
  }

  static Future<Map<String, dynamic>> upsertFinalTermMarks({
    int? classId,
    int? subjectId,
    String? className,
    String? subjectName,
    String? examDate,
    String? remarks,
    required int totalMarks,
    required List<Map<String, dynamic>> entries,
  }) {
    return _postTermMarks(
      endpoint: 'student_final_term_marks_upsert',
      classId: classId,
      subjectId: subjectId,
      className: className,
      subjectName: subjectName,
      examDate: examDate,
      remarks: remarks,
      totalMarks: totalMarks,
      entries: entries,
    );
  }

  static Future<Map<String, dynamic>> _postTermMarks({
    required String endpoint,
    int? classId,
    int? subjectId,
    String? className,
    String? subjectName,
    String? examDate,
    String? remarks,
    required int totalMarks,
    required List<Map<String, dynamic>> entries,
  }) async {
    try {
      final body = <String, dynamic>{
        if (classId != null) 'class_id': classId,
        if (subjectId != null) 'subject_id': subjectId,
        if (className != null) 'class_name': className,
        if (subjectName != null) 'subject_name': subjectName,
        'total_marks': totalMarks,
        if (examDate != null) 'exam_date': examDate,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        'entries': entries,
      };
      final response = await _makeRequest(
        endpoint,
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to upsert term marks: $e');
    }
  }

  /// Search subjects by level and partial name
  static Future<List<Map<String, dynamic>>> searchSubjects({
    required String level,
    required String query,
    int limit = 20,
  }) async {
    try {
      final qp = 'level=${Uri.encodeComponent(level)}&q=${Uri.encodeComponent(query)}&limit=$limit';
      final response = await _makeRequest('subject_search&$qp');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['subjects'] ?? []);
      }
      throw Exception(result['error'] ?? 'Search failed');
    } catch (e) {
      throw Exception('Search failed: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getStudentFirstTermMarks({
    int? classId,
    int? studentUserId,
  }) {
    return _getStudentTermMarks(
      endpoint: 'student_first_term_marks',
      classId: classId,
      studentUserId: studentUserId,
    );
  }

  static Future<List<Map<String, dynamic>>> getStudentFinalTermMarks({
    int? classId,
    int? studentUserId,
  }) {
    return _getStudentTermMarks(
      endpoint: 'student_final_term_marks',
      classId: classId,
      studentUserId: studentUserId,
    );
  }

  static Future<List<Map<String, dynamic>>> _getStudentTermMarks({
    required String endpoint,
    int? classId,
    int? studentUserId,
  }) async {
    try {
      final qp = <String>[
        if (classId != null) 'class_id=$classId',
        if (studentUserId != null) 'student_user_id=$studentUserId',
      ].join('&');
      final target = qp.isEmpty ? endpoint : '$endpoint&$qp';
      final response = await _makeRequest(target);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['marks'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch term marks');
    } catch (e) {
      throw Exception('Failed to fetch term marks: $e');
    }
  }

  /// Fetch subjects for a class when only class name is known (level auto-inferred server-side)
  static Future<List<Map<String, dynamic>>> getSubjectsForStudentClass({
    required String className,
  }) async {
    try {
      final qp = 'class_name=${Uri.encodeComponent(className)}';
      final response = await _makeRequest('class_subjects&$qp');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['subjects'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch student class subjects');
    } catch (e) {
      throw Exception('Failed to fetch student class subjects: $e');
    }
  }

  /// Upload user profile picture
  /// Accepts either [filePath] (non-web) or [fileBytes] + [fileName] (web)
  static Future<Map<String, dynamic>> uploadProfilePicture({
    required int userId,
    String? filePath,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl?endpoint=upload_profile_picture');
      final request = http.MultipartRequest('POST', uri);

      final token = await _getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['user_id'] = userId.toString();

      if (fileBytes != null && fileName != null) {
        request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
      } else if (!kIsWeb && filePath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', filePath));
      } else {
        throw Exception('No valid file provided for upload');
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to upload profile picture: $e');
    }
  }

  static void _dlog(String message) {
    log('[ApiService] $message');
  }

  static String _formatDateTime(DateTime value) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
  }

  /// List previous class attendance dates with counts (Teacher)
  static Future<List<Map<String, dynamic>>> getClassAttendanceHistory({
    required String className,
    int limit = 30,
  }) async {
    try {
      final endpoint =
          'class_attendance_history&class_name=${Uri.encodeComponent(className)}&limit=$limit';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['history'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch attendance history');
    } catch (e) {
      throw Exception('Failed to fetch attendance history: $e');
    }
  }

  /// List subjects linked to a class (by level and class name)
  static Future<List<Map<String, dynamic>>> getClassSubjects({
    required String level,
    required String className,
  }) async {
    try {
      final qp = 'level=${Uri.encodeComponent(level)}&class_name=${Uri.encodeComponent(className)}';
      final response = await _makeRequest('class_subjects&$qp');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['subjects'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch class subjects');
    } catch (e) {
      throw Exception('Failed to fetch class subjects: $e');
    }
  }

  /// Link a subject to a class (creates subject in subjects table if needed)
  static Future<Map<String, dynamic>> linkSubjectToClass({
    required String level,
    required String className,
    required String subjectName,
  }) async {
    try {
      final response = await _makeRequest(
        'class_subject',
        method: 'POST',
        body: {
          'level': level,
          'class_name': className,
          'subject_name': subjectName,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to link subject: $e');
    }
  }

  /// Unlink a subject from a class (does not delete from subjects table)
  static Future<Map<String, dynamic>> unlinkSubjectFromClass({
    required String level,
    required String className,
    required String subjectName,
  }) async {
    try {
      final qp = 'level=${Uri.encodeComponent(level)}&class_name=${Uri.encodeComponent(className)}&subject_name=${Uri.encodeComponent(subjectName)}';
      final response = await _makeRequest('class_subject&$qp', method: 'DELETE');
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to unlink subject: $e');
    }
  }

  /// Rename a class within a level (Super Admin)
  static Future<Map<String, dynamic>> renameClass({
    required String level,
    required String oldName,
    required String newName,
  }) async {
    try {
      final response = await _makeRequest(
        'class',
        method: 'PUT',
        body: {
          'level': level,
          'old_name': oldName,
          'new_name': newName,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to rename class: $e');
    }
  }

  /// Add a class to a given level (Super Admin)
  static Future<Map<String, dynamic>> addClass({
    required String level,
    required String className,
  }) async {
    try {
      final response = await _makeRequest(
        'class',
        method: 'POST',
        body: {
          'level': level,
          'class_name': className,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to add class: $e');
    }
  }

  /// Delete a class from a given level (Super Admin)
  static Future<Map<String, dynamic>> deleteClass({
    required String level,
    required String className,
  }) async {
    try {
      final response = await _makeRequest(
        'class&level=${Uri.encodeComponent(level)}&class_name=${Uri.encodeComponent(className)}',
        method: 'DELETE',
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete class: $e');
    }
  }

  /// Unassign all teachers (class teacher and all subject teachers) from a class without deleting the class
  static Future<Map<String, dynamic>> unassignClassTeachers({
    required String level,
    required String className,
  }) async {
    try {
      final response = await _makeRequest(
        'class_unassign_teachers',
        method: 'POST',
        body: {
          'level': level,
          'class_name': className,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to unassign teachers: $e');
    }
  }

  /// Dismember a class: unlink all students from this class (does not delete class or users)
  static Future<Map<String, dynamic>> dismemberClass({
    required String level,
    required String className,
  }) async {
    try {
      final response = await _makeRequest(
        'class_dismember',
        method: 'POST',
        body: {
          'level': level,
          'class_name': className,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to dismember class: $e');
    }
  }

  /// Unlink a single student from a class (helper for partial dismember)
  static Future<Map<String, dynamic>> unlinkStudentFromClass({
    required int studentUserId,
    required String className,
  }) async {
    try {
      final response = await _makeRequest(
        'class_student_unlink',
        method: 'POST',
        body: {
          'student_user_id': studentUserId,
          'class_name': className,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to unlink student from class: $e');
    }
  }

  /// Fetch class attendance entries for a specific date (Teacher)
  static Future<List<Map<String, dynamic>>> getClassAttendance({
    required String className,
    required String date, // YYYY-MM-DD
  }) async {
    try {
      final endpoint =
          'class_attendance&class_name=${Uri.encodeComponent(className)}&date=${Uri.encodeComponent(date)}';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['attendance'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch class attendance');
    } catch (e) {
      throw Exception('Failed to fetch class attendance: $e');
    }
  }

  /// Record class attendance in batch (Teacher)
  /// entries: [{ 'student_user_id': int, 'status': 'present'|'absent'|'leave', 'remarks'?: String }]
  static Future<Map<String, dynamic>> recordClassAttendance({
    required String className,
    required String date, // YYYY-MM-DD
    required List<Map<String, dynamic>> entries,
  }) async {
    try {
      final body = {
        'attendance_date': date,
        'class_name': className,
        'entries': entries,
      };
      final response = await _makeRequest(
        'record_class_attendance',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to record class attendance: $e');
    }
  }

  // Shared preferences key for storing user session
  static const String _userSessionKey = 'user_session';
  // Shared preferences key for storing JWT token
  static const String _tokenKey = 'jwt_token';

  // Request timeout duration
  static const Duration _timeoutDuration = Duration(seconds: 30);

  /// Create a new support ticket
  static Future<Map<String, dynamic>> createTicket({
    required String level1,
    required String level2,
    required String content,
  }) async {
    try {
      final body = {
        'level1': level1,
        'level2': level2,
        'content': content,
      };
      final response = await _makeRequest(
        'ticket',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to create ticket: $e');
    }
  }

  /// List all tickets for the current user
  static Future<List<Map<String, dynamic>>> listTickets() async {
    try {
      final response = await _makeRequest('tickets');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['tickets'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch tickets');
    } catch (e) {
      throw Exception('Failed to fetch tickets: $e');
    }
  }

  /// Reply to an existing ticket
  static Future<Map<String, dynamic>> replyTicket({
    required int ticketId,
    required String replyKey,
    String? status,
  }) async {
    try {
      final body = {
        'ticket_id': ticketId,
        'reply_key': replyKey,
        if (status != null) 'status': status,
      };
      final response = await _makeRequest(
        'ticket_reply',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to reply to ticket: $e');
    }
  }

  /// Get the current user session from shared preferences
  static Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString(_userSessionKey);
      if (userData != null) {
        return json.decode(userData);
      }
    } catch (e) {
      log('Error getting current user: $e');
    }
    return null;
  }

  /// Save user session to shared preferences
  static Future<void> saveUserSession(Map<String, dynamic> user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userSessionKey, json.encode(user));
    } catch (e) {
      log('Error saving user session: $e');
    }
  }

  /// Clear user session (logout)
  static Future<void> clearUserSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userSessionKey);
    } catch (e) {
      log('Error clearing user session: $e');
    }
  }

  /// Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
  }

  /// Save JWT token
  static Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      log('Error saving token: $e');
    }
  }

  /// Get JWT token
  static Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      log('Error getting token: $e');
      return null;
    }
  }

  /// Delete user profile picture (Super Admin/Admin)
  static Future<Map<String, dynamic>> deleteUserProfilePicture(
      int userId) async {
    try {
      final response = await _makeRequest(
        'delete_user_profile_picture',
        method: 'POST',
        body: {
          'user_id': userId,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete profile picture: $e');
    }
  }

  /// Clear JWT token
  static Future<void> _clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (e) {
      log('Error clearing token: $e');
    }
  }

  // ==================== COURSE META / SUMMARY ENDPOINTS ====================

  /// Fetch course summary/meta from backend `course_summary` endpoint.
  /// Provide either (classId & subjectId) or (level, className, subjectName).
  static Future<Map<String, dynamic>?> getCourseSummary({
    int? classId,
    int? subjectId,
    String? level,
    String? className,
    String? subjectName,
  }) async {
    try {
      final qp = <String>[
        if (classId != null) 'class_id=$classId',
        if (subjectId != null) 'subject_id=$subjectId',
        if (level != null) 'level=${Uri.encodeComponent(level)}',
        if (className != null) 'class_name=${Uri.encodeComponent(className)}',
        if (subjectName != null)
          'subject_name=${Uri.encodeComponent(subjectName)}',
      ].join('&');
      final endpoint = qp.isEmpty ? 'course_summary' : 'course_summary&$qp';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return Map<String, dynamic>.from(result['meta'] ?? {});
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch course summary: $e');
    }
  }

  /// Save course summary/meta. Requires Admin Teacher JWT (role Admin, not super admin).
  /// Provide either (classId & subjectId) or (level, className, subjectName).
  static Future<Map<String, dynamic>> saveCourseSummary({
    int? classId,
    int? subjectId,
    String? level,
    String? className,
    String? subjectName,
    String? todayTopics,
    String? reviseTopics,
    String? upcomingLectureAt, // 'YYYY-MM-DD HH:MM:SS'
    String? nextQuizAt, // 'YYYY-MM-DD HH:MM:SS'
    String? nextQuizTopic,
    String? nextAssignmentUrl,
    String? nextAssignmentDeadline, // 'YYYY-MM-DD HH:MM:SS'
    int? nextAssignmentNumber,
    int? totalLectures,
    String? lecturesJson, // JSON string array of {number,name,link}
    String? lastQuizTakenAt, // 'YYYY-MM-DD HH:MM:SS'
    int? lastQuizNumber,
    String? lastAssignmentTakenAt, // 'YYYY-MM-DD HH:MM:SS'
    int? lastAssignmentNumber,
  }) async {
    try {
      final body = <String, dynamic>{
        if (classId != null) 'class_id': classId,
        if (subjectId != null) 'subject_id': subjectId,
        if (level != null) 'level': level,
        if (className != null) 'class_name': className,
        if (subjectName != null) 'subject_name': subjectName,
        if (todayTopics != null) 'today_topics': todayTopics,
        if (reviseTopics != null) 'revise_topics': reviseTopics,
        if (upcomingLectureAt != null) 'upcoming_lecture_at': upcomingLectureAt,
        if (nextQuizAt != null) 'next_quiz_at': nextQuizAt,
        if (nextQuizTopic != null) 'next_quiz_topic': nextQuizTopic,
        if (nextAssignmentUrl != null) 'next_assignment_url': nextAssignmentUrl,
        if (nextAssignmentDeadline != null)
          'next_assignment_deadline': nextAssignmentDeadline,
        if (nextAssignmentNumber != null)
          'next_assignment_number': nextAssignmentNumber,
        if (totalLectures != null) 'total_lectures': totalLectures,
        if (lecturesJson != null) 'lectures_json': lecturesJson,
        if (lastQuizTakenAt != null) 'last_quiz_taken_at': lastQuizTakenAt,
        if (lastQuizNumber != null) 'last_quiz_number': lastQuizNumber,
        if (lastAssignmentTakenAt != null)
          'last_assignment_taken_at': lastAssignmentTakenAt,
        if (lastAssignmentNumber != null)
          'last_assignment_number': lastAssignmentNumber,
      };
      final response = await _makeRequest(
        'course_summary',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save course summary: $e');
    }
  }

  // ==================== COURSE ASSIGNMENT ENDPOINTS ====================

  /// List teachers (admins that are not super admins)
  static Future<List<Map<String, dynamic>>> getTeachers() async {
    try {
      final response = await _makeRequest('teachers');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['teachers'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch teachers');
    } catch (e) {
      throw Exception('Failed to fetch teachers: $e');
    }
  }

  /// List classes for a given education level
  static Future<List<Map<String, dynamic>>> getClasses(String level) async {
    try {
      final response =
          await _makeRequest('classes&level=${Uri.encodeComponent(level)}');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['classes'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch classes');
    } catch (e) {
      throw Exception('Failed to fetch classes: $e');
    }
  }

  /// List subjects for a given education level
  static Future<List<Map<String, dynamic>>> getSubjects(String level) async {
    try {
      final response =
          await _makeRequest('subjects&level=${Uri.encodeComponent(level)}');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['subjects'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch subjects');
    } catch (e) {
      throw Exception('Failed to fetch subjects: $e');
    }
  }

  /// Add a subject to a given level (Super Admin)
  static Future<Map<String, dynamic>> addSubject({
    required String level,
    required String subjectName,
  }) async {
    try {
      final response = await _makeRequest(
        'subject',
        method: 'POST',
        body: {
          'level': level,
          'subject_name': subjectName,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to add subject: $e');
    }
  }

  /// Delete a subject from a given level (Super Admin)
  static Future<Map<String, dynamic>> deleteSubject({
    required String level,
    required String subjectName,
  }) async {
    try {
      final response = await _makeRequest(
        'subject&level=${Uri.encodeComponent(level)}&subject_name=${Uri.encodeComponent(subjectName)}',
        method: 'DELETE',
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete subject: $e');
    }
  }

  /// Fetch assignments. Optionally filter by level and class name
  static Future<List<Map<String, dynamic>>> getAssignments(
      {String? level, String? className}) async {
    try {
      final qp = [
        if (level != null) 'level=${Uri.encodeComponent(level)}',
        if (className != null) 'class_name=${Uri.encodeComponent(className)}',
      ].join('&');
      final endpoint = qp.isEmpty ? 'assignments' : 'assignments&$qp';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['assignments'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch assignments');
    } catch (e) {
      throw Exception('Failed to fetch assignments: $e');
    }
  }

  /// Save assignments for a teacher for a class at a given level
  /// subjects should be an array of subject names matching the chosen level
  static Future<Map<String, dynamic>> saveAssignments({
    required int teacherUserId,
    required String level,
    required String className,
    required List<String> subjects,
  }) async {
    try {
      final response = await _makeRequest(
        'save_assignments',
        method: 'POST',
        body: {
          'teacher_user_id': teacherUserId,
          'level': level,
          'class_name': className,
          'subjects': subjects,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save assignments: $e');
    }
  }

  /// Remove a specific subject assignment for a class
  static Future<Map<String, dynamic>> deleteAssignment({
    required int assignmentId,
  }) async {
    try {
      final response = await _makeRequest(
        'assignment&id=$assignmentId',
        method: 'DELETE',
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete assignment: $e');
    }
  }

  // ==================== CLASS SUBJECT PLANNER ====================

  static Future<Map<String, dynamic>> getPlanner({
    required int classId,
    required int subjectId,
    int? teacherAssignmentId,
  }) async {
    try {
      final params = <String>[
        'class_id=$classId',
        'subject_id=$subjectId',
        if (teacherAssignmentId != null) 'teacher_assignment_id=$teacherAssignmentId',
      ].join('&');
      final response = await _makeRequest('planner&$params');
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to load planner: $e');
    }
  }

  static Future<Map<String, dynamic>> savePlannerPlan({
    int? planId,
    required int classId,
    required int subjectId,
    int? teacherAssignmentId,
    String? academicTermLabel,
    String? frequency,
    String? singleDate,
    String? rangeStart,
    String? rangeEnd,
    String? status,
  }) async {
    try {
      final body = <String, dynamic>{
        'class_id': classId,
        'subject_id': subjectId,
        if (planId != null) 'plan_id': planId,
        if (teacherAssignmentId != null) 'teacher_assignment_id': teacherAssignmentId,
        if (academicTermLabel != null) 'academic_term_label': academicTermLabel,
        if (frequency != null) 'frequency': frequency,
        if (singleDate != null) 'single_date': singleDate,
        if (rangeStart != null) 'range_start': rangeStart,
        if (rangeEnd != null) 'range_end': rangeEnd,
        if (status != null) 'status': status,
      };
      final response = await _makeRequest(
        'planner_plan',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save planner plan: $e');
    }
  }

  static Future<Map<String, dynamic>> savePlannerItem({
    int? id,
    required int planId,
    String? itemType,
    String? title,
    String? topic,
    String? description,
    int? totalMarks,
    double? weightPercent,
    String? scheduledFor,
    String? scheduledUntil,
    String? status,
    String? verificationNotes,
    String? deferredTo,
    List<Map<String, dynamic>>? sessions,
  }) async {
    try {
      final body = <String, dynamic>{
        'plan_id': planId,
        if (id != null) 'id': id,
        if (itemType != null) 'item_type': itemType,
        if (title != null) 'title': title,
        if (topic != null) 'topic': topic,
        if (description != null) 'description': description,
        if (totalMarks != null) 'total_marks': totalMarks,
        if (weightPercent != null) 'weight_percent': weightPercent,
        if (scheduledFor != null) 'scheduled_for': scheduledFor,
        if (scheduledUntil != null) 'scheduled_until': scheduledUntil,
        if (status != null) 'status': status,
        if (verificationNotes != null) 'verification_notes': verificationNotes,
        if (deferredTo != null) 'deferred_to': deferredTo,
        if (sessions != null) 'sessions': sessions,
      };
      final response = await _makeRequest(
        'planner_item',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save planner item: $e');
    }
  }

  static Future<Map<String, dynamic>> updatePlannerItemStatus({
    required int id,
    required String status,
    String? verificationNotes,
    String? scheduledFor,
    String? scheduledUntil,
    String? deferredTo,
  }) async {
    try {
      final body = <String, dynamic>{
        'id': id,
        'status': status,
        if (verificationNotes != null) 'verification_notes': verificationNotes,
        if (scheduledFor != null) 'scheduled_for': scheduledFor,
        if (scheduledUntil != null) 'scheduled_until': scheduledUntil,
        if (deferredTo != null) 'deferred_to': deferredTo,
      };
      final response = await _makeRequest(
        'planner_item_status',
        method: 'PUT',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to update planner item status: $e');
    }
  }

  static Future<Map<String, dynamic>> deletePlannerItem({
    required int id,
  }) async {
    try {
      final response = await _makeRequest('planner_item&id=$id', method: 'DELETE');
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete planner item: $e');
    }
  }

  /// Generic HTTP request method with timeout
  static Future<http.Response> _makeRequest(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Map<String, String>? additionalParams,
  }) async {
    String url = '$baseUrl?endpoint=$endpoint';
    if (additionalParams != null && additionalParams.isNotEmpty) {
      final queryParams = additionalParams.entries
          .map((e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      url += '&$queryParams';
    }
    log('Making request to URL: $url');
    final uri = Uri.parse(url);

    // Attach Authorization header if token exists
    final token = await _getToken();
    final requestHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };
    if (token != null && token.isNotEmpty) {
      requestHeaders['Authorization'] = 'Bearer $token';
    }

    Future<http.Response> send(Uri target) async {
      switch (method.toUpperCase()) {
        case 'GET':
          return await http
              .get(target, headers: requestHeaders)
              .timeout(_timeoutDuration);
        case 'POST':
          return await http
              .post(target,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null)
              .timeout(_timeoutDuration);
        case 'PUT':
          return await http
              .put(target,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null)
              .timeout(_timeoutDuration);
        case 'DELETE':
          return await http
              .delete(target, headers: requestHeaders)
              .timeout(_timeoutDuration);
        default:
          throw Exception('Unsupported HTTP method: $method');
      }
    }

    Future<http.Response> tryFallbackIfLocalHost(Object e) async {
      final host = uri.host;
      final isLocalHost =
          host == '10.0.2.2' || host == 'localhost' || host == '127.0.0.1';
      if (!isLocalHost) {
        if (e is Exception) {
          throw e;
        } else {
          throw Exception(e.toString());
        }
      }
      const lanIp = '192.168.18.30';
      final fallback = uri.replace(host: lanIp);
      log('Error contacting $host (${e.runtimeType}). Retrying with LAN IP: $lanIp -> $fallback');
      final response = await send(fallback);
      log('Fallback response status: ${response.statusCode}');
      return response;
    }

    try {
      final response = await send(uri);
      log('Response status: ${response.statusCode}');
      log('Response body: ${response.body}');
      return response;
    } on SocketException catch (e) {
      try {
        return await tryFallbackIfLocalHost(e);
      } catch (_) {
        throw Exception(
            'Network error: Cannot connect to server (${e.message}). Ensure phone and PC are on same Wi‑Fi and server is running.');
      }
    } on TimeoutException catch (e) {
      try {
        return await tryFallbackIfLocalHost(e);
      } catch (_) {
        throw Exception(
            'Network error: Request timed out. Please ensure the server at $baseUrl is reachable from your device.');
      }
    } on http.ClientException catch (e) {
      try {
        return await tryFallbackIfLocalHost(e);
      } catch (_) {
        throw Exception('Network error: ${e.message}');
      }
    } on HttpException catch (e) {
      throw Exception('Network error: HTTP request failed - ${e.message}');
    } on FormatException catch (e) {
      throw Exception('Network error: Invalid response format - ${e.message}');
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        throw Exception('Network error: Request timed out. Please try again.');
      }
      throw Exception('Network error: $e');
    }
  }

  /// Parse API response and handle errors
  static Map<String, dynamic> _parseResponse(http.Response response) {
    try {
      // Check if response body is empty
      if (response.body.isEmpty) {
        throw Exception('Empty response from server');
      }

      // Trim and attempt normal decode first
      String raw = response.body.trim();
      // Strip UTF-8 BOM and any stray zero-width/invisible characters
      const bom = '\uFEFF';
      if (raw.startsWith(bom)) {
        raw = raw.substring(1);
      }
      raw = raw
          .replaceAll('\u200B', '') // zero-width space
          .replaceAll('\u200C', '') // zero-width non-joiner
          .replaceAll('\u200D', '') // zero-width joiner
          .replaceAll('\u2060', '') // word joiner
          .replaceAll('\u00A0', ' '); // non-breaking space -> space
      try {
        final jsonResponse = json.decode(raw);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (jsonResponse is! Map<String, dynamic>) {
            throw Exception('Invalid response format: Expected JSON object');
          }
          return jsonResponse;
        } else {
          if (jsonResponse is Map<String, dynamic> &&
              jsonResponse.containsKey('error')) {
            throw Exception(
                jsonResponse['error'] ?? 'HTTP ${response.statusCode}');
          } else {
            throw Exception('HTTP ${response.statusCode}: ${response.body}');
          }
        }
      } on FormatException {
        // Fallback: extract first JSON object if there is extra noise around it
        final start = raw.indexOf('{');
        final end = raw.lastIndexOf('}');
        if (start != -1 && end != -1 && end > start) {
          final cleaned = raw.substring(start, end + 1);
          final jsonResponse = json.decode(cleaned);
          if (jsonResponse is! Map<String, dynamic>) {
            throw Exception('Invalid response format: Expected JSON object');
          }
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return jsonResponse;
          } else {
            if (jsonResponse.containsKey('error')) {
              throw Exception(
                  jsonResponse['error'] ?? 'HTTP ${response.statusCode}');
            } else {
              throw Exception('HTTP ${response.statusCode}: $cleaned');
            }
          }
        }
        // If we get here, rethrow original format error
        rethrow;
      }
    } on FormatException catch (e) {
      throw Exception('Invalid JSON response: ${e.message}');
    } catch (e) {
      if (e.toString().contains('Empty response')) {
        throw Exception('Server returned empty response. Please try again.');
      }
      rethrow;
    }
  }

  // ==================== AUTHENTICATION ENDPOINTS ====================

  /// User login
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final response = await _makeRequest(
        'login',
        method: 'POST',
        body: {
          'email': email,
          'password': password,
        },
      );

      final result = _parseResponse(response);

      if (result['success'] == true) {
        // Save token if present
        final token = result['token'];
        if (token is String && token.isNotEmpty) {
          await _saveToken(token);
        }
        // Save user session if present
        if (result['user'] != null) {
          await saveUserSession(result['user']);
        }
      }

      return result;
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  /// User registration
  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String role = 'Student',
  }) async {
    try {
      final response = await _makeRequest(
        'register',
        method: 'POST',
        body: {
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        },
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  /// User logout
  static Future<void> logout() async {
    await clearUserSession();
    await _clearToken();
  }

  // ==================== USER MANAGEMENT ENDPOINTS ====================

  /// Get all users
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final response = await _makeRequest('users');
      final result = _parseResponse(response);

      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['users'] ?? []);
      } else {
        throw Exception(result['error'] ?? 'Failed to fetch users');
      }
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }

  /// Get user by ID
  static Future<Map<String, dynamic>> getUserById(int id) async {
    try {
      final response = await _makeRequest('user&id=$id');
      final result = _parseResponse(response);

      if (result['success'] == true) {
        return result['user'];
      } else {
        throw Exception(result['error'] ?? 'Failed to fetch user');
      }
    } catch (e) {
      throw Exception('Failed to fetch user: $e');
    }
  }

  /// Create new user
  static Future<Map<String, dynamic>> createUser(
    String name,
    String email, {
    String? password,
    String role = 'Student',
  }) async {
    try {
      final body = {
        'name': name,
        'email': email,
        'role': role,
      };

      if (password != null && password.isNotEmpty) {
        body['password'] = password;
      }

      final response = await _makeRequest(
        'user',
        method: 'POST',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  /// Get courses assigned to the authenticated teacher
  static Future<List<Map<String, dynamic>>> getMyCourses() async {
    try {
      final response = await _makeRequest('my_courses');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['courses'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch my courses');
    } catch (e) {
      throw Exception('Failed to fetch my courses: $e');
    }
  }

  /// Update user
  static Future<Map<String, dynamic>> updateUser(
    int id, {
    String? name,
    String? email,
    String? role,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (role != null) body['role'] = role;

      final response = await _makeRequest(
        'user&id=$id',
        method: 'PUT',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  /// Delete user (Super Admin)
  static Future<Map<String, dynamic>> deleteUser(int id) async {
    try {
      final response = await _makeRequest(
        'user&id=$id',
        method: 'DELETE',
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }

  /// Test connection to the API
  static Future<Map<String, dynamic>> testConnection() async {
    try {
      // Backend expects endpoint=test
      final response = await _makeRequest('test');
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Connection test failed: $e');
    }
  }

  /// Submit assignment link
  static Future<Map<String, dynamic>> submitAssignmentLink({
    required int classId,
    required int subjectId,
    required int assignmentNumber,
    required String linkUrl,
  }) async {
    try {
      _dlog('submitAssignmentLink -> baseUrl=$baseUrl');
      final body = {
        'action': 'submit_assignment',
        'class_id': classId,
        'subject_id': subjectId,
        'assignment_number': assignmentNumber,
        'submission_type': 'link',
        'content': linkUrl,
      };
      _dlog('submitAssignmentLink body: $body');

      final response = await _makeRequest(
        'submit_assignment',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      _dlog('submitAssignmentLink error: $e');
      throw Exception('Failed to submit assignment link: $e');
    }
  }

  /// Submit assignment file
  static Future<Map<String, dynamic>> submitAssignmentFile({
    required int classId,
    required int subjectId,
    required int assignmentNumber,
    required String filePath,
  }) async {
    try {
      _dlog('submitAssignmentFile -> baseUrl=$baseUrl');
      // Important: backend router reads endpoint from query string
      final uri = Uri.parse('$baseUrl?endpoint=submit_assignment');
      final request = http.MultipartRequest('POST', uri);

      // Add authentication header
      final token = await _getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add form fields (endpoint also present in URL for router)
      request.fields['class_id'] = classId.toString();
      request.fields['subject_id'] = subjectId.toString();
      request.fields['assignment_number'] = assignmentNumber.toString();
      request.fields['submission_type'] = 'file';
      _dlog('submitAssignmentFile fields: ${request.fields}');

      // Add file
      final file = await http.MultipartFile.fromPath('file', filePath);
      _dlog('submitAssignmentFile attaching file: path=$filePath');
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      log('File upload response status: ${response.statusCode}');
      log('File upload response body: ${response.body}');
      return _parseResponse(response);
    } catch (e) {
      _dlog('submitAssignmentFile error: $e');
      throw Exception('Failed to submit assignment file: $e');
    }
  }

  /// Submit assignment file using bytes (for web compatibility)
  static Future<Map<String, dynamic>> submitAssignmentBytes({
    required int classId,
    required int subjectId,
    required int assignmentNumber,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    try {
      _dlog('submitAssignmentBytes -> baseUrl=$baseUrl');
      // Important: backend router reads endpoint from query string
      final uri = Uri.parse('$baseUrl?endpoint=submit_assignment');
      final request = http.MultipartRequest('POST', uri);

      // Add authentication header
      final token = await _getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add form fields
      request.fields['endpoint'] = 'submit_assignment';
      request.fields['class_id'] = classId.toString();
      request.fields['subject_id'] = subjectId.toString();
      request.fields['assignment_number'] = assignmentNumber.toString();
      request.fields['submission_type'] = 'file';
      _dlog('submitAssignmentBytes fields: ${request.fields}');

      // Add file from bytes
      final file = http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      );
      _dlog(
          'submitAssignmentBytes attaching file: name=$fileName, bytes=${fileBytes.length}');
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      log('Bytes upload response status: ${response.statusCode}');
      log('Bytes upload response body: ${response.body}');
      return _parseResponse(response);
    } catch (e) {
      _dlog('submitAssignmentBytes error: $e');
      throw Exception('Failed to submit assignment file: $e');
    }
  }

  /// Get assignment submissions (for admin/teacher view)
  static Future<List<Map<String, dynamic>>> getAssignmentSubmissions({
    int? classId,
    int? subjectId,
    int? assignmentNumber,
    int? studentUserId,
  }) async {
    try {
      final body = {
        'action': 'get_assignment_submissions',
      };

      if (classId != null) body['class_id'] = classId.toString();
      if (subjectId != null) body['subject_id'] = subjectId.toString();
      if (assignmentNumber != null) {
        body['assignment_number'] = assignmentNumber.toString();
      }

      final response = await _makeRequest(
        'get_assignment_submissions',
        method: 'POST',
        body: body,
      );
      final result = _parseResponse(response);

      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['submissions'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch submissions');
    } catch (e) {
      throw Exception('Failed to fetch assignment submissions: $e');
    }
  }

  /// Download assignment file
  static Future<String> downloadAssignmentFile({
    required int submissionId,
  }) async {
    try {
      final body = {
        'action': 'download_assignment',
        'submission_id': submissionId,
      };

      final response = await _makeRequest(
        'download_assignment',
        method: 'POST',
        body: body,
      );
      final result = _parseResponse(response);

      if (result['success'] == true) {
        if (result['type'] == 'link') {
          return result['url'];
        }
        // For file downloads, the backend will stream the file
        // This would need additional handling for actual file downloads
        return 'File download initiated';
      }
      throw Exception(result['error'] ?? 'Failed to download file');
    } catch (e) {
      throw Exception('Failed to download assignment file: $e');
    }
  }

  /// Get user profile
  static Future<Map<String, dynamic>?> getUserProfile(int userId) async {
    try {
      final response = await _makeRequest('profile&user_id=$userId');
      final result = _parseResponse(response);

      if (result['success'] == true) {
        return result['profile'];
      } else {
        throw Exception(result['error'] ?? 'Failed to fetch profile');
      }
    } catch (e) {
      throw Exception('Failed to fetch profile: $e');
    }
  }

  /// Create user profile
  static Future<Map<String, dynamic>> createUserProfile(
    int userId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      final body = {'user_id': userId, ...profileData};

      final response = await _makeRequest(
        'profile',
        method: 'POST',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to create profile: $e');
    }
  }

  /// Update user profile
  static Future<Map<String, dynamic>> updateUserProfile(
    int userId,
    Map<String, dynamic> profileData,
  ) async {
    try {
      final body = {'user_id': userId, ...profileData};

      final response = await _makeRequest(
        'profile&user_id=$userId',
        method: 'PUT',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  // ==================== COURSE ENDPOINTS ====================

  /// Get all courses
  static Future<List<Map<String, dynamic>>> getAllCourses() async {
    try {
      final response = await _makeRequest('courses');
      final result = _parseResponse(response);

      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['courses'] ?? []);
      } else {
        throw Exception(result['error'] ?? 'Failed to fetch courses');
      }
    } catch (e) {
      throw Exception('Failed to fetch courses: $e');
    }
  }

  /// Create new course
  static Future<Map<String, dynamic>> createCourse(
    String name, {
    String? description,
  }) async {
    try {
      final body = {'name': name};
      if (description != null) body['description'] = description;

      final response = await _makeRequest(
        'course',
        method: 'POST',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to create course: $e');
    }
  }

  // ==================== CLASS ROSTER ENDPOINTS ====================

  /// Get students in a class (roster)
  /// Returns: [{ user_id, name, roll_number, ... }]
  static Future<List<Map<String, dynamic>>> getStudentsInClass(
      String className) async {
    try {
      final endpoint =
          'students_in_class&class_name=${Uri.encodeComponent(className)}';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['students'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch students for class');
    } catch (e) {
      throw Exception('Failed to fetch students for class: $e');
    }
  }

  // ==================== ATTENDANCE ENDPOINTS ====================

  /// Get user attendance
  static Future<List<Map<String, dynamic>>> getUserAttendance(
      int userId) async {
    try {
      final response = await _makeRequest('attendance&user_id=$userId');
      // Debug preview to diagnose JSON issues
      try {
        final body = response.body;
        final preview =
            body.length > 300 ? '${body.substring(0, 300)}...' : body;
        log('[ApiService] attendance status=${response.statusCode}; bodyPreview=$preview');
      } catch (_) {}
      final result = _parseResponse(response);

      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['attendance'] ?? []);
      } else {
        throw Exception(result['error'] ?? 'Failed to fetch attendance');
      }
    } catch (e) {
      throw Exception('Failed to fetch attendance: $e');
    }
  }

  /// Record attendance
  static Future<Map<String, dynamic>> recordAttendance(
    int userId,
    int courseId,
    String date, {
    String status = 'present',
    String? topic,
  }) async {
    try {
      final body = {
        'user_id': userId,
        'course_id': courseId,
        'date': date,
        'status': status,
      };
      if (topic != null) body['topic'] = topic;

      final response = await _makeRequest(
        'attendance',
        method: 'POST',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to record attendance: $e');
    }
  }

  /// Get global term start date
  static Future<String?> getTermStartDate() async {
    try {
      final response = await _makeRequest('term_start');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return result['term_start_date'] as String?;
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch term start date: $e');
    }
  }

  /// Set term start date (Admin only)
  static Future<Map<String, dynamic>> setTermStartDate(String yyyyMmDd) async {
    try {
      final response = await _makeRequest(
        'term_start',
        method: 'POST',
        body: {'term_start_date': yyyyMmDd},
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to set term start date: $e');
    }
  }

  /// Get attendance summary for current user (or specified userId if Admin)
  static Future<Map<String, dynamic>> getAttendanceSummary(
      {int? userId}) async {
    try {
      final endpoint = userId != null
          ? 'attendance_summary&user_id=$userId'
          : 'attendance_summary';
      // Temporary debug logging for diagnosing attendance fetch
      try {
        final token = await _getToken();
        final fullUrl = '${ApiService.baseUrl}?endpoint=$endpoint';
        log('[ApiService] GET $fullUrl (tokenPresent=${token != null && token.isNotEmpty})');
      } catch (_) {}

      final response = await _makeRequest(endpoint);
      try {
        final body = response.body;
        final preview =
            body.length > 300 ? '${body.substring(0, 300)}...' : body;
        log('[ApiService] attendance_summary status=${response.statusCode}; bodyPreview=$preview');
      } catch (_) {}

      final result = _parseResponse(response);
      if (result['success'] == true) {
        return result;
      }
      throw Exception(result['error'] ?? 'Failed to fetch attendance summary');
    } catch (e) {
      log('[ApiService] attendance_summary error: $e');
      throw Exception('Failed to fetch attendance summary: $e');
    }
  }

  /// Upsert a daily attendance record (Admin)
  static Future<Map<String, dynamic>> upsertAttendanceRecord({
    required int userId,
    required String date, // YYYY-MM-DD
    required String status, // present | absent | leave
  }) async {
    try {
      final response = await _makeRequest(
        'attendance_record',
        method: 'POST',
        body: {
          'user_id': userId,
          'date': date,
          'status': status,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to upsert attendance record: $e');
    }
  }

  // ==================== UTILITY METHODS ====================

  /// Get current user ID from session
  static Future<int?> getCurrentUserId() async {
    final user = await getCurrentUser();
    final dynamic rawId = user?['id'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    return null;
  }

  /// Refresh user session data
  static Future<void> refreshUserSession() async {
    try {
      final userId = await getCurrentUserId();
      if (userId != null) {
        final user = await getUserById(userId);
        await saveUserSession(user);
      }
    } catch (e) {
      log('Error refreshing user session: $e');
    }
  }

  // ==================== CALENDAR ENDPOINTS ====================

  /// Fetch calendar data for a month (holidays + user events)
  static Future<Map<String, dynamic>> getCalendarMonth(
      int year, int month) async {
    try {
      final response = await _makeRequest('calendar&year=$year&month=$month');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return result;
      }
      throw Exception(result['error'] ?? 'Failed to fetch calendar');
    } catch (e) {
      throw Exception('Failed to fetch calendar: $e');
    }
  }

  /// Create a new calendar event (requires Teacher/Admin JWT)
  static Future<Map<String, dynamic>> createCalendarEvent({
    required String date, // YYYY-MM-DD
    required String title,
    String? duration,
    String? description,
  }) async {
    try {
      final body = {
        'date': date,
        'title': title,
        if (duration != null) 'duration': duration,
        if (description != null && description.isNotEmpty)
          'description': description,
      };
      final response = await _makeRequest(
        'calendar_event',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to create calendar event: $e');
    }
  }

  /// Delete a calendar event (requires Super Admin JWT)
  static Future<Map<String, dynamic>> deleteCalendarEvent(int eventId) async {
    try {
      final response = await _makeRequest(
        'calendar_event&id=$eventId',
        method: 'DELETE',
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to delete calendar event: $e');
    }
  }

  // ==================== NOTICES ENDPOINTS ====================

  /// List recent notices
  static Future<List<Map<String, dynamic>>> listNotices(
      {int limit = 10}) async {
    try {
      final response = await _makeRequest('notices&limit=$limit');
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['notices'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch notices');
    } catch (e) {
      throw Exception('Failed to fetch notices: $e');
    }
  }

  /// Create a notice (Admin/Teacher/Principal)
  static Future<Map<String, dynamic>> createNotice({
    required String title,
    String? body,
  }) async {
    try {
      final response = await _makeRequest(
        'notice',
        method: 'POST',
        body: {
          'title': title,
          if (body != null) 'body': body,
        },
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to create notice: $e');
    }
  }

  // ==================== MARKS ENDPOINTS ====================

  /// Fetch student marks for a class/subject and specific kind+number
  /// Provide either (classId & subjectId) or (level, className, subjectName).
  static Future<List<Map<String, dynamic>>> getStudentMarks({
    int? classId,
    int? subjectId,
    String? level,
    String? className,
    String? subjectName,
    required String kind, // 'quiz' | 'assignment'
    required int number,
  }) async {
    try {
      final qp = <String>[
        if (classId != null) 'class_id=$classId',
        if (subjectId != null) 'subject_id=$subjectId',
        if (level != null) 'level=${Uri.encodeComponent(level)}',
        if (className != null) 'class_name=${Uri.encodeComponent(className)}',
        if (subjectName != null)
          'subject_name=${Uri.encodeComponent(subjectName)}',
        'kind=${Uri.encodeComponent(kind)}',
        'number=$number',
      ].join('&');
      final endpoint = qp.isEmpty ? 'student_marks' : 'student_marks&$qp';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['marks'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch student marks');
    } catch (e) {
      throw Exception('Failed to fetch student marks: $e');
    }
  }

  /// Upsert marks for multiple students. Requires Admin Teacher JWT.
  /// entries: [{ 'student_user_id': int, 'obtained_marks': num }]
  static Future<Map<String, dynamic>> upsertStudentMarks({
    int? classId,
    int? subjectId,
    String? level,
    String? className,
    String? subjectName,
    required String kind, // 'quiz' | 'assignment'
    required int number,
    required int totalMarks,
    String? takenAt, // 'YYYY-MM-DD HH:MM:SS'
    String? topic,
    String? title,
    String? description,
    String? deadline,
    String? scheduledAt,
    String? attemptedAt,
    String? submittedAt,
    String? gradedAt,
    required List<Map<String, dynamic>> entries,
  }) async {
    try {
      final body = <String, dynamic>{
        if (classId != null) 'class_id': classId,
        if (subjectId != null) 'subject_id': subjectId,
        if (level != null) 'level': level,
        if (className != null) 'class_name': className,
        if (subjectName != null) 'subject_name': subjectName,
        'kind': kind,
        'number': number,
        'total_marks': totalMarks,
        'entries': entries,
      };

      if (kind == 'assignment') {
        if (title != null) body['title'] = title;
        if (description != null) body['description'] = description;
        if (deadline != null) body['deadline'] = deadline;
        final submittedTimestamp = submittedAt ?? takenAt;
        if (submittedTimestamp != null) body['submitted_at'] = submittedTimestamp;
        if (gradedAt != null) body['graded_at'] = gradedAt;
      } else {
        if (title != null) body['title'] = title;
        if (topic != null) body['topic'] = topic;
        if (scheduledAt != null) body['scheduled_at'] = scheduledAt;
        final attemptTimestamp = attemptedAt ?? takenAt;
        if (attemptTimestamp != null) body['attempted_at'] = attemptTimestamp;
        if (gradedAt != null) body['graded_at'] = gradedAt;
      }

      if (kind == 'assignment' && topic != null) {
        body['topic'] = topic;
      }
      if (kind == 'quiz' && submittedAt != null) {
        body['submitted_at'] = submittedAt;
      }

      final response = await _makeRequest(
        'student_marks_upsert',
        method: 'POST',
        body: body,
      );
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to upsert student marks: $e');
    }
  }

  /// Get student's quiz history for a class and subject.
  /// Returns latest-first list of entries: [{ number, total_marks, obtained_marks, updated_at, topic?, taken_at? }]
  static Future<List<Map<String, dynamic>>> getStudentQuizHistory({
    required int classId,
    required int subjectId,
    int? userId, // optional; if omitted, server uses current user from JWT
  }) async {
    try {
      final qp = <String>[
        'class_id=$classId',
        'subject_id=$subjectId',
        if (userId != null) 'user_id=$userId',
      ].join('&');
      final endpoint = 'student_quiz_history&$qp';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['history'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch quiz history');
    } catch (e) {
      throw Exception('Failed to fetch quiz history: $e');
    }
  }

  /// Fetches metadata for a course including next assignment number
  static Future<Map<String, dynamic>> getCourseMeta({
    required int classId,
    required int subjectId,
  }) async {
    try {
      final endpoint =
          'get_course_meta&class_id=${classId.toString()}&subject_id=${subjectId.toString()}';
      final response = await _makeRequest(endpoint);

      return _parseResponse(response);
    } catch (e) {
      debugPrint('Error fetching course meta: $e');
      return {'success': false, 'error': 'Failed to fetch course metadata'};
    }
  }

  /// Get student's assignment history for a class and subject.
  /// Returns latest-first list of entries: [{ number, total_marks, obtained_marks, updated_at, topic?, taken_at? }]
  static Future<List<Map<String, dynamic>>> getStudentAssignmentHistory({
    required int classId,
    required int subjectId,
    int? userId, // optional; if omitted, server uses current user from JWT
  }) async {
    try {
      final qp = <String>[
        'class_id=$classId',
        'subject_id=$subjectId',
        if (userId != null) 'user_id=$userId',
      ].join('&');
      final endpoint = 'student_assignment_history&$qp';
      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['history'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch assignment history');
    } catch (e) {
      throw Exception('Failed to fetch assignment history: $e');
    }
  }

  /// Submit an assignment with either a file upload or a link
  static Future<Map<String, dynamic>> submitAssignment({
    required int classId,
    required int subjectId,
    required int assignmentNumber,
    required String submissionType, // 'file' or 'link'
    required File file,
    String? filePath,
    String? link,
  }) async {
    try {
      final uri = Uri.parse('${baseUrl}submit_assignment');
      final request = http.MultipartRequest('POST', uri);

      // Add auth token if available
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add form fields
      request.fields['class_id'] = classId.toString();
      request.fields['subject_id'] = subjectId.toString();
      request.fields['assignment_number'] = assignmentNumber.toString();
      request.fields['submission_type'] = submissionType;

      // Add file if provided
      if (submissionType == 'file') {
        final fileStream = http.ByteStream(file.openRead());
        final length = await file.length();
        final extension = filePath != null && filePath.contains('.')
            ? filePath.split('.').last
            : 'bin';
        final multipartFile = http.MultipartFile(
          'file',
          fileStream,
          length,
          filename:
              filePath?.split('/').last ?? 'assignment_submission.$extension',
        );
        request.files.add(multipartFile);
      } else if (submissionType == 'link' && link != null) {
        request.fields['link'] = link;
      } else {
        throw Exception(
            'Invalid submission: either file or link must be provided');
      }

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success'] == true) {
          return result;
        } else {
          throw Exception(result['error'] ?? 'Failed to submit assignment');
        }
      } else {
        throw Exception('Failed to submit assignment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to submit assignment: $e');
    }
  }

  /// Record a payment for a student
  ///
  /// [studentId] The ID of the student
  /// [amount] The payment amount
  /// [paymentMethod] The payment method used
  /// [notes] Optional notes about the payment
  /// Returns the updated student record with payment info
  static Future<Map<String, dynamic>> recordPayment({
    required int studentId,
    required double amount,
    required String paymentMethod,
    String? notes,
  }) async {
    try {
      final response = await _makeRequest(
        'record_payment',
        method: 'POST',
        body: {
          'student_id': studentId,
          'amount': amount,
          'payment_method': paymentMethod,
          if (notes != null) 'notes': notes,
        },
      );

      final result = _parseResponse(response);
      if (result['success'] == true) {
        return Map<String, dynamic>.from(result['student'] ?? {});
      }
      throw Exception(result['error'] ?? 'Failed to record payment');
    } catch (e) {
      throw Exception('Failed to record payment: $e');
    }
  }

  /// Get payment history for a student
  ///
  /// [studentId] The ID of the student
  /// Returns a list of payment records
  static Future<List<Map<String, dynamic>>> getPaymentHistory(
      int studentId) async {
    try {
      // Append query directly to endpoint since _makeRequest doesn't accept queryParams
      final response = await _makeRequest(
        'payment_history?student_id=$studentId',
        method: 'GET',
      );

      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['payments'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to fetch payment history');
    } catch (e) {
      throw Exception('Failed to fetch payment history: $e');
    }
  }

  /// Search for students by name or roll number
  ///
  /// [query] The search term (student name or roll number)
  /// [searchType] Either 'name' or 'roll' to specify search type
  /// Returns a list of student records matching the search criteria
  static Future<List<Map<String, dynamic>>> searchStudents(
      String query, String searchType) async {
    try {
      final endpoint = 'search_students';
      final response = await _makeRequest(
        endpoint,
        method: 'POST',
        body: {
          'query': query,
          'type': searchType,
        },
      );

      final result = _parseResponse(response);
      if (result['success'] == true) {
        return List<Map<String, dynamic>>.from(result['students'] ?? []);
      }
      throw Exception(result['error'] ?? 'Failed to search students');
    } catch (e) {
      throw Exception('Failed to search students: $e');
    }
  }

  /// Save course summary (today's topics and topics to revise)
  static Future<Map<String, dynamic>> saveSummary({
    int? classId,
    int? subjectId,
    String? className,
    String? subjectName,
    required String todayTopics,
    required String reviseTopics,
  }) async {
    try {
      final response = await _makeRequest(
        'save_course_summary',
        method: 'POST',
        body: {
          if (classId != null) 'class_id': classId.toString(),
          if (subjectId != null) 'subject_id': subjectId.toString(),
          if (className != null) 'class_name': className,
          if (subjectName != null) 'subject_name': subjectName,
          'today_topics': todayTopics,
          'revise_topics': reviseTopics,
        },
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to save summary: $e');
    }
  }

  // ==================== CHALLAN ENDPOINTS ====================
  /// Create challan for a student with optional file upload. Requires Super Admin JWT.
  static Future<Map<String, dynamic>> createChallan({
    required int studentUserId,
    required String title,
    String category = 'fee',
    double? amount,
    String? dueDate, // YYYY-MM-DD
    String? filePath,
    String? fileName,
    List<int>? fileBytes,
  }) async {
    final uri = Uri.parse('$baseUrl?endpoint=challan_create');

    final request = http.MultipartRequest('POST', uri);

    // Auth header
    final token = await _getToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Fields
    request.fields['student_user_id'] = studentUserId.toString();
    request.fields['title'] = title;
    request.fields['category'] = category;
    if (amount != null) request.fields['amount'] = amount.toString();
    if (dueDate != null && dueDate.isNotEmpty) {
      request.fields['due_date'] = dueDate;
    }

    log('[DEBUG API] Request fields: ${request.fields}');

    // File (always use bytes for web compatibility)
    if (fileBytes != null && fileBytes.isNotEmpty && fileName != null) {
      log('[DEBUG API] Adding file from bytes: ${fileBytes.length} bytes, name: $fileName');
      final mf =
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName);
      request.files.add(mf);
      log('[DEBUG API] File added from bytes');
    } else if (filePath != null && filePath.isNotEmpty && !kIsWeb) {
      // Only use fromPath on non-web platforms
      log('[DEBUG API] Adding file from path: $filePath');
      final mf = await http.MultipartFile.fromPath('file', filePath,
          filename: fileName ?? filePath.split('/').last.split('\\').last);
      request.files.add(mf);
      log('[DEBUG API] File added from path');
    } else {
      log('[DEBUG API] No file to upload');
    }

    log('[DEBUG API] Sending request...');
    final streamed = await request.send();
    log('[DEBUG API] Response status: ${streamed.statusCode}');

    final response = await http.Response.fromStream(streamed);
    log('[DEBUG API] Response body: ${response.body}');

    final result = _parseResponse(response);
    log('[DEBUG API] Parsed result: $result');
    return result;
  }

  /// Upload a generic user file (e.g., avatar) using bytes. Stores metadata in user_files.
  static Future<Map<String, dynamic>> uploadUserFileBytes({
    required String fileName,
    required List<int> fileBytes,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl?endpoint=user_file_upload');
      final request = http.MultipartRequest('POST', uri);

      // Add authentication header
      final token = await _getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Attach file
      final mf =
          http.MultipartFile.fromBytes('file', fileBytes, filename: fileName);
      request.files.add(mf);

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to upload file: $e');
    }
  }

  /// Get user profile picture URL
  static Future<String?> getUserProfilePictureUrl(int userId) async {
    try {
      log('Fetching profile picture URL for user: $userId');
      // Backend expects POST for this endpoint. Keep user_id as query param.
      final response = await _makeRequest(
        'user_profile_picture',
        method: 'POST',
        additionalParams: {'user_id': userId.toString()},
      );
      final result = _parseResponse(response);

      log('Profile picture API response: $result');

      if (result['success'] == true) {
        final url = result['profile_picture_url'];
        log('Profile picture URL found: $url');
        return url;
      } else {
        return null; // No profile picture uploaded
      }
    } catch (e) {
      log('Error fetching profile picture URL: $e');
      return null;
    }
  }

  /// List challans - Admin sees all, Student sees own
  static Future<Map<String, dynamic>> listChallans({int? studentId}) async {
    try {
      String endpoint = 'challan_list';
      if (studentId != null) {
        endpoint += '&student_id=$studentId';
      }

      final response = await _makeRequest(endpoint);
      final result = _parseResponse(response);

      return result;
    } catch (e) {
      return {'success': false, 'error': 'Failed to list challans: $e'};
    }
  }

  /// Student: Upload payment proof for a challan
  static Future<Map<String, dynamic>> uploadPaymentProof({
    required String challanId,
    String? filePath,
    String? fileName,
    List<int>? fileBytes,
  }) async {
    try {
      final endpoint = 'upload_payment_proof';

      var request = http.MultipartRequest(
          'POST', Uri.parse('$baseUrl?endpoint=$endpoint'));

      // Add form fields
      request.fields['challan_id'] = challanId;

      // Add file
      if (fileBytes != null && fileName != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'payment_proof',
          fileBytes,
          filename: fileName,
        ));
      } else if (filePath != null && fileName != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'payment_proof',
          filePath,
          filename: fileName,
        ));
      } else {
        throw Exception('No file provided');
      }

      // Add authorization header (use the same token mechanism as other requests)
      final token = await _getToken();
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      log('Upload payment proof response: ${response.statusCode} ${response.body}');

      final result = _parseResponse(response);
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Upload failed');
      }

      return result;
    } catch (e) {
      log('Upload payment proof error: $e');
      rethrow;
    }
  }

  /// Admin: Verify or reject challan payment
  static Future<Map<String, dynamic>> verifyChallan({
    required int challanId,
    required String action, // 'verify' or 'reject'
    String? remarks,
  }) async {
    try {
      final body = {
        'challan_id': challanId,
        'action': action,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      };

      final response = await _makeRequest(
        'challan_verify',
        method: 'POST',
        body: body,
      );

      return _parseResponse(response);
    } catch (e) {
      throw Exception('Failed to verify challan: $e');
    }
  }

  /// Chat message send to backend (groq_router.php)
  static Future<String> sendMessage(String userMessage) async {
    try {
      final apiUrl = '$baseUrl?endpoint=chat_assistant';
      try {
        final client = http.Client();

        final response = await http
            .post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json; charset=UTF-8',
            'Accept': 'application/json',
            'Connection': 'close',
          },
          body: jsonEncode({'message': userMessage}),
        )
            .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException(
                'The connection has timed out. The server is taking too long to respond.');
          },
        ).whenComplete(() {
          client.close();
        });

        log('Chat API Response Status: ${response.statusCode}');
        log('Chat API Response Body: ${response.body}');

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);

          if (responseData['success'] == true) {
            if (responseData['data'] != null &&
                responseData['data']['reply'] != null) {
              return responseData['data']['reply'];
            } else if (responseData['message'] != null) {
              return responseData['message'];
            }
            return 'Received empty response from server';
          } else {
            return 'Error: ${responseData['message'] ?? 'Unknown error occurred'}';
          }
        } else {
          return 'Server error: ${response.statusCode} - ${response.body}';
        }
      } on SocketException catch (e) {
        log('SocketException: $e');
        return 'Failed to connect to the server. Please check your internet connection.';
      } on FormatException catch (e) {
        log('FormatException: $e');
        return 'Invalid response from server. Please try again.';
      } on http.ClientException catch (e) {
        log('ClientException: $e');
        return 'Failed to connect to the server. Please check your connection.';
      } catch (e) {
        log('Unexpected error: $e');
        return 'An unexpected error occurred. Please try again.';
      }
    } catch (e) {
      log('Outer exception in sendMessage: $e');
      return 'Failed to process your request. Please try again.';
    }
  }
}
