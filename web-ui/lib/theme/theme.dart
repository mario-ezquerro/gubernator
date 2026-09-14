import 'package:flutter/material.dart';

/// Comprehensive Gubernator Theme Definition
class GubernatorThemeDef {
  final String id;
  final String name;
  final String subtitle;
  final bool isDark;
  final IconData icon;
  final Color primary;
  final Color secondary;
  final Color canvas;
  final Color surface;
  final Color border;
  final Color sidebarBg;
  final Color sidebarBorder;
  final Color sidebarSurface;
  final Color sidebarActive;
  final Color textPrimary;
  final Color textSecondary;

  const GubernatorThemeDef({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.isDark,
    required this.icon,
    required this.primary,
    required this.secondary,
    required this.canvas,
    required this.surface,
    required this.border,
    required this.sidebarBg,
    required this.sidebarBorder,
    required this.sidebarSurface,
    required this.sidebarActive,
    required this.textPrimary,
    required this.textSecondary,
  });
}

// ─── Legacy Color Aliases for Compatibility ──────────────────────────────
const Color sidebarDarkBg = Color(0xFF0A0F1A);
const Color sidebarLightBg = Color(0xFFF1F5F9);
const Color sidebarDarkSurface = Color(0xFF111827);
const Color sidebarLightSurface = Color(0xFFFFFFFF);
const Color sidebarDarkBorder = Color(0xFF1E293B);
const Color sidebarLightBorder = Color(0xFFE2E8F0);
const Color sidebarActiveIndicator = Color(0xFFF97316);

class GubernatorTheme {
  // ─── 13 Curated Production Themes ─────────────────────────────────────
  static const List<GubernatorThemeDef> allThemes = [
    // 1. Gubernator Dark (Default)
    GubernatorThemeDef(
      id: 'dark',
      name: 'Gubernator Dark',
      subtitle: 'Slate & Imperial Orange',
      isDark: true,
      icon: Icons.dark_mode,
      primary: Color(0xFFF97316),
      secondary: Color(0xFF38BDF8),
      canvas: Color(0xFF0F172A),
      surface: Color(0xFF1E293B),
      border: Color(0xFF334155),
      sidebarBg: Color(0xFF0A0F1A),
      sidebarBorder: Color(0xFF1E293B),
      sidebarSurface: Color(0xFF111827),
      sidebarActive: Color(0xFFF97316),
      textPrimary: Colors.white,
      textSecondary: Color(0xFF94A3B8),
    ),

    // 2. Gubernator Light
    GubernatorThemeDef(
      id: 'light',
      name: 'Gubernator Light',
      subtitle: 'Clean Slate & Imperial Orange',
      isDark: false,
      icon: Icons.light_mode,
      primary: Color(0xFFEA580C),
      secondary: Color(0xFF0284C7),
      canvas: Color(0xFFF8FAFC),
      surface: Color(0xFFFFFFFF),
      border: Color(0xFFE2E8F0),
      sidebarBg: Color(0xFFF1F5F9),
      sidebarBorder: Color(0xFFE2E8F0),
      sidebarSurface: Color(0xFFFFFFFF),
      sidebarActive: Color(0xFFEA580C),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF64748B),
    ),

    // 3. Quiet Light
    GubernatorThemeDef(
      id: 'quietLight',
      name: 'Quiet Light',
      subtitle: 'Soft Pastel & Lilac Accent',
      isDark: false,
      icon: Icons.cloud_outlined,
      primary: Color(0xFF7C3AED),
      secondary: Color(0xFF0D9488),
      canvas: Color(0xFFF5F5F7),
      surface: Color(0xFFFFFFFF),
      border: Color(0xFFE5E7EB),
      sidebarBg: Color(0xFFEFEFF4),
      sidebarBorder: Color(0xFFE5E7EB),
      sidebarSurface: Color(0xFFF9FAFB),
      sidebarActive: Color(0xFF7C3AED),
      textPrimary: Color(0xFF1F2937),
      textSecondary: Color(0xFF6B7280),
    ),

    // 4. Dark Dimmed
    GubernatorThemeDef(
      id: 'darkDimmed',
      name: 'Dark Dimmed',
      subtitle: 'Subtle Charcoal & Azure',
      isDark: true,
      icon: Icons.nightlight_round,
      primary: Color(0xFF539BF5),
      secondary: Color(0xFF57AB5A),
      canvas: Color(0xFF1C2128),
      surface: Color(0xFF22272E),
      border: Color(0xFF373E47),
      sidebarBg: Color(0xFF161B22),
      sidebarBorder: Color(0xFF373E47),
      sidebarSurface: Color(0xFF22272E),
      sidebarActive: Color(0xFF539BF5),
      textPrimary: Color(0xFFADBAC7),
      textSecondary: Color(0xFF768390),
    ),

