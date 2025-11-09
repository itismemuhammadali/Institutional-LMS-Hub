import 'dart:developer' show log;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'home.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onProfileUpdated;

  const ProfileScreen({super.key, this.onProfileUpdated});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _user; // from users table (name, email, etc.)
  String? _profilePictureUrl; // Profile picture URL

  // Render helper: show dash when value is null/empty
  String _v(dynamic value) {
    if (value == null) return '-';
    final s = value.toString().trim();
    return s.isEmpty ? '-' : s;
  }
  // Role helper: treat Admin and Super Admin as admin-like
  bool _isAdminLike() {
    final role = (_user?['role'] ?? _userProfile?['role'] ?? '')
        .toString()
        .toLowerCase();
    return role == 'admin' || role == 'super admin';
  }

  bool _isStudent() {
    final role = (_user?['role'] ?? _userProfile?['role'] ?? '')
        .toString()
        .toLowerCase();
    return role == 'student';
  }

  void _log(String message) {
    log('[ProfileScreen] $message');
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }
  Future<void> _loadUserProfile() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final userId = await ApiService.getCurrentUserId();
      if (userId != null) {
        final profile = await ApiService.getUserProfile(userId);
        // Use local session user to avoid Forbidden for non-admin roles
        final user = await ApiService.getCurrentUser();
        if (!mounted) return;
        setState(() {
          _userProfile = profile;
          _user = user;
          _isLoading = false;
        });

        // Load profile picture after profile is loaded
        await _loadProfilePicture(userId);
      } else {
        if (!mounted) return;
        setState(() {
          _error = 'User not logged in';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProfilePicture(int userId) async {
    try {
      _log('Loading profile picture for user $userId (current: $_profilePictureUrl)');

      // First check if profile picture URL is in the profile data
      String? profilePictureUrl;

      if (_userProfile != null) {
        _log('Profile data keys: ${_userProfile!.keys.toList()}');
        // Check common field names for profile picture URL
        profilePictureUrl = _userProfile!['profile_picture_url'] ??
            _userProfile!['avatar_url'] ??
            _userProfile!['profile_image_url'] ??
            _userProfile!['picture_url'];
        _log('Profile picture URL from profile data: $profilePictureUrl');
      } else {
        _log('No profile data available');
      }

      // If not found in profile data, fetch it separately
      if (profilePictureUrl == null || profilePictureUrl.isEmpty) {
        _log('No profile picture URL in profile data; fetching from API');
        try {
          _log('Calling ApiService.getUserProfilePictureUrl($userId)');
          profilePictureUrl = await ApiService.getUserProfilePictureUrl(userId);
          _log('API returned profile picture URL: $profilePictureUrl');
        } catch (apiError) {
          _log('API call failed: $apiError');
          profilePictureUrl = null;
        }
      } else {
        _log('Using profile data URL, skipping API call');
      }

      _log('Final profile picture URL: $profilePictureUrl');

      if (mounted) {
        setState(() {
          // Add cache-busting query to ensure latest image is fetched
          if (profilePictureUrl != null && profilePictureUrl.isNotEmpty) {
            final ts = DateTime.now().millisecondsSinceEpoch;
            final separator = profilePictureUrl.contains('?') ? '&' : '?';
            _profilePictureUrl = '$profilePictureUrl${separator}t=$ts';
          } else {
            _profilePictureUrl = profilePictureUrl;
          }
        });
        _log('Profile picture state updated: $_profilePictureUrl');
      } else {
        _log('Widget not mounted; skipping profile picture state update');
      }

    } catch (e) {
      _log('Error loading profile picture: $e');
      if (mounted) {
        setState(() {
          _profilePictureUrl = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF8B5CF6),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: const Color(0xFFFFFFFF),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading profile',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadUserProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
              ),
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          if (!ResponsiveHelper.isMobile(context))
            // Full-bleed header bar (touches edges)
            Container(
              height: 64,
              width: double.infinity,
              color: const Color(0xFF1E3A8A),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const StudentDashboard()),
                      );
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'My Profile',
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
                  // Profile Header
                  _buildProfileHeader(),
                  const SizedBox(height: 30),
                  // Personal Information Section
                  _buildSectionTitle('Personal Information'),
                  const SizedBox(height: 20),
                  _buildPersonalInfoSection(),
                  const SizedBox(height: 30),
                  // Academic Information Section
                  _buildSectionTitle('Academic Information'),
                  const SizedBox(height: 20),
                  _buildAcademicInfoSection(),
                  const SizedBox(height: 30),
                  // Contact Information Section
                  _buildSectionTitle('Contact Information'),
                  const SizedBox(height: 20),
                  _buildContactInfoSection(),
                  const SizedBox(height: 30),
                  // Emergency Contact Section
                  _buildSectionTitle('Emergency Contact'),
                  const SizedBox(height: 20),
                  _buildEmergencyContactSection(),
                  const SizedBox(height: 30),
                  // Address Information Section
                  _buildSectionTitle('Address Information'),
                  const SizedBox(height: 20),
                  _buildAddressInfoSection(),
                  const SizedBox(height: 30),
                  // Action Buttons
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAvatarPopup(BuildContext context) {
    String? selectedFileName;
    List<int>? selectedBytes;
    Uint8List? croppedBytes;
    ui.Image? originalImage;
    Offset imageOffset = Offset.zero;
    double imageScale = 1.0;
    bool showCropEditor = false;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? colorScheme.surface : Colors.white;
    final onSurfaceColor = isDark ? colorScheme.onSurface : const Color(0xFF1E293B);
    const Color accentBlue = Color(0xFF1E3A8A);

    Future<Uint8List> cropToCircle(Uint8List inputBytes,
        {int outputSize = 512}) async {
      final codec = await ui.instantiateImageCodec(inputBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final int srcSize = img.width < img.height ? img.width : img.height;
      final double srcLeft = (img.width - srcSize) / 2.0;
      final double srcTop = (img.height - srcSize) / 2.0;
      final srcRect = Rect.fromLTWH(
          srcLeft, srcTop, srcSize.toDouble(), srcSize.toDouble());
      final dstRect =
          Rect.fromLTWH(0, 0, outputSize.toDouble(), outputSize.toDouble());

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, dstRect);

      final paint = Paint()..isAntiAlias = true;
      final path = Path()
        ..addOval(Rect.fromCircle(
            center: Offset(outputSize / 2.0, outputSize / 2.0),
            radius: outputSize / 2.0));
      canvas.clipPath(path);
      canvas.drawImageRect(img, srcRect, dstRect, paint);

      final picture = recorder.endRecording();
      final uiImage = await picture.toImage(outputSize, outputSize);
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    }

    Future<Uint8List> cropToCircleWithPosition(
        Uint8List inputBytes, ui.Image img, Offset offset, double scale,
        {int outputSize = 512}) async {
      final double cropSize = outputSize.toDouble();
      final double imageWidth = img.width.toDouble();
      final double imageHeight = img.height.toDouble();

      // Calculate the scaled image dimensions
      final double scaledWidth = imageWidth * scale;
      final double scaledHeight = imageHeight * scale;

      // Calculate the crop circle radius in the editor (260x260 container with 20px margin)
      final double editorSize = 260.0;
      final double editorCropRadius = (editorSize / 2) - 20;
      final double editorCenterX = editorSize / 2;
      final double editorCenterY = editorSize / 2;

      // Calculate the image position in the editor
      final double imageLeft = editorCenterX - scaledWidth / 2 + offset.dx;
      final double imageTop = editorCenterY - scaledHeight / 2 + offset.dy;

      // Calculate the crop circle position relative to the image
      final double cropCenterX = editorCenterX;
      final double cropCenterY = editorCenterY;

      // Calculate the offset from the crop center to the image top-left
      final double cropOffsetX = cropCenterX - imageLeft;
      final double cropOffsetY = cropCenterY - imageTop;

      // Convert to source image coordinates
      final double srcCropCenterX = cropOffsetX / scale;
      final double srcCropCenterY = cropOffsetY / scale;
      final double srcCropRadius = editorCropRadius / scale;

      // Calculate the source rectangle
      final double srcLeft = srcCropCenterX - srcCropRadius;
      final double srcTop = srcCropCenterY - srcCropRadius;
      final double srcSize = srcCropRadius * 2;

      final srcRect = Rect.fromLTWH(
        srcLeft.clamp(0.0, imageWidth - srcSize),
        srcTop.clamp(0.0, imageHeight - srcSize),
        srcSize.clamp(0.0, imageWidth - srcLeft.clamp(0.0, imageWidth)),
        srcSize.clamp(0.0, imageHeight - srcTop.clamp(0.0, imageHeight)),
      );

      final dstRect = Rect.fromLTWH(0, 0, cropSize, cropSize);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, dstRect);

      final paint = Paint()..isAntiAlias = true;
      final path = Path()
        ..addOval(Rect.fromCircle(
            center: Offset(cropSize / 2.0, cropSize / 2.0),
            radius: cropSize / 2.0));
      canvas.clipPath(path);
      canvas.drawImageRect(img, srcRect, dstRect, paint);

      final picture = recorder.endRecording();
      final uiImage = await picture.toImage(outputSize, outputSize);
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          backgroundColor: surfaceColor,
          title: Text(
            'Profile Photo',
            style: GoogleFonts.inter(
              color: onSurfaceColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!showCropEditor) ...[
                    // Preview mode
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accentBlue, width: 3),
                      ),
                      child: ClipOval(
                        child: croppedBytes != null
                            ? Image.memory(croppedBytes!, fit: BoxFit.cover)
                            : originalImage != null
                                ? FutureBuilder<Uint8List>(
                                    future: cropToCircleWithPosition(
                                      Uint8List.fromList(selectedBytes!),
                                      originalImage!,
                                      imageOffset,
                                      imageScale,
                                    ),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        return Image.memory(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                        );
                                      }
                                      return Container(
                                        color: accentBlue.withValues(alpha: 0.1),
                                        child: const CircularProgressIndicator(
                                          color: accentBlue,
                                          strokeWidth: 2,
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: accentBlue.withValues(alpha: 0.08),
                                    child: Icon(
                                      Icons.person,
                                      size: 80,
                                      color: accentBlue.withValues(alpha: 0.7),
                                    ),
                                  ),
                      ),
                    ),
                  ] else ...[
                    // Crop editor mode
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentBlue, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: originalImage != null
                            ? _buildCropEditor(
                                originalImage!,
                                imageOffset,
                                imageScale,
                                setS,
                                (newOffset) => imageOffset = newOffset,
                                (newScale) => imageScale = newScale,
                              )
                            : Container(
                                color: accentBlue.withValues(alpha: 0.1),
                                child: const Icon(
                                  Icons.person,
                                  size: 80,
                                  color: accentBlue,
                                ),
                              ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (selectedFileName != null)
                    Text(
                      selectedFileName!,
                      style: GoogleFonts.inter(
                          color: onSurfaceColor.withValues(alpha: 0.7),
                          fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  if (showCropEditor) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Drag to position • Pinch to zoom',
                      style: GoogleFonts.inter(
                          color: onSurfaceColor.withValues(alpha: 0.6),
                          fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    // Zoom controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            setS(() {
                              imageScale = (imageScale * 0.8).clamp(0.5, 3.0);
                            });
                          },
                          icon: Icon(Icons.zoom_out, color: onSurfaceColor),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                accentBlue.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${(imageScale * 100).round()}%',
                          style: GoogleFonts.inter(
                            color: onSurfaceColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          onPressed: () {
                            setS(() {
                              imageScale = (imageScale * 1.2).clamp(0.5, 3.0);
                            });
                          },
                          icon: Icon(Icons.zoom_in, color: onSurfaceColor),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                accentBlue.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Reset button
                    TextButton.icon(
                      onPressed: () {
                        setS(() {
                          imageOffset = Offset.zero;
                          imageScale = 1.0;
                        });
                      },
                      icon: const Icon(Icons.center_focus_strong,
                          size: 16, color: Colors.white),
                      label: Text(
                        'Reset Position',
                        style: GoogleFonts.inter(
                            color: accentBlue, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor:
                            accentBlue.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            Row(
              children: [
                TextButton(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      withData: true,
                      type: FileType.image,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      final f = result.files.single;
                      final codec = await ui.instantiateImageCodec(f.bytes!);
                      final frame = await codec.getNextFrame();
                      setS(() {
                        selectedFileName = f.name;
                        selectedBytes = f.bytes;
                        croppedBytes = null;
                        originalImage = frame.image;
                        imageOffset = Offset.zero;
                        imageScale = 1.0;
                        showCropEditor = false;
                      });
                    }
                  },
                  child: Text(
                    'Select File',
                    style: GoogleFonts.inter(color: accentBlue, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                if (selectedBytes != null && !showCropEditor)
                  TextButton(
                    onPressed: () {
                      setS(() {
                        showCropEditor = true;
                      });
                    },
                    child: Text(
                      'Edit Crop',
                      style: GoogleFonts.inter(color: accentBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (selectedBytes != null && showCropEditor) ...[
                  TextButton(
                    onPressed: () {
                      setS(() {
                        showCropEditor = false;
                      });
                    },
                    child: Text(
                      'Preview',
                      style: GoogleFonts.inter(color: accentBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      if (originalImage != null) {
                        final result = await cropToCircleWithPosition(
                          Uint8List.fromList(selectedBytes!),
                          originalImage!,
                          imageOffset,
                          imageScale,
                        );
                        setS(() {
                          croppedBytes = result;
                          showCropEditor = false;
                        });
                      }
                    },
                    child: Text(
                      'Apply Crop',
                      style: GoogleFonts.inter(color: accentBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                if (selectedBytes != null && !showCropEditor) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final result = await cropToCircle(
                          Uint8List.fromList(selectedBytes!));
                      setS(() {
                        croppedBytes = result;
                      });
                    },
                    child: Text(
                      'Auto Crop',
                      style: GoogleFonts.inter(color: accentBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: (croppedBytes == null)
                      ? null
                      : () async {
                          try {
                            final fileName = (selectedFileName ?? 'avatar')
                                .replaceAll(' ', '_');
                            final res = await ApiService.uploadUserFileBytes(
                              fileName: fileName.endsWith('.png')
                                  ? fileName
                                  : ('$fileName.png'),
                              fileBytes: croppedBytes!,
                            );
                            if (res['success'] == true) {
                              _log('Profile picture upload successful');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Avatar uploaded successfully.',
                                        style: GoogleFonts.inter(
                                            color: Colors.white)),
                                    backgroundColor: const Color(0xFFF59E0B),
                                  ),
                                );
                              }
                              if (context.mounted) Navigator.of(context).pop();

                              // Refresh profile picture in this screen
                              _log('Refreshing profile picture after upload');
                              final userId =
                                  await ApiService.getCurrentUserId();
                              if (userId != null) {
                                _log('Reloading profile picture for user $userId');
                                await _loadProfilePicture(userId);
                                _log('Profile picture refresh completed');
                              } else {
                                _log('No user ID found for refresh');
                              }

                              // Call the callback to refresh profile picture in home screen
                              _log('Invoking home screen profile refresh callback');
                              widget.onProfileUpdated?.call();
                              _log('Profile refresh callback completed');
                            } else {
                              _log('Profile picture upload failed: ${res['error']}');
                              throw Exception(res['error'] ?? 'Upload failed');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Upload failed: $e',
                                      style: GoogleFonts.inter(
                                          color: colorScheme.onError)),
                                  backgroundColor: colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white),
                  child: Text(
                    'Upload File',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: GoogleFonts.inter(
                    color: onSurfaceColor.withValues(alpha: 0.7), fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCropEditor(
      ui.Image image,
      Offset offset,
      double scale,
      StateSetter setState,
      Function(Offset) onOffsetChanged,
      Function(double) onScaleChanged) {
    return GestureDetector(
      onScaleUpdate: (details) {
        setState(() {
          // Handle both pan (translation) and scale
          onOffsetChanged(offset + details.focalPointDelta);
          onScaleChanged((scale * details.scale).clamp(0.5, 3.0));
        });
      },
      child: CustomPaint(
        size: const Size(260, 260),
        painter: CropEditorPainter(image, offset, scale),
      ),
    );
  }

Widget _buildProfileHeader() {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color lightCard = Color(0xFFE7E0DE);
  const Color lightBorder = Color(0xFFD9D2D0);
  const Color accentBlue = Color(0xFF1E3A8A);
  final onSurface = Theme.of(context).colorScheme.onSurface;

  return Container(
    width: double.infinity,
    padding: ResponsiveHelper.responsivePadding(
      context,
      mobile: const EdgeInsets.all(20),
      tablet: const EdgeInsets.all(24),
      desktop: const EdgeInsets.all(28),
    ),
    decoration: isDark
        ? BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          )
        : BoxDecoration(
            color: lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: lightBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: accentBlue.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 480;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _showAvatarPopup(context),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1E3A8A), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _profilePictureUrl != null && _profilePictureUrl!.isNotEmpty
                            ? Image.network(
                                _profilePictureUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                                  child: const Icon(Icons.person, size: 50, color: Color(0xFF1E3A8A)),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                                child: const Icon(Icons.person, size: 50, color: Color(0xFF1E3A8A)),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _user?['name']?.toString() ?? _v(_userProfile?['full_name']),
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            color: isDark ? onSurface : accentBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _user?['email']?.toString() ?? _v(_userProfile?['email']),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? onSurface.withValues(alpha: 0.7) : accentBlue.withValues(alpha: 0.8),
                          ),
                          softWrap: true,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isAdminLike() ? 'Admin' : 'Class: ${_v(_userProfile?['class'])}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? onSurface.withValues(alpha: 0.7) : accentBlue.withValues(alpha: 0.8),
                          ),
                          softWrap: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => _showEditProfileDialog(context),
                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF1E3A8A), size: 24),
                ),
              ),
            ],
          );
        }

        return Row(
          children: [
            GestureDetector(
              onTap: () => _showAvatarPopup(context),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1E3A8A), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _profilePictureUrl != null && _profilePictureUrl!.isNotEmpty
                      ? Image.network(
                          _profilePictureUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, _) => Container(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                            child: const Icon(Icons.person, size: 50, color: Color(0xFF1E3A8A)),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                              child: const CircularProgressIndicator(
                                color: Color(0xFF8B5CF6),
                                strokeWidth: 2,
                              ),
                            );
                          },
                        )
                      : Container(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                          child: const Icon(Icons.person, size: 50, color: Color(0xFF1E3A8A)),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _v(_user?['name'] ?? _userProfile?['full_name']),
                    style: GoogleFonts.inter(
                      fontSize: ResponsiveHelper.getSubheadingSize(context),
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : accentBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAdminLike()
                        ? 'Registration Number: ${_v(_userProfile?['registration_no'])}'
                        : 'Roll No: ${_v(_userProfile?['roll_number'])}',
                    style: GoogleFonts.inter(
                      fontSize: ResponsiveHelper.getBodySize(context),
                      color: isDark ? Colors.white.withValues(alpha: 0.7) : accentBlue.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isAdminLike()
                        ? 'Class Teacher of: ${_v(_userProfile?['class_teacher_of'])}'
                        : 'Class: ${_v(_userProfile?['class'])}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.white.withValues(alpha: 0.7) : accentBlue.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            if (!_isStudent())
              IconButton(
                onPressed: () => _showEditProfileDialog(context),
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF1E3A8A), size: 24),
              ),
          ],
        );
      },
    ),
  );
}
Widget _buildSectionTitle(String title) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color accentBlue = Color(0xFF1E3A8A);

  return Text(
    title,
    style: GoogleFonts.inter(
      fontSize: ResponsiveHelper.getSubheadingSize(context),
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white : accentBlue,
    ),
  );
}
BoxDecoration _sectionDecoration() {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color lightCard = Color(0xFFE7E0DE);
  const Color lightBorder = Color(0xFFD9D2D0);

  if (isDark) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
        width: 1,
      ),
    );
  }
  return BoxDecoration(
    color: lightCard,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: lightBorder, width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 14,
        offset: const Offset(0, 8),
      ),
    ],
  );
}
Widget _buildPersonalInfoSection() {
  final items = [
    MapEntry('Full Name', _v(_user?['name'] ?? _userProfile?['full_name'])),
    MapEntry('CNIC No', _v(_userProfile?['cnic'])),
    MapEntry('Date of Birth', _v(_userProfile?['date_of_birth'])),
    MapEntry('Gender', _v(_userProfile?['gender'])),
    MapEntry('Blood Group', _v(_userProfile?['blood_group'])),
    MapEntry('Nationality', _v(_userProfile?['nationality'])),
    MapEntry('Religion', _v(_userProfile?['religion'])),
  ];

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _sectionDecoration(),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bool useTwoColumns = constraints.maxWidth >= 420;

        if (!useTwoColumns) {
          return Column(
            children: [
              for (final entry in items) _buildInfoRow(entry.key, entry.value),
            ],
          );
        }

        final rows = <Widget>[];
        for (int i = 0; i < items.length; i += 2) {
          final first = items[i];
          final Widget firstWidget = Expanded(
            child: _buildInfoRow(first.key, first.value, forceHorizontal: true),
          );

          Widget? secondWidget;
          if (i + 1 < items.length) {
            final second = items[i + 1];
            secondWidget = Expanded(
              child: _buildInfoRow(second.key, second.value, forceHorizontal: true),
            );
          }

          rows.add(
            Padding(
              padding: EdgeInsets.only(bottom: i + 2 < items.length ? 12 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  firstWidget,
                  if (secondWidget != null) ...[
                    const SizedBox(width: 16),
                    secondWidget,
                  ],
                ],
              ),
            ),
          );
        }

        return Column(children: rows);
      },
    ),
  );
}

