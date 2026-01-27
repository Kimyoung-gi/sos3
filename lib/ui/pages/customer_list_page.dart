import 'dart:async';
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
import '../widgets/customer_card.dart';
import 'customer_register_page.dart';

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

  /// CSV 재로드 처리
  void _handleCsvReload(String filename) {
    if (_isInitialLoad || _isReloading || _isLoading) {
      return;
    }
    
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isReloading && !_isLoading && !_isInitialLoad) {
        _loadCustomers();
      }
    });
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
      
      // 초기 로딩 시에만 CSV 로드
      if (_isInitialLoad) {
        try {
          final csvText = await CsvService.load('customerlist.csv');
          if (csvText.isNotEmpty) {
            final rows = CsvParserExtended.parseCustomerBase(csvText);
            final validCustomers = rows.where((r) => r.data != null).map((r) => r.data!).toList();
            if (validCustomers.isNotEmpty) {
              await customerRepo.replaceFromCsv(validCustomers);
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
        return matchesName || matchesProductName || matchesProductType;
      }).toList();
    }
    
    // 본부 필터
    if (selectedHq != null && selectedHq != '전체') {
      filtered = filtered.where((customer) {
        final hqPrefix = customer.hq.length >= 2 ? customer.hq.substring(0, 2) : customer.hq;
        return hqPrefix == selectedHq;
      }).toList();
    }
    
    // 즐겨찾기 상단 고정 정렬
    filtered.sort((a, b) {
      final aIsFavorite = _isFavorite(a.customerKey);
      final bIsFavorite = _isFavorite(b.customerKey);
      if (aIsFavorite != bIsFavorite) {
        return bIsFavorite ? 1 : -1; // 즐겨찾기 먼저
      }
      // 같은 그룹 내에서는 고객사명 오름차순
      return a.customerName.compareTo(b.customerName);
    });
    
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
      // 상세 화면에서 돌아올 때 즐겨찾기 상태 갱신
      _loadFavorites();
      _applyFilters();
    });
  }

  /// 고객사 등록 페이지로 이동
  Future<void> _navigateToRegister() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CustomerRegisterPage(),
      ),
    );
    
    // 등록 완료 시 리스트 리로드
    if (result != null || mounted) {
      _loadCustomers();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF1A1A1A)),
          onPressed: () {
            // 햄버거 메뉴 (필요시 구현)
          },
        ),
        title: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/images/sos_logo.png',
            height: 28,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _navigateToRegister,
            icon: const Icon(Icons.add, color: Color(0xFFFF6F61), size: 20),
            label: const Text(
              '고객사 등록',
              style: TextStyle(
                color: Color(0xFFFF6F61),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 검색바
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '고객명 또는 상품명 검색',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFFF6F61), width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          // 본부 필터 Chips
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _hqList.length,
              itemBuilder: (context, index) {
                final hq = _hqList[index];
                final isSelected = (hq == '전체' && _selectedHq == null) || _selectedHq == hq;
                
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(hq),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedHq = hq == '전체' ? null : hq;
                      });
                      _applyFilters();
                    },
                    selectedColor: const Color(0xFFFF6F61).withOpacity(0.2),
                    checkmarkColor: const Color(0xFFFF6F61),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFFFF6F61) : Colors.grey[700],
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFFFF6F61) : Colors.grey[300]!,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                );
              },
            ),
          ),
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
                              style: TextStyle(color: Colors.grey[600]),
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
                    : _filteredList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  '검색 결과가 없습니다',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _filteredList.length,
                            itemBuilder: (context, index) {
                              final customer = _filteredList[index];
                              return CustomerCard(
                                customer: customer,
                                isFavorite: _isFavorite(customer.customerKey),
                                onTap: () => _navigateToDetail(customer),
                                onFavoriteToggle: () => _toggleFavorite(customer.customerKey),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
