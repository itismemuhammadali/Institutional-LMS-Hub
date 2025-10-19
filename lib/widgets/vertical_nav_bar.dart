import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/responsive_helper.dart';

class VerticalNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final bool isExpanded;
  final Function(bool) onToggleExpanded;
  final bool showAddStudent;
  final bool showCourses;
  final bool showCourseAssignment;
  final bool showAdminDues;
  final bool showStudentDues;
  final bool showTakeAttendance;
  final bool showGenerateTicket;
  final bool showAcademicRecords;

  const VerticalNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.showAddStudent = false,
    this.showCourses = true,
    this.showCourseAssignment = false,
    this.showAdminDues = false,
    this.showStudentDues = true,
    this.showTakeAttendance = false,
    this.showGenerateTicket = false,
    this.showAcademicRecords = false,
  });

  @override
  State<VerticalNavBar> createState() => _VerticalNavBarState();
}

class _VerticalNavBarState extends State<VerticalNavBar> {
  List<NavItem> get _navItems {
    List<NavItem> items = [
      NavItem(
        icon: Icons.home_outlined,
        label: 'Home',
        index: 1,
      ),
    ];
    
    // Only show Courses for non-superadmin users
    if (widget.showCourses) {
      items.add(NavItem(
        icon: Icons.book_outlined,
        label: 'Courses',
        index: 2,
      ));
    }

    if (widget.showAcademicRecords) {
      items.add(NavItem(
        icon: Icons.insights_outlined,
        label: 'Academic Records',
        index: 11,
      ));
    }

    // Take Attendance (admins / super admins)
    if (widget.showTakeAttendance) {
      items.add(NavItem(
        icon: Icons.fact_check_outlined,
        label: 'Take Attendance',
        index: 9,
      ));
    }
    
    // Only show Course Assignment for superadmin users
    if (widget.showCourseAssignment) {
      items.add(NavItem(
        icon: Icons.assignment_ind,
        label: 'Assign Courses',
        index: 7,
      ));
    }
    
    if (widget.showStudentDues) {
      items.add(NavItem(
        icon: Icons.payment_outlined,
        label: 'Dues',
        index: 3,
      ));
    }
    
    // Show Admin Dues for admin users
    if (widget.showAdminDues) {
      items.add(NavItem(
        icon: Icons.receipt_long_outlined,
        label: 'Admin Dues',
        index: 8,
      ));
    }
    
    // Show Tickets for superadmin users
    if (widget.showGenerateTicket) {
      items.add(NavItem(
        icon: Icons.confirmation_number_outlined,
        label: 'Tickets',
        index: 10,
      ));
    }
    
    return items;
  }

