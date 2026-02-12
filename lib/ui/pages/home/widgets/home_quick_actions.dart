import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../customer_register_page.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_text_styles.dart';

/// 빠른 실행 아이콘 카드 (2x2 그리드)
class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flash_on, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              '빠른 실행',
              style: AppTextStyles.sectionTitle,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppDimens.cardSpacing,
          crossAxisSpacing: AppDimens.cardSpacing,
          childAspectRatio: 1.2,
          children: [
            _QuickActionCard(
              icon: Icons.add_circle_outline,
              label: '고객사 등록',
              color: AppColors.primaryLight,
              iconColor: AppColors.primary,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CustomerRegisterPage(),
                  ),
                );
              },
            ),
            _QuickActionCard(
              icon: Icons.search,
              label: '고객사 검색',
              color: const Color(0xFFE3F2FD),
              iconColor: const Color(0xFF2196F3),
              onTap: () {
                context.go('/main/1'); // 고객사 탭
              },
            ),
            _QuickActionCard(
              icon: Icons.calendar_month,
              label: '캘린더뷰',
              color: const Color(0xFFF3E5F5),
              iconColor: const Color(0xFF9C27B0),
              onTap: () {
                context.go('/main/5', extra: 'calendar_view');
              },
            ),
            _QuickActionCard(
              icon: Icons.work_outline,
              label: 'OD',
              color: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF4CAF50),
              onTap: () => context.go('/main/4'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 빠른 실행 카드
class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppDimens.cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(AppDimens.shadowOpacity),
              blurRadius: AppDimens.shadowBlur,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