    // 5. Solarized Dark
    GubernatorThemeDef(
      id: 'solarizedDark',
      name: 'Solarized Dark',
      subtitle: 'Deep Teal & Solar Yellow',
      isDark: true,
      icon: Icons.wb_sunny_outlined,
      primary: Color(0xFFB58900),
      secondary: Color(0xFF2AA198),
      canvas: Color(0xFF002B36),
      surface: Color(0xFF073642),
      border: Color(0xFF0E4C5A),
      sidebarBg: Color(0xFF00212B),
      sidebarBorder: Color(0xFF073642),
      sidebarSurface: Color(0xFF073642),
      sidebarActive: Color(0xFFB58900),
      textPrimary: Color(0xFF93A1A1),
      textSecondary: Color(0xFF586E75),
    ),

    // 6. Solarized Light
    GubernatorThemeDef(
      id: 'solarizedLight',
      name: 'Solarized Light',
      subtitle: 'Warm Cream Parchment',
      isDark: false,
      icon: Icons.wb_sunny,
      primary: Color(0xFF268BD2),
      secondary: Color(0xFFCB4B16),
      canvas: Color(0xFFFDF6E3),
      surface: Color(0xFFEEE8D5),
      border: Color(0xFFDCD4BE),
      sidebarBg: Color(0xFFF5EEDA),
      sidebarBorder: Color(0xFFE0D8C3),
      sidebarSurface: Color(0xFFFAF2DD),
      sidebarActive: Color(0xFF268BD2),
      textPrimary: Color(0xFF586E75),
      textSecondary: Color(0xFF839496),
    ),

    // 7. Monokai Pro
    GubernatorThemeDef(
      id: 'monokai',
      name: 'Monokai Pro',
      subtitle: 'Vivid Neon Magenta & Green',
      isDark: true,
      icon: Icons.code,
      primary: Color(0xFFF92672),
      secondary: Color(0xFFA6E22E),
      canvas: Color(0xFF1E1F1C),
      surface: Color(0xFF272822),
      border: Color(0xFF3E3D32),
      sidebarBg: Color(0xFF161714),
      sidebarBorder: Color(0xFF2D2E28),
      sidebarSurface: Color(0xFF22231E),
      sidebarActive: Color(0xFFF92672),
      textPrimary: Color(0xFFF8F8F2),
      textSecondary: Color(0xFF75715E),
    ),

    // 8. Imperial Roman Red
    GubernatorThemeDef(
      id: 'crimsonRed',
      name: 'Imperial Red',
      subtitle: 'Roman Legionary Crimson & Gold',
      isDark: true,
      icon: Icons.shield,
      primary: Color(0xFFE11D48),
      secondary: Color(0xFFF59E0B),
      canvas: Color(0xFF17090C),
      surface: Color(0xFF241014),
      border: Color(0xFF3F1920),
      sidebarBg: Color(0xFF100608),
      sidebarBorder: Color(0xFF2B0E14),
      sidebarSurface: Color(0xFF1C0B0F),
      sidebarActive: Color(0xFFE11D48),
      textPrimary: Color(0xFFFCE7EB),
      textSecondary: Color(0xFFA87580),
    ),

    // 9. Cyberpunk / Synthwave '84
    GubernatorThemeDef(
      id: 'cyberpunk',
      name: 'Cyberpunk 84',
      subtitle: 'Neon Pink & Electric Cyan',
      isDark: true,
      icon: Icons.bolt,
      primary: Color(0xFFFF2A85),
      secondary: Color(0xFF00F0FF),
      canvas: Color(0xFF120A24),
      surface: Color(0xFF1C1236),
      border: Color(0xFF352060),
      sidebarBg: Color(0xFF0B0617),
      sidebarBorder: Color(0xFF261545),
      sidebarSurface: Color(0xFF150C2B),
      sidebarActive: Color(0xFFFF2A85),
      textPrimary: Color(0xFFF0E6FF),
      textSecondary: Color(0xFF9E84C7),
    ),

    // 10. Nord
    GubernatorThemeDef(
      id: 'nord',
      name: 'Nord',
      subtitle: 'Arctic Polar Night & Frost',
      isDark: true,
      icon: Icons.ac_unit,
      primary: Color(0xFF88C0D0),
      secondary: Color(0xFF81A1C1),
      canvas: Color(0xFF242933),
      surface: Color(0xFF2E3440),
      border: Color(0xFF3B4252),
      sidebarBg: Color(0xFF1E222B),
      sidebarBorder: Color(0xFF2E3440),
      sidebarSurface: Color(0xFF272C37),
      sidebarActive: Color(0xFF88C0D0),
      textPrimary: Color(0xFFECEFF4),
      textSecondary: Color(0xFF949EB2),
    ),

