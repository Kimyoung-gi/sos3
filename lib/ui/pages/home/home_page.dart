import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import 'widgets/home_greeting_card.dart';
import 'widgets/home_quick_actions.dart';
import 'widgets/home_recent_activity.dart';

/// 홈 페이지 - 인사 카드, 빠른실행, 즐겨찾기/최근 등록 고객사 (SOS 2.0 톤앤매너)
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            automaticallyImplyLeading: false,
            leadingWidth: 0,
            title: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset(
                'assets/images/sos_logo.png',
                height: 28,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            centerTitle: true,
            actions: const [],
            floating: true,
            snap: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pagePadding,
                vertical: AppDimens.cardSpacing,
              ),
              child: const HomeGreetingCard(),
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
          // 즐겨찾기 + 최근 등록한 고객사
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
