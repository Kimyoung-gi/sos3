import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart' show CustomerData, CustomerDetailScreen;
import '../../repositories/customer_repository.dart';
import '../../services/auth_service.dart';
import '../../utils/customer_converter.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../widgets/page_menu_title.dart';
import '../widgets/customer_card.dart';

/// 캘린더뷰 — 약정만료일(개통일+36개월) 기준으로 고객사(상품유형) 표기, 일자당 최대 3개 + "+N개"
class CalendarViewPage extends StatefulWidget {
  const CalendarViewPage({super.key});

  @override
  State<CalendarViewPage> createState() => _CalendarViewPageState();
}

class _CalendarViewPageState extends State<CalendarViewPage> {
  late DateTime _currentMonth;
  Map<String, List<CustomerData>> _expiryByDate = {};
  bool _isLoading = true;

  static DateTime? _parseOpenDate(String openedAt) {
    if (openedAt.isEmpty) return null;
    final normalized = openedAt.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length < 8) return null;
    final y = int.tryParse(normalized.substring(0, 4));
    final m = int.tryParse(normalized.substring(4, 6));
    final d = int.tryParse(normalized.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime _addMonths(DateTime d, int months) {
    return DateTime(d.year, d.month + months, d.day);
  }

  static String _dateKey(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<AuthService>();
      final repo = context.read<CustomerRepository>();
      final user = auth.currentUser;
      final list = await repo.getFiltered(user);
      final dataList = CustomerConverter.toCustomerDataList(list);
      final byDate = <String, List<CustomerData>>{};
      for (final c in dataList) {
        final open = _parseOpenDate(c.openedAt);
        if (open == null) continue;
        final expiry = _addMonths(open, 36);
        final key = _dateKey(expiry);
        byDate.putIfAbsent(key, () => []).add(c);
      }
      if (mounted) {
        setState(() {
          _expiryByDate = byDate;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _daysInMonth {
    return DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
  }

  /// 일(0) ~ 토(6) 배치용: Dart weekday 1=월, 7=일 → 일=0 컬럼
  int get _firstWeekday {
    final w = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    return w % 7;
  }

  static const List<String> _weekdays = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 1,
        automaticallyImplyLeading: false,
        leading: const PageMenuTitle(icon: Icons.calendar_month, label: '캘린더뷰'),
        leadingWidth: 120,
        centerTitle: true,
        title: Image.asset(
          'assets/images/sos_logo.png',
          height: 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        actions: const [SizedBox(width: 120)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppDimens.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMonthNav(),
                    const SizedBox(height: 16),
                    _buildWeekdayRow(),
                    const SizedBox(height: 8),
                    _buildCalendarGrid(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMonthNav() {
    final title = '${_currentMonth.year}년 ${_currentMonth.month}월';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() {
              _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
            });
          },
        ),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() {
              _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
            });
          },
        ),
      ],
    );
  }

  Widget _buildWeekdayRow() {
    return Row(
      children: _weekdays.map((w) => Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))))).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstPad = _firstWeekday;
    final days = _daysInMonth;
    final totalCells = firstPad + days;
    final rows = (totalCells / 7).ceil();
    final list = <Widget>[];
    for (int row = 0; row < rows; row++) {
      final rowChildren = <Widget>[];
      for (int col = 0; col < 7; col++) {
        final index = row * 7 + col;
        if (index < firstPad) {
          rowChildren.add(const Expanded(child: SizedBox.shrink()));
        } else {
          final day = index - firstPad + 1;
          if (day > days) {
            rowChildren.add(const Expanded(child: SizedBox.shrink()));
          } else {
            final date = DateTime(_currentMonth.year, _currentMonth.month, day);
            final key = _dateKey(date);
            final items = _expiryByDate[key] ?? [];
            rowChildren.add(Expanded(
              child: _DayCell(
                date: date,
                items: items,
                isCurrentMonth: true,
                onTapDay: () => _openDayList(date, items),
              ),
            ));
          }
        }
      }
      list.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rowChildren,
      ));
      if (row < rows - 1) list.add(const SizedBox(height: 6));
    }
    return Column(children: list);
  }

  void _openDayList(DateTime date, List<CustomerData> items) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ExpiryDayListScreen(date: date, customers: items),
      ),
    );
  }
}

const int _maxDisplay = 3;

class _DayCell extends StatelessWidget {
  final DateTime date;
  final List<CustomerData> items;
  final bool isCurrentMonth;
  final VoidCallback onTapDay;

  const _DayCell({
    required this.date,
    required this.items,
    required this.isCurrentMonth,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _isSameDay(date, DateTime.now());
    return GestureDetector(
      onTap: onTapDay,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        margin: const EdgeInsets.only(right: 2, bottom: 2),
        decoration: BoxDecoration(
          color: isToday ? AppColors.primaryLight.withOpacity(0.3) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: AppColors.customerRed, width: 1) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isCurrentMonth ? (isToday ? AppColors.customerRed : AppColors.textPrimary) : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 2),
              ...items.take(_maxDisplay).map((c) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: Text(
                      '${c.customerName}(${c.productType})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF333333)),
                    ),
                  )),
              if (items.length > _maxDisplay)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
                  child: Text(
                    '+${items.length - _maxDisplay}개',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.customerRed),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// 특정 일자 약정만료 고객 목록 (약정만료 예정 메뉴 형태)
class ExpiryDayListScreen extends StatelessWidget {
  final DateTime date;
  final List<CustomerData> customers;

  const ExpiryDayListScreen({super.key, required this.date, required this.customers});

  static String _dateTitle(DateTime d) {
    return '${d.year}년 ${d.month}월 ${d.day}일 약정만료 예정';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text(_dateTitle(date), style: const TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                '약정만료 예정 고객 ${customers.length}건',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              ),
            ),
            Expanded(
              child: customers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text('해당 일자 약정만료 예정 고객이 없습니다', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: customers.length,
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CustomerCard(
                            customer: customer,
                            isFavorite: false,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => CustomerDetailScreen(
                                    customer: customer,
                                    onFavoriteChanged: () {},
                                  ),
                                ),
                              );
                            },
                            onFavoriteToggle: () {},
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