Widget _buildAcademicInfoSection() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _sectionDecoration(),
    child: Column(
      children: [
        if (_isAdminLike())
          _buildInfoRow('Registration Number', _v(_userProfile?['registration_no']))
        else
          _buildInfoRow('Roll Number', _v(_userProfile?['roll_number'])),
        if (_isAdminLike())
          _buildInfoRow('Class Teacher of', _v(_userProfile?['class_teacher_of']))
        else
          _buildInfoRow('Class', _v(_userProfile?['class'])),
        _buildInfoRow('Batch', _v(_userProfile?['batch'])),
        _buildInfoRow('Enrollment Date', _v(_userProfile?['enrollment_date'])),
      ],
    ),
  );
}

Widget _buildContactInfoSection() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _sectionDecoration(),
    child: Column(
      children: [
        _buildInfoRow('Email', _v(_user?['email'] ?? _userProfile?['email'])),
        _buildInfoRow('Phone Number', _v(_userProfile?['phone'])),
        _buildInfoRow('WhatsApp', _v(_userProfile?['whatsapp'])),
        _buildInfoRow('Alternative Phone', _v(_userProfile?['alternative_phone'])),
      ],
    ),
  );
}

Widget _buildEmergencyContactSection() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _sectionDecoration(),
    child: Column(
      children: [
        _buildInfoRow('Emergency Contact', _v(_userProfile?['emergency_contact'])),
        _buildInfoRow('Relationship', _v(_userProfile?['emergency_relationship'])),
        _buildInfoRow('Alternative Emergency', _v(_userProfile?['alternative_emergency'])),
        _buildInfoRow('Relationship', _v(_userProfile?['alternative_emergency_relationship'])),
      ],
    ),
  );
}