  @override
  Widget build(BuildContext context) {
    // On mobile, show as drawer overlay
    if (ResponsiveHelper.isMobile(context)) {
      return widget.isExpanded ? _buildMobileDrawer(context) : const SizedBox.shrink();
    }
    
    // On tablet/desktop, show as sidebar
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color navBg = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A);
    final Color navFg = isDark ? Colors.black : Colors.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: ResponsiveHelper.getNavWidth(context, widget.isExpanded),
      decoration: BoxDecoration(
        color: navBg,
        border: Border(
          right: BorderSide(
            color: navFg.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: ResponsiveHelper.responsiveValue(
              context,
              mobile: 8,
              tablet: 10,
              desktop: 12,
            ),
          ),
          
          // Menu toggle button (tablet/desktop only)
          Padding(
            padding: EdgeInsets.only(
              bottom: ResponsiveHelper.responsiveValue(
                context,
                mobile: 4,
                tablet: 8,
                desktop: 8,
              ),
            ),
            child: _buildMenuToggleButton(),
          ),
          
          // Navigation Items - Flexible to prevent overflow
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                children: [
                  ..._navItems.map((item) => Padding(
                    padding: EdgeInsets.only(
                      bottom: ResponsiveHelper.responsiveValue(
                        context,
                        mobile: 4,
                        tablet: 5,
                        desktop: 5,
                      ),
                    ),
                    child: _buildNavItem(item),
                  )),

                  // Teacher/Principal-only: Add Student
                  if (widget.showAddStudent)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: ResponsiveHelper.responsiveValue(
                          context,
                          mobile: 4,
                          tablet: 5,
                          desktop: 5,
                        ),
                      ),
                      child: _buildNavItem(
                        NavItem(
                          icon: Icons.group_add,
                          label: 'Manage Members',
                          index: 6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Bottom section - Profile and Settings (always visible)
          Container(
            padding: EdgeInsets.only(
              top: ResponsiveHelper.responsiveValue(
                context,
                mobile: 2,
                tablet: 3,
                desktop: 3,
              ),
            ),
            child: Column(
              children: [
                // Profile
                Padding(
                  padding: EdgeInsets.only(
                    bottom: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 4,
                      tablet: 5,
                      desktop: 5,
                    ),
                  ),
                  child: _buildNavItem(
                    NavItem(
                      icon: Icons.person_outline,
                      label: 'Profile',
                      index: 4,
                    ),
                  ),
                ),
                
                // Settings
                Padding(
                  padding: EdgeInsets.only(
                    bottom: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 4,
                      tablet: 5,
                      desktop: 5,
                    ),
                  ),
                  child: _buildNavItem(
                    NavItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      index: 5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(NavItem item) {
    final isActive = widget.selectedIndex == item.index;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color navFg = isDark ? Colors.black : Colors.white;
    
    return GestureDetector(
      onTap: () {
        widget.onItemSelected(item.index);
      },
      child: Container(
        width: widget.isExpanded 
            ? ResponsiveHelper.getNavWidth(context, true) - 20
            : ResponsiveHelper.responsiveValue(
                context,
                mobile: 50,
                tablet: 60,
                desktop: 60,
              ),
        height: ResponsiveHelper.responsiveValue(
          context,
          mobile: 50,
          tablet: 60,
          desktop: 60,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.responsiveValue(
            context,
            mobile: 8,
            tablet: 10,
            desktop: 10,
          ),
        ),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: widget.isExpanded
            ? Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 16,
                      tablet: 20,
                      desktop: 20,
                    ),
                  ),
                  Icon(
                    item.icon,
                    color: isActive ? navFg : navFg.withValues(alpha: 0.7),
                    size: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 20,
                      tablet: 24,
                      desktop: 24,
                    ),
                  ),
                  SizedBox(
                    width: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 6,
                      tablet: 8,
                      desktop: 8,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      item.label,
                      style: GoogleFonts.inter(
                        fontSize: ResponsiveHelper.responsiveValue(
                          context,
                          mobile: 12,
                          tablet: 14,
                          desktop: 14,
                        ),
                        color: isActive ? navFg : navFg.withValues(alpha: 0.85),
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Center(
                child: Icon(
                  item.icon,
                  color: isActive ? navFg : navFg.withValues(alpha: 0.7),
                  size: ResponsiveHelper.responsiveValue(
                    context,
                    mobile: 20,
                    tablet: 24,
                    desktop: 24,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color navBg = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A);
    final Color navFg = isDark ? Colors.black : Colors.white;
    return Container(
      width: ResponsiveHelper.screenWidth(context) * 0.75,
      height: ResponsiveHelper.screenHeight(context),
      decoration: BoxDecoration(
        color: navBg,
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.school,
                    color: navFg,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Institute Portal',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: navFg,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.onToggleExpanded(false),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            Divider(color: navFg.withValues(alpha: 0.2)),
            
            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ..._navItems.map((item) => _buildMobileNavItem(item)),

                  Divider(color: navFg.withValues(alpha: 0.2)),
                  
                  _buildMobileNavItem(
                    NavItem(
                      icon: Icons.person_outline,
                      label: 'Profile',
                      index: 4,
                    ),
                  ),
                  
                  _buildMobileNavItem(
                    NavItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      index: 5,
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

  Widget _buildMobileNavItem(NavItem item) {
    final isActive = widget.selectedIndex == item.index;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color navFg = isDark ? Colors.black : Colors.white;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isActive ? navFg : navFg.withValues(alpha: 0.7),
          size: 24,
        ),
        title: Text(
          item.label,
          style: GoogleFonts.inter(
            fontSize: 16,
            color: isActive ? navFg : navFg,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onTap: () {
          widget.onItemSelected(item.index);
          widget.onToggleExpanded(false); // Close drawer after selection
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        tileColor: isActive ? Colors.white.withValues(alpha: isDark ? 0.2 : 0.15) : null,
      ),
    );
  }

  Widget _buildMenuToggleButton() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color navFg = isDark ? Colors.black : Colors.white;
    
    return GestureDetector(
      onTap: () {
        widget.onToggleExpanded(!widget.isExpanded);
      },
      child: Container(
        width: widget.isExpanded 
            ? ResponsiveHelper.getNavWidth(context, true) - 20
            : ResponsiveHelper.responsiveValue(
                context,
                mobile: 50,
                tablet: 60,
                desktop: 60,
              ),
        height: ResponsiveHelper.responsiveValue(
          context,
          mobile: 50,
          tablet: 60,
          desktop: 60,
        ),
        margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.responsiveValue(
            context,
            mobile: 8,
            tablet: 10,
            desktop: 10,
          ),
        ),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: widget.isExpanded
            ? Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 16,
                      tablet: 20,
                      desktop: 20,
                    ),
                  ),
                  _buildMenuIcon(navFg),
                  SizedBox(
                    width: ResponsiveHelper.responsiveValue(
                      context,
                      mobile: 6,
                      tablet: 8,
                      desktop: 8,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'Menu',
                      style: GoogleFonts.inter(
                        fontSize: ResponsiveHelper.responsiveValue(
                          context,
                          mobile: 12,
                          tablet: 14,
                          desktop: 14,
                        ),
                        color: navFg.withValues(alpha: 0.85),
                        fontWeight: FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Center(
                child: _buildMenuIcon(navFg),
              ),
      ),
    );
  }

  Widget _buildMenuIcon(Color color) {
    return CustomPaint(
      size: Size(
        ResponsiveHelper.responsiveValue(
          context,
          mobile: 20,
          tablet: 24,
          desktop: 24,
        ),
        ResponsiveHelper.responsiveValue(
          context,
          mobile: 20,
          tablet: 24,
          desktop: 24,
        ),
      ),
      painter: MenuIconPainter(color: color.withValues(alpha: 0.7)),
    );
  }
}

class MenuIconPainter extends CustomPainter {
  final Color color;
  
  MenuIconPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    
    final double lineSpacing = size.height / 4;
    final double lineWidth = size.width * 0.75;
    final double startX = (size.width - lineWidth) / 2;
    
    // Top line
    canvas.drawLine(
      Offset(startX, lineSpacing),
      Offset(startX + lineWidth, lineSpacing),
      paint,
    );
    
    // Middle line
    canvas.drawLine(
      Offset(startX, size.height / 2),
      Offset(startX + lineWidth, size.height / 2),
      paint,
    );
    
    // Bottom line
    canvas.drawLine(
      Offset(startX, size.height - lineSpacing),
      Offset(startX + lineWidth, size.height - lineSpacing),
      paint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NavItem {
  final IconData icon;
  final String label;
  final int index;

  NavItem({
    required this.icon,
    required this.label,
    required this.index,
  });
}
