import 'package:flutter/material.dart';

import '../../main.dart' show CustomerData;
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 고객 카드 위젯 (고객관리 시안 톤앤매너)
class CustomerCard extends StatelessWidget {
  final CustomerData customer;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  /// 최근 영업활동 내용 (없으면 "영업활동 없음" 표시)
  final String? recentActivity;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteToggle,
    this.recentActivity,
  });

  Color _getStatusColor(String status) {
    switch (status) {
      case '영업전':
        return AppColors.pillUnselectedText;
      case '영업중':
        return const Color(0xFF2196F3);
      case '영업실패':
        return Colors.red;
      case '영업성공':
      case '완료':
        return const Color(0xFF10B981);
      default:
        return AppColors.pillUnselectedText;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case '영업성공':
        return '완료';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimens.customerCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.customerCardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 회사명 영역: 빨간 매장 아이콘 + 회사명 bold + 영업상태 pill
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.store_outlined, size: 20, color: AppColors.customerRed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        customer.customerName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // 영업상태 pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(customer.salesStatus).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                      ),
                      child: Text(
                        _getStatusLabel(customer.salesStatus),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(customer.salesStatus),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 개통일 (담당자 위, 시작 공간 맞춤)
                if (customer.openedAt.isNotEmpty)
                  Text(
                    '개통일: ${customer.openedAt}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                  ),
                if (customer.openedAt.isNotEmpty) const SizedBox(height: 8),
                // 담당자 / 상품
                Text(
                  '담당자: ${customer.personInCharge.isEmpty ? "없음" : customer.personInCharge}  ·  상품: ${customer.productName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                // 최근 메모 (최대 2줄, 연한 grey 박스, radius 10, 13px, ellipsis)
                if (customer.memo.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.pillUnselectedBg.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      customer.memo,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (customer.memo.isNotEmpty) const SizedBox(height: 12),
                // 영업활동 영역: 회색 음영, 하단 선으로 전화/문자와 구분
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.pillUnselectedBg.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    (recentActivity != null && recentActivity!.trim().isNotEmpty)
                        ? recentActivity!
                        : '영업활동 없음',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 10),
                Divider(height: 1, thickness: 1, color: AppColors.border),
                const SizedBox(height: 10),
                // 전화 / 문자 버튼 + 즐겨찾기 별
                Row(
                  children: [
                    // 전화: red bg, white text, radius 20
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.call, size: 18, color: Colors.white),
                      label: const Text(
                        '전화',
                        style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.customerRed,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 문자: white bg, grey border, icon
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: Icon(Icons.sms_outlined, size: 18, color: AppColors.textSecondary),
                      label: Text(
                        '문자',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        minimumSize: const Size(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // 즐겨찾기 별 (우측 하단, 터치 영역 min 36px)
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        icon: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite ? const Color(0xFFFFC107) : AppColors.textSecondary,
                          size: 26,
                        ),
                        onPressed: onFavoriteToggle,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
