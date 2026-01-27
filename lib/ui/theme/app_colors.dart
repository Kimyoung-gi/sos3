import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 컬러 팔레트
class AppColors {
  AppColors._();

  // Primary (코랄)
  static const Color primary = Color(0xFFFF6B63);
  static const Color primaryDark = Color(0xFFF04E45);
  static const Color primaryLight = Color(0xFFFFE8E6);

  // Background
  static const Color background = Color(0xFFF6F7F9);

  // Card
  static const Color card = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF111318);
  static const Color textSecondary = Color(0xFF6B7280);

  // Divider/Border
  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFE5E7EB);

  // Status Badge
  static const Color statusInactive = Color(0xFF9CA3AF); // 영업전
  static const Color statusActive = Color(0xFF3B82F6); // 영업중
  static const Color statusComplete = Color(0xFF10B981); // 완료
  static const Color statusProgress = Color(0xFFF59E0B); // 진행/보류

  // Gradient
  static const LinearGradient bannerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFF6B63),
      Color(0xFFFF8A80),
      Color(0xFFFFB3B3),
      Color(0xFFFFFFFF),
    ],
    stops: [0.0, 0.3, 0.7, 1.0],
  );
}
