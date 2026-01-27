import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

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
        Text(
          '빠른 실행',
          style: AppTextStyles.sectionTitleLarge,
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
              icon: Icons.dashboard_outlined,
              label: '대시보드',
              color: const Color(0xFFF3E5F5),
              iconColor: const Color(0xFF9C27B0),
              onTap: () {
                context.go('/main/3'); // 대시보드 탭
              },
            ),
            _QuickActionCard(
              icon: Icons.language,
              label: 'OD 열기',
              color: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF4CAF50),
              onTap: () async {
                const odUrl = 'https://kimyoung-gi.github.io/11/';
                try {
                  final uri = Uri.parse(odUrl);
                  if (kIsWeb) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                      webOnlyWindowName: '_blank',
                    );
                  } else {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('브라우저에서 열 수 없습니다'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
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
