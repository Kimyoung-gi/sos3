import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/customer_repository.dart';
import '../../utils/customer_converter.dart';
import '../../main.dart' show CustomerData, CustomerDetailScreen;
import '../../services/auth_service.dart';
import '../../services/csv_service.dart';
import '../../services/csv_reload_bus.dart';
import '../../utils/csv_parser_extended.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../widgets/customer_card.dart';

/// 고객사 리스트 페이지 (전면 개편)
class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  List<CustomerData> _originalList = [];
  List<CustomerData> _filteredList = [];
  
  final TextEditingController _searchController = TextEditingController();
  String? _selectedHq;
  bool _isLoading = true;
  String? _errorMessage;
  
  // 검색 debounce
  Timer? _searchDebounceTimer;
  
  // CSV 재로드 이벤트 구독
  StreamSubscription<String>? _csvReloadSubscription;
  Timer? _reloadDebounceTimer;
  bool _isReloading = false;
  bool _isInitialLoad = true;
  
  // 본부 리스트
  static const List<String> _hqList = ['전체', '강북', '강남', '강서', '동부', '서부'];
  
  // 즐겨찾기 상태 관리 (MainNavigationScreen에서 가져옴)
  Set<String> _favoriteKeys = {};
  // 탭: 0 = 검색(전체), 1 = 즐겨찾기만
  int _selectedTabIndex = 0;
  // 고객별 최근 영업활동 (customerKey -> 최근 활동 내용)
  Map<String, String> _recentActivities = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _loadCustomers();
    _searchController.addListener(_onSearchChanged);
    _setupCsvReloadListener();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _reloadDebounceTimer?.cancel();
    _csvReloadSubscription?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// 즐겨찾기 로드
  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? keys = prefs.getStringList('favorite_customer_keys');
      if (keys != null) {
        setState(() {
          _favoriteKeys = keys.toSet();
        });
      }
    } catch (e) {
      debugPrint('즐겨찾기 로드 오류: $e');
    }
  }

  /// 즐겨찾기 토글
  Future<void> _toggleFavorite(String customerKey) async {
    setState(() {
      if (_favoriteKeys.contains(customerKey)) {
        _favoriteKeys.remove(customerKey);
      } else {
        _favoriteKeys.add(customerKey);
      }
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_customer_keys', _favoriteKeys.toList());
    } catch (e) {
      debugPrint('즐겨찾기 저장 오류: $e');
    }
    
    // 필터링 다시 적용 (즐겨찾기 정렬 반영)
    _applyFilters();
  }

  /// 즐겨찾기 상태 확인
  bool _isFavorite(String customerKey) {
    return _favoriteKeys.contains(customerKey);
  }

  /// CSV 재로드 이벤트 구독
  void _setupCsvReloadListener() {
    _csvReloadSubscription = CsvReloadBus().stream.listen((filename) {
      if (_isCustomerFile(filename)) {
        debugPrint('[고객사] 고객사 파일 재로드 이벤트 수신: $filename');
        _handleCsvReload(filename);
      }
    });
  }

  /// CSV 재로드 처리 (고객사 등록 후 목록 갱신용 — 지연 없이 즉시 새로고침)
  void _handleCsvReload(String filename) {
    _reloadDebounceTimer?.cancel();
    if (_isInitialLoad) return;
    if (_isReloading || _isLoading) {
      _reloadDebounceTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _loadCustomers();
      });
      return;
    }
    _loadCustomers();
  }

  /// 고객사 파일인지 확인
  bool _isCustomerFile(String filename) {
    return filename.contains('customerlist') || filename.contains('고객사');
  }

  /// 고객 데이터 로드
  Future<void> _loadCustomers() async {
    if (!_isInitialLoad && (_isReloading || _isLoading)) {
      return;
    }
    
    try {
      setState(() {
        _isReloading = true;
        _isLoading = true;
      });
      
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final currentUser = authService.currentUser;
      
      // 초기 로딩 시에만 CSV 로드 (merge 사용: 고객사 등록으로 추가한 데이터가 유지되도록)
      if (_isInitialLoad) {
        try {
          final csvText = await CsvService.load('customerlist.csv');
          if (csvText.isNotEmpty) {
            final rows = CsvParserExtended.parseCustomerBase(csvText);
            final validCustomers = rows.where((r) => r.data != null).map((r) => r.data!).toList();
            if (validCustomers.isNotEmpty) {
              await customerRepo.mergeFromCsv(validCustomers, updateOnDuplicate: true);
            }
          }
        } catch (e) {
          debugPrint('⚠️ customerlist.csv 로드 실패 (무시): $e');
        }
      }
      
      // RBAC 필터링된 고객 목록 가져오기
      final customers = await customerRepo.getFiltered(currentUser);
      
      // Customer -> CustomerData 변환
      final customerDataList = CustomerConverter.toCustomerDataList(customers);
      
      // 즐겨찾기 상태 적용
      final customersWithFavorites = customerDataList.map((c) {
        c.isFavorite = _isFavorite(c.customerKey);
        return c;
      }).toList();
      
      if (mounted) {
        setState(() {
          _originalList = customersWithFavorites;
          _isLoading = false;
          _isReloading = false;
          _isInitialLoad = false;
          _errorMessage = null;
        });
        _applyFilters();
        _loadRecentActivities();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 데이터 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isReloading = false;
          _isInitialLoad = false;
          _errorMessage = '고객사 데이터를 불러올 수 없습니다: ${e.toString()}';
        });
      }
    }
  }

  /// SharedPreferences에서 고객별 최근 영업활동 로드 (카드에 표시용)
  Future<void> _loadRecentActivities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.endsWith('_sales_activities'));
      final Map<String, String> map = {};
      for (final key in keys) {
        final customerKey = key.replaceFirst(RegExp(r'_sales_activities$'), '');
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw) as List<dynamic>?;
          if (decoded == null || decoded.isEmpty) continue;
          // createdAt 기준 최신 항목의 text
          String? latestText;
          DateTime? latestAt;
          for (final e in decoded) {
            if (e is! Map<String, dynamic>) continue;
            final text = e['text'] as String? ?? '';
            final createdAt = e['createdAt'];
            DateTime? at;
            if (createdAt is String) at = DateTime.tryParse(createdAt);
            if (at != null && (latestAt == null || at.isAfter(latestAt))) {
              latestAt = at;
              latestText = text;
            }
          }
          if (latestText != null && latestText.trim().isNotEmpty) {
            map[customerKey] = latestText.trim();
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _recentActivities = map);
    } catch (e) {
      debugPrint('최근 영업활동 로드 오류: $e');
    }
  }

  /// 검색어 변경 핸들러 (debounce)
  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _applyFilters();
    });
  }

  /// 필터 적용
  void _applyFilters() {
    final searchQuery = _searchController.text.trim().toLowerCase();
    final selectedHq = _selectedHq;
    
    List<CustomerData> filtered = List.from(_originalList);
    
    // 검색어 필터
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((customer) {
        final matchesName = customer.customerName.toLowerCase().contains(searchQuery);
        final matchesProductName = customer.productName.toLowerCase().contains(searchQuery);
        final matchesProductType = customer.productType.toLowerCase().contains(searchQuery);
        final matchesPersonInCharge = customer.personInCharge.toLowerCase().contains(searchQuery);
        return matchesName || matchesProductName || matchesProductType || matchesPersonInCharge;
      }).toList();
    }
    
    // 본부 필터
    if (selectedHq != null && selectedHq != '전체') {
      filtered = filtered.where((customer) {
        final hqPrefix = customer.hq.length >= 2 ? customer.hq.substring(0, 2) : customer.hq;
        return hqPrefix == selectedHq;
      }).toList();
    }
    
    setState(() {
      _filteredList = filtered;
    });
  }

  /// 고객 상세 화면으로 이동
  void _navigateToDetail(CustomerData customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerDetailScreen(
          customer: customer,
          onFavoriteChanged: () {
            _loadFavorites();
            _applyFilters();
          },
        ),
      ),
    ).then((_) {
      // 상세 화면에서 돌아올 때 즐겨찾기·최근 영업활동 갱신
      _loadFavorites();
      _applyFilters();
      _loadRecentActivities();
    });
  }

  /// 탭에 따라 표시할 리스트 (검색=전체, 즐겨찾기=즐겨찾기만)
  List<CustomerData> get _listForDisplay {
    if (_selectedTabIndex == 1) {
      return _filteredList.where((c) => _isFavorite(c.customerKey)).toList();
    }
    return _filteredList;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 1,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business_rounded, color: AppColors.textPrimary, size: 20),
              const SizedBox(width: 6),
              Text('고객사', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
        ),
        leadingWidth: 90,
        centerTitle: true,
        title: Image.asset(
          'assets/images/sos_logo.png',
          height: 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        actions: const [SizedBox(width: 90)],
      ),
      body: Column(
        children: [
          // 검색바 (시안: 화이트, radius 12~16, 그림자, 높이 48~52, 좌 검색 우 필터)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 12, AppDimens.pagePadding, 8),
            child: Container(
              height: AppDimens.searchBarHeight,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '고객명 또는 담당자 검색',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 22),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          // 탭: DB검색 | 즐겨찾기 (열 꽉 채움)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
            child: Row(
              children: [
                Expanded(
                  child: _TabSegment(
                    label: 'DB검색',
                    isSelected: _selectedTabIndex == 0,
                    onTap: () => setState(() => _selectedTabIndex = 0),
                  ),
                ),
                Expanded(
                  child: _TabSegment(
                    label: '즐겨찾기',
                    isSelected: _selectedTabIndex == 1,
                    onTap: () => setState(() => _selectedTabIndex = 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 본부 필터 Pills (시안: 선택 red bg white text, 미선택 light grey bg dark grey, radius 20)
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
              itemCount: _hqList.length,
              itemBuilder: (context, index) {
                final hq = _hqList[index];
                final isSelected = (hq == '전체' && _selectedHq == null) || _selectedHq == hq;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: isSelected ? AppColors.pillSelectedBg : AppColors.pillUnselectedBg,
                    borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedHq = hq == '전체' ? null : hq;
                        });
                        _applyFilters();
                      },
                      borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Center(
                          child: Text(
                            hq,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? Colors.white : AppColors.pillUnselectedText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // 고객 리스트
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: TextStyle(color: AppColors.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadCustomers,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      )
                    : _listForDisplay.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: AppColors.textSecondary),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedTabIndex == 1
                                      ? '즐겨찾기한 고객이 없습니다'
                                      : '검색 결과가 없습니다',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.pagePadding,
                              vertical: 8,
                            ),
                            itemCount: _listForDisplay.length,
                            itemBuilder: (context, index) {
                              final customer = _listForDisplay[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: AppDimens.cardSpacing),
                                child: CustomerCard(
                                  customer: customer,
                                  isFavorite: _isFavorite(customer.customerKey),
                                  onTap: () => _navigateToDetail(customer),
                                  onFavoriteToggle: () => _toggleFavorite(customer.customerKey),
                                  recentActivity: _recentActivities[customer.customerKey],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// 상단 탭 세그먼트 (DB검색 | 즐겨찾기, 열 꽉 채움)
class _TabSegment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabSegment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.customerRed : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 3,
            width: double.infinity,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.customerRed : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}
