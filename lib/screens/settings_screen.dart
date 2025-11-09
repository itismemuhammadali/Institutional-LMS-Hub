import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme_controller.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'api_test_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await ApiService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
      });
    } catch (_) {
      // keep silent
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = ThemeController.instance.themeMode.value == ThemeMode.dark;
    const primaryBlue = Color(0xFF1E3A8A);
    final w = MediaQuery.of(context).size.width;
    final bool showSegmentsInHeader = false; // controls now live in the card

    return Scaffold(
      body: Column(
        children: [
          // Header bar (full-bleed) - only show on tablet/desktop
          if (!ResponsiveHelper.isMobile(context))
            Container(
              height: 64,
              width: double.infinity,
              color: primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else {
                        Navigator.of(context).maybePop();
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Settings',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
          Card(
            color: isDark ? theme.cardColor : const Color(0xFFE7E0DE),
            surfaceTintColor: Colors.transparent,
            elevation: isDark ? 2 : 6,
            shadowColor:
                isDark ? Colors.black.withValues(alpha: 0.4) : primaryBlue.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isDark
                    ? theme.dividerColor.withValues(alpha: 0.3)
                    : const Color(0xFFD9D2D0),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 420;
                  if (isNarrow) {
                    final bool canFitSegments = constraints.maxWidth >= 360;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)]),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: const Icon(Icons.color_lens, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'App Theme',
                                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Turn on Dark Mode',
                                  style: GoogleFonts.inter(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
                                  softWrap: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (canFitSegments)
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.wb_sunny_outlined)),
                              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.nights_stay_outlined)),
                            ],
                            selected: {isDark ? ThemeMode.dark : ThemeMode.light},
                            onSelectionChanged: (s) {
                              final mode = s.first;
                              ThemeController.instance.setThemeMode(mode);
                              setState(() {});
                            },
                          )
                        else
                          IconButton(
                            tooltip: isDark ? 'Switch to Light' : 'Switch to Dark',
                            onPressed: () {
                              final mode = isDark ? ThemeMode.light : ThemeMode.dark;
                              ThemeController.instance.setThemeMode(mode);
                              setState(() {});
                            },
                            icon: Icon(isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded),
                          ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF06B6D4)]),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: const Icon(Icons.color_lens, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'App Theme',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Switch between Light and Dark',
                                style: GoogleFonts.inter(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
                                softWrap: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.wb_sunny_outlined)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.nights_stay_outlined)),
                        ],
                        selected: {isDark ? ThemeMode.dark : ThemeMode.light},
                        onSelectionChanged: (s) {
                          final mode = s.first;
                          ThemeController.instance.setThemeMode(mode);
                          setState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: isDark ? theme.cardColor : const Color(0xFFE7E0DE),
            surfaceTintColor: Colors.transparent,
            elevation: isDark ? 1 : 4,
            shadowColor:
                isDark ? Colors.black.withValues(alpha: 0.35) : primaryBlue.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: isDark
                    ? theme.dividerColor.withValues(alpha: 0.3)
                    : const Color(0xFFD9D2D0),
              ),
            ),
            child: ListTile(
              leading: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.secondary.withValues(alpha: 0.15)
                      : primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.lock_outline,
                  color: isDark ? theme.colorScheme.secondary : primaryBlue,
                ),
              ),
              title: Text('Change Password', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              subtitle: Text('Update your account password', style: GoogleFonts.inter(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/change-password'),
            ),
          ),
          const SizedBox(height: 16),
          if (_currentUser != null && (_currentUser!['is_super_admin'] == 1 || _currentUser!['is_super_admin'] == '1'))
            Card(
              color: isDark ? theme.cardColor : const Color(0xFFE7E0DE),
              surfaceTintColor: Colors.transparent,
              elevation: isDark ? 1 : 4,
              shadowColor:
                  isDark ? Colors.black.withValues(alpha: 0.35) : primaryBlue.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: isDark
                      ? theme.dividerColor.withValues(alpha: 0.3)
                      : const Color(0xFFD9D2D0),
                ),
              ),
              child: ListTile(
                leading: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.developer_mode,
                    color: isDark ? theme.colorScheme.primary : primaryBlue,
                  ),
                ),
                title: Text(
                  'Test API',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? theme.textTheme.titleMedium?.color ?? Colors.white
                        : primaryBlue,
                  ),
                ),
                subtitle: Text(
                  'Open API testing utilities',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark
                        ? theme.textTheme.bodySmall?.color ?? Colors.white
                        : primaryBlue,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ApiTestScreen(),
                    ),
                  );
                },
              ),
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
