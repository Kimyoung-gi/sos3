import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_text_styles.dart';
import 'widgets/home_banner_carousel.dart';
import 'widgets/home_quick_actions.dart';
import 'widgets/home_recent_activity.dart';

/// 홈 페이지 - 배너, 빠른실행, 최근활동
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // AppBar
          SliverAppBar(
            backgroundColor: AppColors.card,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset(
                'assets/images/sos_logo.png',
                height: 28,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            leadingWidth: 120,
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: AppColors.textPrimary),
                onPressed: () {
                  // 검색 기능 (추후 구현)
                },
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
                onPressed: () {
                  // 알림 기능 (추후 구현)
                },
              ),
              const SizedBox(width: 8),
            ],
            floating: true,
            snap: true,
          ),
          // 배너 캐러셀
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
                vertical: AppDimens.cardSpacing,
              ),
              child: const HomeBannerCarousel(),
            ),
          ),
          // 빠른 실행
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
                vertical: AppDimens.cardSpacing,
              ),
              child: const HomeQuickActions(),
            ),
          ),
          // 최근 활동
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
                vertical: AppDimens.cardSpacing,
              ),
              child: const HomeRecentActivity(),
            ),
          ),
          // 하단 여백
          const SliverToBoxAdapter(
            child: SizedBox(height: AppDimens.pagePadding),
          ),
        ],
      ),
    );
  }
}
