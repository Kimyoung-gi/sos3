import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../customer_register_page.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_text_styles.dart';

/// 홈 배너 캐러셀 (PageView + dot indicator)
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({super.key});

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 배너 PageView
        SizedBox(
          height: AppDimens.bannerHeight,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: 3,
            itemBuilder: (context, index) {
              return _BannerCard(
                index: index,
                onTap: (action) => _handleBannerAction(context, action),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Dot indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (index) => Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index
                    ? AppColors.primary
                    : AppColors.divider,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleBannerAction(BuildContext context, String action) {
    switch (action) {
      case 'register':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const CustomerRegisterPage(),
          ),
        );
        break;
      case 'favorites':
        // 더보기의 즐겨찾기로 이동
        context.go('/main/4'); // 더보기 탭
        // TODO: 더보기 페이지에서 즐겨찾기 섹션으로 스크롤하거나 별도 라우팅
        break;
      case 'dashboard':
        context.go('/main/3'); // 대시보드 탭
        break;
    }
  }
}

/// 배너 카드
class _BannerCard extends StatelessWidget {
  final int index;
  final Function(String) onTap;

  const _BannerCard({
    required this.index,
    required this.onTap,
  });

  String get _title {
    switch (index) {
      case 0:
        return 'SOS 2.0';
      case 1:
        return '고객사 관리';
      case 2:
        return '영업 현황';
      default:
        return 'SOS 2.0';
    }
  }

  String get _subtitle {
    switch (index) {
      case 0:
        return '오늘의 영업을 시작하세요';
      case 1:
        return '고객 정보를 효율적으로 관리하세요';
      case 2:
        return '실시간 대시보드로 현황을 파악하세요';
      default:
        return '오늘의 영업을 시작하세요';
    }
  }

  String get _ctaText {
    switch (index) {
      case 0:
        return '고객사 등록';
      case 1:
        return '즐겨찾기';
      case 2:
        return '대시보드';
      default:
        return '고객사 등록';
    }
  }

  String get _ctaAction {
    switch (index) {
      case 0:
        return 'register';
      case 1:
        return 'favorites';
      case 2:
        return 'dashboard';
      default:
        return 'register';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusLarge),
        gradient: AppColors.bannerGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(AppDimens.shadowOpacity),
            blurRadius: AppDimens.shadowBlur,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 우측 상단 장식 원형
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.12),
              ),
            ),
          ),
          // 내용
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: AppTextStyles.bannerTitle.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      style: AppTextStyles.bannerSubtitle.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                // CTA 버튼
                InkWell(
                  onTap: () => onTap(_ctaAction),
                  borderRadius: BorderRadius.circular(AppDimens.pillRadius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppDimens.pillRadius),
                    ),
                    child: Text(
                      _ctaText,
                      style: AppTextStyles.buttonLarge.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
