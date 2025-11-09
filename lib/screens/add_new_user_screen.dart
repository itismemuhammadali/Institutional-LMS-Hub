import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import '../services/api_service.dart';
import '../widgets/vertical_nav_bar.dart';
import '../utils/responsive_helper.dart';
import 'home.dart';

class AddNewUserScreen extends StatefulWidget {
  const AddNewUserScreen({
    super.key,
    this.showAddStudent = true,
    this.showCourses = true,
    this.showCourseAssignment = false,
    this.showAdminDues = false,
    this.showStudentDues = true,
  });

  final bool showAddStudent;
  final bool showCourses;
  final bool showCourseAssignment;
  final bool showAdminDues;
  final bool showStudentDues;

  @override
  State<AddNewUserScreen> createState() => _AddNewUserScreenState();
}

class _AddNewUserScreenState extends State<AddNewUserScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _rollNoController = TextEditingController();
  final _teacherRegController = TextEditingController();
  final _newSubjectController = TextEditingController();
  final _userSearchController = TextEditingController();
  String _role = 'Student';
  bool _obscurePassword = true;
  // Student-specific fields
  String? _selectedClass;
  String? _selectedStream; // Computer | Bio (for classes 8-10)
  // Teacher-specific fields
  String? _selectedClassTeacher;

  // Sidebar navigation state (only used for layout + highlighting on this screen)
  final int _selectedNavIndex = 6; // Highlight "Add User"
  bool _isNavExpanded = false; // Back to collapsed by default
  TabController? _tabController;

  void _replaceWithDashboard(int index) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => StudentDashboard(initialIndex: index),
        transitionDuration: Duration(milliseconds: 0),
        reverseTransitionDuration: Duration(milliseconds: 0),
      ),
    );
  }

  Future<Uint8List?> _autoCropBytes(Uint8List data, {required bool circleMask}) async {
    try {
      final image = img.decodeImage(data);
      if (image == null) return null;

      final size = math.min(image.width, image.height);
      final offsetX = (image.width - size) ~/ 2;
      final offsetY = (image.height - size) ~/ 2;
      final processed = img.copyCrop(image, x: offsetX, y: offsetY, width: size, height: size);

      if (circleMask) {
        final radius = size / 2;
        final radiusSq = radius * radius;
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            final dx = x - radius + 0.5;
            final dy = y - radius + 0.5;
            if ((dx * dx + dy * dy) > radiusSq) {
              processed.setPixelRgba(x, y, 0, 0, 0, 0);
            }
          }
        }
      }

      final png = img.encodePng(processed);
      return Uint8List.fromList(png);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openProfilePhotoDialog(ColorScheme scheme, Color accent) async {
    final userId = _selectedUserForProfile;
    if (userId == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Uint8List? previewBytes;
        String? previewPath;
        String? fileName;
        bool uploading = false;
        String? inlineError;
        bool showCropper = false;
        final cropController = CropController();

        Future<void> refreshPreviewBytes() async {
          if (previewPath != null && !kIsWeb) {
            final file = File(previewPath!);
            if (await file.exists()) {
              previewBytes = await file.readAsBytes();
            }
          }
        }

        Uint8List? bytesOrNull() =>
            (previewBytes != null && previewBytes!.isNotEmpty) ? previewBytes : null;

        Future<void> selectFile(StateSetter setModalState) async {
          try {
            inlineError = null;
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              allowMultiple: false,
              withData: true,
            );
            if (result == null || result.files.isEmpty) return;
            final picked = result.files.single;
            fileName = picked.name;
            previewPath = kIsWeb ? null : picked.path;
            previewBytes = picked.bytes;

            if (!kIsWeb && (previewPath == null || previewPath!.isEmpty)) {
              inlineError = 'Unable to read selected file path.';
            } else if (previewBytes == null || previewBytes!.isEmpty) {
              // Attempt to read from path for non-web platforms
              if (!kIsWeb && previewPath != null) {
                previewBytes = await File(previewPath!).readAsBytes();
              }
            }

            showCropper = false;
            setModalState(() {});
          } catch (e) {
            inlineError = 'Failed to select file: $e';
            setModalState(() {});
          }
        }

        Future<void> cropManual(StateSetter setModalState) async {
          inlineError = null;
          final initialBytes = bytesOrNull();
          if (initialBytes == null) {
            inlineError = 'Select a photo before cropping.';
            setModalState(() {});
            return;
          }

          showCropper = true;
          setModalState(() {});
        }

        Future<void> cropAuto(StateSetter setModalState) async {
          inlineError = null;
          final initialBytes = bytesOrNull();
          if (initialBytes == null) {
            inlineError = 'Select a photo before auto cropping.';
            setModalState(() {});
            return;
          }

          final processed = await _autoCropBytes(initialBytes, circleMask: true);
          if (processed != null) {
            previewBytes = processed;
            previewPath = null;
            inlineError = null;
            setModalState(() {});
          } else {
            inlineError = 'Unable to auto crop image.';
            setModalState(() {});
          }
        }

        Future<void> upload(StateSetter setModalState) async {
          if ((previewBytes == null || previewBytes!.isEmpty) && (previewPath == null || previewPath!.isEmpty)) {
            inlineError = 'Please select a photo first.';
            setModalState(() {});
            return;
          }

          setModalState(() {
            uploading = true;
            inlineError = null;
          });

          try {
            final res = await ApiService.uploadProfilePicture(
              userId: userId,
              filePath: (!kIsWeb && previewPath != null) ? previewPath : null,
              fileBytes: previewBytes,
              fileName: fileName ?? 'profile_$userId.png',
            );

            if (res['success'] == true) {
              if (mounted) {
                setState(() => _isLoadingProfilePic = true);
              }
              await _loadProfilePicture(userId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile picture updated')),
                );
              }
              if (context.mounted) Navigator.pop(dialogContext);
            } else {
              throw Exception(res['error'] ?? 'Upload failed');
            }
          } catch (e) {
            inlineError = 'Failed to upload profile picture: $e';
            setModalState(() {
              uploading = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget previewWidget;
            if (showCropper && previewBytes != null && previewBytes!.isNotEmpty) {
              previewWidget = SizedBox(
                height: 300,
                child: Crop(
                  controller: cropController,
                  image: previewBytes!,
                  aspectRatio: 1,
                  withCircleUi: true,
                  onCropped: (cropResult) {
                    switch (cropResult) {
                      case CropSuccess(:final croppedImage):
                        previewBytes = croppedImage;
                        previewPath = null;
                        showCropper = false;
                        inlineError = null;
                        setModalState(() {});
                      case CropFailure(:final cause):
                        inlineError = 'Failed to crop image: $cause';
                        setModalState(() {});
                    }
                  },
                ),
              );
            } else if (previewBytes != null && previewBytes!.isNotEmpty) {
              previewWidget = ClipOval(
                child: Image.memory(previewBytes!, fit: BoxFit.cover, width: 220, height: 220),
              );
            } else if (previewPath != null && !kIsWeb) {
              previewWidget = ClipOval(
                child: Image.file(File(previewPath!), fit: BoxFit.cover, width: 220, height: 220),
              );
            } else if (_selectedUserProfilePicUrl != null && _selectedUserProfilePicUrl!.isNotEmpty) {
              previewWidget = ClipOval(
                child: Image.network(_selectedUserProfilePicUrl!, width: 220, height: 220, fit: BoxFit.cover),
              );
            } else {
              previewWidget = CircleAvatar(
                radius: 110,
                backgroundColor: scheme.primary.withValues(alpha: 0.15),
                child: Icon(Icons.person, size: 100, color: scheme.primary),
              );
            }

            return AlertDialog(
              backgroundColor: scheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              title: Text('Profile Photo', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: scheme.onSurface)),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    previewWidget,
                    const SizedBox(height: 12),
                    Text(fileName ?? 'No file selected', style: GoogleFonts.inter(color: scheme.onSurface.withValues(alpha: 0.7))),
                    if (inlineError != null) ...[
                      const SizedBox(height: 12),
                      Text(inlineError!, style: GoogleFonts.inter(color: scheme.error)),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                TextButton(
                  onPressed: uploading ? null : () => selectFile(setModalState),
                  child: const Text('Select File'),
                ),
                TextButton(
                  onPressed: uploading
                      ? null
                      : () {
                          if (showCropper) {
                            cropController.cropCircle();
                          } else {
                            cropManual(setModalState);
                          }
                        },
                  child: const Text('Edit Crop'),
                ),
                TextButton(
                  onPressed: uploading ? null : () => cropAuto(setModalState),
                  child: const Text('Auto Crop'),
                ),
                FilledButton(
                  onPressed: uploading ? null : () => upload(setModalState),
                  style: FilledButton.styleFrom(backgroundColor: scheme.primary),
                  child: uploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Upload File'),
                ),
                TextButton(
                  onPressed: uploading ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _deriveNextClassName(String current) {
    final regex = RegExp(r'^(.*?)(\d+)([^\d]*)$');
    final match = regex.firstMatch(current.trim());
    if (match == null) {
      return '${current.trim()} +1';
    }
    final prefix = match.group(1) ?? '';
    final number = int.tryParse(match.group(2) ?? '');
    final suffix = match.group(3) ?? '';
    if (number == null) {
      return '${current.trim()} +1';
    }
    return '${prefix.trim()} ${number + 1}${suffix.trim().isEmpty ? '' : ' ${suffix.trim()}'}'.trim();
  }

  Widget _buildFloatingMobileNavbar() {
    final int idx = _tabController?.index ?? 0;
    Color bg = const Color(0xFF1E293B);
    Color active = Colors.white;
    Color inactive = Colors.white.withValues(alpha: 0.7);

    Widget buildItem(IconData icon, int index) {
      final bool selected = idx == index;
      return InkWell(
        onTap: () {
          _tabController?.animateTo(index);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 48,
          height: 40,
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: selected ? active : inactive, size: 22),
        ),
      );
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
          ],
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildItem(Icons.person_add_alt_1, 0),
            const SizedBox(width: 8),
            buildItem(Icons.class_, 1),
            const SizedBox(width: 8),
            buildItem(Icons.person, 2),
          ],
        ),
      ),
    );
  }

  // Date field with showDatePicker, stores value as YYYY-MM-DD in controller
  Widget _buildDateField({
    required TextEditingController controller,
    required String label,
  }) {
    String formatDate(DateTime d) {
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      return '${d.year}-$mm-$dd';
    }

    DateTime? tryParse(String v) {
      try {
        if (v.isEmpty) return null;
        return DateTime.parse(v);
      } catch (_) {
        return null;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          keyboardType: TextInputType.none,
          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
          onTap: () async {
            final now = DateTime.now();
            final initial = tryParse(controller.text) ?? DateTime(now.year - 15, now.month, now.day);
            final first = DateTime(1970);
            final last = DateTime(now.year + 5);
            final picked = await showDatePicker(
              context: context,
              initialDate: initial.isBefore(first) || initial.isAfter(last) ? now : initial,
              firstDate: first,
              lastDate: last,
              helpText: label,
            );
            if (picked != null) {
              controller.text = formatDate(picked);
              setState(() {});
            }
          },
          decoration: InputDecoration(
            hintText: 'YYYY-MM-DD',
            hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
            prefixIcon: Icon(Icons.event, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
            filled: true,
            fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
            ),
          ),
        ),
      ],
    );
  }

  // Generic dropdown field
  Widget _buildDropdownField({
    required String label,
    required List<String> items,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: scheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items
              .map((e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e),
                  ))
              .toList(),
          onChanged: onChanged,
          dropdownColor: Theme.of(context).scaffoldBackgroundColor,
          style: GoogleFonts.inter(color: scheme.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: scheme.onSurface.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.25)),
            ),
          ),
        ),
      ],
    );
  }

  // Opens a bottom sheet to manage subjects for a given level (contextual to a class)
  void _openSubjectsEditor(
    BuildContext context, {
    required String level,
    required String className,
    required ColorScheme scheme,
    required Color accent,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final newSubjectCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<List<Map<String, dynamic>>> load() => ApiService.getSubjects(level);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Subjects for $className', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(level, style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'New Subject',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: newSubjectCtrl,
                              onChanged: (_) => setModalState(() {}),
                              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'e.g., Mathematics',
                                hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          final name = newSubjectCtrl.text.trim();
                          if (name.isEmpty) return;
                          try {
                            // Link subject to the selected class (creates subject if missing)
                            final res = await ApiService.linkSubjectToClass(
                              level: level,
                              className: className,
                              subjectName: name,
                            );
                            if (res['success'] == true) {
                              newSubjectCtrl.clear();
                              setModalState(() {});
                            } else {
                              throw Exception(res['error'] ?? 'Add subject failed');
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add subject failed: $e')));
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
                        child: const Text('Add'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    // Live suggestions from existing subjects in this level
                    if (newSubjectCtrl.text.trim().isNotEmpty)
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: ApiService.searchSubjects(level: level, query: newSubjectCtrl.text.trim(), limit: 10),
                        builder: (ctx, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const SizedBox(height: 4);
                          }
                          final items = snap.data ?? const [];
                          if (items.isEmpty) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07)),
                              itemBuilder: (c, i) {
                                final s = items[i];
                                final name = (s['name'] ?? '').toString();
                                return ListTile(
                                  dense: true,
                                  title: Text(name, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface)),
                                  trailing: TextButton(
                                    onPressed: () {
                                      newSubjectCtrl.text = name;
                                      setModalState(() {});
                                    },
                                    child: const Text('Select'),
                                  ),
                                  onTap: () {
                                    newSubjectCtrl.text = name;
                                    setModalState(() {});
                                  },
                                );
                              },
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: ApiService.getClassSubjects(level: level, className: className),
                        builder: (ctx, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return _skeletonList(scheme);
                          }
                          if (snapshot.hasError) {
                            return _errorState(scheme, title: 'Failed to load subjects', message: '${snapshot.error}', actions: [
                              _outlinedBtn('Retry', onTap: () => setModalState(() {})),
                            ]);
                          }
                          final subjects = snapshot.data ?? [];
                          if (subjects.isEmpty) {
                            return _emptyState(scheme, title: 'No subjects', message: 'Add your first subject to get started.');
                          }
                          return ListView.separated(
                            itemCount: subjects.length,
                            separatorBuilder: (_, __) => Divider(color: scheme.onSurface.withValues(alpha: 0.1)),
                            itemBuilder: (ctx, i) {
                              final s = subjects[i];
                              final name = (s['name'] ?? s['subject_name'] ?? '').toString();
                              return ListTile(
                                title: Text(name, style: GoogleFonts.inter(color: scheme.onSurface)),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error,),
                                  onPressed: () async {
                                    try {
                                      final res = await ApiService.unlinkSubjectFromClass(
                                        level: level,
                                        className: className,
                                        subjectName: name,
                                      );
                                      if (res['success'] == true) {
                                        setModalState(() {});
                                      } else {
                                        throw Exception(res['error'] ?? 'Delete failed');
                                      }
                                    } catch (e) {
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                                    }
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
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

  // Dynamically loaded classes from backend
  List<String> _classes = [];
  bool _classesLoading = false;
  String? _classesError;
  final List<String> _streams = const ['Computer', 'Bio'];
  // Management state
  String _levelForMgmt = 'Primary';
  final _newClassController = TextEditingController();
  String? _selectedClassForSubjectEdit; // when set, subjects tab shows context for this class

  // Access control
  bool _authLoading = true;
  bool _isSuperAdmin = false;

  // Members filters
  final TextEditingController _memberSearchController = TextEditingController();
  String _memberRoleFilter = 'All'; // All | Student | Teacher | Admin

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadClasses();
    _checkSuperAdmin();
  }

  Future<void> _checkSuperAdmin() async {
    try {
      final user = await ApiService.getCurrentUser();
      final isSuper = user != null && (user['is_super_admin'] == 1 || user['is_super_admin'] == '1' || user['role']?.toString().toLowerCase() == 'super_admin');
      if (mounted) setState(() { _isSuperAdmin = isSuper; _authLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _isSuperAdmin = false; _authLoading = false; });
    }
  }

  Future<void> _loadClasses() async {
    setState(() {
      _classesLoading = true;
      _classesError = null;
    });
    try {
      // Fetch classes for Early Years, Primary (Class 1-7) and Secondary (Class 8-10)
      final earlyYears = await ApiService.getClasses('Early Years');
      final primary = await ApiService.getClasses('Primary');
      final secondary = await ApiService.getClasses('Secondary');
      final combined = <String>{}
        ..addAll(earlyYears.map((c) => (c['name'] ?? '').toString()))
        ..addAll(primary.map((c) => (c['name'] ?? '').toString()))
        ..addAll(secondary.map((c) => (c['name'] ?? '').toString()));

      final list = combined.where((e) => e.isNotEmpty).toList();
      // Custom sort: Early Years first (defined order), then Class 1..10
      const earlyOrder = ['Playgroup', 'Nursery', 'Prep', 'KG', 'Montessori'];
      int earlyIndex(String name) {
        return earlyOrder.indexOf(name);
      }
      int classNumber(String name) {
        final match = RegExp(r'^Class\s+(\d+)$').firstMatch(name.trim());
        return match != null ? int.tryParse(match.group(1)!) ?? 999 : 999;
      }
      list.sort((a, b) {
        final ai = earlyIndex(a);
        final bi = earlyIndex(b);
        final aIsEarly = ai != -1;
        final bIsEarly = bi != -1;
        if (aIsEarly && bIsEarly) return ai.compareTo(bi);
        if (aIsEarly) return -1;
        if (bIsEarly) return 1;
        return classNumber(a).compareTo(classNumber(b));
      });

      setState(() {
        _classes = list;
        // Reset previously selected values if they are no longer valid
        if (_selectedClass != null && !_classes.contains(_selectedClass)) {
          _selectedClass = null;
        }
        if (_selectedClassTeacher != null && !_classes.contains(_selectedClassTeacher)) {
          _selectedClassTeacher = null;
        }
      });
    } catch (e) {
      setState(() {
        _classesError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _classesLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _rollNoController.dispose();
    _teacherRegController.dispose();
    _newClassController.dispose();
    _newSubjectController.dispose();
    _memberSearchController.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color lightCard = Color(0xFFE7E0DE);
    const Color lightBorder = Color(0xFFD9D2D0);
    const Color accentBlue = Color(0xFF1E3A8A);
    final Color accent = isDark ? scheme.primary : accentBlue;
    final bool isMobile = ResponsiveHelper.isMobile(context);
    const primaryBlue = Color(0xFF1E3A8A);

    if (_authLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isSuperAdmin) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: scheme.error, size: 48),
              const SizedBox(height: 12),
              Text('Access Denied', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text('This screen is only available to Super Admins.', style: GoogleFonts.inter(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _replaceWithDashboard(1),
                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: scheme.onPrimary),
                child: const Text('Go to Dashboard'),
              )
            ],
          ),
        ),
      );
    }

    final Widget content = Padding(
        padding: EdgeInsets.all(ResponsiveHelper.isMobile(context) ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header area
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: const SizedBox.shrink(),
            ),
          // Manage tabs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TabBar moved into the header row above
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMembersTab(scheme, accent),
                      _buildClassesTab(scheme, accent),
                      _buildProfileTab(scheme, accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: isMobile
          ? PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: primaryBlue,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => setState(() => _isNavExpanded = true),
                          icon: const Icon(Icons.menu, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Add New User',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Manage Members',
                          onPressed: () {},
                          icon: const Icon(Icons.group_add, color: primaryBlue),
                          style: IconButton.styleFrom(backgroundColor: Colors.white, shape: const CircleBorder()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: ResponsiveHelper.isMobile(context)
          ? Stack(
              children: [
                // Main content
                Positioned.fill(child: content),
                // Floating horizontal navbar with 3 icons
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: _buildFloatingMobileNavbar(),
                ),
                // Mobile drawer overlay from VerticalNavBar
                if (_isNavExpanded)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: VerticalNavBar(
                      selectedIndex: _selectedNavIndex,
                      onItemSelected: (index) {
                        setState(() => _isNavExpanded = false);
                        if (index == 6) return;
                        _replaceWithDashboard(index);
                      },
                      isExpanded: _isNavExpanded,
                      onToggleExpanded: (expanded) {
                        setState(() => _isNavExpanded = expanded);
                      },
                      showAddStudent: true, // Add User
                      showCourses: false, // hide Courses
                      showCourseAssignment: true, // Assign Courses
                      showAdminDues: true, // Admin Dues
                      showStudentDues: false, // hide Student Dues
                      showTakeAttendance: true, // Take Attendance
                      showGenerateTicket: true, // Tickets
                    ),
                  ),
              ],
           )
          : Row(
              children: [
                VerticalNavBar(
                  selectedIndex: _selectedNavIndex,
                  onItemSelected: (index) {
                    setState(() => _isNavExpanded = false);
                    if (index == 6) return; // already on Add User
                    // Navigate to dashboard targeting the selected tab without animation
                    _replaceWithDashboard(index);
                  },
                  isExpanded: _isNavExpanded,
                  onToggleExpanded: (expanded) {
                    setState(() => _isNavExpanded = expanded);
                  },
                  showAddStudent: true,
                  showCourses: false,
                  showCourseAssignment: true,
                  showAdminDues: true,
                  showStudentDues: false,
                  showTakeAttendance: true,
                  showGenerateTicket: true,
                ),
                Expanded(
                  child: Column(
                    children: [
                      // Desktop-only in-content header (doesn't overlap nav bar)
                      Container(
                        height: 64,
                        color: primaryBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            // Back button to Home
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => _replaceWithDashboard(1),
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Manage Members',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            const Spacer(),
                            // Tabs in header (right-aligned)
                            _buildPillTabBar(context, scheme, accent),
                          ],
                        ),
                      ),
                      // Main content body
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMembersTab(ColorScheme scheme, Color accent) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Role, Class, and Stream - responsive layout
                LayoutBuilder(
                  builder: (ctx, cons) {
                    final isNarrow = cons.maxWidth < 600;
                    if (isNarrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildRoleDropdown(),
                          const SizedBox(height: 14),
                          if (_role.toLowerCase() == 'student') ...[
                            if (_selectedClass != null && _requiresStream(_selectedClass)) ...[
                              _buildClassDropdown(),
                              const SizedBox(height: 14),
                              _buildStreamDropdown(),
                            ] else ...[
                              _buildClassDropdown(),
                            ],
                          ],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Role Dropdown - full width for admin/superadmin, half for others
                        if ((_role.toLowerCase() == 'admin' || _role.toLowerCase() == 'superadmin')) ...[
                          Expanded(
                            child: _buildRoleDropdown(),
                          ),
                        ] else ...[
                          Expanded(
                            flex: 2,
                            child: _buildRoleDropdown(),
                          ),
                          const SizedBox(width: 14),
                          // Class Dropdown (for Students)
                          if (_role.toLowerCase() == 'student') ...[
                            if (_selectedClass != null && _requiresStream(_selectedClass)) ...[
                              // When stream is needed, take half width
                              Expanded(
                                flex: 2,
                                child: _buildClassDropdown(),
                              ),
                              const SizedBox(width: 14),
                              // Stream Dropdown (for Classes 8-10)
                              Expanded(
                                flex: 2,
                                child: _buildStreamDropdown(),
                              ),
                            ] else ...[
                              // When no stream needed, take full width
                              Expanded(
                                flex: 4,
                                child: _buildClassDropdown(),
                              ),
                            ],
                          ] else ...[
                            const Spacer(flex: 4),
                          ],
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                
                // Full Name
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Enter full name',
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  icon: Icons.person,
                ),
                const SizedBox(height: 14),
                
                // Email
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    final emailRegex = RegExp(r'^\S+@\S+\.\S+$');
                    if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
                    return null;
                  },
                  icon: Icons.email,
                ),
                const SizedBox(height: 14),
                
                // Password
                _buildPasswordField(),
                const SizedBox(height: 14),
                
                // Confirm Password
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Confirm Password',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Please confirm the password';
                        if (v != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: 'Re-enter password',
                        hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                        prefixIcon: Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                
                // Roll Number (for Students)
                if (_role == 'Student') ...[
                  _buildTextField(
                    controller: _rollNoController,
                    label: 'Roll Number',
                    hint: 'Enter roll number',
                    validator: (v) => _role == 'Student' && (v == null || v.trim().isEmpty) 
                        ? 'Roll number is required' 
                        : null,
                    icon: Icons.numbers,
                  ),
                  const SizedBox(height: 14),
                ],
                
                // Registration Number (for Teachers, Admins, and Super Admins)
                if (_role == 'Teacher' || _role == 'Admin' || _role == 'Super Admin') ...[
                  if (_role == 'Teacher') ...[
                    _buildClassTeacherDropdown(),
                    const SizedBox(height: 14),
                  ],
                  _buildTextField(
                    controller: _teacherRegController,
                    label: _role == 'Teacher' 
                        ? 'Teacher Registration Number' 
                        : '$_role Registration Number',
                    hint: 'Enter registration number',
                    validator: (v) => (_role == 'Teacher' || _role == 'Admin' || _role == 'Super Admin') && 
                        (v == null || v.trim().isEmpty) 
                        ? 'Registration number is required' 
                        : null,
                    icon: Icons.badge,
                  ),
                  const SizedBox(height: 14),
                ],
                
                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Save Changes',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassesTab(ColorScheme scheme, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _chipTitle('Classes', scheme),
          const SizedBox(width: 12),
          _levelDropdown(),
          const Spacer(),
          _iconBtn(Icons.refresh, onTap: () => setState(() {})),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: _buildTextField(controller: _newClassController, label: 'New Class', hint: 'e.g., Class 6')),
          const SizedBox(width: 12),
          Transform.translate(
            offset: const Offset(0, -5),
            child: SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final name = _newClassController.text.trim();
                  if (name.isEmpty) return;
                  try {
                    final res = await ApiService.addClass(level: _levelForMgmt, className: name);
                if (res['success'] == true) {
                  _newClassController.clear();
                  if (mounted) setState(() {});
                } else {
                  throw Exception(res['error'] ?? 'Add class failed');
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add class failed: $e')));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
                child: Text('Add', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ),
          )
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ApiService.getClasses(_levelForMgmt),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return _skeletonList(scheme);
              if (snapshot.hasError) return _errorState(scheme, title: 'Failed to load classes', message: '${snapshot.error}', actions: [_outlinedBtn('Retry', onTap: () => setState(() {}))]);
              final classes = snapshot.data ?? [];
              if (classes.isEmpty) return _emptyState(scheme, title: 'No classes', message: 'Get started by adding a class.');
              return ListView.separated(
                itemCount: classes.length,
                separatorBuilder: (_, __) => Divider(color: scheme.onSurface.withValues(alpha: 0.1)),
                itemBuilder: (context, i) {
                  final c = classes[i];
                  final name = (c['name'] ?? c['class_name'] ?? '').toString();
                  return ListTile(
                    title: Text(name, style: GoogleFonts.inter(color: scheme.onSurface)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Edit subjects for this class in-place (modal)
                        IconButton(
                          tooltip: 'Edit Subjects',
                          icon: const Icon(Icons.menu_book_outlined, color: Color(0xFFF59E0B)),
                          onPressed: () {
                            _openSubjectsEditor(context, level: _levelForMgmt, className: name, scheme: scheme, accent: accent);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.drive_file_rename_outline, color: Color(0xFF60A5FA)),
                          onPressed: () async {
                            final controller = TextEditingController(text: name);
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: Theme.of(context).colorScheme.surface,
                                title: Text('Rename Class', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                                content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'New class name')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              try {
                                final res = await ApiService.renameClass(level: _levelForMgmt, oldName: name, newName: controller.text.trim());
                                if (res['success'] == true) {
                                  if (mounted) setState(() {});
                                } else {
                                  throw Exception(res['error'] ?? 'Rename failed');
                                }
                              } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
                              }
                            }
                          },
                        ),
                        // Unassign teachers from this class
                        IconButton(
                          tooltip: 'Unassign Teachers',
                          icon: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF60A5FA)),
                          onPressed: () async {
                            Future<List<Map<String, dynamic>>> loadRows() async {
                              int? parseInt(dynamic value) {
                                if (value == null) return null;
                                if (value is int) return value;
                                return int.tryParse(value.toString());
                              }
                              final results = await Future.wait([
                                ApiService.getClassSubjects(level: _levelForMgmt, className: name),
                                ApiService.getAssignments(level: _levelForMgmt, className: name),
                              ]);
                              final subjects = List<Map<String, dynamic>>.from(results[0] as List);
                              final assignments = List<Map<String, dynamic>>.from(results[1] as List);
                              final assignmentBySubject = <int, Map<String, dynamic>>{};
                              for (final assignment in assignments) {
                                final subjectId = parseInt(assignment['subject_id']);
                                if (subjectId == null) continue;
                                assignmentBySubject[subjectId] = assignment;
                              }
                              final rows = <Map<String, dynamic>>[];
                              for (final subject in subjects) {
                                final subjectId = parseInt(subject['subject_id']) ?? parseInt(subject['id']);
                                final subjectNameValue = subject['name'] ?? subject['subject_name'];
                                final subjectName = subjectNameValue == null ? '' : subjectNameValue.toString();
                                if (subjectId == null || subjectName.trim().isEmpty) continue;
                                final assignment = assignmentBySubject[subjectId];
                                final teacherNameRaw = assignment?['teacher_name'];
                                rows.add({
                                  'subjectId': subjectId,
                                  'subjectName': subjectName,
                                  'assignmentId': parseInt(assignment?['id']),
                                  'teacherName': teacherNameRaw == null || teacherNameRaw.toString().trim().isEmpty
                                      ? null
                                      : teacherNameRaw.toString(),
                                });
                              }
                              rows.sort((a, b) => a['subjectName'].toString().toLowerCase().compareTo(b['subjectName'].toString().toLowerCase()));
                              return rows;
                            }

                            Future<List<Map<String, dynamic>>> rowsFuture = loadRows();
                            int? deletingAssignmentId;
                            String? inlineError;
                            final parentContext = context;

                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) {
                                final scheme = Theme.of(dialogContext).colorScheme;
                                const Color dialogPrimary = Color(0xFF1E3A8A);
                                final Color dialogSecondary = dialogPrimary.withValues(alpha: 0.75);
                                final Color dialogMuted = dialogPrimary.withValues(alpha: 0.6);
                                TextStyle labelStyle(Color color) => GoogleFonts.inter(color: color, height: 1.35);
                                return StatefulBuilder(
                                  builder: (context, setDialogState) {
                                    Widget buildHeaderRow(TextStyle style) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 4, top: 4),
                                        child: Row(
                                          children: [
                                            Expanded(flex: 5, child: Text('Subject', style: style)),
                                            Expanded(flex: 5, child: Text('Teacher', style: style)),
                                            const SizedBox(width: 44),
                                          ],
                                        ),
                                      );
                                    }

                                    Widget buildRow(Map<String, dynamic> row) {
                                      final subjectName = row['subjectName'] as String? ?? '';
                                      final teacherName = row['teacherName'] as String?;
                                      final assignmentId = row['assignmentId'] as int?;
                                      final bool isDeleting = deletingAssignmentId != null && deletingAssignmentId == assignmentId;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Row(
                                          children: [
                                            Expanded(flex: 5, child: Text(subjectName, style: labelStyle(dialogPrimary))),
                                            Expanded(
                                              flex: 5,
                                              child: Text(
                                                teacherName ?? 'No teacher assigned',
                                                style: labelStyle(
                                                  teacherName == null ? dialogMuted : dialogSecondary,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 44,
                                              child: isDeleting
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : IconButton(
                                                      tooltip: assignmentId != null
                                                          ? 'Unassign $subjectName'
                                                          : 'No teacher to unassign',
                                                      icon: Icon(
                                                        Icons.person_remove_alt_1_outlined,
                                                        color: assignmentId != null ? scheme.error : dialogMuted,
                                                      ),
                                                      onPressed: assignmentId == null
                                                          ? null
                                                          : () async {
                                                              setDialogState(() {
                                                                inlineError = null;
                                                                deletingAssignmentId = assignmentId;
                                                              });
                                                              try {
                                                                final res = await ApiService.deleteAssignment(
                                                                  assignmentId: assignmentId,
                                                                );
                                                                if (res['success'] == true) {
                                                                  setDialogState(() {
                                                                    rowsFuture = loadRows();
                                                                    deletingAssignmentId = null;
                                                                  });
                                                                  if (mounted) {
                                                                    ScaffoldMessenger.of(parentContext).showSnackBar(
                                                                      SnackBar(
                                                                        content: Text(
                                                                          'Unassigned $subjectName',
                                                                          style: GoogleFonts.inter(color: Colors.white),
                                                                        ),
                                                                        backgroundColor: scheme.error,
                                                                      ),
                                                                    );
                                                                  }
                                                                } else {
                                                                  throw Exception(res['error'] ?? 'Failed to unassign');
                                                                }
                                                              } catch (e) {
                                                                setDialogState(() {
                                                                  inlineError = 'Failed to unassign: $e';
                                                                  deletingAssignmentId = null;
                                                                });
                                                              }
                                                            },
                                                    ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return AlertDialog(
                                      backgroundColor: scheme.surface,
                                      title: Text('Unassign Teachers', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                      content: FutureBuilder<List<Map<String, dynamic>>>(
                                        future: rowsFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Fetching class subjects and teachers...', style: labelStyle(dialogSecondary)),
                                                  const SizedBox(height: 18),
                                                  const Center(child: CircularProgressIndicator()),
                                                ],
                                              ),
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Unable to load current assignments for "$name".', style: labelStyle(dialogSecondary)),
                                                  const SizedBox(height: 12),
                                                  Text('Details: ${snapshot.error}', style: labelStyle(scheme.error)),
                                                  const SizedBox(height: 8),
                                                  Text('You can still proceed to clear all assignments using the button below.', style: labelStyle(dialogMuted)),
                                                ],
                                              ),
                                            );
                                          }

                                          final rows = snapshot.data ?? const [];
                                          if (rows.isEmpty) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('This class does not have any subjects linked yet.', style: labelStyle(dialogMuted)),
                                                  const SizedBox(height: 12),
                                                  Text('Use the class subjects manager to link subjects, then assign teachers.', style: labelStyle(dialogMuted)),
                                                ],
                                              ),
                                            );
                                          }

                                          return SizedBox(
                                            width: 420,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                buildHeaderRow(labelStyle(dialogPrimary).copyWith(fontWeight: FontWeight.w600)),
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxHeight: 260),
                                                  child: Scrollbar(
                                                    thumbVisibility: rows.length > 5,
                                                    child: ListView.separated(
                                                      shrinkWrap: true,
                                                      itemCount: rows.length,
                                                      separatorBuilder: (_, __) => Divider(color: dialogPrimary.withValues(alpha: 0.15), height: 1),
                                                      itemBuilder: (_, index) => buildRow(rows[index]),
                                                    ),
                                                  ),
                                                ),
                                                if (inlineError != null) ...[
                                                  const SizedBox(height: 12),
                                                  Text(inlineError!, style: labelStyle(scheme.error)),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext, false),
                                          child: Text('Cancel', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext, true),
                                          child: Text('Unassign', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );

                            if (ok == true) {
                              try {
                                final res = await ApiService.unassignClassTeachers(level: _levelForMgmt, className: name);
                                if (res['success'] == true) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Teachers unassigned from $name', style: GoogleFonts.inter(color: Colors.white)),
                                        backgroundColor: Theme.of(context).colorScheme.primary,
                                      ),
                                    );
                                    setState(() {});
                                  }
                                } else {
                                  throw Exception(res['error'] ?? 'Operation failed');
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Operation failed: $e')),
                                  );
                                }
                              }
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Promote Students',
                          icon: const Icon(Icons.arrow_circle_up_outlined, color: Color(0xFF22C55E)),
                          onPressed: () async {
                            final nextClassName = _deriveNextClassName(name);
                            final promotionLabel = 'Promoted to $nextClassName';

                            Future<List<Map<String, dynamic>>> loadStudents() async {
                              final roster = await ApiService.getStudentsInClass(name);
                              roster.sort((a, b) {
                                final an = (a['student_name'] ?? a['name'] ?? '').toString().toLowerCase();
                                final bn = (b['student_name'] ?? b['name'] ?? '').toString().toLowerCase();
                                return an.compareTo(bn);
                              });
                              return roster;
                            }

                            Future<List<Map<String, dynamic>>> studentsFuture = loadStudents();
                            String? inlineError;
                            int? promotingStudentId;
                            bool promoteAllLoading = false;
                            final parentContext = context;

                            await showDialog<void>(
                              context: context,
                              builder: (dialogContext) {
                                final scheme = Theme.of(dialogContext).colorScheme;
                                const Color dialogPrimary = Color(0xFF1E3A8A);
                                final Color dialogSecondary = dialogPrimary.withValues(alpha: 0.9);
                                final Color dialogMuted = dialogPrimary.withValues(alpha: 0.65);
                                TextStyle labelStyle(Color color) => GoogleFonts.inter(color: color, height: 1.35);

                                return StatefulBuilder(
                                  builder: (context, setDialogState) {
                                    Widget studentTile(Map<String, dynamic> student) {
                                      final displayName = (student['student_name'] ?? student['name'] ?? student['full_name'] ?? 'Student').toString();
                                      final roll = (student['roll_number'] ?? student['roll_no'] ?? student['roll']).toString();
                                      final hasRoll = roll.isNotEmpty && roll.toLowerCase() != 'null';
                                      final studentIdRaw = student['student_user_id'] ?? student['user_id'] ?? student['id'];
                                      final studentId = studentIdRaw is int ? studentIdRaw : int.tryParse(studentIdRaw?.toString() ?? '');
                                      final isPromoting = promotingStudentId != null && promotingStudentId == studentId;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(displayName, style: labelStyle(dialogPrimary)),
                                                  if (hasRoll)
                                                    Text('Roll: $roll', style: labelStyle(dialogMuted).copyWith(fontSize: 13)),
                                                ],
                                              ),
                                            ),
                                            SizedBox(
                                              width: 44,
                                              child: isPromoting
                                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                  : IconButton(
                                                      tooltip: studentId == null
                                                          ? 'Missing student id'
                                                          : 'Promote $displayName to $nextClassName',
                                                      icon: Icon(Icons.trending_up, color: scheme.primary),
                                                      onPressed: studentId == null
                                                          ? null
                                                          : () async {
                                                              setDialogState(() {
                                                                inlineError = null;
                                                                promotingStudentId = studentId;
                                                              });
                                                              try {
                                                                final res = await ApiService.updateUserProfile(studentId, {
                                                                  'class': promotionLabel,
                                                                });
                                                                if (res['success'] == true) {
                                                                  setDialogState(() {
                                                                    promotingStudentId = null;
                                                                    studentsFuture = loadStudents();
                                                                  });
                                                                  if (mounted) {
                                                                    ScaffoldMessenger.of(parentContext).showSnackBar(
                                                                      SnackBar(
                                                                        content: Text('Promoted $displayName to $nextClassName', style: GoogleFonts.inter(color: Colors.white)),
                                                                        backgroundColor: scheme.primary,
                                                                      ),
                                                                    );
                                                                  }
                                                                } else {
                                                                  throw Exception(res['error'] ?? 'Promotion failed');
                                                                }
                                                              } catch (e) {
                                                                setDialogState(() {
                                                                  inlineError = 'Failed to promote student: $e';
                                                                  promotingStudentId = null;
                                                                });
                                                              }
                                                            },
                                                    ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }

                                    return AlertDialog(
                                      backgroundColor: scheme.surface,
                                      title: Text('Promote Students', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                      content: FutureBuilder<List<Map<String, dynamic>>>(
                                        future: studentsFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Loading students in "$name"...', style: labelStyle(dialogSecondary)),
                                                  const SizedBox(height: 18),
                                                  const Center(child: CircularProgressIndicator()),
                                                ],
                                              ),
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Unable to load class roster.', style: labelStyle(dialogSecondary)),
                                                  const SizedBox(height: 12),
                                                  Text('Details: ${snapshot.error}', style: labelStyle(scheme.error)),
                                                ],
                                              ),
                                            );
                                          }

                                          final students = snapshot.data ?? const [];
                                          if (students.isEmpty) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('No students enrolled in "$name".', style: labelStyle(dialogMuted)),
                                                  const SizedBox(height: 12),
                                                  Text('Students promoted here will have their class updated to "$promotionLabel".', style: labelStyle(dialogMuted)),
                                                ],
                                              ),
                                            );
                                          }

                                          return SizedBox(
                                            width: 420,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Destined class: $promotionLabel', style: labelStyle(dialogPrimary).copyWith(fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 12),
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxHeight: 260),
                                                  child: Scrollbar(
                                                    thumbVisibility: students.length > 5,
                                                    child: ListView.separated(
                                                      shrinkWrap: true,
                                                      itemCount: students.length,
                                                      separatorBuilder: (_, __) => Divider(color: dialogPrimary.withValues(alpha: 0.15), height: 1),
                                                      itemBuilder: (_, index) => studentTile(students[index]),
                                                    ),
                                                  ),
                                                ),
                                                if (inlineError != null) ...[
                                                  const SizedBox(height: 12),
                                                  Text(inlineError!, style: labelStyle(scheme.error)),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: promoteAllLoading ? null : () => Navigator.pop(dialogContext),
                                          child: Text('Close', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                        ),
                                        TextButton(
                                          onPressed: promoteAllLoading
                                              ? null
                                              : () async {
                                                  setDialogState(() {
                                                    inlineError = null;
                                                    promoteAllLoading = true;
                                                  });
                                                  try {
                                                    final roster = await loadStudents();
                                                    for (final student in roster) {
                                                      final studentIdRaw = student['student_user_id'] ?? student['user_id'] ?? student['id'];
                                                      final studentId = studentIdRaw is int
                                                          ? studentIdRaw
                                                          : int.tryParse(studentIdRaw?.toString() ?? '');
                                                      if (studentId == null) continue;
                                                      final res = await ApiService.updateUserProfile(studentId, {
                                                        'class': promotionLabel,
                                                      });
                                                      if (res['success'] != true) {
                                                        throw Exception(res['error'] ?? 'Failed to promote student ID $studentId');
                                                      }
                                                    }
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(parentContext).showSnackBar(
                                                        SnackBar(
                                                          content: Text('Promoted all students in $name to $nextClassName', style: GoogleFonts.inter(color: Colors.white)),
                                                          backgroundColor: scheme.primary,
                                                        ),
                                                      );
                                                    }
                                                    Navigator.pop(dialogContext);
                                                  } catch (e) {
                                                    setDialogState(() {
                                                      inlineError = 'Failed to promote class: $e';
                                                      promoteAllLoading = false;
                                                    });
                                                  }
                                                },
                                          child: promoteAllLoading
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                              : Text('Promote All', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                        // Dismember class (unlink students)
                        IconButton(
                          tooltip: 'Dismember Class',
                          icon: Icon(Icons.link_off_rounded, color: Theme.of(context).colorScheme.error,),
                          onPressed: () async {
                            Future<List<Map<String, dynamic>>> loadStudents() async {
                              final roster = await ApiService.getStudentsInClass(name);
                              roster.sort((a, b) {
                                final an = (a['student_name'] ?? a['name'] ?? '').toString().toLowerCase();
                                final bn = (b['student_name'] ?? b['name'] ?? '').toString().toLowerCase();
                                return an.compareTo(bn);
                              });
                              return roster;
                            }

                            Future<List<Map<String, dynamic>>> studentsFuture = loadStudents();
                            String? inlineError;
                            int? removingStudentId;
                            bool dismemberAllLoading = false;
                            final parentContext = context;

                            final action = await showDialog<String>(
                              context: context,
                              builder: (dialogContext) {
                                final scheme = Theme.of(dialogContext).colorScheme;
                                const Color dialogPrimary = Color(0xFF1E3A8A);
                                final Color dialogSecondary = dialogPrimary.withValues(alpha: 0.9);
                                final Color dialogMuted = dialogPrimary.withValues(alpha: 0.65);
                                TextStyle labelStyle(Color color) => GoogleFonts.inter(color: color, height: 1.35);

                                return StatefulBuilder(
                                  builder: (context, setDialogState) {
                                    return AlertDialog(
                                      backgroundColor: scheme.surface,
                                      title: Text('Dismember Class', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                      content: FutureBuilder<List<Map<String, dynamic>>>(
                                        future: studentsFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState == ConnectionState.waiting) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Fetching enrolled students for "$name"...', style: labelStyle(dialogSecondary)),
                                                  const SizedBox(height: 18),
                                                  const Center(child: CircularProgressIndicator()),
                                                ],
                                              ),
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('Unable to load class roster.', style: labelStyle(dialogSecondary)),
                                                  const SizedBox(height: 12),
                                                  Text('Details: ${snapshot.error}', style: labelStyle(scheme.error)),
                                                  const SizedBox(height: 8),
                                                  Text('You can still dismember all students using the button below.', style: labelStyle(dialogMuted)),
                                                ],
                                              ),
                                            );
                                          }

                                          final students = snapshot.data ?? const [];
                                          if (students.isEmpty) {
                                            return SizedBox(
                                              width: 420,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('No students are currently linked to "$name".', style: labelStyle(dialogMuted)),
                                                  const SizedBox(height: 12),
                                                  Text('Use the class roster tools to add students, or dismember all to ensure a clean slate.', style: labelStyle(dialogMuted)),
                                                ],
                                              ),
                                            );
                                          }

                                          return SizedBox(
                                            width: 420,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Students currently linked:', style: labelStyle(dialogPrimary).copyWith(fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 12),
                                                ConstrainedBox(
                                                  constraints: const BoxConstraints(maxHeight: 260),
                                                  child: Scrollbar(
                                                    thumbVisibility: students.length > 5,
                                                    child: ListView.separated(
                                                      shrinkWrap: true,
                                                      itemCount: students.length,
                                                      separatorBuilder: (_, __) => Divider(color: dialogPrimary.withValues(alpha: 0.15), height: 1),
                                                      itemBuilder: (_, index) {
                                                        final student = students[index];
                                                        final displayName = (student['student_name'] ?? student['name'] ?? student['full_name'] ?? 'Student').toString();
                                                        final roll = (student['roll_number'] ?? student['roll_no'] ?? student['roll']).toString();
                                                        final bool hasRoll = roll.isNotEmpty && roll.toLowerCase() != 'null';
                                                        final studentIdRaw = student['student_user_id'] ?? student['user_id'] ?? student['id'];
                                                        final studentId = studentIdRaw is int ? studentIdRaw : int.tryParse(studentIdRaw?.toString() ?? '');
                                                        final bool isRemoving = removingStudentId != null && removingStudentId == studentId;
                                                        return Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                                          child: Row(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Expanded(
                                                                child: Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text(displayName, style: labelStyle(dialogPrimary)),
                                                                    if (hasRoll)
                                                                      Text('Roll: $roll', style: labelStyle(dialogMuted).copyWith(fontSize: 13)),
                                                                  ],
                                                                ),
                                                              ),
                                                              SizedBox(
                                                                width: 44,
                                                                child: isRemoving
                                                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                                                    : IconButton(
                                                                        tooltip: studentId == null ? 'Missing student id' : 'Dismember $displayName',
                                                                        icon: Icon(Icons.person_remove_alt_1_outlined, color: scheme.error),
                                                                        onPressed: studentId == null
                                                                            ? null
                                                                            : () async {
                                                                                setDialogState(() {
                                                                                  inlineError = null;
                                                                                  removingStudentId = studentId;
                                                                                });
                                                                                try {
                                                                                  final newClassLabel = 'Dismembered from $name';
                                                                                  final profileRes = await ApiService.updateUserProfile(
                                                                                    studentId,
                                                                                    {
                                                                                      'class': newClassLabel,
                                                                                    },
                                                                                  );
                                                                                  if (profileRes['success'] != true) {
                                                                                    throw Exception(profileRes['error'] ?? 'Failed to update profile');
                                                                                  }
                                                                                  final res = await ApiService.unlinkStudentFromClass(
                                                                                    studentUserId: studentId,
                                                                                    className: name,
                                                                                  );
                                                                                  if (res['success'] == true) {
                                                                                    studentsFuture = loadStudents();
                                                                                    setDialogState(() {
                                                                                      removingStudentId = null;
                                                                                    });
                                                                                    if (mounted) {
                                                                                      ScaffoldMessenger.of(parentContext).showSnackBar(
                                                                                        SnackBar(
                                                                                          content: Text('Removed $displayName from $name', style: GoogleFonts.inter(color: Colors.white)),
                                                                                          backgroundColor: scheme.error,
                                                                                        ),
                                                                                      );
                                                                                    }
                                                                                  } else {
                                                                                    throw Exception(res['error'] ?? 'Failed to dismember student');
                                                                                  }
                                                                                } catch (e) {
                                                                                  setDialogState(() {
                                                                                    inlineError = 'Failed to dismember student: $e';
                                                                                    removingStudentId = null;
                                                                                  });
                                                                                }
                                                                              },
                                                                      ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                if (inlineError != null) ...[
                                                  const SizedBox(height: 12),
                                                  Text(inlineError!, style: labelStyle(scheme.error)),
                                                ],
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext),
                                          child: Text('Cancel', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                        ),
                                        TextButton(
                                          onPressed: dismemberAllLoading
                                              ? null
                                              : () async {
                                                  setDialogState(() {
                                                    inlineError = null;
                                                    dismemberAllLoading = true;
                                                  });
                                                  try {
                                                    final roster = await loadStudents();
                                                    for (final student in roster) {
                                                      final studentIdRaw = student['student_user_id'] ?? student['user_id'] ?? student['id'];
                                                      final studentId = studentIdRaw is int ? studentIdRaw : int.tryParse(studentIdRaw?.toString() ?? '');
                                                      if (studentId == null) {
                                                        continue;
                                                      }
                                                      final newClassLabel = 'Dismembered from $name';
                                                      final profileRes = await ApiService.updateUserProfile(
                                                        studentId,
                                                        {
                                                          'class': newClassLabel,
                                                        },
                                                      );
                                                      if (profileRes['success'] != true) {
                                                        throw Exception(profileRes['error'] ?? 'Failed to update profile for student ID $studentId');
                                                      }
                                                    }

                                                    final res = await ApiService.dismemberClass(level: _levelForMgmt, className: name);
                                                    if (res['success'] == true) {
                                                      Navigator.pop(dialogContext, 'bulk');
                                                    } else {
                                                      throw Exception(res['error'] ?? 'Operation failed');
                                                    }
                                                  } catch (e) {
                                                    setDialogState(() {
                                                      inlineError = 'Failed to dismember class: $e';
                                                      dismemberAllLoading = false;
                                                    });
                                                  }
                                                },
                                          child: dismemberAllLoading
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                              : Text('Dismember All', style: GoogleFonts.inter(color: dialogPrimary, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );

                            if (action == 'bulk') {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Class $name dismembered', style: GoogleFonts.inter(color: Colors.white)),
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                  ),
                                );
                                setState(() {});
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== Subjects Tab ====================
  
  // ==================== Profile Tab ====================
  List<Map<String, dynamic>> _filteredUsers = [];
  
  void _filterUsers(List<Map<String, dynamic>> allUsers, String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = allUsers;
      } else {
        _filteredUsers = allUsers.where((user) {
          final name = (user['name'] ?? '').toString().toLowerCase();
          final email = (user['email'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase()) || email.contains(query.toLowerCase());
        }).toList();
      }
    });
  }
  Widget _buildSubjectsTab(ColorScheme scheme, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedClassForSubjectEdit != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(children: [
              Text('Editing subjects for: $_selectedClassForSubjectEdit', style: GoogleFonts.inter(color: Colors.white)),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => setState(() => _selectedClassForSubjectEdit = null),
                child: const Text('Clear'),
              )
            ]),
          ),
        Row(children: [
          _chipTitle('Subjects', scheme),
          const SizedBox(width: 12),
          _levelDropdown(),
          const Spacer(),
          _iconBtn(Icons.refresh, onTap: () => setState(() {})),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildTextField(controller: _newSubjectController, label: 'New Subject', hint: 'e.g., Mathematics')),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () async {
              final name = _newSubjectController.text.trim();
              if (name.isEmpty) return;
              try {
                // First, try to add/link the subject to the class
                final res = await ApiService.addSubject(level: _levelForMgmt, subjectName: name);
                if (res['success'] == true) {
                  _newSubjectController.clear();
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Subject "$name" added successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } else {
                  throw Exception(res['error'] ?? 'Add subject failed');
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add subject failed: $e')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Add'),
          )
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ApiService.getSubjects(_levelForMgmt),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return _skeletonList(scheme);
              if (snapshot.hasError) return _errorState(scheme, title: 'Failed to load subjects', message: '${snapshot.error}', actions: [_outlinedBtn('Retry', onTap: () => setState(() {}))]);
              final subjects = snapshot.data ?? [];
              if (subjects.isEmpty) return _emptyState(scheme, title: 'No subjects', message: 'Add your first subject to get started.');
              return ListView.separated(
                itemCount: subjects.length,
                separatorBuilder: (_, __) => Divider(color: scheme.onSurface.withValues(alpha: 0.1)),
                itemBuilder: (context, i) {
                  final s = subjects[i];
                  final name = (s['name'] ?? s['subject_name'] ?? '').toString();
                  return ListTile(
                    title: Text(name, style: GoogleFonts.inter(color: scheme.onSurface)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error,),
                      tooltip: 'Remove subject from class',
                      onPressed: () async {
                        // Show confirmation dialog
                        final bool? confirmed = await showDialog<bool>(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('Remove Subject'),
                              content: Text('Are you sure you want to remove "$name" from this class?\n\nThis will unlink the subject from the class but won\'t delete the subject entirely.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                                  child: Text('Remove'),
                                ),
                              ],
                            );
                          },
                        );
                        
                        if (confirmed != true) return;
                        
                        try {
                          final res = await ApiService.deleteSubject(level: _levelForMgmt, subjectName: name);
                          if (res['success'] == true) {
                            if (mounted) {
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Subject "$name" removed from class'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          } else {
                            throw Exception(res['error'] ?? 'Remove failed');
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== Profile Tab ====================
  int? _selectedUserForProfile;
  String? _selectedUserProfilePicUrl;
  bool _isLoadingProfilePic = false;

  Future<void> _loadProfilePicture(int? userId) async {
    if (userId == null) {
      setState(() {
        _selectedUserProfilePicUrl = null;
        _isLoadingProfilePic = false;
      });
      return;
    }

    setState(() => _isLoadingProfilePic = true);
    
    try {
      final url = await ApiService.getUserProfilePictureUrl(userId);
      if (mounted) {
        setState(() {
          _selectedUserProfilePicUrl = url;
          _isLoadingProfilePic = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedUserProfilePicUrl = null;
          _isLoadingProfilePic = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load profile picture: $e')),
        );
      }
    }
  }

  Widget _buildProfileTab(ColorScheme scheme, Color accent) {
    final bool isMobile = ResponsiveHelper.isMobile(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profile Management',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.light
                ? const Color(0xFF1E3A8A)
                : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        // Search bar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _userSearchController,
                style: GoogleFonts.inter(color: scheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search users by name or email...',
                  hintStyle: GoogleFonts.inter(
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xFF1E3A8A).withValues(alpha: 0.5)
                        : scheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xFF1E3A8A)
                        : scheme.onSurface.withValues(alpha: 0.7),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.light
                      ? const Color(0xFFE7E0DE)
                      : scheme.onSurface.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFFD9D2D0)
                          : scheme.onSurface.withValues(alpha: 0.15),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFF1E3A8A)
                          : scheme.onSurface.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                onChanged: (query) {
                  setState(() {}); // Trigger rebuild to filter users
                },
              ),
            ),
            const SizedBox(width: 12),
            // Delete user completely
            ElevatedButton.icon(
                onPressed: _selectedUserForProfile == null ? null : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      title: Text('Delete User', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
                      content: Text('This will permanently delete the user and their profile. Continue?', style: GoogleFonts.inter(color: Colors.white70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      final res = await ApiService.deleteUser(_selectedUserForProfile!);
                      if (res['success'] == true) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User deleted', style: GoogleFonts.inter(color: scheme.onPrimary)), backgroundColor: Theme.of(context).colorScheme.primary,));
                          setState(() { _selectedUserForProfile = null; });
                        }
                      } else {
                        throw Exception(res['error'] ?? 'Delete failed');
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete User'),
              ),
            ],
          ),
        const SizedBox(height: 16),

        // User List (hide once a user is selected)
        if (_selectedUserForProfile == null)
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ApiService.getAllUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading users: ${snapshot.error}', 
                    style: GoogleFonts.inter(color: scheme.error)),
                );
              }
              
              final allUsers = snapshot.data ?? [];
              
              // Filter users based on search query
              final query = _userSearchController.text.toLowerCase();
              final filteredUsers = query.isEmpty 
                ? allUsers 
                : allUsers.where((user) {
                    final name = (user['name'] ?? '').toString().toLowerCase();
                    final email = (user['email'] ?? '').toString().toLowerCase();
                    return name.contains(query) || email.contains(query);
                  }).toList();
              
              if (filteredUsers.isEmpty) {
                return Center(
                  child: Text(
                    query.isEmpty ? 'No users found' : 'No users match your search',
                    style: GoogleFonts.inter(color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                );
              }
              
              return ListView.builder(
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  final id = user['id'] ?? user['user_id'];
                  final userId = int.tryParse('$id') ?? id;
                  final name = (user['name'] ?? 'Unknown').toString();
                  final email = (user['email'] ?? 'No email').toString();
                  final isSelected = _selectedUserForProfile == userId;
                  
                  final bool light = Theme.of(context).brightness == Brightness.light;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: light
                          ? (isSelected
                              ? const Color(0xFF1E3A8A).withValues(alpha: 0.12)
                              : const Color(0xFFE7E0DE))
                          : (isSelected
                              ? scheme.primary.withValues(alpha: 0.1)
                              : scheme.onSurface.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: light
                            ? (isSelected
                                ? const Color(0xFF1E3A8A).withValues(alpha: 0.35)
                                : const Color(0xFFD9D2D0))
                            : (isSelected
                                ? scheme.primary.withValues(alpha: 0.3)
                                : scheme.onSurface.withValues(alpha: 0.1)),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: light
                          ? [
                              BoxShadow(
                                color: const Color(0xFF1E3A8A).withValues(alpha: 0.07),
                                blurRadius: 14,
                                offset: const Offset(0, 7),
                              ),
                            ]
                          : [],
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: light
                            ? const Color(0xFF1E3A8A).withValues(alpha: 0.15)
                            : scheme.primary.withValues(alpha: 0.2),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: GoogleFonts.inter(
                            color: light ? const Color(0xFF1E3A8A) : scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: GoogleFonts.inter(
                          color: light ? const Color(0xFF1E3A8A) : scheme.onSurface,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        email,
                        style: GoogleFonts.inter(
                          color: light
                              ? const Color(0xFF1E3A8A).withValues(alpha: 0.7)
                              : scheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle,
                              color: light ? const Color(0xFF1E3A8A) : scheme.primary)
                          : null,
                      onTap: () {
                        setState(() => _selectedUserForProfile = userId);
                        _loadProfilePicture(userId);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        
        const SizedBox(height: 16),

        if (_selectedUserForProfile != null)
          Expanded(
            child: FutureBuilder<Map<String, dynamic>?>(
              future: ApiService.getUserProfile(_selectedUserForProfile!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.inter(color: scheme.error)));
                final p = snapshot.data;
                if (p == null) return Center(child: Text('No profile data', style: GoogleFonts.inter(color: scheme.onSurface.withValues(alpha: 0.7))));
                final classController = TextEditingController(text: (p['class'] ?? '').toString());
                final streamController = TextEditingController(text: (p['batch'] ?? p['stream'] ?? '').toString());
                final rollController = TextEditingController(text: (p['roll_number'] ?? '').toString());
                final regController = TextEditingController(text: (p['registration_no'] ?? '').toString());
                // Additional personal info
                final cnicController = TextEditingController(text: (p['cnic'] ?? p['cnic_no'] ?? '').toString());
                final dobController = TextEditingController(text: (p['dob'] ?? p['date_of_birth'] ?? '').toString());
                String genderValue = (p['gender'] ?? '').toString();
                String bloodGroupValue = (p['blood_group'] ?? '').toString();
                final nationalityController = TextEditingController(text: (p['nationality'] ?? '').toString());
                final religionController = TextEditingController(text: (p['religion'] ?? '').toString());
                // Academic
                final classTeacherOfController = TextEditingController(text: (p['class_teacher_of'] ?? '').toString());
                final enrollmentDateController = TextEditingController(text: (p['enrollment_date'] ?? '').toString());
                // Contact
                final phoneController = TextEditingController(text: (p['phone'] ?? p['phone_number'] ?? '').toString());
                final whatsappController = TextEditingController(text: (p['whatsapp'] ?? '').toString());
                final altPhoneController = TextEditingController(text: (p['alt_phone'] ?? p['alternative_phone'] ?? '').toString());
                // Emergency
                final emergencyPhoneController = TextEditingController(text: (p['emergency_contact'] ?? '').toString());
                final emergencyRelationController = TextEditingController(text: (p['emergency_relation'] ?? p['emergency_relationship'] ?? '').toString());
                final altEmergencyPhoneController = TextEditingController(text: (p['alt_emergency_contact'] ?? '').toString());
                final altEmergencyRelationController = TextEditingController(text: (p['alt_emergency_relation'] ?? p['alt_emergency_relationship'] ?? '').toString());
                // Address
                final currentAddressController = TextEditingController(text: (p['address_current'] ?? p['current_address'] ?? '').toString());
                final permanentAddressController = TextEditingController(text: (p['address_permanent'] ?? p['permanent_address'] ?? '').toString());
                final cityController = TextEditingController(text: (p['city'] ?? '').toString());
                final provinceController = TextEditingController(text: (p['province'] ?? '').toString());
                final postalCodeController = TextEditingController(text: (p['postal_code'] ?? '').toString());
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Align(
                      child: Column(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            margin: const EdgeInsets.only(bottom: 12, top: 10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: scheme.primary.withValues(alpha: 0.2), width: 2),
                            ),
                            child: ClipOval(
                              child: _isLoadingProfilePic
                                  ? Center(child: CircularProgressIndicator(color: accent))
                                  : _selectedUserProfilePicUrl != null && _selectedUserProfilePicUrl!.isNotEmpty
                                      ? Image.network(
                                          _selectedUserProfilePicUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, size: 40, color: Colors.red),
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                    : null,
                                                color: accent,
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: scheme.surfaceContainerHighest,
                                          child: Icon(Icons.person, size: 50, color: scheme.onSurfaceVariant),
                                        ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _selectedUserForProfile == null
                                ? null
                                : () => _openProfilePhotoDialog(scheme, accent),
                            icon: const Icon(Icons.photo_camera),
                            label: const Text('Change Profile Picture'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: scheme.primary,
                              foregroundColor: scheme.onPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Edit Profile Details',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.light
                            ? const Color(0xFF1E3A8A)
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Basic Information Section
                    Text(
                      'Basic Information',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.light
                            ? const Color(0xFF1E3A8A)
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(controller: rollController, label: 'Roll Number', hint: 'e.g., 12A'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: classController, label: 'Class', hint: 'e.g., Class 9 or KG'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: streamController, label: 'Stream (Computer/Bio)', hint: 'Optional for Class 8-10'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: regController, label: 'Registration No', hint: 'e.g., T-12345'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: classTeacherOfController, label: 'Class Teacher of', hint: 'e.g., Class 4'),
                    const SizedBox(height: 20),
                    Text('Personal Information', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    const SizedBox(height: 12),
                    _buildTextField(controller: cnicController, label: 'CNIC No', hint: 'e.g., 12345-1234567-1'),
                    const SizedBox(height: 12),
                    _buildDateField(controller: dobController, label: 'Date of Birth'),
                    const SizedBox(height: 12),
                    _buildDropdownField(
                      label: 'Gender',
                      value: genderValue.isEmpty ? null : genderValue,
                      items: const ['Male', 'Female', 'Other'],
                      onChanged: (v) { setState(() { genderValue = v ?? ''; }); },
                    ),
                    const SizedBox(height: 12),
                    _buildDropdownField(
                      label: 'Blood Group',
                      value: bloodGroupValue.isEmpty ? null : bloodGroupValue,
                      items: const ['O+', 'O-', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-'],
                      onChanged: (v) { setState(() { bloodGroupValue = v ?? ''; }); },
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(controller: nationalityController, label: 'Nationality', hint: 'e.g., Pakistani'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: religionController, label: 'Religion', hint: 'e.g., Islam'),
                    const SizedBox(height: 20),
                    Text('Academic Information', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    const SizedBox(height: 12),
                    _buildDateField(controller: enrollmentDateController, label: 'Enrollment Date'),
                    const SizedBox(height: 20),
                    Text('Contact Information', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    const SizedBox(height: 12),
                    _buildTextField(controller: phoneController, label: 'Phone Number', hint: '+92-3XX-XXXXXXX'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: whatsappController, label: 'WhatsApp', hint: '+92-3XX-XXXXXXX'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: altPhoneController, label: 'Alternative Phone', hint: '+92-3XX-XXXXXXX'),
                    const SizedBox(height: 20),
                    Text('Emergency Contact', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    const SizedBox(height: 12),
                    _buildTextField(controller: emergencyPhoneController, label: 'Emergency Phone', hint: '+92-3XX-XXXXXXX', keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),
                    _buildTextField(controller: emergencyRelationController, label: 'Relationship', hint: 'e.g., Father'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: altEmergencyPhoneController, label: 'Alt. Emergency Phone', hint: '+92-3XX-XXXXXXX', keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),
                    _buildTextField(controller: altEmergencyRelationController, label: 'Relationship', hint: 'e.g., Mother'),
                    const SizedBox(height: 20),
                    Text('Address Information', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    const SizedBox(height: 12),
                    _buildTextField(controller: currentAddressController, label: 'Current Address', hint: 'Street, Area'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: permanentAddressController, label: 'Permanent Address', hint: 'Street, Area'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: cityController, label: 'City', hint: 'e.g., Lahore'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: provinceController, label: 'Province', hint: 'e.g., Punjab'),
                    const SizedBox(height: 12),
                    _buildTextField(controller: postalCodeController, label: 'Postal Code', hint: 'e.g., 54000'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          // Prepare the data to update
                          final data = {
                            'class': classController.text,
                            'stream': streamController.text,
                            'roll_number': rollController.text,
                            'registration_no': regController.text,
                            'class_teacher_of': classTeacherOfController.text,
                            'cnic': cnicController.text,
                            'cnic_no': cnicController.text,
                            'dob': dobController.text,
                            'date_of_birth': dobController.text,
                            'gender': genderValue,
                            'blood_group': bloodGroupValue,
                            'nationality': nationalityController.text,
                            'religion': religionController.text,
                            'enrollment_date': enrollmentDateController.text,
                            'phone': phoneController.text,
                            'phone_number': phoneController.text,
                            'whatsapp': whatsappController.text,
                            'alt_phone': altPhoneController.text,
                            'alternative_phone': altPhoneController.text,
                            'emergency_contact': emergencyPhoneController.text,
                            'emergency_relation': emergencyRelationController.text,
                            'emergency_relationship': emergencyRelationController.text,
                            'alt_emergency_contact': altEmergencyPhoneController.text,
                            'alt_emergency_relation': altEmergencyRelationController.text,
                            'alt_emergency_relationship': altEmergencyRelationController.text,
                            'address_current': currentAddressController.text,
                            'current_address': currentAddressController.text,
                            'address_permanent': permanentAddressController.text,
                            'permanent_address': permanentAddressController.text,
                            'city': cityController.text,
                            'province': provinceController.text,
                            'postal_code': postalCodeController.text,
                          };

                          final res = await ApiService.updateUserProfile(_selectedUserForProfile!, data);
                          if (res['success'] == true) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Profile updated successfully', style: GoogleFonts.inter(color: scheme.onPrimary)),
                                  backgroundColor: accent,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              setState(() {});
                            }
                          } else {
                            throw Exception(res['error'] ?? 'Update failed');
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Update failed: $e'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    )
                  ],
                );
              },
            ),
          ),
        ],
    );
  }

  Widget _levelDropdown() {
    final items = const ['Early Years', 'Primary', 'Secondary'];
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          style: GoogleFonts.inter(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          value: _levelForMgmt,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          items: items
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _levelForMgmt = v);
          },
        ),
      ),
    );
  }

  // ---------- UI Helpers ----------
  Widget _buildPillTabBar(BuildContext context, ColorScheme scheme, Color accent) {
    return SizedBox(
      height: 38,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        labelColor: scheme.onPrimary,
        unselectedLabelColor: Colors.white70,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        // Selected tab: blue-ish square (slightly rounded)
        indicator: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(6),
        ),
        // zero vertical padding so the indicator fills the square area
        indicatorPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        indicatorSize: TabBarIndicatorSize.label,
        tabs: const [
          Tab(child: SizedBox(width: 36, height: 34, child: Center(child: Icon(Icons.person_add_alt_1, size: 20)))),
          Tab(child: SizedBox(width: 36, height: 34, child: Center(child: Icon(Icons.class_, size: 20)))),
          Tab(child: SizedBox(width: 36, height: 34, child: Center(child: Icon(Icons.person, size: 20)))),
        ],
      ),
    );
  }

Widget _sectionCard({required ColorScheme scheme, required Widget child, String? title, Widget? trailing}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color lightCard = Color(0xFFE7E0DE);
  const Color lightBorder = Color(0xFFD9D2D0);
  const Color accentBlue = Color(0xFF1E3A8A);

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: isDark
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.onSurface.withValues(alpha: 0.08),
                scheme.onSurface.withValues(alpha: 0.03),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12), width: 1),
          )
        : BoxDecoration(
            color: lightCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: lightBorder, width: 1),
            boxShadow: [
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
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _chipTitle(title, scheme),
                const Spacer(),
                if (trailing != null) trailing,
              ],
            ),
          ),
        child,
      ],
    ),
  );
}
Widget _chipTitle(String text, ColorScheme scheme) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color lightCard = Color(0xFFE7E0DE);
  const Color lightBorder = Color(0xFFD9D2D0);
  const Color accentBlue = Color(0xFF1E3A8A);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: isDark ? scheme.primary.withValues(alpha: 0.12) : lightCard,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: isDark ? scheme.primary.withValues(alpha: 0.25) : lightBorder),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : accentBlue,
      ),
    ),
  );
}

Widget _iconBtn(IconData icon, {required VoidCallback onTap}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color accentBlue = Color(0xFF1E3A8A);

  return IconButton(
    onPressed: onTap,
    icon: Icon(icon, color: isDark ? Colors.white : accentBlue),
    style: IconButton.styleFrom(
      backgroundColor: isDark ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12) : accentBlue.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
  Widget _searchField(ColorScheme scheme) {
    return TextField(
      controller: _memberSearchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search name or email',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _memberSearchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () { _memberSearchController.clear(); setState(() {}); },
              ),
        filled: true,
        isDense: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.15))),
      ),
    );
  }
