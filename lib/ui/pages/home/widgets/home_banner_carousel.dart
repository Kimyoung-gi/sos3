import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../customer_register_page.dart';
import 'package:first_app/repositories/promotion_banner_repository.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';

/// 홈 배너 캐러셀 (프로모션 이미지 또는 기본 배너)
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
        context.go('/main/4');
        break;
      case 'dashboard':
        context.go('/main/3');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<PromotionBannerRepository>();
    
    return StreamBuilder<List<String>>(
      stream: repo.watchPromotionImageUrls(limit: 3),
      builder: (context, snapshot) {
        // 에러 처리
        if (snapshot.hasError) {
          debugPrint('❌ 배너 스트림 에러: ${snapshot.error}');
          // 에러 시 기본 배너 표시
          return _buildDefaultBanner();
        }

        // 로딩 중
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              SizedBox(
                height: AppDimens.bannerHeight,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimens.cardRadiusLarge),
                    color: Colors.grey[200],
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ],
          );
        }

        // 배너 0개: 기본 배너 표시
        final imageUrls = snapshot.data ?? [];
        debugPrint('🏠 홈 배너 이미지 URL 개수: ${imageUrls.length}');
        if (imageUrls.isEmpty) {
          return _buildDefaultBanner();
        }

        // 프로모션 이미지 배너 표시 (1~3개)
        return Column(
          children: [
            SizedBox(
              height: AppDimens.bannerHeight,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return _PromotionBannerCard(imageUrl: imageUrls[index]);
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                imageUrls.length,
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
      },
    );
  }

  Widget _buildDefaultBanner() {
    return Column(
      children: [
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
}

/// 프로모션 이미지 배너 카드
class _PromotionBannerCard extends StatelessWidget {
  final String imageUrl;

  const _PromotionBannerCard({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(AppDimens.shadowOpacity),
            blurRadius: AppDimens.shadowBlur,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusLarge),
        child: Image.network(
          imageUrl,
          height: AppDimens.bannerHeight,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey[200],
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint('❌ 배너 이미지 로딩 실패: imageUrl=$imageUrl');
            debugPrint('에러: $error');
            debugPrint('스택 트레이스: $stackTrace');
            return Container(
              decoration: BoxDecoration(
                gradient: AppColors.bannerGradient,
              ),
              child: const Center(
                child: Icon(Icons.error_outline, color: Colors.white70, size: 48),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 배너 카드 (기본 배너)
class _BannerCard extends StatelessWidget {
  final int index;
  final Function(String) onTap;

  const _BannerCard({
    required this.index,
    required this.onTap,
  });

  String get _title {
    switch (index) {
      case 0: return 'SOS 2.0';
      case 1: return '고객사 관리';
      case 2: return '영업 현황';
      default: return 'SOS 2.0';
    }
  }

  String get _subtitle {
    switch (index) {
      case 0: return '오늘의 영업을 시작하세요';
      case 1: return '고객 정보를 효율적으로 관리하세요';
      case 2: return '실시간 대시보드로 현황을 파악하세요';
      default: return '오늘의 영업을 시작하세요';
    }
  }

  String get _ctaText {
    switch (index) {
      case 0: return '고객사 등록';
      case 1: return '즐겨찾기';
      case 2: return '대시보드';
      default: return '고객사 등록';
    }
  }

  String get _ctaAction {
    switch (index) {
      case 0: return 'register';
      case 1: return 'favorites';
      case 2: return 'dashboard';
      default: return 'register';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusLarge),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: AppDimens.shadowBlur,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(_subtitle, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9))),
              ],
            ),
            InkWell(
              onTap: () => onTap(_ctaAction),
              borderRadius: BorderRadius.circular(AppDimens.pillRadius),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppDimens.pillRadius),
                ),
                child: Text(_ctaText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}