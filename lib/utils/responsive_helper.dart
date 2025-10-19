import 'package:flutter/material.dart';

class ResponsiveHelper {
  // Enhanced Breakpoints for better responsive design
  static const double mobileBreakpoint = 640;
  static const double tabletBreakpoint = 768;
  static const double desktopBreakpoint = 1024;
  static const double largeDesktopBreakpoint = 1440;
  static const double ultraWideBreakpoint = 1920;

  // Device type detection
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint &&
      MediaQuery.of(context).size.width < largeDesktopBreakpoint;

  static bool isLargeDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= largeDesktopBreakpoint &&
      MediaQuery.of(context).size.width < ultraWideBreakpoint;

  static bool isUltraWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= ultraWideBreakpoint;

  // Screen size helpers
  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  // Enhanced responsive values with ultra-wide support
  static double responsiveValue(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
    double? largeDesktop,
    double? ultraWide,
  }) {
    if (isUltraWide(context) && ultraWide != null) {
      return ultraWide;
    } else if (isLargeDesktop(context) && largeDesktop != null) {
      return largeDesktop;
    } else if (isDesktop(context) && desktop != null) {
      return desktop;
    } else if (isTablet(context) && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  // Responsive padding
  static EdgeInsets responsivePadding(
    BuildContext context, {
    required EdgeInsets mobile,
    EdgeInsets? tablet,
    EdgeInsets? desktop,
    EdgeInsets? largeDesktop,
  }) {
    if (isLargeDesktop(context) && largeDesktop != null) {
      return largeDesktop;
    } else if (isDesktop(context) && desktop != null) {
      return desktop;
    } else if (isTablet(context) && tablet != null) {
      return tablet;
    }
    return mobile;
  }

  // Enhanced grid columns with better spacing
  static int getGridColumns(BuildContext context) {
    if (isUltraWide(context)) return 6;
    if (isLargeDesktop(context)) return 4;
    if (isDesktop(context)) return 3;
    if (isTablet(context)) return 2;
    return 1;
  }

  // Grid aspect ratio based on content type
  static double getCardAspectRatio(BuildContext context, {bool isWideCard = false}) {
    if (isWideCard) {
      return responsiveValue(
        context,
        mobile: 2.5,
        tablet: 3.0,
        desktop: 3.5,
        largeDesktop: 4.0,
      );
    }
    return responsiveValue(
      context,
      mobile: 1.2,
      tablet: 1.3,
      desktop: 1.4,
      largeDesktop: 1.5,
    );
  }

  // Navigation width
  static double getNavWidth(BuildContext context, bool isExpanded) {
    if (isMobile(context)) {
      return isExpanded ? screenWidth(context) * 0.75 : 0;
    } else if (isTablet(context)) {
      return isExpanded ? 250 : 80;
    } else {
      return isExpanded ? 280 : 80;
    }
  }

  // Content padding based on screen size
  static EdgeInsets getContentPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: responsiveValue(
        context,
        mobile: 16,
        tablet: 24,
        desktop: 32,
        largeDesktop: 48,
      ),
      vertical: responsiveValue(
        context,
        mobile: 16,
        tablet: 20,
        desktop: 24,
        largeDesktop: 32,
      ),
    );
  }

  // Font sizes
  static double getHeadingSize(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 24,
      tablet: 28,
      desktop: 32,
      largeDesktop: 36,
    );
  }

  static double getSubheadingSize(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 18,
      tablet: 20,
      desktop: 22,
      largeDesktop: 24,
    );
  }

  static double getBodySize(BuildContext context) {
    return responsiveValue(
      context,
      mobile: 14,
      tablet: 15,
      desktop: 16,
      largeDesktop: 16,
    );
  }

  // Card dimensions
  static double getCardWidth(BuildContext context) {
    final width = screenWidth(context);
    if (isMobile(context)) return width - 32;
    if (isTablet(context)) return (width - 80) / 2 - 24;
    if (isDesktop(context)) return (width - 120) / 3 - 32;
    return (width - 160) / 4 - 40;
  }

  // Layout helpers
  static bool shouldUseDrawer(BuildContext context) => isMobile(context);
  
  static bool shouldShowSidebar(BuildContext context) => !isMobile(context);

  static CrossAxisAlignment getMainAxisAlignment(BuildContext context) {
    return isMobile(context) 
        ? CrossAxisAlignment.stretch 
        : CrossAxisAlignment.start;
  }

  // Enhanced form field width
  static double getFormFieldWidth(BuildContext context) {
    final width = screenWidth(context);
    if (isMobile(context)) return width - 32;
    if (isTablet(context)) return 400;
    if (isDesktop(context)) return 450;
    return 500;
  }

  // Container max width for content
  static double getMaxContentWidth(BuildContext context) {
    // Always allow full-bleed content. Individual screens should manage their own internal padding.
    return screenWidth(context);
  }

  // Spacing helpers
  static double getSpacing(BuildContext context, {String size = 'medium'}) {
    final multiplier = switch (size) {
      'xs' => 0.25,
      'sm' => 0.5,
      'medium' => 1.0,
      'lg' => 1.5,
      'xl' => 2.0,
      'xxl' => 3.0,
      _ => 1.0,
    };
    
    return responsiveValue(
      context,
      mobile: 16 * multiplier,
      tablet: 20 * multiplier,
      desktop: 24 * multiplier,
      largeDesktop: 28 * multiplier,
    );
  }

  // Enhanced button sizing
  static Size getButtonSize(BuildContext context, {String variant = 'default'}) {
    final height = responsiveValue(
      context,
      mobile: variant == 'large' ? 56 : 48,
      tablet: variant == 'large' ? 60 : 52,
      desktop: variant == 'large' ? 64 : 56,
    );
    
    final width = variant == 'full' ? double.infinity : 
                 variant == 'large' ? 200.0 : 160.0;
    
    return Size(width, height);
  }

  // Modern shadow elevation
  static List<BoxShadow> getElevation(BuildContext context, {int level = 1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadowColor = isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.1);
    
    return switch (level) {
      0 => [],
      1 => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
      2 => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
      3 => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
      _ => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
      ],
    };
  }
}
