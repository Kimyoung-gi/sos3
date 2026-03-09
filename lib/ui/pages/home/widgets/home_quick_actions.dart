import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../repositories/customer_repository.dart';
import '../../../../repositories/od_repository.dart';
import '../../../../services/auth_service.dart';
import '../../../../utils/customer_converter.dart';
import '../../../../main.dart' show CustomerData;
import '../../../../services/csv_reload_bus.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_text_styles.dart';

/// 대시보드 — 관리 고객사 / 고객사_영업중 / 약정만료예정 / OD 카드 (권한별·전체 수량 표시)
class HomeQuickActions extends StatefulWidget {
  const HomeQuickActions({super.key});

  @override
  State<HomeQuickActions> createState() => _HomeQuickActionsState();
}

class _HomeQuickActionsState extends State<HomeQuickActions> {
  int _customerTotal = 0;
  int _customerSalesActive = 0;
  int _expiringCount = 0;
  int _odTotal = 0;
  bool _loading = true;
  String? _errorMessage;
  StreamSubscription<String>? _reloadSub;

  @override
  void initState() {
    super.initState();
    _loadCounts();
    _reloadSub = CsvReloadBus().stream.listen((filename) {
      if (filename.contains('customerlist') || filename.contains('고객사') || filename.toUpperCase().contains('OD')) {
        _loadCounts();
      }
    });
  }

  @override
  void dispose() {
    _reloadSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final odRepo = OdRepository();
      final user = authService.currentUser;

      final customers = await customerRepo.getFiltered(user);
      final list = CustomerConverter.toCustomerDataList(customers);

      final salesActive = customers.where((c) => c.salesStatus == '영업중').length;
      final expiring = _countExpiringSoon(list);

      final odList = await odRepo.loadAll();

      if (mounted) {
        setState(() {
          _customerTotal = customers.length;
          _customerSalesActive = salesActive;
          _expiringCount = expiring;
          _odTotal = odList.length;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('대시보드 카운트 로드 오류: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// 당일 기준 -1개월 ~ +1개월 약정만료 고객 수 (개통일+36개월)
  int _countExpiringSoon(List<CustomerData> list) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).subtract(const Duration(days: 31));
    final end = now.add(const Duration(days: 31));
    int count = 0;
    for (final c in list) {
      final open = _openDateToDateTime(c.openedAt);
      if (open == null) continue;
      final expiry = _addMonths(open, 36);
      if ((expiry.isAfter(start) || expiry.isAtSameMomentAs(start)) &&
          (expiry.isBefore(end) || expiry.isAtSameMomentAs(end))) {
        count++;
      }
    }
    return count;
  }

  DateTime? _openDateToDateTime(String s) {
    if (s.trim().isEmpty) return null;
    return DateTime.tryParse(s.trim());
  }

  DateTime _addMonths(DateTime d, int months) {
    var y = d.year;
    var m = d.month + months;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    final day = d.day.clamp(1, DateTime(y, m + 1, 0).day);
    return DateTime(y, m, day);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dashboard_rounded, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              '대시보드',
              style: AppTextStyles.sectionTitle,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_errorMessage != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('로드 실패: $_errorMessage', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppDimens.cardSpacing,
            crossAxisSpacing: AppDimens.cardSpacing,
            childAspectRatio: 1.15,
            children: [
              _DashboardCard(
                icon: Icons.business_center_rounded,
                label: '관리 고객사',
                count: _customerTotal,
                color: AppColors.primaryLight,
                iconColor: AppColors.primary,
                onTap: () => context.go('/main/1'),
              ),
              _DashboardCard(
                icon: Icons.store_rounded,
                label: '고객사_영업중',
                count: _customerSalesActive,
                color: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF2196F3),
                onTap: () => context.go('/main/1?salesStatus=영업중'),
              ),
              _DashboardCard(
                icon: Icons.calendar_month,
                label: '약정만료예정',
                count: _expiringCount,
                color: const Color(0xFFF3E5F5),
                iconColor: const Color(0xFF9C27B0),
                onTap: () {
                  context.go('/main/5', extra: 'calendar_view');
                },
              ),
              _DashboardCard(
                icon: Icons.work_outline,
                label: 'OD',
                count: _odTotal,
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

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.label,
    required this.count,
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
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: AppTextStyles.sectionTitle.copyWith(fontSize: 20, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