Widget _roleChips(ColorScheme scheme) {
  final roles = ['All', 'Student', 'Teacher', 'Admin'];
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color lightCard = Color(0xFFE7E0DE);
  const Color lightBorder = Color(0xFFD9D2D0);
  const Color accentBlue = Color(0xFF1E3A8A);

  return Wrap(
    spacing: 6,
    children: roles.map((r) {
      final selected = _memberRoleFilter == r;
      return ChoiceChip(
        selected: selected,
        label: Text(r),
        onSelected: (_) => setState(() => _memberRoleFilter = r),
        labelStyle: GoogleFonts.inter(
          color: selected
              ? Colors.white
              : (isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.75)),
        ),
        selectedColor: isDark ? scheme.primary : accentBlue,
        backgroundColor: isDark ? scheme.onSurface.withValues(alpha: 0.08) : lightCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: isDark ? scheme.onSurface.withValues(alpha: 0.18) : lightBorder),
        ),
      );
    }).toList(),
  );
}

Widget _emptyState(ColorScheme scheme, {required String title, required String message}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color accentBlue = Color(0xFF1E3A8A);

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 56,
          color: isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.65),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : accentBlue,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: GoogleFonts.inter(color: isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.75)),
        ),
      ],
    ),
  );
}
Widget _errorState(ColorScheme scheme, {required String title, required String message, List<Widget>? actions}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  const Color accentBlue = Color(0xFF1E3A8A);

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : accentBlue,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: GoogleFonts.inter(color: isDark ? Colors.white70 : accentBlue.withValues(alpha: 0.75)),
          textAlign: TextAlign.center,
        ),
        if (actions != null) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ],
    ),
  );
}
  Widget _outlinedBtn(String label, {required VoidCallback onTap}) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Theme.of(context).colorScheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }

  Widget _filledBtn(String label, {required VoidCallback onTap}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }

  Widget _skeletonList(ColorScheme scheme) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, __) => Container(
        height: 60,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Password is required';
            if (v.length < 6) return 'Password must be at least 6 characters';
            return null;
          },
          decoration: InputDecoration(
            hintText: 'Enter password',
            hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
            prefixIcon: Icon(Icons.lock, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
              prefixIcon: icon != null ? Icon(icon, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)) : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown() {
    final List<String> roleList = ['Student', 'Admin', 'Super Admin'];
    
    // Ensure _role is properly initialized with a valid value
    if (!roleList.any((role) => role.toLowerCase() == _role.toLowerCase())) {
      _role = roleList.first;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: ButtonTheme(
              alignedDropdown: true,
              child: DropdownButtonFormField<String>(
                initialValue: _role,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down),
                iconSize: 24,
                elevation: 16,
                style: GoogleFonts.inter(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                  hintText: 'Select role',
                  hintStyle: GoogleFonts.inter(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                items: roleList.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value, // Use the exact role name from the list
                      style: GoogleFonts.inter(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _role = newValue ?? '';
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClassDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Class',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedClass,
              hint: Text(
                _classesLoading
                    ? 'Loading classes...'
                    : (_classesError != null ? 'Failed to load classes' : 'Select class'),
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70)),
              ),
              dropdownColor: Theme.of(context).colorScheme.surface,
              iconEnabledColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
              borderRadius: BorderRadius.circular(12),
              items: _classes
                  .map((c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: _classesLoading
                  ? null
                  : (v) {
                setState(() {
                  _selectedClass = v;
                  if (!_requiresStream(_selectedClass)) {
                    _selectedStream = null;
                  }
                });
              },
            ),
          ),
        ),
        if (_classesLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Fetching classes...', style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
              ],
            ),
          ),
        if (_classesError != null && !_classesLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Could not load classes. Tap to retry.',
                    style: GoogleFonts.inter(fontSize: 12, color: Theme.of(context).colorScheme.error),
                  ),
                ),
                TextButton(
                  onPressed: _loadClasses,
                  child: Text('Retry', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildClassTeacherDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Class Teacher',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedClassTeacher,
              hint: Text('Select class to be class teacher of', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70))),
              dropdownColor: Theme.of(context).colorScheme.surface,
              iconEnabledColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
              borderRadius: BorderRadius.circular(12),
              items: _classes
                  .map((c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedClassTeacher = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStreamDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stream',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedStream,
              hint: Text('Select stream', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70))),
              dropdownColor: Theme.of(context).colorScheme.surface,
              iconEnabledColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.70),
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
              borderRadius: BorderRadius.circular(12),
              items: _streams
                  .map((s) => DropdownMenuItem<String>(
                        value: s,
                        child: Text(s),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedStream = v);
              },
            ),
          ),
        ),
      ],
    );
  }

  bool _requiresStream(String? className) {
    if (className == null) return false;
    return className == 'Class 8' || className == 'Class 9' || className == 'Class 10';
  }

  void _onSave() async {
    if (!mounted) return;
    if (_formKey.currentState?.validate() != true) return;
    // Additional validation for Student class/stream
    if (_role == 'Student') {
      if (_selectedClass == null || _selectedClass!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please select a class for the student',
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      if (_rollNoController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Roll No is required for students',
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      if (_requiresStream(_selectedClass) && (_selectedStream == null || _selectedStream!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please select a stream (Computer/Bio) for Class 8-10',
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
    }
    if (_role == 'Admin' || _role == 'Super Admin') {
      if (_teacherRegController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Registration number is required',
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
    }

    try {
      // Show loading state
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: scheme.onPrimary,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Creating user...',
                style: GoogleFonts.inter(color: scheme.onPrimary),
              ),
            ],
          ),
          backgroundColor: scheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );

      // Map UI role to API role value (super admin expected lowercase with underscore)
      final apiRole = _role == 'Super Admin' ? 'super_admin' : _role;
      // Call the API service to create user
      final result = await ApiService.createUser(
        _nameController.text.trim(),
        _emailController.text.trim(),
        password: _passwordController.text.trim(),
        role: apiRole,
      );
      
      if (result['success'] == true) {
        // If Student, create profile with class and (optional) stream stored in 'batch'
        if (_role == 'Student') {
          final int? userId = result['user_id'] is int
              ? result['user_id']
              : int.tryParse('${result['user_id']}');
          if (userId != null) {
            try {
              final profileData = <String, dynamic>{
                'class': _selectedClass,
                if (_selectedStream != null) 'batch': _selectedStream, // use batch to hold stream
                if (_rollNoController.text.trim().isNotEmpty) 'roll_number': _rollNoController.text.trim(),
              };
              await ApiService.createUserProfile(userId, profileData);
            } catch (e) {
              // Non-fatal: profile creation failure should be surfaced but not block user creation notice
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'User created, but profile save failed: ${e.toString()}',
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onTertiary),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                  ),
                );
              }
            }
          }
        }
        // If Teacher/Admin, create profile with registration no and optional class teacher assignment
        if (_role == 'Admin' || _role == 'Super Admin') {
          final int? userId = result['user_id'] is int
              ? result['user_id']
              : int.tryParse('${result['user_id']}');
          if (userId != null) {
            try {
              final profileData = <String, dynamic>{
                'registration_no': _teacherRegController.text.trim(),
                if (_role == 'Admin' && (_selectedClassTeacher != null && _selectedClassTeacher!.isNotEmpty))
                  'class_teacher_of': _selectedClassTeacher,
              };
              await ApiService.createUserProfile(userId, profileData);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'User created, but profile save failed: ${e.toString()}',
                      style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onTertiary),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.tertiary,
                  ),
                );
              }
            }
          }
        }
        // User created successfully
        if (mounted) {
          final scheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'User created successfully! ID: ${result['user_id']}',
                style: GoogleFonts.inter(color: scheme.onSecondary),
              ),
              backgroundColor: scheme.secondary,
            ),
          );
          
          // Navigate back
          Navigator.of(context).maybePop();
        }
      } else {
        // User creation failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['error'] ?? 'Failed to create user',
                style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onError),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } catch (e) {
      // Handle network or other errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString()}',
              style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
