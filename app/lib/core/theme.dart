import 'package:flutter/material.dart';

/// F-Mate 디자인 토큰.
/// 흰 배경 + 그린 브랜드 컬러. 텍스트·버튼에 쓰는 진한 그린(brandDark)은
/// 흰 배경 대비 4.5:1 이상이 되도록 골랐다(접근성).
class FmColors {
  FmColors._();

  static const brand = Color(0xFF16A34A);
  static const brandDark = Color(0xFF15803D);
  static const brandSoft = Color(0xFFE8F7EE);
  static const background = Colors.white;
  static const surfaceMuted = Color(0xFFF5F7F6);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEF2F2);
}

/// 간격은 4의 배수만 사용한다.
class FmSpace {
  FmSpace._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class FmRadius {
  FmRadius._();

  static const double card = 16;
  static const double control = 12;
  static const double chip = 999;
}

ThemeData buildFmTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: FmColors.brand,
    primary: FmColors.brandDark,
    surface: Colors.white,
    error: FmColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: FmColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: FmColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: FmColors.textPrimary,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: FmColors.brandSoft,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FmRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: FmColors.textPrimary,
        side: const BorderSide(color: FmColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FmRadius.control),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    dividerColor: FmColors.border,
  );
}

/// 입력창 공통 스타일.
InputDecoration fmInputDecoration({
  required String label,
  String? hint,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(FmRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: FmColors.surfaceMuted,
    contentPadding: const EdgeInsets.symmetric(horizontal: FmSpace.l, vertical: FmSpace.l),
    border: border(FmColors.border),
    enabledBorder: border(FmColors.border),
    focusedBorder: border(FmColors.brandDark, 2),
    errorBorder: border(FmColors.danger),
    focusedErrorBorder: border(FmColors.danger, 2),
  );
}
