import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class ApiTestScreen extends StatefulWidget {
  const ApiTestScreen({super.key});

  @override
  State<ApiTestScreen> createState() => _ApiTestScreenState();
}

class _ApiTestScreenState extends State<ApiTestScreen> {
  String _testResult = 'Click a test button to start testing...';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80.0),
        child: Padding(
          padding: const EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFF8B5CF6),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'API Test Screen',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Test Results Display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test Results:',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _testResult,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.white,
                      ).copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Test Buttons
            Text(
              'API Endpoints:',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            
            _buildTestButton(
              'Test Connection',
              Icons.wifi,
              const Color(0xFF10B981),
              _testConnection,
            ),
            
            _buildTestButton(
              'Get All Users',
              Icons.people,
              const Color(0xFF3B82F6),
              _testGetUsers,
            ),
            
            _buildTestButton(
              'Get All Courses',
              Icons.school,
              const Color(0xFF8B5CF6),
              _testGetCourses,
            ),
            
            _buildTestButton(
              'Get Current User',
              Icons.person,
              const Color(0xFFEC4899),
              _testGetCurrentUser,
            ),
            
            _buildTestButton(
              'Get User Profile',
              Icons.account_circle,
              const Color(0xFFF59E0B),
              _testGetUserProfile,
            ),
            
            _buildTestButton(
              'Create Test User',
              Icons.person_add,
              const Color(0xFF06B6D4),
              _testCreateUser,
            ),
            
            _buildTestButton(
              'Test Login',
              Icons.login,
              const Color(0xFF10B981),
              _testLogin,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestButton(
    String title,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          icon: Icon(icon, size: 20),
          label: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _setResult(String result) {
    setState(() {
      _testResult = result;
    });
  }

  void _setLoading(bool loading) {
    setState(() {
      _isLoading = loading;
    });
  }

  Future<void> _testConnection() async {
    _setLoading(true);
    try {
      final result = await ApiService.testConnection();
      if (result['success'] == true) {
        _setResult(
          '✅ Connection successful!\nAPI is reachable and responding.\n\nServer: ${result['server_url']}\nPlatform: ${result['platform']}\nTimestamp: ${result['timestamp']}',
        );
      } else {
        _setResult('❌ Connection failed!\n${result['message']}\n\nServer: ${result['server_url']}');
      }
    } catch (e) {
      _setResult('❌ Connection error: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _testGetUsers() async {
    _setLoading(true);
    try {
      final users = await ApiService.getAllUsers();
      _setResult('✅ Users fetched successfully!\n\n${users.map((u) => '• ${u['name']} (${u['email']}) - ${u['role']}').join('\n')}');
    } catch (e) {
      _setResult('❌ Failed to fetch users: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _testGetCourses() async {
    _setLoading(true);
    try {
      final courses = await ApiService.getAllCourses();
      _setResult('✅ Courses fetched successfully!\n\n${courses.map((c) => '• ${c['name']}${c['description'] != null ? ': ${c['description']}' : ''}').join('\n')}');
    } catch (e) {
      _setResult('❌ Failed to fetch courses: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _testGetCurrentUser() async {
    _setLoading(true);
    try {
      final user = await ApiService.getCurrentUser();
      if (user != null) {
        _setResult('✅ Current user:\n\n• ID: ${user['id']}\n• Name: ${user['name']}\n• Email: ${user['email']}\n• Role: ${user['role']}');
      } else {
        _setResult('ℹ️ No user currently logged in');
      }
    } catch (e) {
      _setResult('❌ Failed to get current user: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _testGetUserProfile() async {
    _setLoading(true);
    try {
      final userId = await ApiService.getCurrentUserId();
      if (userId != null) {
        final profile = await ApiService.getUserProfile(userId);
        if (profile != null) {
          _setResult('✅ User profile fetched successfully!\n\n• Full Name: ${profile['full_name'] ?? 'N/A'}\n• Roll Number: ${profile['roll_number'] ?? 'N/A'}\n• Class: ${profile['class'] ?? 'N/A'}\n• Phone: ${profile['phone'] ?? 'N/A'}');
        } else {
          _setResult('ℹ️ No profile found for current user');
        }
      } else {
        _setResult('ℹ️ No user currently logged in');
      }
    } catch (e) {
      _setResult('❌ Failed to get user profile: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _testCreateUser() async {
    _setLoading(true);
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final result = await ApiService.createUser(
        'Test User $timestamp',
        'testuser$timestamp@example.com',
        role: 'Student',
      );
      _setResult('✅ Test user created successfully!\n\n• User ID: ${result['user_id']}\n• Message: ${result['message']}');
    } catch (e) {
      _setResult('❌ Failed to create test user: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _testLogin() async {
    _setLoading(true);
    try {
      final result = await ApiService.login('john.doe@example.com', 'password123');
      if (result['success'] == true) {
        _setResult('✅ Login successful!\n\n• Welcome: ${result['user']['name']}\n• Email: ${result['user']['email']}\n• Role: ${result['user']['role']}');
      } else {
        _setResult('❌ Login failed: ${result['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      _setResult('❌ Login error: ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }
}
