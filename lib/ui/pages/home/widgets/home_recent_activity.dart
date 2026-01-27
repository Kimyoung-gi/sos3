import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../repositories/customer_repository.dart';
import '../../../../utils/customer_converter.dart';
import '../../../../main.dart' show CustomerData, CustomerDetailScreen;
import '../../../../services/auth_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_dimens.dart';
import '../../../theme/app_text_styles.dart';

/// 최근 활동 피드
class HomeRecentActivity extends StatefulWidget {
  const HomeRecentActivity({super.key});

  @override
  State<HomeRecentActivity> createState() => _HomeRecentActivityState();
}

class _HomeRecentActivityState extends State<HomeRecentActivity> {
  List<_ActivityItem> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final currentUser = authService.currentUser;

      // RBAC 필터링된 고객 목록 가져오기
      final customers = await customerRepo.getFiltered(currentUser);
      final customerDataList = CustomerConverter.toCustomerDataList(customers);

      // 활동 아이템 생성 (우선순위: memo > 영업중 > 기타)
      final List<_ActivityItem> activities = [];

      for (final customer in customerDataList) {
        // 메모가 있는 고객
        if (customer.memo.isNotEmpty) {
          activities.add(_ActivityItem(
            customer: customer,
            type: ActivityType.memo,
            message: '메모 업데이트',
            icon: Icons.note_outlined,
          ));
        }
        // 영업중인 고객
        if (customer.salesStatus == '영업중') {
          activities.add(_ActivityItem(
            customer: customer,
            type: ActivityType.status,
            message: "영업상태 '영업중'",
            icon: Icons.trending_up,
          ));
        }
      }

      // 중복 제거 (같은 고객의 여러 활동 중 하나만)
      final Map<String, _ActivityItem> uniqueActivities = {};
      for (final activity in activities) {
        final key = activity.customer.customerKey;
        if (!uniqueActivities.containsKey(key)) {
          uniqueActivities[key] = activity;
        }
      }

      // 최대 10개만 표시
      final sortedActivities = uniqueActivities.values.toList()
        ..sort((a, b) {
          // 메모 우선, 그 다음 영업중
          if (a.type != b.type) {
            return a.type == ActivityType.memo ? -1 : 1;
          }
          return 0;
        });

      if (mounted) {
        setState(() {
          _activities = sortedActivities.take(10).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('최근 활동 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '최근 활동',
          style: AppTextStyles.sectionTitleLarge,
        ),
        const SizedBox(height: 16),
        _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            : _activities.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _activities.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final activity = _activities[index];
                      return _ActivityCard(
                        activity: activity,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => CustomerDetailScreen(
                                customer: activity.customer,
                                onFavoriteChanged: () {},
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ],
    );
  }
}

/// 활동 타입
enum ActivityType {
  memo,
  status,
}

/// 활동 아이템
class _ActivityItem {
  final CustomerData customer;
  final ActivityType type;
  final String message;
  final IconData icon;

  _ActivityItem({
    required this.customer,
    required this.type,
    required this.message,
    required this.icon,
  });
}

/// 활동 카드
class _ActivityCard extends StatelessWidget {
  final _ActivityItem activity;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.activity,
    required this.onTap,
  });

  Color _getIconColor() {
    switch (activity.type) {
      case ActivityType.memo:
        return AppColors.primary;
      case ActivityType.status:
        return AppColors.statusActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
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
            // 아이콘
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getIconColor().withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                activity.icon,
                color: _getIconColor(),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // 텍스트
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${activity.customer.customerName} · ${activity.message}',
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '오늘', // TODO: 실제 updatedAt 사용 시 교체
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            // 화살표
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

/// 빈 상태
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimens.cardRadius),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            '최근 활동이 없습니다',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
