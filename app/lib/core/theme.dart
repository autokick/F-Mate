import 'package:flutter/material.dart';

/// F-Mate 디자인 토큰.
/// 흰 바탕 + 거의 검정(ink) 글자를 기본으로 하고, 초록(brand)은 예약·결제처럼 중요한 행동에만 쓴다.
/// 흰 글자를 올리는 초록(brandDark)은 흰 배경 대비 4.5:1 이상이 되도록 골랐다(접근성).
class FmColors {
  FmColors._();

  /// 장식용 밝은 초록 (아이콘, 진행 표시)
  static const brand = Color(0xFF00A866);

  /// 버튼·강조 글자용 초록 (흰 글자 대비 5:1)
  static const brandDark = Color(0xFF007F4D);

  /// 연한 초록 배경 (칩, 남은 시간 표시)
  static const brandSoft = Color(0xFFE7F5EE);

  /// 연한 초록 위 글자
  static const brandOnSoft = Color(0xFF00653D);

  /// 선택된 칩·탭 등에 쓰는 거의 검정
  static const ink = Color(0xFF0F1419);

  static const background = Colors.white;
  static const surfaceMuted = Color(0xFFF2F4F6);
  static const border = Color(0xFFE5E8EB);
  static const divider = Color(0xFFEEF0F2);
  static const textPrimary = Color(0xFF0F1419);
  static const textSecondary = Color(0xFF5B6573);
  static const textTertiary = Color(0xFF8A939E);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEF2F2);

  /// 사진이 아직 없을 때 자리 색
  static const photoPlaceholder = Color(0xFFE3E8E5);

  /// 숏폼(영상) 화면 배경
  static const videoBackground = Color(0xFF0B0D10);
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

  /// 화면 좌우 여백
  static const double page = 20;
}

class FmRadius {
  FmRadius._();

  static const double card = 20;
  static const double control = 14;
  static const double button = 16;
  static const double chip = 999;
}

const String kFmFont = 'Pretendard';

ThemeData buildFmTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: FmColors.brand,
    primary: FmColors.brandDark,
    onPrimary: Colors.white,
    secondary: FmColors.ink,
    surface: Colors.white,
    onSurface: FmColors.textPrimary,
    error: FmColors.danger,
  );

  const baseText = TextTheme(
    headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: FmColors.textPrimary),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: FmColors.textPrimary),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: FmColors.textPrimary),
    titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: FmColors.textPrimary),
    titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: FmColors.textPrimary),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: FmColors.textPrimary),
    bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: FmColors.textPrimary),
    bodySmall: TextStyle(fontSize: 13, height: 1.45, color: FmColors.textSecondary),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: kFmFont,
    colorScheme: scheme,
    textTheme: baseText,
    scaffoldBackgroundColor: FmColors.background,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: FmColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kFmFont,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: FmColors.textPrimary,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: kFmFont, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FmColors.brandDark,
        foregroundColor: Colors.white,
        disabledBackgroundColor: FmColors.surfaceMuted,
        disabledForegroundColor: FmColors.textTertiary,
        minimumSize: const Size(64, 56),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FmRadius.button)),
        textStyle: const TextStyle(fontFamily: kFmFont, fontSize: 17, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: FmColors.textPrimary,
        backgroundColor: FmColors.surfaceMuted,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FmRadius.control)),
        textStyle: const TextStyle(fontFamily: kFmFont, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FmColors.brandDark,
        textStyle: const TextStyle(fontFamily: kFmFont, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: FmColors.ink,
      disabledColor: FmColors.surfaceMuted,
      checkmarkColor: Colors.white,
      showCheckmark: false,
      side: const BorderSide(color: FmColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FmRadius.chip)),
      labelStyle: WidgetStateTextStyle.resolveWith((states) => TextStyle(
            fontFamily: kFmFont,
            fontSize: 14,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? Colors.white : FmColors.textPrimary,
          )),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: FmColors.textPrimary,
      unselectedLabelColor: FmColors.textTertiary,
      indicatorColor: FmColors.ink,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: FmColors.divider,
      labelStyle: TextStyle(fontFamily: kFmFont, fontSize: 15, fontWeight: FontWeight.w800),
      unselectedLabelStyle: TextStyle(fontFamily: kFmFont, fontSize: 15, fontWeight: FontWeight.w600),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: FmColors.ink,
      contentTextStyle: const TextStyle(fontFamily: kFmFont, fontSize: 15, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FmRadius.control)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: FmSpace.page),
      titleTextStyle: TextStyle(fontFamily: kFmFont, fontSize: 16, fontWeight: FontWeight.w600, color: FmColors.textPrimary),
      subtitleTextStyle: TextStyle(fontFamily: kFmFont, fontSize: 13, color: FmColors.textSecondary),
    ),
    dividerColor: FmColors.divider,
    dividerTheme: const DividerThemeData(color: FmColors.divider, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: FmColors.brandDark),
  );
}

/// 입력창 공통 스타일 (테두리 없는 회색 채움).
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
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(FmColors.ink, 1.5),
    errorBorder: border(FmColors.danger),
    focusedErrorBorder: border(FmColors.danger, 1.5),
  );
}
