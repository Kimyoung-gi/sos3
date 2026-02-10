import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/auth_service.dart';
import '../../../theme/app_colors.dart';

/// 상단 인사 카드 (레드 그라데이션 - SOS 2.0)
class HomeGreetingCard extends StatelessWidget {
  const HomeGreetingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        final name = auth.currentUser?.name ?? '회원';
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            gradient: AppColors.greetingGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '안녕하세요,',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.greetingTextWhite70,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$name님',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: AppColors.greetingTextWhite,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '오늘도 화이팅 하세요! 🔥',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.greetingTextWhite70,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
