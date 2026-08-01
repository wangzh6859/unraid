import 'package:flutter/material.dart';

/// 主题预设：亮度 + 强调色的组合。
/// 深色系是默认风格；浅色系适合户外；强调色只影响主色（按钮/渐变/CPU 环等）。
enum ThemePreset {
  darkOrange('深色 · 橙', Brightness.dark, Color(0xFFF77E1C)),
  darkTeal('深色 · 青绿', Brightness.dark, Color(0xFF14B8A6)),
  darkBlue('深色 · 蓝', Brightness.dark, Color(0xFF4C8DFF)),
  lightOrange('浅色 · 橙', Brightness.light, Color(0xFFE8630C)),
  lightTeal('浅色 · 青绿', Brightness.light, Color(0xFF0E9488)),
  lightBlue('浅色 · 蓝', Brightness.light, Color(0xFF2563EB)),
  system('跟随系统 · 橙', null, Color(0xFFF77E1C));

  final String label;
  final Brightness? brightness; // null = 跟随系统
  final Color accent;

  const ThemePreset(this.label, this.brightness, this.accent);

  static ThemePreset fromIndex(int index) {
    const values = ThemePreset.values;
    if (index < 0 || index >= values.length) return ThemePreset.darkOrange;
    return values[index];
  }
}

/// 全局主题控制器：设置页切换后立即生效（MaterialApp 监听重建）。
class ThemeController {
  static final ValueNotifier<ThemePreset> current =
      ValueNotifier(ThemePreset.darkOrange);

  static void apply(ThemePreset preset) {
    AppColors.isLight = preset.brightness == Brightness.light;
    AppColors.accentColor = preset.accent;
    current.value = preset;
  }
}

/// 整个 App 的视觉语言。
///
/// 品牌/状态色（teal/blue/red/yellow/green）在深浅主题下通用，保持 const；
/// 背景/文字/边框/主色（orange）跟随当前主题动态变化，供深浅色切换。
class AppColors {
  static bool isLight = false;
  static Color accentColor = const Color(0xFFF77E1C);

  // 品牌色与状态色（深浅主题通用）
  static const teal = Color(0xFF34D3B4);
  static const blue = Color(0xFF4C8DFF);
  static const red = Color(0xFFFF5C5C);
  static const yellow = Color(0xFFFFC24B);
  static const green = Color(0xFF34D399);
  static const orangeDim = Color(0xFFB8580F);

  // 以下颜色随主题变化
  static Color get orange => accentColor;

  static Color get background =>
      isLight ? const Color(0xFFF4F5F7) : const Color(0xFF0E1116);

  static Color get surface =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF161B22);

  static Color get surfaceElevated =>
      isLight ? const Color(0xFFECEFF3) : const Color(0xFF1D232C);

  static Color get border =>
      isLight ? const Color(0xFFD8DCE3) : const Color(0xFF2A313C);

  static Color get textPrimary =>
      isLight ? const Color(0xFF1B1F27) : const Color(0xFFF3F5F7);

  static Color get textSecondary =>
      isLight ? const Color(0xFF5B6472) : const Color(0xFF8A93A2);

  static Color get textFaint =>
      isLight ? const Color(0xFF9AA2AE) : const Color(0xFF5A6270);

  static LinearGradient get gradientPrimary => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accentColor,
          Color.lerp(accentColor, Colors.white, isLight ? 0.35 : 0.2)!,
        ],
      );

  static const gradientTeal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF14B8A6), teal],
  );

  static const gradientBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2563EB), blue],
  );
}

class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    // 注意：这里特意不用 google_fonts。google_fonts 默认在 App 启动时
    // 联网下载字体文件，一旦网络不通或者请求被拦截，会导致启动阶段崩溃。
    // 改用系统自带字体，不联网、不会闪退，视觉上依然干净清爽。
    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    final elevatedStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      side: BorderSide(color: AppColors.border),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.orange,
        onPrimary: isDark ? Colors.black : Colors.white,
        secondary: AppColors.teal,
        onSecondary: Colors.black,
        error: AppColors.red,
        onError: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 22,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.orange, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: AppColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: isDark ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(style: elevatedStyle),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        // 显式指定文字颜色：浅色主题下默认样式会是白字，看不清
        contentTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 13.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.orange,
        unselectedItemColor: AppColors.textFaint,
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: DividerThemeData(color: AppColors.border),
    );
  }
}
