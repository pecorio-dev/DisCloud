import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Discord Colors
class DiscordColors {
  // Brand
  static const Color blurple = Color(0xFF5865F2);
  static const Color green = Color(0xFF57F287);
  static const Color yellow = Color(0xFFFEE75C);
  static const Color fuchsia = Color(0xFFEB459E);
  static const Color red = Color(0xFFED4245);
  
  // Dark Theme
  static const Color darkBackground = Color(0xFF313338);
  static const Color darkSecondary = Color(0xFF2B2D31);
  static const Color darkTertiary = Color(0xFF1E1F22);
  static const Color darkFloating = Color(0xFF232428);
  static const Color darkBorder = Color(0xFF3F4147);
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkTextMuted = Color(0xFFB5BAC1);
  static const Color darkTextFaint = Color(0xFF949BA4);
  
  // Light Theme
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSecondary = Color(0xFFF2F3F5);
  static const Color lightTertiary = Color(0xFFE3E5E8);
  static const Color lightBorder = Color(0xFFE1E2E4);
  static const Color lightText = Color(0xFF060607);
  static const Color lightTextMuted = Color(0xFF4E5058);
  static const Color lightTextFaint = Color(0xFF80848E);
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  
  ThemeMode get themeMode => _themeMode;
  
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLight => _themeMode == ThemeMode.light;
  bool get isSystem => _themeMode == ThemeMode.system;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme') ?? 'system';
    _themeMode = _themeModeFromString(themeName);
    notifyListeners();
  }

  Future<void> setTheme(String themeName) async {
    _themeMode = _themeModeFromString(themeName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', themeName);
    notifyListeners();
  }

  ThemeMode _themeModeFromString(String name) {
    switch (name) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: DiscordColors.blurple,
    scaffoldBackgroundColor: DiscordColors.lightSecondary,
    canvasColor: DiscordColors.lightBackground,
    
    colorScheme: const ColorScheme.light(
      primary: DiscordColors.blurple,
      secondary: DiscordColors.blurple,
      surface: DiscordColors.lightBackground,
      error: DiscordColors.red,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: DiscordColors.lightText,
      onError: Colors.white,
    ),
    
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: DiscordColors.lightBackground,
      foregroundColor: DiscordColors.lightText,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: DiscordColors.lightText,
      ),
      iconTheme: IconThemeData(color: DiscordColors.lightTextMuted),
    ),
    
    cardTheme: CardThemeData(
      elevation: 0,
      color: DiscordColors.lightBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: DiscordColors.lightBorder),
      ),
    ),
    
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: DiscordColors.blurple,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: DiscordColors.lightTextMuted,
      textColor: DiscordColors.lightText,
    ),
    
    dividerTheme: const DividerThemeData(
      color: DiscordColors.lightBorder,
      thickness: 1,
      space: 1,
    ),
    
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DiscordColors.lightSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DiscordColors.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DiscordColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DiscordColors.blurple, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DiscordColors.red),
      ),
      labelStyle: const TextStyle(color: DiscordColors.lightTextMuted),
      hintStyle: const TextStyle(color: DiscordColors.lightTextFaint),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DiscordColors.blurple,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DiscordColors.lightText,
        side: const BorderSide(color: DiscordColors.lightBorder),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DiscordColors.blurple,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return DiscordColors.lightTextFaint;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return DiscordColors.green;
        return DiscordColors.lightTertiary;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return DiscordColors.blurple;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: DiscordColors.lightTextFaint, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DiscordColors.blurple,
      linearTrackColor: DiscordColors.lightTertiary,
    ),
    
    dialogTheme: DialogThemeData(
      backgroundColor: DiscordColors.lightBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titleTextStyle: const TextStyle(
        color: DiscordColors.lightText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        color: DiscordColors.lightTextMuted,
        fontSize: 14,
      ),
    ),
    
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DiscordColors.lightText,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    
    popupMenuTheme: PopupMenuThemeData(
      color: DiscordColors.lightBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: const TextStyle(color: DiscordColors.lightText),
    ),
    
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DiscordColors.lightBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: DiscordColors.lightText),
      displayMedium: TextStyle(color: DiscordColors.lightText),
      displaySmall: TextStyle(color: DiscordColors.lightText),
      headlineLarge: TextStyle(color: DiscordColors.lightText),
      headlineMedium: TextStyle(color: DiscordColors.lightText),
      headlineSmall: TextStyle(color: DiscordColors.lightText),
      titleLarge: TextStyle(color: DiscordColors.lightText),
      titleMedium: TextStyle(color: DiscordColors.lightText),
      titleSmall: TextStyle(color: DiscordColors.lightTextMuted),
      bodyLarge: TextStyle(color: DiscordColors.lightText),
      bodyMedium: TextStyle(color: DiscordColors.lightText),
      bodySmall: TextStyle(color: DiscordColors.lightTextMuted),
      labelLarge: TextStyle(color: DiscordColors.lightText),
      labelMedium: TextStyle(color: DiscordColors.lightTextMuted),
      labelSmall: TextStyle(color: DiscordColors.lightTextFaint),
    ),
    
    iconTheme: const IconThemeData(color: DiscordColors.lightTextMuted),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: DiscordColors.blurple,
    scaffoldBackgroundColor: DiscordColors.darkTertiary,
    canvasColor: DiscordColors.darkSecondary,
    
    colorScheme: const ColorScheme.dark(
      primary: DiscordColors.blurple,
      secondary: DiscordColors.blurple,
      surface: DiscordColors.darkSecondary,
      error: DiscordColors.red,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: DiscordColors.darkText,
      onError: Colors.white,
    ),
    
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: DiscordColors.darkSecondary,
      foregroundColor: DiscordColors.darkText,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: DiscordColors.darkText,
      ),
      iconTheme: IconThemeData(color: DiscordColors.darkTextMuted),
    ),
    
    cardTheme: CardThemeData(
      elevation: 0,
      color: DiscordColors.darkSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: DiscordColors.blurple,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: DiscordColors.darkTextMuted,
      textColor: DiscordColors.darkText,
      tileColor: Colors.transparent,
    ),
    
    dividerTheme: const DividerThemeData(
      color: DiscordColors.darkBorder,
      thickness: 1,
      space: 1,
    ),
    
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DiscordColors.darkTertiary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DiscordColors.blurple, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: DiscordColors.red),
      ),
      labelStyle: const TextStyle(color: DiscordColors.darkTextMuted),
      hintStyle: const TextStyle(color: DiscordColors.darkTextFaint),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DiscordColors.blurple,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: DiscordColors.darkText,
        side: const BorderSide(color: DiscordColors.darkBorder),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: DiscordColors.darkText,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return DiscordColors.darkTextFaint;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return DiscordColors.green;
        return DiscordColors.darkBorder;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return DiscordColors.blurple;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: DiscordColors.darkTextFaint, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: DiscordColors.blurple,
      linearTrackColor: DiscordColors.darkBorder,
    ),
    
    dialogTheme: DialogThemeData(
      backgroundColor: DiscordColors.darkBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titleTextStyle: const TextStyle(
        color: DiscordColors.darkText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        color: DiscordColors.darkTextMuted,
        fontSize: 14,
      ),
    ),
    
    snackBarTheme: SnackBarThemeData(
      backgroundColor: DiscordColors.darkBackground,
      contentTextStyle: const TextStyle(color: DiscordColors.darkText),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    
    popupMenuTheme: PopupMenuThemeData(
      color: DiscordColors.darkFloating,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: const TextStyle(color: DiscordColors.darkText),
    ),
    
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: DiscordColors.darkSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: DiscordColors.darkText),
      displayMedium: TextStyle(color: DiscordColors.darkText),
      displaySmall: TextStyle(color: DiscordColors.darkText),
      headlineLarge: TextStyle(color: DiscordColors.darkText),
      headlineMedium: TextStyle(color: DiscordColors.darkText),
      headlineSmall: TextStyle(color: DiscordColors.darkText),
      titleLarge: TextStyle(color: DiscordColors.darkText),
      titleMedium: TextStyle(color: DiscordColors.darkText),
      titleSmall: TextStyle(color: DiscordColors.darkTextMuted),
      bodyLarge: TextStyle(color: DiscordColors.darkText),
      bodyMedium: TextStyle(color: DiscordColors.darkText),
      bodySmall: TextStyle(color: DiscordColors.darkTextMuted),
      labelLarge: TextStyle(color: DiscordColors.darkText),
      labelMedium: TextStyle(color: DiscordColors.darkTextMuted),
      labelSmall: TextStyle(color: DiscordColors.darkTextFaint),
    ),
    
    iconTheme: const IconThemeData(color: DiscordColors.darkTextMuted),
  );
}
