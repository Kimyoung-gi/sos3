import 'package:flutter/material.dart';

import '../../main.dart' show CustomerData;

/// 고객 카드 위젯
class CustomerCard extends StatelessWidget {
  final CustomerData customer;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const CustomerCard({
    super.key,
    required this.customer,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  /// 영업상태 Badge 색상
  Color _getStatusColor(String status) {
    switch (status) {
      case '영업전':
        return Colors.grey;
      case '영업중':
        return Colors.blue;
      case '영업실패':
        return Colors.red;
      case '영업성공':
      case '완료':
        return Colors.green;
      case '진행중':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// 영업상태 라벨
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 영업상태 Badge + 즐겨찾기
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 영업상태 Badge (고객명 없이 Badge만)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(customer.salesStatus),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getStatusLabel(customer.salesStatus),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // 즐겨찾기 버튼
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.star : Icons.star_border,
                      color: isFavorite ? const Color(0xFFFF6F61) : Colors.grey[400],
                      size: 24,
                    ),
                    onPressed: onFavoriteToggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 고객명
              Text(
                customer.customerName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              // 상품유형 + 상품명
              Text(
                '${customer.productType} ${customer.productName}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              // 개통일자
              Text(
                customer.openedAt,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
