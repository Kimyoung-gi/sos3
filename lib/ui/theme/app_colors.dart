import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 컬러 팔레트
class AppColors {
  AppColors._();

  // Primary (코랄)
  static const Color primary = Color(0xFFFF6B63);
  static const Color primaryDark = Color(0xFFF04E45);
  static const Color primaryLight = Color(0xFFFFE8E6);

  // 고객관리 시안 Red (#E6002D 계열)
  static const Color customerRed = Color(0xFFE6002D);
  static const Color pillSelectedBg = Color(0xFFE6002D);
  static const Color pillUnselectedBg = Color(0xFFE8E9EC);
  static const Color pillUnselectedText = Color(0xFF6B7280);

  // Background (밝은 라이트 그레이 - SOS 2.0)
  static const Color background = Color(0xFFF5F6F8);

  // Card
  static const Color card = Color(0xFFFFFFFF);

  // 인사 카드
  static const LinearGradient greetingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE53935), Color(0xFFC62828)],
  );
  static const Color greetingTextWhite = Color(0xFFFFFFFF);
  static const Color greetingTextWhite70 = Color(0xB3FFFFFF);

  // 섹션 "전체보기" 링크
  static const Color sectionSeeAll = Color(0xFFFF6B63);

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
