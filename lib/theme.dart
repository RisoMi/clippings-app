/// 设计 token 与主题：与设计说明的 9 个颜色变量一一对应，深色只换值不换结构。
library;

import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color card;
  final Color soft;
  final Color line;
  final Color ink;
  final Color sub;
  final Color weak;
  final Color accent;
  final Color accentSoft;
  final Color accentLine;
  final Color danger;

  const AppColors({
    required this.bg,
    required this.card,
    required this.soft,
    required this.line,
    required this.ink,
    required this.sub,
    required this.weak,
    required this.accent,
    required this.accentSoft,
    required this.accentLine,
    required this.danger,
  });

  static const light = AppColors(
    bg: Color(0xFFF7F5F0),
    card: Color(0xFFFFFFFF),
    soft: Color(0xFFF1EFE8),
    line: Color(0xFFE9E5DC),
    ink: Color(0xFF22231F),
    sub: Color(0xFF6E6D66),
    weak: Color(0xFFA3A199),
    accent: Color(0xFF2F6A54),
    accentSoft: Color(0xFFE7F0EB),
    accentLine: Color(0xFFC9DCD0),
    danger: Color(0xFFA8705E),
  );

  static const dark = AppColors(
    bg: Color(0xFF151917),
    card: Color(0xFF202623),
    soft: Color(0xFF2A302C),
    line: Color(0xFF333B36),
    ink: Color(0xFFF2F4F1),
    sub: Color(0xFFA9B2AB),
    weak: Color(0xFF707A73),
    accent: Color(0xFF5FAE87),
    accentSoft: Color(0xFF20382C),
    accentLine: Color(0xFF3B5A48),
    danger: Color(0xFFC98D78),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? card,
    Color? soft,
    Color? line,
    Color? ink,
    Color? sub,
    Color? weak,
    Color? accent,
    Color? accentSoft,
    Color? accentLine,
    Color? danger,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      soft: soft ?? this.soft,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      sub: sub ?? this.sub,
      weak: weak ?? this.weak,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentLine: accentLine ?? this.accentLine,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      sub: Color.lerp(sub, other.sub, t)!,
      weak: Color.lerp(weak, other.weak, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentLine: Color.lerp(accentLine, other.accentLine, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

class AppRadii {
  static const card = 18.0;
  static const row = 14.0;
  static const thumb = 12.0;
  static const pill = 25.0;
}

class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
        primary: c.accent,
        surface: c.card,
        onSurface: c.ink,
        error: c.danger,
      ),
    );

    return base.copyWith(
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: c.ink, size: 20),
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: TextStyle(color: c.ink, fontSize: 28, fontWeight: FontWeight.w700, height: 1.3),
        headlineSmall: TextStyle(color: c.ink, fontSize: 22, fontWeight: FontWeight.w700, height: 1.35),
        titleMedium: TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w600, height: 1.45),
        bodyLarge: TextStyle(color: c.ink, fontSize: 13, height: 1.7),
        bodyMedium: TextStyle(color: c.sub, fontSize: 12, height: 1.65),
        bodySmall: TextStyle(color: c.weak, fontSize: 11, height: 1.6),
        labelSmall: TextStyle(color: c.weak, fontSize: 10, fontWeight: FontWeight.w500),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: TextStyle(color: c.bg, fontSize: 12),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: brightness == Brightness.dark ? const Color(0xFF151917) : Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.line),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.pill)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.card,
        hintStyle: TextStyle(color: c.weak, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.row),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.row),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.row),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
      ),
    );
  }
}
