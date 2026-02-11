import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../repositories/customer_repository.dart';
import '../../../../services/csv_reload_bus.dart';
import '../../../../utils/customer_converter.dart';
import '../../../../main.dart' show CustomerData, CustomerDetailScreen, MoreNavIntent;
import '../../../../services/auth_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_text_styles.dart';

/// 홈 하단: 즐겨찾기(최대 4) + 약정만료 예정(최대 4) + 최근 등록한 고객사(최대 4)
class HomeRecentActivity extends StatefulWidget {
  const HomeRecentActivity({super.key});

  @override
  State<HomeRecentActivity> createState() => _HomeRecentActivityState();
}

class _HomeRecentActivityState extends State<HomeRecentActivity> {
  List<CustomerData> _favoriteCustomers = [];
  List<CustomerData> _expiringSoon = [];
  List<CustomerData> _recentRegistered = [];
  bool _isLoading = true;
  StreamSubscription<String>? _csvReloadSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _csvReloadSubscription = CsvReloadBus().stream.listen((filename) {
      if (filename.contains('customerlist') || filename.contains('고객사')) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _csvReloadSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final currentUser = authService.currentUser;

      final customers = await customerRepo.getFiltered(currentUser);
      final customerDataList = CustomerConverter.toCustomerDataList(customers);
      final keyToCustomer = {for (final c in customerDataList) c.customerKey: c};

      // 즐겨찾기: 저장된 순서 유지, 최근 4개(리스트 끝 4개) → 역순으로 표시
      final prefs = await SharedPreferences.getInstance();
      final favoriteKeys = prefs.getStringList('favorite_customer_keys') ?? [];
      final recentFavoriteKeys = favoriteKeys.length <= 4
          ? favoriteKeys.reversed.toList()
          : favoriteKeys.reversed.take(4).toList();
      final favoriteCustomers = recentFavoriteKeys
          .map((key) => keyToCustomer[key])
          .whereType<CustomerData>()
          .toList();
      for (final c in favoriteCustomers) {
        c.isFavorite = true;
      }

      // 약정만료 예정: 당일 기준 -1개월 ~ +1개월 (개통일+36개월 기준), 최대 4개
      final expiringSoon = _filterExpiringSoon(customerDataList);

      // 최근 등록한 고객사: openDate 기준 내림차순, 최대 4개
      final sorted = List<CustomerData>.from(customerDataList)
        ..sort((a, b) {
          final da = _parseOpenDate(a.openedAt);
          final db = _parseOpenDate(b.openedAt);
          return db.compareTo(da);
        });
      final recentRegistered = sorted.take(4).toList();

      if (mounted) {
        setState(() {
          _favoriteCustomers = favoriteCustomers;
          _expiringSoon = expiringSoon;
          _recentRegistered = recentRegistered;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('홈 즐겨찾기/최근등록 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// openDate 문자열을 정렬용 int로 (YYYYMMDD)
  int _parseOpenDate(String openDate) {
    if (openDate.isEmpty) return 0;
    final normalized = openDate.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length >= 8) {
      return int.tryParse(normalized.substring(0, 8)) ?? 0;
    }
    return int.tryParse(normalized.padRight(8, '0')) ?? 0;
  }

  static DateTime? _openDateToDateTime(String openDate) {
    if (openDate.isEmpty) return null;
    final n = openDate.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.length < 8) return null;
    final y = int.tryParse(n.substring(0, 4));
    final m = int.tryParse(n.substring(4, 6));
    final d = int.tryParse(n.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime _addMonths(DateTime d, int months) {
    return DateTime(d.year, d.month + months, d.day);
  }

  /// 당일 기준 -1개월 ~ +1개월 약정만료 고객, 만료일 순 정렬 후 최대 4개
  List<CustomerData> _filterExpiringSoon(List<CustomerData> list) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1).subtract(const Duration(days: 31));
    final end = now.add(const Duration(days: 31));
    final withExpiry = <CustomerData>[];
    for (final c in list) {
      final open = _openDateToDateTime(c.openedAt);
      if (open == null) continue;
      final expiry = _addMonths(open, 36);
      if ((expiry.isAfter(start) || expiry.isAtSameMomentAs(start)) &&
          (expiry.isBefore(end) || expiry.isAtSameMomentAs(end))) {
        withExpiry.add(c);
      }
    }
    withExpiry.sort((a, b) {
      final ea = _addMonths(_openDateToDateTime(a.openedAt) ?? DateTime(0), 36);
      final eb = _addMonths(_openDateToDateTime(b.openedAt) ?? DateTime(0), 36);
      return ea.compareTo(eb);
    });
    return withExpiry.take(4).toList();
  }

  void _navigateToMore(String route) {
    context.read<MoreNavIntent>().goToMore(route);
    context.go('/main/5');
  }

  void _openCustomerDetail(CustomerData customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customer: customer,
          onFavoriteChanged: () => _load(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 즐겨찾기 섹션 (제목 + 전체보기)
        _SectionHeader(
          icon: Icons.star_rounded,
          title: '즐겨찾기',
          onViewAll: () => _navigateToMore('favorites'),
        ),
        const SizedBox(height: 12),
        _isLoading
            ? const _LoadingBlock()
            : _favoriteCustomers.isEmpty
                ? const _EmptyBlock(message: '즐겨찾기한 고객이 없습니다')
                : _CustomerListBlock(
                    customers: _favoriteCustomers,
                    onTap: _openCustomerDetail,
                  ),
        const SizedBox(height: 24),
        // 약정만료 예정 섹션 (제목 + 전체보기, 4개만 표시)
        _SectionHeader(
          icon: Icons.event_busy,
          title: '약정만료 예정',
          onViewAll: () => _navigateToMore('contract_expiring'),
        ),
        const SizedBox(height: 12),
        _isLoading
            ? const _LoadingBlock()
            : _expiringSoon.isEmpty
                ? const _EmptyBlock(message: '해당 기간 약정만료 예정 고객이 없습니다')
                : _CustomerListBlock(
                    customers: _expiringSoon,
                    onTap: _openCustomerDetail,
                  ),
        const SizedBox(height: 24),
        // 최근 등록한 고객사 섹션 (제목 + 전체보기)
        _SectionHeader(
          icon: Icons.person_add_alt_1_rounded,
          title: '최근 등록한 고객사',
          onViewAll: () => _navigateToMore('recent'),
        ),
        const SizedBox(height: 12),
        _isLoading
            ? const _LoadingBlock()
            : _recentRegistered.isEmpty
                ? const _EmptyBlock(message: '등록된 고객이 없습니다')
                : _CustomerListBlock(
                    customers: _recentRegistered,
                    onTap: _openCustomerDetail,
                  ),
      ],
    );
  }
}

/// 섹션 제목 + 오른쪽 전체보기 버튼
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onViewAll;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(title, style: AppTextStyles.sectionTitle),
        const Spacer(),
        TextButton(
          onPressed: onViewAll,
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '전체보기 >',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.customerRed,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  final String message;

  const _EmptyBlock({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
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
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 28, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CustomerListBlock extends StatelessWidget {
  final List<CustomerData> customers;
  final void Function(CustomerData) onTap;

  const _CustomerListBlock({
    required this.customers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: customers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final customer = customers[index];
        return _CustomerTile(
          customer: customer,
          onTap: () => onTap(customer),
        );
      },
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerData customer;
  final VoidCallback onTap;

  const _CustomerTile({
    required this.customer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.customerRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.store_outlined,
                color: AppColors.customerRed,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.customerName,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (customer.openedAt.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '개통일 ${customer.openedAt}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
