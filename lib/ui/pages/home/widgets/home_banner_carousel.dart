import 'package:flutter/material.dart';

import '../../customer_register_page.dart';
import '../../../theme/app_dimens.dart';

/// 홈 배너 - 단일 이미지 + 고객사 등록 버튼
class HomeBannerCarousel extends StatelessWidget {
  const HomeBannerCarousel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDimens.bannerHeight,
      child: const _BannerCard(),
    );
  }
}

/// 배너 카드 (배경이미지 + CTA)
class _BannerCard extends StatelessWidget {
  const _BannerCard();

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimens.cardRadiusLarge),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경 이미지 (Image.asset: 미등록 시 네임드 Placeholder)
            Image.asset(
              'assets/images/home_banner.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              // 파일이 없으면 투명 컬러를 보여주어 아무것도 안 보이게 할 수 있음
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
            // 하단 CTA 버튼 : 고객사 등록
            Positioned(
              bottom: 16,
              right: 16,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CustomerRegisterPage(),
                    ),
                  );
                },
                child: const Text(
                  '고객사 등록',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}