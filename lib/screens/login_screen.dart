import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../theme_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
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
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    const Color(0xFF000000),
                    const Color(0xFF1A1A1A).withValues(alpha: 0.8),
                    const Color(0xFF000000),
                  ]
                : [
                    const Color(0xFFF8FAFC),
                    const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                    const Color(0xFFF8FAFC),
                  ],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                          ),
                          child: SingleChildScrollView(
                            padding: ResponsiveHelper.getContentPadding(context),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: ResponsiveHelper.getSpacing(context, size: 'lg'),
                                ),
                                
                                // Logo and Title Section
                                _buildHeaderSection(),
                                SizedBox(
                                  height: ResponsiveHelper.getSpacing(context, size: 'xl'),
                                ),
                                
                                // Login Form
                                _buildLoginForm(),
                                SizedBox(
                                  height: ResponsiveHelper.getSpacing(context, size: 'lg'),
                                ),
                                
                                // Login Button
                                _buildLoginButton(),
                                SizedBox(
                                  height: ResponsiveHelper.getSpacing(context, size: 'lg'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Theme toggle button in top-right corner
            Positioned(
              top: 50,
              right: 20,
              child: _buildThemeToggle(),
            ),
          ],
      ),
    ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      children: [
        // App Logo/Icon
        Container(
          width: ResponsiveHelper.responsiveValue(
            context,
            mobile: 120,
            tablet: 140,
            desktop: 160,
            largeDesktop: 180,
          ),
          height: ResponsiveHelper.responsiveValue(
            context,
            mobile: 120,
            tablet: 140,
            desktop: 160,
            largeDesktop: 180,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [
                      const Color(0xFF60A5FA),
                      const Color(0xFF1E3A8A),
                      const Color(0xFF60A5FA),
                    ]
                  : [
                      const Color(0xFF1E3A8A),
                      const Color(0xFF3B82F6),
                      const Color(0xFF1E3A8A),
                    ],
            ),
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.responsiveValue(
                context,
                mobile: 32,
                tablet: 36,
                desktop: 40,
              ),
            ),
            boxShadow: ResponsiveHelper.getElevation(context, level: 3),
          ),
          child: Icon(
            Icons.school_rounded,
            size: ResponsiveHelper.responsiveValue(
              context,
              mobile: 60,
              tablet: 70,
              desktop: 80,
              largeDesktop: 90,
            ),
            color: Colors.white,
          ),
        ),
        SizedBox(
          height: ResponsiveHelper.getSpacing(context, size: 'lg'),
        ),
        
        // Title
        Text(
          'Institute Portal',
          style: GoogleFonts.inter(
            fontSize: ResponsiveHelper.getHeadingSize(context),
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF111827),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height: ResponsiveHelper.getSpacing(context, size: 'sm'),
        ),
        
        // Subtitle
        Text(
          'Welcome back! Please sign in to continue',
          style: GoogleFonts.inter(
            fontSize: ResponsiveHelper.getBodySize(context),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.7)
                : const Color(0xFF6B7280),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Email/Username Field
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.responsiveValue(
                  context,
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
              ),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.2)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: ResponsiveHelper.getElevation(context, level: 1),
            ),
            child: TextFormField(
              controller: _emailController,
              style: GoogleFonts.inter(
                fontSize: ResponsiveHelper.getBodySize(context),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF111827),
              ),
              decoration: InputDecoration(
                hintText: 'Email',
                hintStyle: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.getBodySize(context),
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.4)
                      : const Color(0xFF6B7280),
                ),
                prefixIcon: Icon(
                  Icons.email_outlined,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.7)
                      : const Color(0xFF1E3A8A),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.getSpacing(context, size: 'medium'),
                  vertical: ResponsiveHelper.responsiveValue(
                    context,
                    mobile: 16,
                    tablet: 18,
                    desktop: 20,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                return null;
              },
            ),
          ),
          SizedBox(
            height: ResponsiveHelper.getSpacing(context, size: 'medium'),
          ),
          
          // Password Field
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.responsiveValue(
                  context,
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
              ),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.2)
                    : const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: ResponsiveHelper.getElevation(context, level: 1),
            ),
            child: TextFormField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              style: GoogleFonts.inter(
                fontSize: ResponsiveHelper.getBodySize(context),
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF111827),
              ),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.getBodySize(context),
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.4)
                      : const Color(0xFF6B7280),
                ),
                prefixIcon: Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.7)
                      : const Color(0xFF1E3A8A),
                ),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.7)
                        : const Color(0xFF1E3A8A),
                  ),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.getSpacing(context, size: 'medium'),
                  vertical: ResponsiveHelper.responsiveValue(
                    context,
                    mobile: 16,
                    tablet: 18,
                    desktop: 20,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    final buttonSize = ResponsiveHelper.getButtonSize(context, variant: 'large');
    return Container(
      width: double.infinity,
      height: buttonSize.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: Theme.of(context).brightness == Brightness.dark
              ? [
                  const Color(0xFF60A5FA),
                  const Color(0xFF1E3A8A),
                ]
              : [
                  const Color(0xFF1E3A8A),
                  const Color(0xFF3B82F6),
                ],
        ),
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.responsiveValue(
            context,
            mobile: 16,
            tablet: 18,
            desktop: 20,
          ),
        ),
        boxShadow: ResponsiveHelper.getElevation(context, level: 2),
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.responsiveValue(
                context,
                mobile: 16,
                tablet: 18,
                desktop: 20,
              ),
            ),
          ),
          elevation: 0,
        ).copyWith(
          overlayColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'Sign In',
                style: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.responsiveValue(
                    context,
                    mobile: 16,
                    tablet: 18,
                    desktop: 18,
                  ),
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }





  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      // Call the API service for login
      final result = await ApiService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      
      if (result['success'] == true) {
        // Login successful
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Welcome back, ${result['user']['name']}!',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          
          // Navigate to dashboard
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      } else {
        // Login failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['error'] ?? 'Login failed',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } on FormatException {
      // Handle JSON parsing errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Server response error: Invalid data format',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } on Exception catch (e) {
      // Handle network or other errors
      String errorMessage = 'Connection error';
      
      if (e.toString().contains('Network error')) {
        errorMessage = 'Network connection failed. Please check your internet connection.';
      } else if (e.toString().contains('SocketException')) {
        errorMessage = 'Cannot connect to server. Please check if the server is running.';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = 'Request timed out. Please try again.';
      } else if (e.toString().contains('Database connection failed')) {
        errorMessage = 'Server database error. Please contact administrator.';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: GoogleFonts.inter(),
            ),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _handleLogin(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildThemeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.2),
        ),
      ),
      child: IconButton(
        onPressed: () {
          ThemeController.instance.toggle();
        },
        icon: Icon(
          Theme.of(context).brightness == Brightness.dark
              ? Icons.light_mode
              : Icons.dark_mode,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black,
        ),
      ),
    );
  }
}