Widget _buildAddressInfoSection() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: _sectionDecoration(),
    child: Column(
      children: [
        _buildInfoRow('Current Address', _v(_userProfile?['current_address'])),
        _buildInfoRow('Permanent Address', _v(_userProfile?['permanent_address'])),
        _buildInfoRow('City', _v(_userProfile?['city'])),
        _buildInfoRow('Province', _v(_userProfile?['province'])),
        _buildInfoRow('Postal Code', _v(_userProfile?['postal_code'])),
      ],
    ),
  );
}
  Widget _buildInfoRow(String label, String value, {bool forceHorizontal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isVeryNarrow = !forceHorizontal && constraints.maxWidth < 340;
          final labelMaxWidth = constraints.maxWidth * 0.4;
          final targetLabelWidth = labelMaxWidth.clamp(100.0, 140.0);

          if (isVeryNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label:',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xFF1E3A8A)
                        : Colors.white,
                  ),
                  softWrap: true,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFF1E3A8A)
                          : Colors.white,
                  ),
                  softWrap: true,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: targetLabelWidth,
                child: Text(
                  '$label:',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xFF1E3A8A)
                        : Colors.white.withValues(alpha: 0.8),
                  ),
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xFF1E3A8A)
                        : Colors.white,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              _showChangePasswordDialog(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.lock_outline),
            label: Text(
              'Change Password',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (!_isStudent()) ...[
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                _showEditProfileDialog(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                'Edit Profile',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();

    // Helpers
    InputDecoration deco(String label) {
      final theme = Theme.of(context);
      final bool isLight = theme.brightness == Brightness.light;
      const primaryBlue = Color(0xFF1E3A8A);
      final Color labelColor = isLight ? primaryBlue.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.7);
      final Color fillColor = isLight ? primaryBlue.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.05);
      final Color borderColor = isLight ? const Color(0xFFE5E7EB) : Colors.white.withValues(alpha: 0.12);
      final Color focusColor = isLight ? primaryBlue : const Color(0xFF8B5CF6);

      return InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: labelColor),
        filled: true,
        fillColor: fillColor,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: focusColor, width: 1.2),
        ),
      );
    }

    String vEmail(String? v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      final ok = RegExp(r'^.+@.+\..+$').hasMatch(v.trim());
      return ok ? '' : 'Enter a valid email';
    }

    String? vReq(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;
    String? vOpt(String? v) => null;

    final profile = _userProfile ?? {};
    // Controllers (prefill from profile if available)
    final fullName = TextEditingController(text: profile['full_name'] ?? '');
    final cnic = TextEditingController(text: profile['cnic'] ?? '');
    final dob = TextEditingController(text: profile['date_of_birth'] ?? '');
    final gender = TextEditingController(text: profile['gender'] ?? '');
    final bloodGroup =
        TextEditingController(text: profile['blood_group'] ?? '');
    final nationality =
        TextEditingController(text: profile['nationality'] ?? '');
    final religion = TextEditingController(text: profile['religion'] ?? '');

    final rollNumber =
        TextEditingController(text: profile['roll_number'] ?? '');
    final klass = TextEditingController(text: profile['class'] ?? '');
    final batch = TextEditingController(text: profile['batch'] ?? '');
    final enrollmentDate =
        TextEditingController(text: profile['enrollment_date'] ?? '');

    final email = TextEditingController(text: profile['email'] ?? '');
    final phone = TextEditingController(text: profile['phone'] ?? '');
    final whatsapp = TextEditingController(text: profile['whatsapp'] ?? '');
    final altPhone =
        TextEditingController(text: profile['alternative_phone'] ?? '');

    final emergency =
        TextEditingController(text: profile['emergency_contact'] ?? '');
    final emergencyRel =
        TextEditingController(text: profile['emergency_relationship'] ?? '');
    final altEmergency =
        TextEditingController(text: profile['alternative_emergency'] ?? '');
    final altEmergencyRel = TextEditingController(
        text: profile['alternative_emergency_relationship'] ?? '');

    final currentAddr =
        TextEditingController(text: profile['current_address'] ?? '');
    final permanentAddr =
        TextEditingController(text: profile['permanent_address'] ?? '');
    final city = TextEditingController(text: profile['city'] ?? '');
    final province = TextEditingController(text: profile['province'] ?? '');
    final postalCode =
        TextEditingController(text: profile['postal_code'] ?? '');

    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setS) => AlertDialog(
            backgroundColor:
                Theme.of(context).brightness == Brightness.light ? const Color(0xFFFAFAF7) : const Color(0xFF1E293B),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
              'Complete Your Profile',
              style: GoogleFonts.inter(
                color: Theme.of(context).brightness == Brightness.light
                    ? const Color(0xFF1E3A8A)
                    : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Personal
                    TextFormField(
                        controller: fullName,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Full Name'),
                        validator: vReq),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: cnic,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('CNIC No'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: dob,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Date of Birth (YYYY-MM-DD)'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: gender,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Gender'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: bloodGroup,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Blood Group'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: nationality,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Nationality'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: religion,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Religion'),
                        validator: vOpt),
                    const SizedBox(height: 16),

                    // Academic
                    TextFormField(
                        controller: rollNumber,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Roll Number (optional for Admins)'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: klass,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Class (e.g., Class 10A)'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: batch,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Batch Year'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: enrollmentDate,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Enrollment Date (YYYY-MM-DD)'),
                        validator: vOpt),
                    const SizedBox(height: 16),

                    // Contact
                    TextFormField(
                      controller: email,
                      style: GoogleFonts.inter(
                        color: Theme.of(context).brightness == Brightness.light
                            ? const Color(0xFF1E3A8A)
                            : Colors.white,
                      ),
                      decoration: deco('Email'),
                      validator: (v) {
                        final m = vEmail(v);
                        return m.isEmpty ? null : m;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: phone,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Phone Number'),
                        validator: vReq),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: whatsapp,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('WhatsApp'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: altPhone,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Alternative Phone'),
                        validator: vOpt),
                    const SizedBox(height: 16),

                    // Emergency
                    TextFormField(
                        controller: emergency,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Emergency Contact'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: emergencyRel,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Relationship'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: altEmergency,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Alternative Emergency'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: altEmergencyRel,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Alt. Emergency Relationship'),
                        validator: vOpt),
                    const SizedBox(height: 16),

                    // Address
                    TextFormField(
                        controller: currentAddr,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Current Address'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: permanentAddr,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Permanent Address'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: city,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('City'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: province,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Province'),
                        validator: vOpt),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: postalCode,
                        style: GoogleFonts.inter(
                          color: Theme.of(context).brightness == Brightness.light
                              ? const Color(0xFF1E3A8A)
                              : Colors.white,
                        ),
                        decoration: deco('Postal Code'),
                        validator: vOpt),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).brightness == Brightness.light
                      ? const Color(0xFF1E3A8A)
                      : Colors.white.withValues(alpha: 0.7),
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setS(() => saving = true);
                        try {
                          final userId = await ApiService.getCurrentUserId();
                          if (userId == null) throw Exception('Not logged in');
                          final payload = {
                            'full_name': fullName.text.trim(),
                            'cnic': cnic.text.trim(),
                            'date_of_birth': dob.text.trim(),
                            'gender': gender.text.trim(),
                            'blood_group': bloodGroup.text.trim(),
                            'nationality': nationality.text.trim(),
                            'religion': religion.text.trim(),
                            'roll_number': rollNumber.text.trim(),
                            'class': klass.text.trim(),
                            'batch': batch.text.trim(),
                            'enrollment_date': enrollmentDate.text.trim(),
                            'email': email.text.trim(),
                            'phone': phone.text.trim(),
                            'whatsapp': whatsapp.text.trim(),
                            'alternative_phone': altPhone.text.trim(),
                            'emergency_contact': emergency.text.trim(),
                            'emergency_relationship': emergencyRel.text.trim(),
                            'alternative_emergency': altEmergency.text.trim(),
                            'alternative_emergency_relationship':
                                altEmergencyRel.text.trim(),
                            'current_address': currentAddr.text.trim(),
                            'permanent_address': permanentAddr.text.trim(),
                            'city': city.text.trim(),
                            'province': province.text.trim(),
                            'postal_code': postalCode.text.trim(),
                          };
                          // Remove empty values to avoid overwriting with blanks
                          payload.removeWhere((k, v) => v.isEmpty);

                          final res = await ApiService.updateUserProfile(
                              userId, payload);
                          if (res['success'] == true) {
                            // Reload from backend to reflect DB truth
                            await _loadUserProfile();
                            if (context.mounted) Navigator.pop(context);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Profile updated successfully!',
                                      style: GoogleFonts.inter(
                                          color: Colors.white)),
                                  backgroundColor: const Color(0xFFF59E0B),
                                ),
                              );
                            }
                          } else {
                            throw Exception(res['error'] ?? 'Update failed');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to update profile: $e',
                                    style:
                                        GoogleFonts.inter(color: Colors.white)),
                                backgroundColor: const Color(0xFFFFFFFF),
                              ),
                            );
                          }
                        } finally {
                          setS(() => saving = false);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.light
                      ? const Color(0xFF1E3A8A)
                      : const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        'Save',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final bool isLight = theme.brightness == Brightness.light;
        const primaryBlue = Color(0xFF1E3A8A);
        final Color labelColor = isLight ? primaryBlue.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.7);
        final Color fillColor = isLight ? primaryBlue.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.05);
        final Color borderColor = isLight ? const Color(0xFFE5E7EB) : Colors.white.withValues(alpha: 0.12);
        final Color focusColor = isLight ? primaryBlue : const Color(0xFF8B5CF6);
        final TextStyle fieldStyle = GoogleFonts.inter(color: isLight ? primaryBlue : Colors.white);

        InputDecoration buildDeco(String label) => InputDecoration(
              labelText: label,
              labelStyle: GoogleFonts.inter(color: labelColor),
              filled: true,
              fillColor: fillColor,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: focusColor),
              ),
            );

        return AlertDialog(
          backgroundColor: isLight ? const Color(0xFFFAFAF7) : const Color(0xFF1E293B),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Change Password',
            style: GoogleFonts.inter(
              color: isLight ? primaryBlue : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordController,
                  obscureText: true,
                  style: fieldStyle,
                  decoration: buildDeco('Current Password'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  style: fieldStyle,
                  decoration: buildDeco('New Password'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  style: fieldStyle,
                  decoration: buildDeco('Confirm New Password'),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                foregroundColor: isLight ? primaryBlue : Colors.white.withValues(alpha: 0.7),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final currentPassword = currentPasswordController.text.trim();
                final newPassword = newPasswordController.text.trim();
                final confirmPassword = confirmPasswordController.text.trim();

                if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Please fill in all fields.',
                        style: GoogleFonts.inter(color: Colors.white),
                      ),
                      backgroundColor: const Color(0xFFF97316),
                    ),
                  );
                  return;
                }

                if (newPassword == currentPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'New password must be different from current password.',
                        style: GoogleFonts.inter(color: Colors.white),
                      ),
                      backgroundColor: const Color(0xFFF97316),
                    ),
                  );
                  return;
                }

                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Passwords do not match!',
                        style: GoogleFonts.inter(color: Colors.white),
                      ),
                      backgroundColor: const Color(0xFFF97316),
                    ),
                  );
                  return;
                }

                // TODO: Wire up backend password change endpoint once available.
                // For now, just close the dialog and show success feedback.
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Password changed successfully (mock).',
                      style: GoogleFonts.inter(color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: isLight ? primaryBlue : const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Change Password',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}

class CropEditorPainter extends CustomPainter {
  final ui.Image image;
  final Offset offset;
  final double scale;

  CropEditorPainter(this.image, this.offset, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;
    final double centerY = size.height / 2;
    final double cropRadius = size.width / 2 - 20; // Leave some margin

    // Calculate image dimensions
    final double imageWidth = image.width.toDouble();
    final double imageHeight = image.height.toDouble();

    // Calculate scaled image dimensions
    final double scaledWidth = imageWidth * scale;
    final double scaledHeight = imageHeight * scale;

    // Calculate image position (centered + offset)
    final double imageLeft = centerX - scaledWidth / 2 + offset.dx;
    final double imageTop = centerY - scaledHeight / 2 + offset.dy;

    // Draw the image
    final Rect imageRect =
        Rect.fromLTWH(imageLeft, imageTop, scaledWidth, scaledHeight);
    final Rect sourceRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);

    canvas.drawImageRect(image, sourceRect, imageRect, Paint());

    // Draw the crop circle overlay
    final Paint overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final Paint circlePaint = Paint()
      ..color = const Color(0xFF8B5CF6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Create a path for the overlay (everything except the crop circle)
    final Path overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(
          Rect.fromCircle(center: Offset(centerX, centerY), radius: cropRadius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(overlayPath, overlayPaint);

    // Draw the crop circle border
    canvas.drawCircle(Offset(centerX, centerY), cropRadius, circlePaint);

    // Draw corner indicators
    final Paint cornerPaint = Paint()
      ..color = const Color(0xFF8B5CF6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final double cornerSize = 15;
    final double cornerOffset = cropRadius - cornerSize / 2;

    // Top-left corner
    canvas.drawLine(
      Offset(centerX - cornerOffset, centerY - cropRadius),
      Offset(centerX - cornerOffset + cornerSize, centerY - cropRadius),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX - cropRadius, centerY - cornerOffset),
      Offset(centerX - cropRadius, centerY - cornerOffset + cornerSize),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(centerX + cornerOffset - cornerSize, centerY - cropRadius),
      Offset(centerX + cornerOffset, centerY - cropRadius),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + cropRadius, centerY - cornerOffset),
      Offset(centerX + cropRadius, centerY - cornerOffset + cornerSize),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(centerX - cornerOffset, centerY + cropRadius),
      Offset(centerX - cornerOffset + cornerSize, centerY + cropRadius),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX - cropRadius, centerY + cornerOffset - cornerSize),
      Offset(centerX - cropRadius, centerY + cornerOffset),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(centerX + cornerOffset - cornerSize, centerY + cropRadius),
      Offset(centerX + cornerOffset, centerY + cropRadius),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + cropRadius, centerY + cornerOffset - cornerSize),
      Offset(centerX + cropRadius, centerY + cornerOffset),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(CropEditorPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.offset != offset ||
        oldDelegate.scale != scale;
  }
}
