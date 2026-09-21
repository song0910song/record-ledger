import 'package:flutter/material.dart';

/// 清爽浅色主题 —— 白底 + 主色点缀
class AppColors {
  // 主色：柔和的青绿色，冷静不刺眼
  static const Color primary = Color(0xFF00B894);
  static const Color primaryLight = Color(0xFFE6F9F4);

  // 支出/收入 —— 按中国市场习惯：支出用暖红，收入用绿
  static const Color expense = Color(0xFFE85D5D);
  static const Color income = Color(0xFF00B894);

  // 预警色
  static const Color warn = Color(0xFFF5A623);
  static const Color danger = Color(0xFFE84C3D);

  // 中性色
  static const Color bg = Color(0xFFF7F8FA);
  static const Color card = Colors.white;
  static const Color textMain = Color(0xFF1F2430);
  static const Color textSub = Color(0xFF8A93A5);
  static const Color divider = Color(0xFFEDEFF3);

  /// 分类配色盘
  static const List<Color> palette = [
    Color(0xFF00B894), Color(0xFF6C8AE4), Color(0xFFF5A623),
    Color(0xFFE8686B), Color(0xFF9B6CE4), Color(0xFF4BC0C0),
    Color(0xFFE48A6C), Color(0xFF5BA8E4),
  ];
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      primaryColor: AppColors.primary,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.primary,
        secondary: AppColors.primary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textMain),
        titleTextStyle: TextStyle(
          color: AppColors.textMain,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardTheme(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerColor: AppColors.divider,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textMain,
        displayColor: AppColors.textMain,
      ),
    );
  }
}