    // 11. Dracula
    GubernatorThemeDef(
      id: 'dracula',
      name: 'Dracula',
      subtitle: 'Gothic Purple & Vampire Pink',
      isDark: true,
      icon: Icons.auto_awesome,
      primary: Color(0xFFBD93F9),
      secondary: Color(0xFFFF79C6),
      canvas: Color(0xFF1E1F29),
      surface: Color(0xFF282A36),
      border: Color(0xFF44475A),
      sidebarBg: Color(0xFF181921),
      sidebarBorder: Color(0xFF343746),
      sidebarSurface: Color(0xFF22242F),
      sidebarActive: Color(0xFFBD93F9),
      textPrimary: Color(0xFFF8F8F2),
      textSecondary: Color(0xFF6272A4),
    ),

    // 12. Tokyo Night
    GubernatorThemeDef(
      id: 'tokyoNight',
      name: 'Tokyo Night',
      subtitle: 'Deep Indigo & Neo-Tokyo Blue',
      isDark: true,
      icon: Icons.location_city,
      primary: Color(0xFF7AA2F7),
      secondary: Color(0xFFBB9AF7),
      canvas: Color(0xFF16161E),
      surface: Color(0xFF1A1B26),
      border: Color(0xFF292E42),
      sidebarBg: Color(0xFF13131A),
      sidebarBorder: Color(0xFF24283B),
      sidebarSurface: Color(0xFF1A1B26),
      sidebarActive: Color(0xFF7AA2F7),
      textPrimary: Color(0xFFC0CAF5),
      textSecondary: Color(0xFF565F89),
    ),

    // 13. Gruvbox Dark
    GubernatorThemeDef(
      id: 'gruvbox',
      name: 'Gruvbox Dark',
      subtitle: 'Retro Earthy Brown & Amber',
      isDark: true,
      icon: Icons.music_note,
      primary: Color(0xFFFE8019),
      secondary: Color(0xFFB8BB26),
      canvas: Color(0xFF1D2021),
      surface: Color(0xFF282828),
      border: Color(0xFF3C3836),
      sidebarBg: Color(0xFF181A1B),
      sidebarBorder: Color(0xFF32302F),
      sidebarSurface: Color(0xFF242424),
      sidebarActive: Color(0xFFFE8019),
      textPrimary: Color(0xFFEBDBB2),
      textSecondary: Color(0xFF928374),
    ),
  ];

  static GubernatorThemeDef getThemeDef(String id) {
    return allThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => allThemes[0], // fallback to 'dark'
    );
  }

  /// Builds a complete Material 3 ThemeData from a theme definition.
  static ThemeData buildTheme(GubernatorThemeDef def) {
    final brightness = def.isDark ? Brightness.dark : Brightness.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: def.primary,
      brightness: brightness,
      surface: def.surface,
      primary: def.primary,
      secondary: def.secondary,
      error: const Color(0xFFEF4444),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: def.canvas,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: def.canvas,
        foregroundColor: def.textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: def.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: def.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: def.border),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: TextStyle(
          color: def.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        dataTextStyle: TextStyle(
          color: def.textPrimary,
          fontSize: 14,
        ),
        dividerThickness: 1,
      ),
      dividerTheme: DividerThemeData(color: def.border),
      dialogTheme: DialogThemeData(
        backgroundColor: def.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: def.surface,
        contentTextStyle: TextStyle(color: def.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: def.isDark ? def.canvas : def.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: def.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: def.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: def.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: def.primary,
          foregroundColor: def.isDark ? Colors.white : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: def.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: def.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: def.border),
        ),
        textStyle: TextStyle(color: def.textPrimary, fontSize: 12),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: def.sidebarBg,
        selectedIconTheme: const IconThemeData(color: Colors.white, size: 22),
        unselectedIconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.5), size: 22),
        selectedLabelTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        indicatorColor: def.sidebarActive.withValues(alpha: 0.15),
      ),
    );
  }

  /// Helper to get ThemeData for a given theme id.
  static ThemeData getThemeData(String themeId) {
    return buildTheme(getThemeDef(themeId));
  }

  // ─── Backward Compatibility Getters ──────────────────────────────────
  static ThemeData dark() => buildTheme(getThemeDef('dark'));
  static ThemeData light() => buildTheme(getThemeDef('light'));

  // ─── Status Colors ────────────────────────────────────────────────────
  static Color statusColor(String status, {String? themeId}) {
    final def = getThemeDef(themeId ?? 'dark');
    switch (status.toLowerCase()) {
      case 'running':
      case 'active':
        return const Color(0xFF10B981);
      case 'pending':
      case 'starting':
      case 'pause':
      case 'drain':
      case 'maintenance':
        return const Color(0xFFF59E0B);
      case 'dead':
      case 'down':
        return const Color(0xFFEF4444);
      case 'manager':
        return def.primary;
      case 'worker':
        return def.secondary;
      default:
        return Colors.grey;
    }
  }

  static Color statusBgColor(String status, Brightness brightness, {String? themeId}) {
    final base = statusColor(status, themeId: themeId);
    return base.withValues(alpha: brightness == Brightness.dark ? 0.15 : 0.1);
  }
}
