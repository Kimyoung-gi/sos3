// pubspec.yaml에 다음 패키지 추가 필요:
// dependencies:
//   shared_preferences: ^2.2.3
//   webview_flutter: ^4.4.2 (또는 ^4.7.0 권장)
//   url_launcher: ^6.2.4 (외부 브라우저 열기용, 선택사항)
//
// pubspec.yaml assets 섹션에 다음 CSV 파일들 추가 필요:
//   - assets/kpi_info.csv
//   - assets/kpi_rank.csv
//   - assets/kpi_mobile.csv
//   - assets/kpi_it.csv
//   - assets/kpi_itr.csv
//   - assets/kpi_etc.csv

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
// [WEB] 웹에서는 webview_flutter를 사용하지 않음 - 조건부 import
import 'package:webview_flutter/webview_flutter.dart' if (dart.library.io) 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'dart:async';

// [AUTH] 인증/저장소 import
import 'services/auth_service.dart';
import 'services/csv_service.dart';
import 'services/csv_reload_bus.dart';
import 'models/user.dart';
import 'repositories/user_repository.dart';
import 'repositories/customer_repository.dart';
import 'repositories/sales_status_repository.dart';
import 'repositories/performance_repository.dart';
import 'repositories/upload_history_repository.dart';
import 'utils/customer_converter.dart';
import 'utils/csv_parser_extended.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/admin_login_page.dart';
import 'ui/pages/admin_home_page.dart';

void main() async {
  // Flutter 바인딩 초기화 (필수)
  WidgetsFlutterBinding.ensureInitialized();
  
  // [FIREBASE] Firebase 초기화 (필수)
  // flutterfire configure로 생성된 firebase_options.dart 사용
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase 초기화 완료');
  } catch (e, stackTrace) {
    debugPrint('❌ Firebase 초기화 실패: $e');
    debugPrint('스택 트레이스: $stackTrace');
    // Firebase 초기화 실패 시에도 앱은 계속 실행 (assets fallback 사용)
    // 하지만 Firebase 기능(Storage, Firestore 등)은 사용할 수 없음
  }
  
  // [AUTH] 서비스 초기화
  final authService = AuthService();
  await authService.init();
  
  // [CSV] Firebase Storage 연동 테스트 (선택)
  try {
    final testCsv = await CsvService.load('customerlist.csv');
    debugPrint('✅ CSV 로딩 테스트 성공: customerlist.csv (${testCsv.length} bytes)');
  } catch (e) {
    debugPrint('⚠️ CSV 로딩 테스트 실패 (앱은 계속 실행): $e');
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        Provider.value(value: UserRepository()),
        Provider.value(value: CustomerRepository()),
        Provider.value(value: SalesStatusRepository()),
        Provider.value(value: PerformanceRepository()),
        Provider.value(value: UploadHistoryRepository()),
      ],
      child: const SOSApp(),
    ),
  );
}

// ========================================
// [WEB] CSV 파일 로드 유틸리티
// ========================================
// 웹에서는 파일 선택, 모바일에서는 assets에서 로드
Future<String?> _loadCsvFile(String fileName) async {
  if (kIsWeb) {
    // [WEB] 웹에서는 파일 선택 다이얼로그 표시
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'CSV 파일 선택: $fileName',
      );
      
      if (result != null && result.files.single.path != null) {
        // 웹에서는 bytes를 읽어서 문자열로 변환
        if (result.files.single.bytes != null) {
          return String.fromCharCodes(result.files.single.bytes!);
        } else if (result.files.single.path != null) {
          // 플랫폼별 파일 읽기
          final file = result.files.single;
          if (file.bytes != null) {
            return String.fromCharCodes(file.bytes!);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('파일 선택 오류: $e');
      return null;
    }
  } else {
    // 모바일에서는 assets에서 로드
    try {
      return await rootBundle.loadString('assets/$fileName');
    } catch (e) {
      debugPrint('Assets 로드 오류: $e');
      return null;
    }
  }
}

// ========================================
// [WEB] go_router 설정 (인증 가드 포함)
// ========================================
GoRouter createRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final isLoggedIn = authService.isLoggedIn;
      final isAdmin = authService.isAdmin;
      final path = state.uri.path;
      
      // 로그인 페이지는 로그인 안 된 경우만
      if (path == '/' || path == '/admin-login') {
        if (isLoggedIn) {
          return isAdmin ? '/admin' : '/main';
        }
        return null;
      }
      
      // 보호된 경로: 로그인 필요
      if (path.startsWith('/main') || path.startsWith('/admin')) {
        if (!isLoggedIn) return '/';
        if (path.startsWith('/admin') && !isAdmin) return '/main';
      }
      
      return null;
    },
    refreshListenable: authService,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/admin-login',
        builder: (context, state) => const AdminLoginPage(),
      ),
      GoRoute(
        path: '/main',
        builder: (context, state) => const MainNavigationScreen(),
      ),
      GoRoute(
        path: '/main/:tab',
        builder: (context, state) {
          final tab = state.pathParameters['tab'] ?? '0';
          return MainNavigationScreen(initialTab: int.tryParse(tab) ?? 0);
        },
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomePage(),
      ),
    ],
  );
}

// ========================================
// 앱 루트 위젯 - 테마 컬러 정의
// ========================================
class SOSApp extends StatelessWidget {
  const SOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    return MaterialApp.router(
      title: 'SOS 2.0',
      debugShowCheckedModeBanner: false,
      // 화이트/아이보리 기반 밝은 테마 설정
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: const Color(0xFFFF6F61), // 코랄/연핑크 포인트 컬러
          secondary: const Color(0xFFFF8A80),
          surface: Colors.white,
          onSurface: const Color(0xFF1A1A1A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA), // 밝은 회색 배경
        cardColor: Colors.white,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      routerConfig: createRouter(authService),
    );
  }
}

// [REMOVED] 스플래시 화면 제거됨 - 웹에서는 로그인 페이지로 바로 이동

// ========================================
// 하단 네비게이션 바 구조 (5개 탭)
// ========================================
class MainNavigationScreen extends StatefulWidget {
  final int initialTab;
  
  const MainNavigationScreen({super.key, this.initialTab = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex; // 최초 진입은 고객사 탭
  
  // [FAV] 즐겨찾기 상태 관리
  Set<String> _favoriteCustomerKeys = {};
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    _loadFavorites();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // [WEB] URL과 탭 인덱스 동기화
    _syncWithUrl();
  }
  
  // [WEB] URL과 탭 인덱스 동기화
  void _syncWithUrl() {
    final router = GoRouter.of(context);
    final location = router.routerDelegate.currentConfiguration.uri.path;
    if (location.startsWith('/main/')) {
      final tabStr = location.split('/').last;
      final tab = int.tryParse(tabStr);
      if (tab != null && tab >= 0 && tab <= 5 && tab != _currentIndex) {
        setState(() {
          _currentIndex = tab;
        });
      }
    } else if (location == '/main' && _currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
    }
  }
  
  // [FAV] 즐겨찾기 로컬저장 - 로드
  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? keys = prefs.getStringList('favorite_customer_keys');
      if (keys != null) {
        setState(() {
          _favoriteCustomerKeys = keys.toSet();
        });
      }
    } catch (e) {
      debugPrint('즐겨찾기 로드 오류: $e');
    }
  }
  
  // [FAV] 즐겨찾기 토글
  Future<void> toggleFavorite(String customerKey) async {
    setState(() {
      if (_favoriteCustomerKeys.contains(customerKey)) {
        _favoriteCustomerKeys.remove(customerKey);
      } else {
        _favoriteCustomerKeys.add(customerKey);
      }
    });
    await _saveFavorites();
  }
  
  // [FAV] 즐겨찾기 로컬저장 - 저장
  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('favorite_customer_keys', _favoriteCustomerKeys.toList());
    } catch (e) {
      debugPrint('즐겨찾기 저장 오류: $e');
    }
  }
  
  // [FAV] 즐겨찾기 상태 확인
  bool isFavorite(String customerKey) {
    return _favoriteCustomerKeys.contains(customerKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CustomerHqSelectionScreen(), // 고객사
          FrontierHqSelectionScreen(), // 프론티어
          DashboardScreen(), // 대시보드
          FavoritesScreen(
            favoriteKeys: _favoriteCustomerKeys,
            onToggleFavorite: toggleFavorite,
            isFavorite: isFavorite,
          ), // [FAV] 즐겨찾기
          ODScreen(), // OD
          MoreScreen(), // 더보기
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
          // [WEB] URL 업데이트
          context.go('/main/$index');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store),
            label: '고객사',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '프론티어',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '대시보드',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: '즐겨찾기',
          ),
          NavigationDestination(
            icon: Icon(Icons.language_outlined),
            selectedIcon: Icon(Icons.language),
            label: 'OD',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_outlined),
            selectedIcon: Icon(Icons.more_horiz),
            label: '더보기',
          ),
        ],
      ),
    );
  }
}

// ========================================
// 고객사 데이터 모델
// ========================================
class CustomerData {
  final String customerName;
  final String openedAt;
  final String productName;
  final String productType;
  final String hq;
  final String branch;
  final String seller;
  final String building;
  bool isFavorite;
  String salesStatus;
  String memo;

  CustomerData({
    required this.customerName,
    required this.openedAt,
    required this.productName,
    required this.productType,
    required this.hq,
    required this.branch,
    required this.seller,
    required this.building,
    this.isFavorite = false,
    this.salesStatus = '영업전',
    this.memo = '',
  });

  // [FAV] 고유 키 생성 (고객사명|개통일자|상품명)
  String get customerKey => '$customerName|$openedAt|$productName';
}

// ========================================
// 고객사 본부 선택 화면
// ========================================
class CustomerHqSelectionScreen extends StatelessWidget {
  const CustomerHqSelectionScreen({super.key});

  static const List<String> _hqList = ['강북', '강남', '강서', '동부', '서부'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: GestureDetector(
          onTap: () {
            // 첫 화면으로 이동 (모든 스택 제거)
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
              (route) => false,
            );
          },
          child: Image.asset(
            'assets/images/sos_logo.png',
            // [FIX] 이미지 비율 유지 및 찌그러짐 방지
            height: 28, // height만 지정하여 원본 비율 유지
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _hqList.length,
                itemBuilder: (context, index) {
                  final hq = _hqList[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => CustomerListByHqScreen(selectedHq: hq),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                hq,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFFF6F61),
                              ),
                            ],
                          ),
                        ),
                      ),
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

// ========================================
// 고객사 리스트 화면 - CSV 로딩 및 검색 로직 (본부별)
// ========================================
class CustomerListByHqScreen extends StatefulWidget {
  final String selectedHq;

  const CustomerListByHqScreen({super.key, required this.selectedHq});

  @override
  State<CustomerListByHqScreen> createState() => _CustomerListByHqScreenState();
}

class _CustomerListByHqScreenState extends State<CustomerListByHqScreen> {
  List<CustomerData> _allCustomers = [];
  List<CustomerData> _filteredCustomers = [];
  final TextEditingController _searchController = TextEditingController();
  String? _selectedSalesStatus;
  bool _isLoading = true;
  String? _errorMessage;
  
  // [CSV_RELOAD] 이벤트 구독 및 debounce
  StreamSubscription<String>? _csvReloadSubscription;
  Timer? _reloadDebounceTimer;
  bool _isReloading = false;
  
  final List<String> _salesStatusOptions = ['영업전', '영업중', '영업실패', '영업성공'];

  @override
  void initState() {
    super.initState();
    _loadCsvData();
    _searchController.addListener(_filterCustomers);
    _setupCsvReloadListener();
  }

  @override
  void dispose() {
    _csvReloadSubscription?.cancel();
    _reloadDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }
  
  // [CSV_RELOAD] CSV 재로드 이벤트 구독 설정
  void _setupCsvReloadListener() {
    _csvReloadSubscription = CsvReloadBus().stream.listen((filename) {
      // 고객사 파일인 경우에만 재로드
      if (isCustomerFile(filename)) {
        debugPrint('[고객사] 고객사 파일 재로드 이벤트 수신: $filename');
        _handleCsvReload(filename);
      }
    });
  }
  
  // [CSV_RELOAD] CSV 재로드 처리 (debounce 300ms)
  void _handleCsvReload(String filename) {
    // 중복 로딩 방지
    if (_isReloading || _isLoading) {
      debugPrint('[고객사] 이미 로딩 중이므로 재로드 건너뜀');
      return;
    }
    
    // debounce: 300ms 대기
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isReloading && !_isLoading) {
        debugPrint('[고객사] CSV 재로드 시작: $filename');
        _loadCsvData();
      }
    });
  }

  // [RBAC] Repository에서 로드 및 권한 필터링
  Future<void> _loadCsvData() async {
    // 중복 로딩 방지
    if (_isReloading || _isLoading) {
      debugPrint('[고객사] 이미 로딩 중이므로 건너뜀');
      return;
    }
    
    try {
      setState(() {
        _isReloading = true;
        _isLoading = true;
      });
      
      debugPrint('고객사 데이터 로딩 시작 (Repository + RBAC)...');
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final currentUser = authService.currentUser;
      
      // [CSV] Firebase Storage에서 customerlist.csv 로드 시도 (없으면 assets fallback)
      try {
        final csvText = await CsvService.load('customerlist.csv');
        if (csvText.isNotEmpty) {
          debugPrint('customerlist.csv 로드 성공, 파싱 시작...');
          final rows = CsvParserExtended.parseCustomerBase(csvText);
          final validCustomers = rows.where((r) => r.data != null).map((r) => r.data!).toList();
          if (validCustomers.isNotEmpty) {
            debugPrint('customerlist.csv에서 ${validCustomers.length}건 파싱, Repository에 교체(REPLACE)...');
            await customerRepo.replaceFromCsv(validCustomers); // 기존 데이터 완전 교체
            debugPrint('customerlist.csv 교체 완료');
          }
        }
      } catch (e) {
        debugPrint('⚠️ customerlist.csv 로드 실패 (무시): $e');
      }
      
      // RBAC 필터링된 고객 목록 가져오기
      final customers = await customerRepo.getFiltered(currentUser);
      final scopeLabel = currentUser?.role == UserRole.admin ? 'ALL' : (currentUser?.scopeLabel ?? '없음');
      debugPrint('RBAC 필터링 후 고객 수: ${customers.length}건 (사용자: ${currentUser?.id ?? "없음"}, 권한: $scopeLabel)');
      
      // 선택된 본부로 필터링 (앞 2글자 기준)
      final filteredCustomers = customers.where((c) {
        final hqTrimmed = c.hq.trim();
        final hqPrefix = hqTrimmed.length >= 2 ? hqTrimmed.substring(0, 2) : hqTrimmed;
        final selectedHqTrimmed = widget.selectedHq.trim();
        return hqPrefix == selectedHqTrimmed;
      }).toList();
      
      // Customer -> CustomerData 변환
      final customerDataList = CustomerConverter.toCustomerDataList(filteredCustomers);
      
      debugPrint('본부 필터링 후: ${customerDataList.length}건');
      if (mounted) {
        setState(() {
          _allCustomers = customerDataList;
          _filteredCustomers = customerDataList;
          _isLoading = false;
          _isReloading = false;
          _errorMessage = null;
        });
        _filterCustomers();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 데이터 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isReloading = false;
          _errorMessage = '고객사 데이터를 불러올 수 없습니다: ${e.toString()}';
        });
      }
    }
  }

  // BOM 제거
  String _removeBOM(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  // CSV 파싱 로직 및 저장값 로드
  Future<List<CustomerData>> _parseCsv(String csvData) async {
    final List<CustomerData> customers = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) {
      debugPrint('⚠️ CSV 파일이 비어있습니다');
      return customers;
    }

    // BOM 제거 및 구분자 감지
    final firstLine = _removeBOM(lines[0]);
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    debugPrint('고객사 CSV 구분자: ${isTabDelimited ? "탭" : "쉼표"}');

    // 헤더 인덱스 찾기
    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    debugPrint('고객사 CSV 헤더: $headers');
    
    final int hqIndex = headers.indexWhere((h) => h.contains('본부'));
    final int branchIndex = headers.indexWhere((h) => h.contains('지사'));
    final int customerNameIndex = headers.indexWhere((h) => h.contains('고객명') || h.contains('고객명'));
    final int openedAtIndex = headers.indexWhere((h) => h.contains('개통일자') || h.contains('개통일'));
    final int productTypeIndex = headers.indexWhere((h) => h.contains('상품유형') || h.contains('유형'));
    final int productNameIndex = headers.indexWhere((h) => h.contains('상품명'));
    final int sellerIndex = headers.indexWhere((h) => h.contains('실판매자') || h.contains('판매자') || h.contains('MATE'));
    final int buildingIndex = headers.indexWhere((h) => h.contains('건물명') || h.contains('건물'));

    debugPrint('고객사 CSV 인덱스 - 본부:$hqIndex, 지사:$branchIndex, 고객명:$customerNameIndex, 개통일자:$openedAtIndex, 상품유형:$productTypeIndex, 상품명:$productNameIndex, 실판매자:$sellerIndex, 건물명:$buildingIndex');

    if (hqIndex == -1 || branchIndex == -1 || customerNameIndex == -1 ||
        openedAtIndex == -1 || productTypeIndex == -1 || productNameIndex == -1 ||
        sellerIndex == -1 || buildingIndex == -1) {
      debugPrint('❌ CSV 헤더가 올바르지 않습니다. 찾은 헤더: $headers');
      debugPrint('❌ 누락된 헤더 - 본부:${hqIndex == -1}, 지사:${branchIndex == -1}, 고객명:${customerNameIndex == -1}, 개통일자:${openedAtIndex == -1}, 상품유형:${productTypeIndex == -1}, 상품명:${productNameIndex == -1}, 실판매자:${sellerIndex == -1}, 건물명:${buildingIndex == -1}');
      return customers;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 데이터 파싱 (1번째 줄부터, 마지막 빈 줄 제외)
    int successCount = 0;
    int errorCount = 0;
    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue; // 빈 줄 무시

      final List<String> values = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();

      // 컬럼 수 확인
      if (values.length < headers.length) {
        debugPrint('컬럼 수 부족: line $i');
        continue;
      }

      try {
        final customer = CustomerData(
          customerName: values[customerNameIndex],
          openedAt: values[openedAtIndex],
          productName: values[productNameIndex],
          productType: values[productTypeIndex],
          hq: values[hqIndex],
          branch: values[branchIndex],
          seller: values[sellerIndex],
          building: values[buildingIndex],
          salesStatus: '영업전',
          memo: '',
        );

        // 저장된 영업상태/메모 로드
        final String? savedStatus = prefs.getString('${customer.customerKey}_status');
        final String? savedMemo = prefs.getString('${customer.customerKey}_memo');
        
        // [FAV] 즐겨찾기 상태 로드
        final List<String>? favoriteKeys = prefs.getStringList('favorite_customer_keys');
        if (favoriteKeys != null && favoriteKeys.contains(customer.customerKey)) {
          customer.isFavorite = true;
        }

        if (savedStatus != null) {
          customer.salesStatus = savedStatus;
        }
        if (savedMemo != null) {
          customer.memo = savedMemo;
        }

        customers.add(customer);
        successCount++;
      } catch (e) {
        errorCount++;
        debugPrint('데이터 파싱 오류: line $i, $e');
        if (errorCount <= 5) {
          debugPrint('  오류 상세: line="$line", values=$values');
        }
        continue;
      }
    }

    debugPrint('고객사 CSV 파싱 결과: 성공 $successCount건, 실패 $errorCount건');
    return customers;
  }

  // [FAV] 즐겨찾기 상태 확인
  bool _isFavorite(String customerKey) {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    return mainState?.isFavorite(customerKey) ?? false;
  }
  
  // [FAV] 즐겨찾기 토글
  void _toggleFavorite(String customerKey) {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    mainState?.toggleFavorite(customerKey).then((_) {
      setState(() {
        _filterCustomers();
      });
    });
  }

  // 필터링 로직 (본부 필터 제거, 이미 선택된 본부로 필터링됨)
  // [FAV] 즐겨찾기 상단 고정 정렬
  void _filterCustomers() {
    final String query = _searchController.text.trim().toLowerCase();
    final bool hasSearchQuery = query.isNotEmpty;
    final bool hasSalesStatusFilter = _selectedSalesStatus != null && _selectedSalesStatus != '전체';

    setState(() {
      final filtered = _allCustomers.where((customer) {
        // 영업상태 필터
        if (hasSalesStatusFilter && customer.salesStatus != _selectedSalesStatus) {
          return false;
        }

        // 검색 필터
        if (hasSearchQuery) {
          final bool matchesName = customer.customerName.toLowerCase().contains(query);
          final bool matchesSeller = customer.seller.toLowerCase().contains(query);
          final bool matchesHq = customer.hq.toLowerCase().contains(query);
          if (!matchesName && !matchesSeller && !matchesHq) {
            return false;
          }
        }

        return true;
      }).toList();
      
      // [FAV] 즐겨찾기 상단 고정 정렬
      filtered.sort((a, b) {
        final aIsFavorite = _isFavorite(a.customerKey);
        final bIsFavorite = _isFavorite(b.customerKey);
        if (aIsFavorite != bIsFavorite) {
          return bIsFavorite ? 1 : -1; // 즐겨찾기 먼저
        }
        // 같은 그룹 내에서는 고객사명 오름차순
        return a.customerName.compareTo(b.customerName);
      });
      
      _filteredCustomers = filtered;
    });
  }

  // 필터 다이얼로그 표시 (본부 필터 제거)
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '필터',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _selectedSalesStatus = null;
                              });
                              setState(() {
                                _selectedSalesStatus = null;
                              });
                              _filterCustomers();
                              Navigator.pop(context);
                            },
                            child: const Text('전체 초기화'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 영업상태 필터
                      const Text(
                        '영업상태',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...[..._salesStatusOptions, '전체'].map((status) {
                        final bool isSelected = _selectedSalesStatus == status || (_selectedSalesStatus == null && status == '전체');
                        return ListTile(
                          dense: true,
                          title: Text(status),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Color(0xFFFF6F61))
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedSalesStatus = status == '전체' ? null : status;
                            });
                            _filterCustomers();
                            Navigator.pop(context);
                          },
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            // 첫 화면으로 이동 (모든 스택 제거)
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
              (route) => false,
            );
          },
          child: Image.asset(
            'assets/images/sos_logo.png',
            // [FIX] 이미지 비율 유지 및 찌그러짐 방지
            height: 28, // height만 지정하여 원본 비율 유지
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.selectedHq} 본부',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 검색 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  // 검색바
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        keyboardType: TextInputType.text,
                        enableInteractiveSelection: true,
                        style: const TextStyle(color: Color(0xFF1A1A1A)),
                        decoration: InputDecoration(
                          hintText: '고객사명, 실판매자 검색',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey[400],
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 필터 아이콘 버튼
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune),
                      color: Colors.grey[700],
                      onPressed: _showFilterDialog,
                    ),
                  ),
                ],
              ),
            ),
            // 필터 표시
            if (_selectedSalesStatus != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (_selectedSalesStatus != null)
                        Chip(
                          label: Text('영업상태: $_selectedSalesStatus'),
                          onDeleted: () {
                            setState(() {
                              _selectedSalesStatus = null;
                            });
                            _filterCustomers();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 리스트 또는 로딩/에러
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _loadCsvData();
                                  },
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredCustomers.isEmpty
                          ? Center(
                              child: Text(
                                '검색 결과가 없습니다',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              itemCount: _filteredCustomers.length,
                              itemBuilder: (context, index) {
                                final customer = _filteredCustomers[index];
                                return _CustomerCard(
                                  customer: customer,
                                  isFavorite: _isFavorite(customer.customerKey),
                                  onFavoriteToggle: () => _toggleFavorite(customer.customerKey),
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CustomerDetailScreen(
                                          customer: customer,
                                          onFavoriteChanged: () {
                                            setState(() {
                                              _filterCustomers();
                                            });
                                          },
                                        ),
                                      ),
                                    );
                                    // 상세 화면에서 돌아올 때 카드 업데이트
                                    setState(() {
                                      _filterCustomers();
                                    });
                                  },
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

// ========================================
// 고객사 리스트 화면 - CSV 로딩 및 검색 로직 (기존, 하위 호환용)
// ========================================
class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  List<CustomerData> _allCustomers = [];
  List<CustomerData> _filteredCustomers = [];
  final TextEditingController _searchController = TextEditingController();
  String? _selectedHq;
  String? _selectedSalesStatus;
  bool _isLoading = true;
  String? _errorMessage;
  
  final List<String> _salesStatusOptions = ['영업전', '영업중', '영업실패', '영업성공'];

  @override
  void initState() {
    super.initState();
    _loadCsvData();
    _searchController.addListener(_filterCustomers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // [RBAC] Repository에서 로드 및 권한 필터링
  Future<void> _loadCsvData() async {
    try {
      debugPrint('고객사 데이터 로딩 시작 (Repository + RBAC)...');
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final currentUser = authService.currentUser;
      
      // [CSV] Firebase Storage에서 customerlist.csv 로드 시도 (없으면 assets fallback)
      try {
        final csvText = await CsvService.load('customerlist.csv');
        if (csvText.isNotEmpty) {
          debugPrint('customerlist.csv 로드 성공, 파싱 시작...');
          final rows = CsvParserExtended.parseCustomerBase(csvText);
          final validCustomers = rows.where((r) => r.data != null).map((r) => r.data!).toList();
          if (validCustomers.isNotEmpty) {
            debugPrint('customerlist.csv에서 ${validCustomers.length}건 파싱, Repository에 교체(REPLACE)...');
            await customerRepo.replaceFromCsv(validCustomers); // 기존 데이터 완전 교체
            debugPrint('customerlist.csv 교체 완료');
          }
        }
      } catch (e) {
        debugPrint('⚠️ customerlist.csv 로드 실패 (무시): $e');
      }
      
      // RBAC 필터링된 고객 목록 가져오기
      final customers = await customerRepo.getFiltered(currentUser);
      final scopeLabel = currentUser?.role == UserRole.admin ? 'ALL' : (currentUser?.scopeLabel ?? '없음');
      debugPrint('RBAC 필터링 후 고객 수: ${customers.length}건 (사용자: ${currentUser?.id ?? "없음"}, 권한: $scopeLabel)');
      
      // Customer -> CustomerData 변환
      final customerDataList = CustomerConverter.toCustomerDataList(customers);
      
      debugPrint('고객사 데이터 로딩 완료: ${customerDataList.length}건');
      setState(() {
        _allCustomers = customerDataList;
        _filteredCustomers = customerDataList;
        _isLoading = false;
        _errorMessage = null;
      });
      _filterCustomers();
    } catch (e, stackTrace) {
      debugPrint('❌ 데이터 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = '고객사 데이터를 불러올 수 없습니다: ${e.toString()}';
      });
    }
  }

  // BOM 제거
  String _removeBOM(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  // CSV 파싱 로직 및 저장값 로드
  Future<List<CustomerData>> _parseCsv(String csvData) async {
    final List<CustomerData> customers = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) {
      debugPrint('⚠️ CSV 파일이 비어있습니다');
      return customers;
    }

    // BOM 제거 및 구분자 감지
    final firstLine = _removeBOM(lines[0]);
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    debugPrint('고객사 CSV 구분자: ${isTabDelimited ? "탭" : "쉼표"}');

    // 헤더 인덱스 찾기
    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    debugPrint('고객사 CSV 헤더: $headers');
    
    final int hqIndex = headers.indexWhere((h) => h.contains('본부'));
    final int branchIndex = headers.indexWhere((h) => h.contains('지사'));
    final int customerNameIndex = headers.indexWhere((h) => h.contains('고객명') || h.contains('고객명'));
    final int openedAtIndex = headers.indexWhere((h) => h.contains('개통일자') || h.contains('개통일'));
    final int productTypeIndex = headers.indexWhere((h) => h.contains('상품유형') || h.contains('유형'));
    final int productNameIndex = headers.indexWhere((h) => h.contains('상품명'));
    final int sellerIndex = headers.indexWhere((h) => h.contains('실판매자') || h.contains('판매자') || h.contains('MATE'));
    final int buildingIndex = headers.indexWhere((h) => h.contains('건물명') || h.contains('건물'));

    debugPrint('고객사 CSV 인덱스 - 본부:$hqIndex, 지사:$branchIndex, 고객명:$customerNameIndex, 개통일자:$openedAtIndex, 상품유형:$productTypeIndex, 상품명:$productNameIndex, 실판매자:$sellerIndex, 건물명:$buildingIndex');

    if (hqIndex == -1 || branchIndex == -1 || customerNameIndex == -1 ||
        openedAtIndex == -1 || productTypeIndex == -1 || productNameIndex == -1 ||
        sellerIndex == -1 || buildingIndex == -1) {
      debugPrint('❌ CSV 헤더가 올바르지 않습니다. 찾은 헤더: $headers');
      debugPrint('❌ 누락된 헤더 - 본부:${hqIndex == -1}, 지사:${branchIndex == -1}, 고객명:${customerNameIndex == -1}, 개통일자:${openedAtIndex == -1}, 상품유형:${productTypeIndex == -1}, 상품명:${productNameIndex == -1}, 실판매자:${sellerIndex == -1}, 건물명:${buildingIndex == -1}');
      return customers;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // 데이터 파싱 (1번째 줄부터, 마지막 빈 줄 제외)
    int successCount = 0;
    int errorCount = 0;
    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue; // 빈 줄 무시

      final List<String> values = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();

      // 컬럼 수 확인
      if (values.length < headers.length) {
        debugPrint('컬럼 수 부족: line $i');
        continue;
      }

      try {
        final customer = CustomerData(
          customerName: values[customerNameIndex],
          openedAt: values[openedAtIndex],
          productName: values[productNameIndex],
          productType: values[productTypeIndex],
          hq: values[hqIndex],
          branch: values[branchIndex],
          seller: values[sellerIndex],
          building: values[buildingIndex],
          salesStatus: '영업전',
          memo: '',
        );

        // 저장된 영업상태/메모 로드
        final String? savedStatus = prefs.getString('${customer.customerKey}_status');
        final String? savedMemo = prefs.getString('${customer.customerKey}_memo');
        
        // [FAV] 즐겨찾기 상태 로드
        final List<String>? favoriteKeys = prefs.getStringList('favorite_customer_keys');
        if (favoriteKeys != null && favoriteKeys.contains(customer.customerKey)) {
          customer.isFavorite = true;
        }

        if (savedStatus != null) {
          customer.salesStatus = savedStatus;
        }
        if (savedMemo != null) {
          customer.memo = savedMemo;
        }

        customers.add(customer);
        successCount++;
      } catch (e) {
        errorCount++;
        debugPrint('데이터 파싱 오류: line $i, $e');
        if (errorCount <= 5) {
          debugPrint('  오류 상세: line="$line", values=$values');
        }
        continue;
      }
    }

    debugPrint('고객사 CSV 파싱 결과: 성공 $successCount건, 실패 $errorCount건');
    return customers;
  }

  // 본부 리스트 추출 (중복 제거)
  List<String> _getHqList() {
    final Set<String> hqSet = _allCustomers.map((c) => c.hq).where((hq) => hq.isNotEmpty).toSet();
    final List<String> hqList = ['전체', ...hqSet.toList()..sort()];
    return hqList;
  }

  // 지사 리스트 추출 (본부 필터 적용)
  List<String> _getBranchList() {
    List<CustomerData> filtered = _allCustomers;
    if (_selectedHq != null && _selectedHq != '전체') {
      filtered = filtered.where((c) => c.hq == _selectedHq).toList();
    }
    final Set<String> branchSet = filtered.map((c) => c.branch).where((b) => b.isNotEmpty).toSet();
    final List<String> branchList = ['전체', ...branchSet.toList()..sort()];
    return branchList;
  }
  
  // [FAV] 즐겨찾기 상태 확인
  bool _isFavorite(String customerKey) {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    return mainState?.isFavorite(customerKey) ?? false;
  }
  
  // [FAV] 즐겨찾기 토글
  void _toggleFavorite(String customerKey) {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    mainState?.toggleFavorite(customerKey).then((_) {
      setState(() {
        _filterCustomers();
      });
    });
  }

  // 필터링 로직
  // [FAV] 즐겨찾기 상단 고정 정렬
  void _filterCustomers() {
    final String query = _searchController.text.trim().toLowerCase();
    final bool hasSearchQuery = query.isNotEmpty;
    final bool hasHqFilter = _selectedHq != null && _selectedHq != '전체';
    final bool hasSalesStatusFilter = _selectedSalesStatus != null && _selectedSalesStatus != '전체';

    setState(() {
      _filteredCustomers = _allCustomers.where((customer) {
        // 본부 필터
        if (hasHqFilter && customer.hq != _selectedHq) {
          return false;
        }

        // 영업상태 필터
        if (hasSalesStatusFilter && customer.salesStatus != _selectedSalesStatus) {
          return false;
        }

        // 검색 필터
        if (hasSearchQuery) {
          final bool matchesName = customer.customerName.toLowerCase().contains(query);
          final bool matchesSeller = customer.seller.toLowerCase().contains(query);
          final bool matchesHq = customer.hq.toLowerCase().contains(query);
          if (!matchesName && !matchesSeller && !matchesHq) {
            return false;
          }
        }

        return true;
      }).toList();
      
      // [FAV] 즐겨찾기 상단 고정 정렬
      _filteredCustomers.sort((a, b) {
        final aIsFavorite = _isFavorite(a.customerKey);
        final bIsFavorite = _isFavorite(b.customerKey);
        if (aIsFavorite != bIsFavorite) {
          return bIsFavorite ? 1 : -1; // 즐겨찾기 먼저
        }
        // 같은 그룹 내에서는 고객사명 오름차순
        return a.customerName.compareTo(b.customerName);
      });
    });
  }

  // 필터 다이얼로그 표시
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '필터',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _selectedHq = null;
                                _selectedSalesStatus = null;
                              });
                              setState(() {
                                _selectedHq = null;
                                _selectedSalesStatus = null;
                              });
                              _filterCustomers();
                              Navigator.pop(context);
                            },
                            child: const Text('전체 초기화'),
                          ),
                        ],
                      ),
                  const SizedBox(height: 16),
                  // 본부 필터
                  const Text(
                    '본부',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._getHqList().map((hq) {
                    final bool isSelected = _selectedHq == hq || (_selectedHq == null && hq == '전체');
                    return ListTile(
                      dense: true,
                      title: Text(hq),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFFFF6F61))
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedHq = hq == '전체' ? null : hq;
                        });
                        _filterCustomers();
                        Navigator.pop(context);
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                  // 영업상태 필터
                  const Text(
                    '영업상태',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...[..._salesStatusOptions, '전체'].map((status) {
                    final bool isSelected = _selectedSalesStatus == status || (_selectedSalesStatus == null && status == '전체');
                    return ListTile(
                      dense: true,
                      title: Text(status),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFFFF6F61))
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedSalesStatus = status == '전체' ? null : status;
                        });
                        _filterCustomers();
                        Navigator.pop(context);
                      },
                    );
                  }),
                  const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Image.asset(
          'assets/images/sos_logo.png',
          // [FIX] 이미지 비율 유지 및 찌그러짐 방지
          height: 28, // height만 지정하여 원본 비율 유지
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 검색 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  // 검색바
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        keyboardType: TextInputType.text,
                        enableInteractiveSelection: true,
                        style: const TextStyle(color: Color(0xFF1A1A1A)),
                        decoration: InputDecoration(
                          hintText: '고객사명, 실판매자, 본부 검색',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey[400],
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 필터 아이콘 버튼
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune),
                      color: Colors.grey[700],
                      onPressed: _showFilterDialog,
                    ),
                  ),
                ],
              ),
            ),
            // 필터 표시
            if (_selectedHq != null || _selectedSalesStatus != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (_selectedHq != null)
                        Chip(
                          label: Text('본부: $_selectedHq'),
                          onDeleted: () {
                            setState(() {
                              _selectedHq = null;
                            });
                            _filterCustomers();
                          },
                        ),
                      if (_selectedSalesStatus != null)
                        Chip(
                          label: Text('영업상태: $_selectedSalesStatus'),
                          onDeleted: () {
                            setState(() {
                              _selectedSalesStatus = null;
                            });
                            _filterCustomers();
                          },
                        ),
                    ],
                  ),
              ),
            ),
            const SizedBox(height: 8),
            // 리스트 또는 로딩/에러
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _loadCsvData();
                                  },
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredCustomers.isEmpty
                  ? Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return _CustomerCard(
                          customer: customer,
                          isFavorite: _isFavorite(customer.customerKey),
                          onFavoriteToggle: () => _toggleFavorite(customer.customerKey),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CustomerDetailScreen(
                                  customer: customer,
                                  onFavoriteChanged: () {
                                    setState(() {
                                      _filterCustomers();
                                    });
                                  },
                                ),
                              ),
                            );
                            // 상세 화면에서 돌아올 때 카드 업데이트
                            setState(() {
                              _filterCustomers();
                            });
                          },
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

// ========================================
// 고객사 카드 위젯 (공통 재사용)
// ========================================
// [FAV] 고객사 리스트 별 아이콘 + 본부 위치 조정
class _CustomerCard extends StatefulWidget {
  final CustomerData customer;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const _CustomerCard({
    required this.customer,
    required this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {

  // 고객사명 10글자 제한
  String _getDisplayName() {
    return widget.customer.customerName.length > 10
        ? widget.customer.customerName.substring(0, 10)
        : widget.customer.customerName;
  }

  // 본부 앞 2글자 추출
  String _getHqShort() {
    return widget.customer.hq.length >= 2 ? widget.customer.hq.substring(0, 2) : widget.customer.hq;
  }

  // 영업상태 색상
  Color _getStatusColor(String status) {
    switch (status) {
      case '영업전':
        return Colors.grey;
      case '영업중':
      return Colors.blue;
      case '영업실패':
        return Colors.red;
      case '영업성공':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showMemoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메모 전체보기'),
        content: SingleChildScrollView(
          child: Text(
            widget.customer.memo.isEmpty ? '(메모 없음)' : widget.customer.memo,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                // [FAV] 첫줄: 고객사명(좌) + 별 아이콘(우)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _getDisplayName(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    // [FAV] 별 아이콘 버튼
                    if (widget.onFavoriteToggle != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // 이벤트 전파 방지 - 카드의 onTap이 실행되지 않도록
                          widget.onFavoriteToggle?.call();
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            widget.isFavorite ? Icons.star : Icons.star_border,
                            color: widget.isFavorite ? const Color(0xFFFF6F61) : Colors.grey[400],
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // [FAV] 둘째줄: 개통일자(좌) + 본부 칩(우) - 본부 위치 조정
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '개통일자: ${widget.customer.openedAt}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6F61).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _getHqShort(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6F61),
                        ),
                      ),
                    ),
                  ],
                ),
                      const SizedBox(height: 4),
                // 셋째줄: 상품유형
                      Text(
                  widget.customer.productType,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                const SizedBox(height: 8),
                // 넷째줄: 영업상태 태그 + 메모 미리보기
                Row(
                  children: [
                Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                        color: _getStatusColor(widget.customer.salesStatus).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                        widget.customer.salesStatus,
                    style: TextStyle(
                      fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(widget.customer.salesStatus),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onLongPress: widget.customer.memo.isNotEmpty
                            ? () => _showMemoDialog(context)
                            : null,
                        child: Text(
                          widget.customer.memo.isEmpty
                              ? '메모 없음'
                              : widget.customer.memo,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (widget.customer.memo.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.fullscreen, size: 18),
                        color: Colors.grey[400],
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showMemoDialog(context),
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

// ========================================
// 고객사 상세 화면 - 단일 스크롤 화면
// ========================================
class CustomerDetailScreen extends StatefulWidget {
  final CustomerData customer;
  final VoidCallback onFavoriteChanged;

  const CustomerDetailScreen({
    super.key,
    required this.customer,
    required this.onFavoriteChanged,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late bool _isFavorite;
  late TextEditingController _memoController;
  final List<String> _salesStatusOptions = ['영업전', '영업중', '영업실패', '영업성공'];
  Timer? _memoDebounceTimer;

  @override
  void initState() {
    super.initState();
    // [FAV] MainNavigationScreen의 즐겨찾기 상태 확인
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    _isFavorite = mainState?.isFavorite(widget.customer.customerKey) ?? false;
    _memoController = TextEditingController(text: widget.customer.memo);
    _memoController.addListener(_onMemoChanged);
  }

  @override
  void dispose() {
    _memoController.removeListener(_onMemoChanged);
    _memoDebounceTimer?.cancel();
    _memoController.dispose();
    super.dispose();
  }

  // [FAV] 즐겨찾기 토글 로직
  void _toggleFavorite() async {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    if (mainState != null) {
      await mainState.toggleFavorite(widget.customer.customerKey);
      setState(() {
        _isFavorite = mainState.isFavorite(widget.customer.customerKey);
      });
      widget.onFavoriteChanged();
    }
  }

  // 메모 변경 시 디바운스 저장
  void _onMemoChanged() {
    widget.customer.memo = _memoController.text;
    _memoDebounceTimer?.cancel();
    _memoDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _saveMemo();
    });
  }

  // 영업상태 저장
  Future<void> _saveSalesStatus() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('${widget.customer.customerKey}_status', widget.customer.salesStatus);
    } catch (e) {
      debugPrint('영업상태 저장 오류: $e');
    }
  }

  // 메모 저장
  Future<void> _saveMemo() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('${widget.customer.customerKey}_memo', widget.customer.memo);
    } catch (e) {
      debugPrint('메모 저장 오류: $e');
    }
  }

  // 영업상태 변경
  void _onSalesStatusChanged(String? value) {
    if (value != null) {
      setState(() {
        widget.customer.salesStatus = value;
      });
      _saveSalesStatus();
    }
  }

  void _showMemoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메모 전체보기'),
        content: SingleChildScrollView(
          child: Text(
            widget.customer.memo.isEmpty ? '(메모 없음)' : widget.customer.memo,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.customer.customerName,
          style: const TextStyle(
            fontSize: 18,
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // 즐겨찾기 토글
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? const Color(0xFFFF6F61) : Colors.grey[400],
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 섹션 1: 고객사 기본 정보
            _InfoCard(
        title: '고객사 기본 정보',
        items: [
                _InfoRow(label: '고객명', value: widget.customer.customerName),
                _InfoRow(label: '개통일자', value: widget.customer.openedAt),
                _InfoRow(label: '상품유형', value: widget.customer.productType),
          _InfoRow(label: '상품명', value: widget.customer.productName),
                if (widget.customer.building.isNotEmpty)
                  _InfoRow(label: '건물명', value: widget.customer.building),
              ],
            ),
            const SizedBox(height: 16),
            // 섹션 2: 판매자 정보
            _InfoCard(
              title: '판매자 정보',
        items: [
                _InfoRow(label: '본부', value: widget.customer.hq),
          _InfoRow(label: '지사', value: widget.customer.branch),
                _InfoRow(label: '실판매자(MATE)', value: widget.customer.seller),
              ],
            ),
            const SizedBox(height: 16),
            // 섹션 3: 영업현황
            _SalesStatusCard(
              salesStatus: widget.customer.salesStatus,
              memo: widget.customer.memo,
              memoController: _memoController,
              salesStatusOptions: _salesStatusOptions,
              onSalesStatusChanged: _onSalesStatusChanged,
              onMemoViewAll: _showMemoDialog,
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================
// 정보 카드 위젯 (섹션 카드 - 공통 재사용)
// ========================================
class _InfoCard extends StatelessWidget {
  final String title;
  final List<_InfoRow> items;

  const _InfoCard({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 섹션 제목
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6F61),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE0E0E0)),
            const SizedBox(height: 16),
            // 정보 행들
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: item,
                )),
          ],
        ),
      ),
    );
  }
}

// ========================================
// 정보 행 위젯 (좌: 라벨 / 우: 값)
// ========================================
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌측 라벨
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 우측 값
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1A1A1A),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ========================================
// 영업현황 카드 위젯
// ========================================
class _SalesStatusCard extends StatelessWidget {
  final String salesStatus;
  final String memo;
  final TextEditingController memoController;
  final List<String> salesStatusOptions;
  final ValueChanged<String?> onSalesStatusChanged;
  final VoidCallback onMemoViewAll;

  const _SalesStatusCard({
    required this.salesStatus,
    required this.memo,
    required this.memoController,
    required this.salesStatusOptions,
    required this.onSalesStatusChanged,
    required this.onMemoViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 섹션 제목
            const Text(
              '영업현황',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6F61),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE0E0E0)),
            const SizedBox(height: 16),
            // 영업상태
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    '영업상태',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<String>(
                    value: salesStatus,
                    isExpanded: true,
                    underline: Container(),
                    items: salesStatusOptions.map((String status) {
                      return DropdownMenuItem<String>(
                        value: status,
                        child: Text(
                          status,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: onSalesStatusChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 메모
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '메모',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (memo.isNotEmpty)
                        TextButton(
                          onPressed: onMemoViewAll,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.only(top: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '전체 보기',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF6F61),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: memoController,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: 5,
                    enableInteractiveSelection: true,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: '영업 메모를 입력하세요',
                      hintStyle: TextStyle(
                        color: Colors.grey[400],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFFF6F61)),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================
// 연월 파싱 유틸리티 함수 (전역)
// ========================================
// [FIX] 연월 파싱 보강 - 다양한 형식 지원
int? parseYearMonthToInt(String raw) {
  final s = raw.trim();

  // 202509
  final m1 = RegExp(r'^(\d{4})(\d{2})$').firstMatch(s);
  if (m1 != null) {
    final y = int.parse(m1.group(1)!);
    final m = int.parse(m1.group(2)!);
    if (m >= 1 && m <= 12) return y * 100 + m;
  }

  // 2025-9 / 2025-09 / 2025.9 / 2025.09
  final m2 = RegExp(r'^(\d{4})[-\.](\d{1,2})$').firstMatch(s);
  if (m2 != null) {
    final y = int.parse(m2.group(1)!);
    final m = int.parse(m2.group(2)!);
    if (m >= 1 && m <= 12) return y * 100 + m;
  }

  // 25년9월 / 25년09월 / 2025년9월 / 2025년09월
  final m3 = RegExp(r'^(\d{2,4})\s*년\s*(\d{1,2})\s*월$').firstMatch(s);
  if (m3 != null) {
    var y = int.parse(m3.group(1)!);
    final m = int.parse(m3.group(2)!);
    if (y < 100) y += 2000;
    if (m >= 1 && m <= 12) return y * 100 + m;
  }

  return null;
}

// ========================================
// 프론티어 데이터 모델
// ========================================
class FrontierData {
  final String name;
  final String position;
  final String hq;
  final String center;
  String grade;
  String? latestYearMonth;
  int? latestRank;
  int? latestPoint;

  FrontierData({
    required this.name,
    required this.position,
    required this.hq,
    required this.center,
    this.grade = '',
    this.latestYearMonth,
    this.latestRank,
    this.latestPoint,
  });
}

// 실적 데이터 모델
class PerformanceData {
  final String name;
  final String yearMonth;
  final String category; // 무선, 유선순신규, 유선약정갱신, 기타상품
  final String? type; // 유형 (예: 인터넷, TV, 모바일, 단말 등)
  final int? target;
  final int? actual;
  final double? achievementRate;
  final int? point;
  final int? rank;

  PerformanceData({
    required this.name,
    required this.yearMonth,
    required this.category,
    this.type,
    this.target,
    this.actual,
    this.achievementRate,
    this.point,
    this.rank,
  });
}

// ========================================
// 프론티어 본부 선택 화면
// ========================================
class FrontierHqSelectionScreen extends StatelessWidget {
  const FrontierHqSelectionScreen({super.key});

  static const List<String> _hqList = ['강북', '강남', '강서', '동부', '서부'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: const Text(
          '프론티어',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _hqList.length,
                itemBuilder: (context, index) {
                  final hq = _hqList[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => FrontierCenterSelectionScreen(selectedHq: hq),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                hq,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFFF6F61),
                              ),
                            ],
                          ),
                        ),
                      ),
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

// ========================================
// 프론티어 센터 선택 화면
// ========================================
class FrontierCenterSelectionScreen extends StatefulWidget {
  final String selectedHq;

  const FrontierCenterSelectionScreen({super.key, required this.selectedHq});

  @override
  State<FrontierCenterSelectionScreen> createState() => _FrontierCenterSelectionScreenState();
}

class _FrontierCenterSelectionScreenState extends State<FrontierCenterSelectionScreen> {
  List<FrontierData> _allFrontiers = [];
  List<String> _centerList = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCsvData();
  }

  // CSV 파일들 로드
  Future<void> _loadCsvData() async {
    try {
      debugPrint('프론티어 CSV 파일 로딩 시작...');
      // [CSV] Firebase Storage에서 CSV 로드 (없으면 assets fallback)
      final String staffCsv = await CsvService.load('kpi-info.csv');
      final List<FrontierData> frontiers = _parseStaffCsv(staffCsv);
      
      // 선택된 본부로 필터링
      final filteredFrontiers = frontiers.where((f) => f.hq == widget.selectedHq).toList();
      
      // 센터 리스트 추출
      final centerSet = filteredFrontiers.map((f) => f.center).where((center) => center.isNotEmpty).toSet();
      final centerList = centerSet.toList()..sort();
      
      setState(() {
        _allFrontiers = filteredFrontiers;
        _centerList = centerList;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e, stackTrace) {
      debugPrint('❌ CSV 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = '프론티어 데이터를 불러올 수 없습니다: ${e.toString()}';
      });
    }
  }

  // 인력정보 CSV 파싱
  List<FrontierData> _parseStaffCsv(String csvData) {
    final List<FrontierData> frontiers = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return frontiers;

    final bool isTabDelimited = lines[0].contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = lines[0].split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int positionIndex = _findHeaderIndex(headers, ['직급', 'position']);
    final int hqIndex = _findHeaderIndex(headers, ['본부', 'hq']);
    final int centerIndex = _findHeaderIndex(headers, ['센터', 'center']);
    final int gradeIndex = _findHeaderIndex(headers, ['등급', 'grade']);

    if (nameIndex == -1) {
      return frontiers;
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) {
        continue;
      }

      try {
        frontiers.add(FrontierData(
          name: values[nameIndex],
          position: positionIndex != -1 ? values[positionIndex] : '',
          hq: hqIndex != -1 ? values[hqIndex] : '',
          center: centerIndex != -1 ? values[centerIndex] : '',
          grade: gradeIndex != -1 ? values[gradeIndex] : '',
        ));
      } catch (e) {
        continue;
      }
    }

    return frontiers;
  }

  int _findHeaderIndex(List<String> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase();
      for (final keyword in keywords) {
        if (header.contains(keyword.toLowerCase())) {
          return i;
        }
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            // 첫 화면으로 이동 (모든 스택 제거)
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
              (route) => false,
            );
          },
          child: Image.asset(
            'assets/images/sos_logo.png',
            // [FIX] 이미지 비율 유지 및 찌그러짐 방지
            height: 28, // height만 지정하여 원본 비율 유지
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.selectedHq} 본부',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '센터를 선택하세요',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.red[700], fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _loadCsvData();
                                  },
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _centerList.isEmpty
                          ? const Center(
                              child: Text(
                                '센터가 없습니다',
                                style: TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _centerList.length,
                              itemBuilder: (context, index) {
                                final center = _centerList[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) => FrontierListByCenterScreen(
                                              selectedHq: widget.selectedHq,
                                              selectedCenter: center,
                                            ),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(20),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              center,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1A1A1A),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.chevron_right,
                                              color: Color(0xFFFF6F61),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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

// ========================================
// 프론티어 리스트 화면 (센터별)
// ========================================
class FrontierListByCenterScreen extends StatefulWidget {
  final String selectedHq;
  final String selectedCenter;

  const FrontierListByCenterScreen({
    super.key,
    required this.selectedHq,
    required this.selectedCenter,
  });

  @override
  State<FrontierListByCenterScreen> createState() => _FrontierListByCenterScreenState();
}

class _FrontierListByCenterScreenState extends State<FrontierListByCenterScreen> {
  List<FrontierData> _allFrontiers = [];
  List<FrontierData> _filteredFrontiers = [];
  final TextEditingController _searchController = TextEditingController();
  String? _selectedGrade;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCsvData();
    _searchController.addListener(_filterFrontiers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // CSV 파일들 로드
  Future<void> _loadCsvData() async {
    try {
      debugPrint('프론티어 CSV 파일 로딩 시작...');
      // [CSV] Firebase Storage에서 CSV 로드 (없으면 assets fallback)
      final csvs = await CsvService.loadMultiple([
        'kpi-info.csv',
        'kpi_mobile.csv',
        'kpi_it.csv',
        'kpi_itr.csv',
        'kpi_etc.csv',
      ]);
      final String staffCsv = csvs['kpi-info.csv'] ?? '';
      final String wirelessCsv = csvs['kpi_mobile.csv'] ?? '';
      final String wiredNewCsv = csvs['kpi_it.csv'] ?? '';
      final String wiredRenewCsv = csvs['kpi_itr.csv'] ?? '';
      final String etcCsv = csvs['kpi_etc.csv'] ?? '';

      final List<FrontierData> frontiers = _parseStaffCsv(staffCsv);
      // 선택된 본부와 센터로 필터링
      final filteredFrontiers = frontiers
          .where((f) => f.hq == widget.selectedHq && f.center == widget.selectedCenter)
          .toList();
      
      final List<PerformanceData> performances = [];
      performances.addAll(_parsePerformanceCsv(wirelessCsv, '무선'));
      performances.addAll(_parsePerformanceCsv(wiredNewCsv, '유선순신규'));
      performances.addAll(_parsePerformanceCsv(wiredRenewCsv, '유선약정갱신'));
      performances.addAll(_parsePerformanceCsv(etcCsv, '기타상품'));

      // 최근 연월 기준 등급/순위/포인트 설정
      _updateFrontiersWithLatestData(filteredFrontiers, performances);

      setState(() {
        _allFrontiers = filteredFrontiers;
        _filteredFrontiers = filteredFrontiers;
        _isLoading = false;
        _errorMessage = null;
      });
      _filterFrontiers();
    } catch (e, stackTrace) {
      debugPrint('❌ 프론티어 CSV 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = '프론티어 데이터를 불러올 수 없습니다: ${e.toString()}';
      });
    }
  }

  // 인력정보 CSV 파싱
  List<FrontierData> _parseStaffCsv(String csvData) {
    final List<FrontierData> frontiers = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return frontiers;

    final bool isTabDelimited = lines[0].contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = lines[0].split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int positionIndex = _findHeaderIndex(headers, ['직급', 'position']);
    final int hqIndex = _findHeaderIndex(headers, ['본부', 'hq']);
    final int centerIndex = _findHeaderIndex(headers, ['센터', 'center']);
    final int gradeIndex = _findHeaderIndex(headers, ['등급', 'grade']);

    if (nameIndex == -1) {
      return frontiers;
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) {
        continue;
      }

      try {
        frontiers.add(FrontierData(
          name: values[nameIndex],
          position: positionIndex != -1 ? values[positionIndex] : '',
          hq: hqIndex != -1 ? values[hqIndex] : '',
          center: centerIndex != -1 ? values[centerIndex] : '',
          grade: gradeIndex != -1 ? values[gradeIndex] : '',
        ));
      } catch (e) {
        continue;
      }
    }

    return frontiers;
  }

  int _findHeaderIndex(List<String> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase();
      for (final keyword in keywords) {
        if (header.contains(keyword.toLowerCase())) {
          return i;
        }
      }
    }
    return -1;
  }

  // 실적 CSV 파싱
  List<PerformanceData> _parsePerformanceCsv(String csvData, String category) {
    final List<PerformanceData> performances = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return performances;

    final bool isTabDelimited = lines[0].contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = lines[0].split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int yearMonthIndex = _findHeaderIndex(headers, ['연월', '기준연월', 'yearMonth', 'YYYYMM']);
    final int typeIndex = _findHeaderIndex(headers, ['유형', 'type']);
    final int actualIndex = _findHeaderIndex(headers, ['실적', 'actual', '달성']);

    if (nameIndex == -1 || yearMonthIndex == -1 || actualIndex == -1) {
      return performances;
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) {
        continue;
      }

      try {
        performances.add(PerformanceData(
          name: values[nameIndex],
          yearMonth: values[yearMonthIndex],
          category: category,
          type: typeIndex != -1 ? values[typeIndex] : null,
          actual: actualIndex != -1 ? int.tryParse(values[actualIndex]) : null,
        ));
      } catch (e) {
        continue;
      }
    }

    return performances;
  }

  // 최근 연월 기준 데이터 업데이트
  void _updateFrontiersWithLatestData(List<FrontierData> frontiers, List<PerformanceData> performances) {
    for (final frontier in frontiers) {
      final yearMonths = performances
          .where((p) => p.name == frontier.name)
          .map((p) => p.yearMonth)
          .toSet()
          .toList();

      if (yearMonths.isEmpty) continue;

      String? latestYearMonth;
      int maxYearMonth = 0;

      for (final ym in yearMonths) {
        final normalized = ym.replaceAll('-', '');
        final int? yearMonthInt = int.tryParse(normalized);
        if (yearMonthInt != null && yearMonthInt > maxYearMonth) {
          maxYearMonth = yearMonthInt;
          latestYearMonth = ym;
        }
      }

      if (latestYearMonth == null) continue;
      frontier.latestYearMonth = latestYearMonth;
    }
  }

  // 필터링 로직
  void _filterFrontiers() {
    final String query = _searchController.text.trim().toLowerCase();
    final bool hasSearchQuery = query.isNotEmpty;
    final bool hasGradeFilter = _selectedGrade != null && _selectedGrade != '전체';

    setState(() {
      _filteredFrontiers = _allFrontiers.where((frontier) {
        // 등급 필터
        if (hasGradeFilter && frontier.grade != _selectedGrade) {
          return false;
        }

        // 검색 필터
        if (hasSearchQuery) {
          final bool matchesName = frontier.name.toLowerCase().contains(query);
          final bool matchesHq = frontier.hq.toLowerCase().contains(query);
          final bool matchesCenter = frontier.center.toLowerCase().contains(query);
          if (!matchesName && !matchesHq && !matchesCenter) {
            return false;
          }
        }

        return true;
      }).toList();
    });
  }

  // 필터 다이얼로그 표시
  void _showFilterDialog() {
    final gradeSet = _allFrontiers.map((f) => f.grade).where((grade) => grade.isNotEmpty).toSet();
    final gradeList = ['전체', ...gradeSet.toList()..sort()];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '필터',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedGrade = null;
                              });
                              _filterFrontiers();
                              Navigator.pop(context);
                            },
                            child: const Text('전체 초기화'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '등급',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...gradeList.map((grade) {
                        final bool isSelected = _selectedGrade == grade || (_selectedGrade == null && grade == '전체');
                        return ListTile(
                          dense: true,
                          title: Text(grade),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Color(0xFFFF6F61))
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedGrade = grade == '전체' ? null : grade;
                            });
                            _filterFrontiers();
                            Navigator.pop(context);
                          },
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            // 첫 화면으로 이동 (모든 스택 제거)
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
              (route) => false,
            );
          },
          child: Image.asset(
            'assets/images/sos_logo.png',
            // [FIX] 이미지 비율 유지 및 찌그러짐 방지
            height: 28, // height만 지정하여 원본 비율 유지
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.selectedHq} 본부 - ${widget.selectedCenter} 센터',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 검색 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        keyboardType: TextInputType.text,
                        enableInteractiveSelection: true,
                        style: const TextStyle(color: Color(0xFF1A1A1A)),
                        decoration: InputDecoration(
                          hintText: '성명, 본부, 센터 검색',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune),
                      color: Colors.grey[700],
                      onPressed: _showFilterDialog,
                    ),
                  ),
                ],
              ),
            ),
            // 필터 표시
            if (_selectedGrade != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (_selectedGrade != null)
                        Chip(
                          label: Text('등급: $_selectedGrade'),
                          onDeleted: () {
                            setState(() {
                              _selectedGrade = null;
                            });
                            _filterFrontiers();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 리스트 또는 로딩/에러
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.red[700], fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _loadCsvData();
                                  },
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredFrontiers.isEmpty
                          ? Center(
                              child: Text(
                                '검색 결과가 없습니다',
                                style: TextStyle(color: Colors.grey[600], fontSize: 16),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              itemCount: _filteredFrontiers.length,
                              itemBuilder: (context, index) {
                                final frontier = _filteredFrontiers[index];
                                return _FrontierCard(
                                  frontier: frontier,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => FrontierDetailScreen(frontier: frontier),
                                      ),
                                    );
                                  },
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

// ========================================
// 프론티어 화면 - CSV 로딩 및 리스트 (기존, 하위 호환용)
// ========================================
class FrontierScreen extends StatefulWidget {
  const FrontierScreen({super.key});

  @override
  State<FrontierScreen> createState() => _FrontierScreenState();
}

class _FrontierScreenState extends State<FrontierScreen> {
  List<FrontierData> _allFrontiers = [];
  List<FrontierData> _filteredFrontiers = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedHq;
  String? _selectedCenter;
  String? _selectedGrade;

  @override
  void initState() {
    super.initState();
    _loadCsvData();
    _searchController.addListener(_filterFrontiers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // CSV 파일들 로드
  Future<void> _loadCsvData() async {
    try {
      debugPrint('프론티어 CSV 파일 로딩 시작...');
      // [CSV] Firebase Storage에서 CSV 로드 (없으면 assets fallback)
      // [CSV] 병렬 로딩으로 성능 최적화
      final csvResults = await CsvService.loadMultiple([
        'kpi-info.csv',
        'kpi_mobile.csv',
        'kpi_it.csv',
        'kpi_itr.csv',
        'kpi_etc.csv',
      ]);
      
      final String staffCsv = csvResults['kpi-info.csv'] ?? '';
      debugPrint('인력정보 CSV 로딩 완료: ${staffCsv.length}자');
      final String wirelessCsv = csvResults['kpi_mobile.csv'] ?? '';
      debugPrint('무선 CSV 로딩 완료: ${wirelessCsv.length}자');
      final String wiredNewCsv = csvResults['kpi_it.csv'] ?? '';
      debugPrint('유선순신규 CSV 로딩 완료: ${wiredNewCsv.length}자');
      final String wiredRenewCsv = csvResults['kpi_itr.csv'] ?? '';
      debugPrint('유선약정갱신 CSV 로딩 완료: ${wiredRenewCsv.length}자');
      final String etcCsv = csvResults['kpi_etc.csv'] ?? '';
      debugPrint('기타상품 CSV 로딩 완료: ${etcCsv.length}자');

      final List<FrontierData> frontiers = _parseStaffCsv(staffCsv);
      debugPrint('인력정보 파싱 완료: ${frontiers.length}건');
      
      final List<PerformanceData> performances = [];
      performances.addAll(_parsePerformanceCsv(wirelessCsv, '무선'));
      performances.addAll(_parsePerformanceCsv(wiredNewCsv, '유선순신규'));
      performances.addAll(_parsePerformanceCsv(wiredRenewCsv, '유선약정갱신'));
      performances.addAll(_parsePerformanceCsv(etcCsv, '기타상품'));

      debugPrint('전체 실적 데이터: ${performances.length}건');

      // 최근 연월 기준 등급/순위/포인트 설정
      _updateFrontiersWithLatestData(frontiers, performances);

      debugPrint('프론티어 데이터 준비 완료: ${frontiers.length}건');

      setState(() {
        _allFrontiers = frontiers;
        _filteredFrontiers = frontiers;
        _isLoading = false;
        _errorMessage = null;
      });
      _filterFrontiers();
    } catch (e, stackTrace) {
      debugPrint('❌ 프론티어 CSV 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _errorMessage = '프론티어 데이터를 불러올 수 없습니다: ${e.toString()}';
      });
    }
  }

  // 인력정보 CSV 파싱
  List<FrontierData> _parseStaffCsv(String csvData) {
    final List<FrontierData> frontiers = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return frontiers;

    // CSV 구분자 감지 (쉼표 또는 탭)
    final bool isTabDelimited = lines[0].contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = lines[0].split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
    debugPrint('인력정보 CSV 헤더: $headers');
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int positionIndex = _findHeaderIndex(headers, ['직급', 'position']);
    final int hqIndex = _findHeaderIndex(headers, ['본부', 'hq']);
    final int centerIndex = _findHeaderIndex(headers, ['센터', 'center']);
    final int gradeIndex = _findHeaderIndex(headers, ['등급', 'grade']);

    debugPrint('인력정보 인덱스 - 성명:$nameIndex, 직급:$positionIndex, 본부:$hqIndex, 센터:$centerIndex, 등급:$gradeIndex');

    if (nameIndex == -1) {
      debugPrint('인력정보 CSV 헤더가 올바르지 않습니다. 찾은 헤더: $headers');
      return frontiers;
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) {
        debugPrint('컬럼 수 부족: line $i (${values.length}/${headers.length})');
        continue;
      }

      try {
        frontiers.add(FrontierData(
          name: values[nameIndex],
          position: positionIndex != -1 ? values[positionIndex] : '',
          hq: hqIndex != -1 ? values[hqIndex] : '',
          center: centerIndex != -1 ? values[centerIndex] : '',
          grade: gradeIndex != -1 ? values[gradeIndex] : '',
        ));
      } catch (e) {
        debugPrint('인력정보 파싱 오류: line $i, $e');
        continue;
      }
    }

    return frontiers;
  }

  // 실적 CSV 파싱
  List<PerformanceData> _parsePerformanceCsv(String csvData, String category) {
    final List<PerformanceData> performances = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return performances;

    // CSV 구분자 감지 (쉼표 또는 탭)
    final bool isTabDelimited = lines[0].contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = lines[0].split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
    debugPrint('$category CSV 헤더: $headers');
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int yearMonthIndex = _findHeaderIndex(headers, ['연월', '기준연월', 'yearMonth', 'YYYYMM']);
    final int typeIndex = _findHeaderIndex(headers, ['유형', 'type', '상품유형', 'productType', '제품유형']);
    final int targetIndex = _findHeaderIndex(headers, ['목표', 'target']);
    final int actualIndex = _findHeaderIndex(headers, ['실적', 'actual']);
    final int achievementIndex = _findHeaderIndex(headers, ['달성률', 'achievementRate']);
    final int pointIndex = _findHeaderIndex(headers, ['포인트', 'point']);
    final int rankIndex = _findHeaderIndex(headers, ['순위', 'rank']);

    debugPrint('$category 인덱스 - 성명:$nameIndex, 연월:$yearMonthIndex, 유형:$typeIndex, 목표:$targetIndex, 실적:$actualIndex, 포인트:$pointIndex, 순위:$rankIndex');

    if (nameIndex == -1 || yearMonthIndex == -1) {
      debugPrint('$category CSV 헤더가 올바르지 않습니다. 찾은 헤더: $headers');
      return performances;
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) {
        debugPrint('$category 컬럼 수 부족: line $i (${values.length}/${headers.length})');
        continue;
      }

      try {
        final typeValue = typeIndex != -1 && values[typeIndex].trim().isNotEmpty 
            ? values[typeIndex].trim() 
            : null;
        performances.add(PerformanceData(
          name: values[nameIndex],
          yearMonth: values[yearMonthIndex],
          category: category,
          type: typeValue,
          target: targetIndex != -1 ? _parseInt(values[targetIndex]) : null,
          actual: actualIndex != -1 ? _parseInt(values[actualIndex]) : null,
          achievementRate: achievementIndex != -1 ? _parseDouble(values[achievementIndex]) : null,
          point: pointIndex != -1 ? _parseInt(values[pointIndex]) : null,
          rank: rankIndex != -1 ? _parseInt(values[rankIndex]) : null,
        ));
      } catch (e) {
        debugPrint('$category 파싱 오류: line $i, $e');
        continue;
      }
    }
    
    debugPrint('$category 파싱 완료: ${performances.length}건');

    return performances;
  }

  // 헤더 인덱스 찾기 (유연한 매핑)
  int _findHeaderIndex(List<String> headers, List<String> possibleNames) {
    for (final name in possibleNames) {
      // 정확한 매칭 시도
      int index = headers.indexOf(name);
      if (index != -1) return index;
      
      // 공백 제거 후 매칭
      index = headers.indexWhere((h) => h.trim() == name);
      if (index != -1) return index;
      
      // 부분 매칭 (헤더에 name이 포함되는 경우)
      index = headers.indexWhere((h) => h.trim().contains(name) || name.contains(h.trim()));
      if (index != -1) return index;
    }
    return -1;
  }

  int? _parseInt(String value) {
    if (value.isEmpty) return null;
    return int.tryParse(value);
  }

  double? _parseDouble(String value) {
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  // 최근 연월 기준으로 등급/순위/포인트 업데이트
  void _updateFrontiersWithLatestData(
      List<FrontierData> frontiers, List<PerformanceData> performances) {
    for (final frontier in frontiers) {
      // 해당 성명의 모든 연월 찾기
      final Set<String> yearMonths = performances
          .where((p) => p.name == frontier.name)
          .map((p) => p.yearMonth)
          .toSet();

      if (yearMonths.isEmpty) continue;

      // 최근 연월 찾기 (YYYYMM 또는 YYYY-MM 형식)
      String? latestYearMonth;
      int maxYearMonth = 0;

      for (final ym in yearMonths) {
        final normalized = ym.replaceAll('-', '');
        final int? yearMonthInt = int.tryParse(normalized);
        if (yearMonthInt != null && yearMonthInt > maxYearMonth) {
          maxYearMonth = yearMonthInt;
          latestYearMonth = ym;
        }
      }

      if (latestYearMonth == null) continue;

      frontier.latestYearMonth = latestYearMonth;

      // 우선순위: 무선 > 유선순신규 > 유선약정갱신 > 기타상품
      final List<String> priority = [
        '무선',
        '유선순신규',
        '유선약정갱신',
        '기타상품'
      ];

      for (final cat in priority) {
        final perf = performances.firstWhere(
          (p) =>
              p.name == frontier.name &&
              p.yearMonth == latestYearMonth &&
              p.category == cat,
          orElse: () => PerformanceData(
            name: frontier.name,
            yearMonth: latestYearMonth!,
            category: cat,
          ),
        );

        if (perf.point != null || perf.rank != null) {
          frontier.latestPoint = perf.point;
          frontier.latestRank = perf.rank;
          if (perf.point != null || perf.rank != null) break;
        }
      }

      // 등급이 없으면 최근 연월의 등급 사용 (실적 CSV에서)
      if (frontier.grade.isEmpty) {
        for (final cat in priority) {
          final perf = performances.firstWhere(
            (p) =>
                p.name == frontier.name &&
                p.yearMonth == latestYearMonth &&
                p.category == cat,
            orElse: () => PerformanceData(
              name: frontier.name,
              yearMonth: latestYearMonth!,
              category: cat,
            ),
          );
          // 등급은 보통 인력정보에만 있으므로 여기서는 유지
        }
      }
    }
  }

  // 필터링 로직
  void _filterFrontiers() {
    final String query = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredFrontiers = _allFrontiers.where((frontier) {
        // 검색어 필터
        if (query.isNotEmpty) {
          final bool matchesName = frontier.name.toLowerCase().contains(query);
          final bool matchesHq = frontier.hq.toLowerCase().contains(query);
          final bool matchesCenter = frontier.center.toLowerCase().contains(query);
          if (!matchesName && !matchesHq && !matchesCenter) return false;
        }

        // 본부 필터
        if (_selectedHq != null && _selectedHq != '전체') {
          if (frontier.hq != _selectedHq) return false;
        }

        // 센터 필터
        if (_selectedCenter != null && _selectedCenter != '전체') {
          if (frontier.center != _selectedCenter) return false;
        }

        // 등급 필터
        if (_selectedGrade != null && _selectedGrade != '전체') {
          if (frontier.grade != _selectedGrade) return false;
        }

        return true;
      }).toList();

      // 순위 기준 정렬
      _filteredFrontiers.sort((a, b) {
        if (a.latestRank == null && b.latestRank == null) return 0;
        if (a.latestRank == null) return 1;
        if (b.latestRank == null) return -1;
        return a.latestRank!.compareTo(b.latestRank!);
      });
    });
  }

  // 본부 리스트 추출
  List<String> _getHqList() {
    final Set<String> hqSet = _allFrontiers.map((f) => f.hq).where((hq) => hq.isNotEmpty).toSet();
    final List<String> hqList = ['전체', ...hqSet.toList()..sort()];
    return hqList;
  }

  // 센터 리스트 추출
  List<String> _getCenterList() {
    final Set<String> centerSet = _allFrontiers.map((f) => f.center).where((center) => center.isNotEmpty).toSet();
    final List<String> centerList = ['전체', ...centerSet.toList()..sort()];
    return centerList;
  }

  // 등급 리스트 추출
  List<String> _getGradeList() {
    final Set<String> gradeSet = _allFrontiers.map((f) => f.grade).where((grade) => grade.isNotEmpty).toSet();
    final List<String> gradeList = ['전체', ...gradeSet.toList()..sort()];
    return gradeList;
  }

  // 필터 다이얼로그
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '필터',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                _selectedHq = null;
                                _selectedCenter = null;
                                _selectedGrade = null;
                              });
                              setState(() {
                                _selectedHq = null;
                                _selectedCenter = null;
                                _selectedGrade = null;
                              });
                              _filterFrontiers();
                              Navigator.pop(context);
                            },
                            child: const Text('초기화'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // 본부 필터
                      const Text(
                        '본부',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _getHqList().map((hq) {
                          final bool isSelected = _selectedHq == hq || (_selectedHq == null && hq == '전체');
                          return ChoiceChip(
                            label: Text(hq),
                            selected: isSelected,
                            onSelected: (selected) {
                              setModalState(() {
                                _selectedHq = hq == '전체' ? null : hq;
                              });
                            },
                            selectedColor: const Color(0xFFFF6F61).withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: isSelected ? const Color(0xFFFF6F61) : Colors.grey[700],
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      // 센터 필터
                      const Text(
                        '센터',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _getCenterList().map((center) {
                          final bool isSelected = _selectedCenter == center || (_selectedCenter == null && center == '전체');
                          return ChoiceChip(
                            label: Text(center),
                            selected: isSelected,
                            onSelected: (selected) {
                              setModalState(() {
                                _selectedCenter = center == '전체' ? null : center;
                              });
                            },
                            selectedColor: const Color(0xFFFF6F61).withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: isSelected ? const Color(0xFFFF6F61) : Colors.grey[700],
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      // 등급 필터
                      const Text(
                        '등급',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _getGradeList().map((grade) {
                          final bool isSelected = _selectedGrade == grade || (_selectedGrade == null && grade == '전체');
                          return ChoiceChip(
                            label: Text(grade),
                            selected: isSelected,
                            onSelected: (selected) {
                              setModalState(() {
                                _selectedGrade = grade == '전체' ? null : grade;
                              });
                            },
                            selectedColor: const Color(0xFFFF6F61).withOpacity(0.2),
                            labelStyle: TextStyle(
                              color: isSelected ? const Color(0xFFFF6F61) : Colors.grey[700],
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      // 적용 버튼
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {});
                                _filterFrontiers();
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6F61),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                '적용',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '프론티어',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    color: Colors.grey[700],
                    onPressed: () {
                      // 검색 기능은 검색바로 처리
                    },
                  ),
                ],
              ),
            ),
            // 검색 영역
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  // 검색바
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        keyboardType: TextInputType.text,
                        enableInteractiveSelection: true,
                        style: const TextStyle(color: Color(0xFF1A1A1A)),
                        decoration: InputDecoration(
                          hintText: '성명, 본부, 센터 검색',
                          hintStyle: TextStyle(
                            color: Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey[400],
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 필터 아이콘 버튼
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.tune),
                      color: Colors.grey[700],
                      onPressed: _showFilterDialog,
                    ),
                  ),
                ],
              ),
            ),
            // 필터 표시
            if (_selectedHq != null || _selectedCenter != null || _selectedGrade != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (_selectedHq != null)
                        Chip(
                          label: Text('본부: $_selectedHq'),
                          onDeleted: () {
                            setState(() {
                              _selectedHq = null;
                            });
                            _filterFrontiers();
                          },
                        ),
                      if (_selectedCenter != null)
                        Chip(
                          label: Text('센터: $_selectedCenter'),
                          onDeleted: () {
                            setState(() {
                              _selectedCenter = null;
                            });
                            _filterFrontiers();
                          },
                        ),
                      if (_selectedGrade != null)
                        Chip(
                          label: Text('등급: $_selectedGrade'),
                          onDeleted: () {
                            setState(() {
                              _selectedGrade = null;
                            });
                            _filterFrontiers();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // 리스트 또는 로딩/에러
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _loadCsvData();
                                  },
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredFrontiers.isEmpty
                          ? Center(
                              child: Text(
                                '검색 결과가 없습니다',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              itemCount: _filteredFrontiers.length,
                itemBuilder: (context, index) {
                                final frontier = _filteredFrontiers[index];
                                return _FrontierCard(
                                  frontier: frontier,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            FrontierDetailScreen(frontier: frontier),
                                      ),
                                    );
                                  },
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

// 프론티어 카드 위젯
class _FrontierCard extends StatelessWidget {
  final FrontierData frontier;
  final VoidCallback onTap;

  const _FrontierCard({
    required this.frontier,
    required this.onTap,
  });

  // 등급 색상
  Color _getGradeColor(String grade) {
    if (grade.isEmpty) return Colors.grey;
    final firstChar = grade[0].toUpperCase();
    switch (firstChar) {
      case 'A':
        return Colors.green;
      case 'B':
        return Colors.blue;
      case 'C':
        return Colors.grey;
      case 'D':
        return Colors.orange;
      default:
        return Colors.orange;
    }
  }

  // 본부 앞 2글자
  String _getHqShort() {
    return frontier.hq.length >= 2 ? frontier.hq.substring(0, 2) : frontier.hq;
  }

  // 센터 앞 2글자
  String _getCenterShort() {
    return frontier.center.length >= 2
        ? frontier.center.substring(0, 2)
        : frontier.center;
  }

  @override
  Widget build(BuildContext context) {
    final gradeColor = _getGradeColor(frontier.grade);
    final gradeText = frontier.grade.isNotEmpty ? frontier.grade : '-';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
        borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                // 1행: 이름(좌) + 등급 배지(우)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        frontier.position.isNotEmpty 
                            ? '${frontier.name} ${frontier.position}'
                            : frontier.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                          Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                        color: gradeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                              child: Text(
                        gradeText,
                                style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: gradeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 2행: 본부/센터 요약 라인
                Text(
                  '${_getHqShort()} / ${_getCenterShort()} 프론티어',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================
// 프론티어 상세 화면
// ========================================
class FrontierDetailScreen extends StatefulWidget {
  final FrontierData frontier;

  const FrontierDetailScreen({
    super.key,
    required this.frontier,
  });

  @override
  State<FrontierDetailScreen> createState() => _FrontierDetailScreenState();
}

class _FrontierDetailScreenState extends State<FrontierDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<PerformanceData> _allPerformances = [];
  List<Map<String, dynamic>> _pointRankData = []; // 포인트 순위정보 데이터
  String? _selectedYearMonth;
  List<String> _availableYearMonths = [];
  String _selectedPeriod = '3개월';
  String? _workStartDate; // 업무시작일
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPerformanceData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  // 연월 정규화 (YYYYMM 형태로 통일) - 하위 호환성 유지
  String _normalizeYearMonth(String yearMonth) {
    if (yearMonth.isEmpty) return yearMonth;
    final ymInt = parseYearMonthToInt(yearMonth);
    if (ymInt != null) {
      return ymInt.toString();
    }
    return yearMonth;
  }

  // 성명 정규화 (trim, 공백 제거)
  String _normalizeName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), '');
  }

  // BOM 제거
  String _removeBOM(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  Future<void> _loadPerformanceData() async {
    try {
      // 포인트 순위정보 CSV 로드
      try {
        // [FIREBASE] kpi_rank.csv는 현재 CsvFileKey에 없으므로 assets에서 직접 로드 (필요시 추가)
        final String pointRankCsv = await rootBundle.loadString('assets/kpi_rank.csv');
        debugPrint('포인트 순위정보 CSV 원본 길이: ${pointRankCsv.length}자');
        _pointRankData = _parsePointRankCsv(pointRankCsv);
        debugPrint('포인트 순위정보 로드 완료: ${_pointRankData.length}건');
        if (_pointRankData.isEmpty) {
          debugPrint('⚠️ 경고: 포인트 순위정보 데이터가 비어있습니다!');
        }
      } catch (e) {
        debugPrint('❌ 포인트 순위정보 CSV 로드 실패: $e');
        _pointRankData = [];
      }

      // 인력정보에서 업무시작일 로드
      // [CSV] Firebase Storage에서 CSV 로드 (없으면 assets fallback)
      final String staffCsv = await CsvService.load('kpi-info.csv');
      final parsedWorkStartDate = _parseWorkStartDate(staffCsv);
      debugPrint('업무시작일 로드 결과: $parsedWorkStartDate');

      // [CSV] 병렬 로딩으로 성능 최적화
      final csvResults = await CsvService.loadMultiple([
        'kpi_mobile.csv',
        'kpi_it.csv',
        'kpi_itr.csv',
        'kpi_etc.csv',
      ]);
      
      final String wirelessCsv = csvResults['kpi_mobile.csv'] ?? '';
      final String wiredNewCsv = csvResults['kpi_it.csv'] ?? '';
      final String wiredRenewCsv = csvResults['kpi_itr.csv'] ?? '';
      final String etcCsv = csvResults['kpi_etc.csv'] ?? '';

      final List<PerformanceData> performances = [];
      performances.addAll(_parsePerformanceCsv(wirelessCsv, '무선'));
      performances.addAll(_parsePerformanceCsv(wiredNewCsv, '유선순신규'));
      performances.addAll(_parsePerformanceCsv(wiredRenewCsv, '유선약정갱신'));
      performances.addAll(_parsePerformanceCsv(etcCsv, '기타상품'));

      debugPrint('전체 파싱된 실적 데이터: ${performances.length}건');

      final normalizedFrontierName = _normalizeName(widget.frontier.name);
      final filtered = performances.where((p) => _normalizeName(p.name) == normalizedFrontierName).toList();
      
      debugPrint('프론티어 "${widget.frontier.name}" 매칭 실적 데이터: ${filtered.length}건');

      // 연월 정규화 및 중복 제거 (포인트 순위정보와 실적 데이터 모두에서)
      final yearMonthsSet = <String>{};
      for (final p in filtered) {
        final normalized = _normalizeYearMonth(p.yearMonth);
        yearMonthsSet.add(normalized);
      }
      for (final pr in _pointRankData) {
        final normalized = _normalizeYearMonth(pr['yearMonth'] as String);
        yearMonthsSet.add(normalized);
      }
      final yearMonths = yearMonthsSet.toList()..sort((a, b) => b.compareTo(a)); // 최신순

      setState(() {
        _allPerformances = filtered;
        _availableYearMonths = yearMonths;
        _selectedYearMonth = yearMonths.isNotEmpty ? yearMonths.first : null;
        _workStartDate = parsedWorkStartDate;
        _isLoading = false;
      });
      
      debugPrint('사용 가능한 연월: $yearMonths');
      debugPrint('선택된 연월: $_selectedYearMonth');
    } catch (e) {
      setState(() {
        _allPerformances = [];
        _availableYearMonths = [];
        _selectedYearMonth = null;
        _isLoading = false;
      });
      debugPrint('실적 데이터 로딩 오류: $e');
    }
  }

  // 포인트 순위정보 CSV 파싱
  List<Map<String, dynamic>> _parsePointRankCsv(String csvData) {
    final List<Map<String, dynamic>> pointRankList = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return pointRankList;

    // BOM 제거
    final firstLine = _removeBOM(lines[0]);
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    debugPrint('포인트 순위정보 CSV 헤더: $headers');
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int yearMonthIndex = _findHeaderIndex(headers, ['연월', '기준연월', 'yearMonth', 'YYYYMM']);
    final int rankIndex = _findHeaderIndex(headers, ['순위', 'rank']);
    final int hqIndex = _findHeaderIndex(headers, ['본부', 'hq']);
    final int centerIndex = _findHeaderIndex(headers, ['센터', 'center', '프론티어센터']);

    // 포인트 컬럼 찾기: 1순위 "포인트" 직접 찾기, 없으면 총포인트, 없으면 모든 포인트 컬럼 합산
    int? pointIndex;
    int? totalPointIndex;
    final List<int> pointColumnIndices = [];
    
    // 1순위: "포인트"라는 이름의 컬럼 직접 찾기
    pointIndex = _findHeaderIndex(headers, ['포인트', 'point']);
    if (pointIndex != -1) {
      debugPrint('포인트 순위정보: "포인트" 컬럼 직접 발견 - 인덱스 $pointIndex');
    }
    
    // 총포인트/합계 포인트 컬럼 찾기 (포인트 컬럼이 없을 때만)
    if (pointIndex == -1) {
      for (int i = 0; i < headers.length; i++) {
        final header = headers[i].toLowerCase();
        if ((header.contains('포인트') || header.contains('point')) &&
            (header.contains('총') || header.contains('합계') || header.contains('total') || header.contains('sum'))) {
          totalPointIndex = i;
          debugPrint('포인트 순위정보: 총포인트 컬럼 발견 - 인덱스 $i, 헤더: "${headers[i]}"');
          break;
        }
      }
    }
    
    // 총포인트가 없으면 모든 포인트 컬럼 찾기 (합산용)
    if (pointIndex == -1 && totalPointIndex == null) {
      for (int i = 0; i < headers.length; i++) {
        final header = headers[i].toLowerCase();
        if (header.contains('포인트') || header.contains('point')) {
          pointColumnIndices.add(i);
          debugPrint('포인트 순위정보: 포인트 컬럼 발견 - 인덱스 $i, 헤더: "${headers[i]}"');
        }
      }
    }

    debugPrint('포인트 순위정보 인덱스 - 성명:$nameIndex, 연월:$yearMonthIndex, 순위:$rankIndex, 본부:$hqIndex, 센터:$centerIndex, 포인트:${pointIndex != -1 ? "포인트($pointIndex)" : (totalPointIndex != null ? "총포인트($totalPointIndex)" : "유형별($pointColumnIndices)")}');

    if (nameIndex == -1 || yearMonthIndex == -1) {
      debugPrint('❌ 포인트 순위정보 CSV: 필수 헤더를 찾을 수 없습니다 (성명: $nameIndex, 연월: $yearMonthIndex)');
      debugPrint('포인트 순위정보 CSV: 사용 가능한 헤더 목록: $headers');
      return pointRankList;
    }
    
    if (pointIndex == -1 && pointColumnIndices.isEmpty && totalPointIndex == null && rankIndex == -1) {
      debugPrint('⚠️ 경고: 포인트/순위 컬럼을 찾을 수 없습니다 (포인트: $pointIndex, 총포인트: $totalPointIndex, 포인트 컬럼들: $pointColumnIndices, 순위: $rankIndex)');
    }
    
    if (rankIndex == -1) {
      debugPrint('⚠️ 경고: 순위 컬럼을 찾을 수 없습니다');
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) continue;

      try {
        final name = values[nameIndex].trim();
        final yearMonth = values[yearMonthIndex].trim();
        if (name.isEmpty || yearMonth.isEmpty) {
          debugPrint('포인트 순위정보 CSV: line $i - 이름 또는 연월이 비어있음 (name="$name", yearMonth="$yearMonth")');
          continue;
        }

        // 포인트 계산: "포인트" 컬럼 우선, 없으면 총포인트, 없으면 유형별 포인트 합산
        int? calculatedPoint;
        if (pointIndex != -1 && pointIndex < values.length) {
          // "포인트" 컬럼 직접 사용
          calculatedPoint = _parseInt(values[pointIndex]);
          debugPrint('포인트 순위정보: line $i - 포인트 컬럼에서 값 가져옴: ${values[pointIndex]} -> $calculatedPoint');
        } else if (totalPointIndex != null && totalPointIndex < values.length) {
          calculatedPoint = _parseInt(values[totalPointIndex]);
        } else if (pointColumnIndices.isNotEmpty) {
          int sumPoint = 0;
          for (final idx in pointColumnIndices) {
            if (idx < values.length) {
              final pointValue = _parseInt(values[idx]);
              if (pointValue != null) {
                sumPoint += pointValue;
              }
            }
          }
          calculatedPoint = sumPoint > 0 ? sumPoint : null;
        }
        
        final rank = rankIndex != -1 && rankIndex < values.length ? _parseInt(values[rankIndex]) : null;
        if (rankIndex != -1 && rankIndex < values.length) {
          debugPrint('포인트 순위정보: line $i - 순위 컬럼에서 값 가져옴: ${values[rankIndex]} -> $rank');
        }
        
        pointRankList.add({
          'name': name,
          'yearMonth': yearMonth,
          'point': calculatedPoint,
          'rank': rank,
          'hq': hqIndex != -1 && hqIndex < values.length ? values[hqIndex].trim() : null,
          'center': centerIndex != -1 && centerIndex < values.length ? values[centerIndex].trim() : null,
        });
      } catch (e) {
        debugPrint('포인트 순위정보 CSV 파싱 오류: line $i, $e');
        continue;
      }
    }

    debugPrint('포인트 순위정보 파싱 완료: ${pointRankList.length}건');
    if (pointRankList.isNotEmpty) {
      debugPrint('포인트 순위정보 샘플: ${pointRankList.first}');
      debugPrint('포인트 순위정보 샘플들 (처음 10개):');
      for (int i = 0; i < pointRankList.length && i < 10; i++) {
        final pr = pointRankList[i];
        final name = pr['name'] as String? ?? '';
        final yearMonth = pr['yearMonth'] as String? ?? '';
        debugPrint('  ${i + 1}. name="$name" (정규화: "${_normalizeName(name)}"), yearMonth="$yearMonth" (정규화: "${_normalizeYearMonth(yearMonth)}"), point=${pr['point']}, rank=${pr['rank']}, hq=${pr['hq']}, center=${pr['center']}');
      }
      
      // 연월별 통계
      final yearMonthStats = <String, int>{};
      for (final pr in pointRankList) {
        final ym = pr['yearMonth'] as String? ?? '';
        final normalized = _normalizeYearMonth(ym);
        yearMonthStats[normalized] = (yearMonthStats[normalized] ?? 0) + 1;
      }
      debugPrint('포인트 순위정보 연월별 통계: $yearMonthStats');
    } else {
      debugPrint('포인트 순위정보 파싱 결과: 데이터가 없습니다!');
    }
    return pointRankList;
  }

  // 업무시작일 파싱
  String? _parseWorkStartDate(String csvData) {
    final List<String> lines = csvData.split('\n');
    if (lines.isEmpty) {
      debugPrint('업무시작일 파싱: CSV가 비어있습니다');
      return null;
    }

    final firstLine = _removeBOM(lines[0]);
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    debugPrint('인력정보 CSV 헤더: $headers');
    
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int workStartDateIndex = _findHeaderIndex(headers, ['업무시작일', '시작일', 'workStartDate', '입사일', '입사날짜']);

    debugPrint('업무시작일 파싱: 성명 인덱스=$nameIndex, 업무시작일 인덱스=$workStartDateIndex');

    if (nameIndex == -1) {
      debugPrint('업무시작일 파싱: 성명 헤더를 찾을 수 없습니다');
      return null;
    }
    
    if (workStartDateIndex == -1) {
      debugPrint('업무시작일 파싱: 업무시작일 헤더를 찾을 수 없습니다');
      return null;
    }

    final normalizedFrontierName = _normalizeName(widget.frontier.name);
    debugPrint('업무시작일 파싱: 프론티어 이름="$normalizedFrontierName" 검색 중...');

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) continue;

      final name = values[nameIndex].trim();
      if (_normalizeName(name) == normalizedFrontierName) {
        final workStartDate = values[workStartDateIndex].trim();
        debugPrint('업무시작일 찾음: $workStartDate');
        return workStartDate.isEmpty ? null : workStartDate;
      }
    }

    debugPrint('업무시작일 파싱: "${widget.frontier.name}"에 해당하는 데이터를 찾지 못했습니다');
    return null;
  }

  List<PerformanceData> _parsePerformanceCsv(String csvData, String category) {
    final List<PerformanceData> performances = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return performances;

    // BOM 제거
    final firstLine = _removeBOM(lines[0]);
    // CSV 구분자 감지 (쉼표 또는 탭)
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int yearMonthIndex = _findHeaderIndex(headers, ['연월', '기준연월', 'yearMonth', 'YYYYMM']);
    final int typeIndex = _findHeaderIndex(headers, ['유형', 'type', '상품유형', 'productType', '제품유형']);
    final int targetIndex = _findHeaderIndex(headers, ['목표', 'target']);
    final int actualIndex = _findHeaderIndex(headers, ['실적', '건수', '합계', '성과', '누적', '매출', 'actual']);
    final int achievementIndex = _findHeaderIndex(headers, ['달성률', 'achievementRate']);
    final int pointIndex = _findHeaderIndex(headers, ['포인트', 'point']);
    final int rankIndex = _findHeaderIndex(headers, ['순위', 'rank']);

    if (nameIndex == -1 || yearMonthIndex == -1) {
      debugPrint('$category CSV: 필수 헤더를 찾을 수 없습니다 (성명: $nameIndex, 연월: $yearMonthIndex)');
      return performances;
    }

    debugPrint('$category CSV 파싱: 실제 인덱스=$actualIndex, 목표 인덱스=$targetIndex, 유형 인덱스=$typeIndex');

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => e.trim().replaceAll('"', '')).toList();
      if (values.length < headers.length) continue;

      try {
        final name = values[nameIndex].trim();
        final yearMonth = values[yearMonthIndex].trim();
        if (name.isEmpty || yearMonth.isEmpty) continue;
        
        final typeValue = typeIndex != -1 && values.length > typeIndex && values[typeIndex].trim().isNotEmpty 
            ? values[typeIndex].trim() 
            : null;

        performances.add(PerformanceData(
          name: name,
          yearMonth: yearMonth,
          category: category,
          type: typeValue,
          target: targetIndex != -1 ? _parseInt(values[targetIndex]) : null,
          actual: actualIndex != -1 ? _parseInt(values[actualIndex]) : null,
          achievementRate: achievementIndex != -1 ? _parseDouble(values[achievementIndex]) : null,
          point: pointIndex != -1 ? _parseInt(values[pointIndex]) : null,
          rank: rankIndex != -1 ? _parseInt(values[rankIndex]) : null,
        ));
      } catch (e) {
        continue;
      }
    }

    debugPrint('$category CSV 파싱 완료: ${performances.length}건 (실적 값 있는 건: ${performances.where((p) => p.actual != null).length})');
    if (performances.isNotEmpty) {
      debugPrint('$category CSV 샘플: name=${performances.first.name}, yearMonth=${performances.first.yearMonth}, actual=${performances.first.actual}');
    }
    return performances;
  }

  int _findHeaderIndex(List<String> headers, List<String> possibleNames) {
    for (final name in possibleNames) {
      // 정확한 매칭 시도
      int index = headers.indexOf(name);
      if (index != -1) return index;
      
      // 대소문자 무시 매칭
      index = headers.indexWhere((h) => h.toLowerCase() == name.toLowerCase());
      if (index != -1) return index;
      
      // 공백 제거 후 매칭
      index = headers.indexWhere((h) => h.replaceAll(RegExp(r'\s+'), '') == name.replaceAll(RegExp(r'\s+'), ''));
      if (index != -1) return index;
      
      // 부분 매칭 (헤더에 name이 포함되는 경우)
      index = headers.indexWhere((h) => h.contains(name) || name.contains(h));
      if (index != -1) return index;
    }
    return -1;
  }

  int? _parseInt(String value) {
    if (value.isEmpty || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    // 0은 유효한 값이므로 null이 아닌 0을 반환
    return int.tryParse(trimmed);
  }

  double? _parseDouble(String value) {
    if (value.isEmpty || value.trim().isEmpty) return null;
    return double.tryParse(value.trim());
  }

  // 선택 연월의 포인트/순위 가져오기 (포인트 순위정보 CSV에서만)
  Map<String, dynamic> _getPointAndRank(String? yearMonth) {
    if (_pointRankData.isEmpty) {
      debugPrint('_getPointAndRank: 포인트 순위정보 데이터가 비어있음');
      return {'point': null, 'rank': null, 'totalCount': null};
    }

    final normalizedFrontierName = _normalizeName(widget.frontier.name);
    final normalizedFrontierHq = _normalizeName(widget.frontier.hq);
    final normalizedFrontierCenter = _normalizeName(widget.frontier.center);
    
    debugPrint('_getPointAndRank: 연월=$yearMonth, 프론티어="${widget.frontier.name}" (정규화: $normalizedFrontierName, 본부: $normalizedFrontierHq, 센터: $normalizedFrontierCenter)');
    debugPrint('_getPointAndRank: 포인트 순위정보 데이터 ${_pointRankData.length}건');

    int? targetYmInt;
    
    // 선택 연월이 있으면 파싱, 없으면 kpi_rank.csv에서 가장 최신 연월 사용 - [FIX] 연월 파싱 보강
    if (yearMonth != null) {
      targetYmInt = parseYearMonthToInt(yearMonth);
    }
    
    if (targetYmInt == null && _pointRankData.isNotEmpty) {
      final parsedList = _pointRankData
          .map((pr) => parseYearMonthToInt(pr['yearMonth'] as String))
          .whereType<int>()
          .toList();
      if (parsedList.isNotEmpty) {
        targetYmInt = parsedList.reduce((a, b) => a > b ? a : b);
        debugPrint('_getPointAndRank: 선택 연월이 null이므로 최신 연월 사용: $targetYmInt');
      }
    }
    
    if (targetYmInt == null) {
      debugPrint('_getPointAndRank: 연월이 없어서 null 반환');
      return {'point': null, 'rank': null, 'totalCount': null};
    }

    debugPrint('_getPointAndRank: 정규화된 연월=$targetYmInt');
    
    // 디버그: 해당 연월의 모든 데이터 확인 - [FIX] 연월 파싱 보강
    final allInMonth = _pointRankData.where((pr) {
      final prYmInt = parseYearMonthToInt(pr['yearMonth'] as String);
      return prYmInt != null && prYmInt == targetYmInt;
    }).toList();
    debugPrint('_getPointAndRank: 해당 연월($targetYmInt) 데이터 ${allInMonth.length}건');
    if (allInMonth.isNotEmpty) {
      debugPrint('_getPointAndRank: 샘플 데이터 (처음 5개):');
      for (int i = 0; i < allInMonth.length && i < 5; i++) {
        final pr = allInMonth[i];
        final prName = pr['name'] as String;
        final prNormalized = _normalizeName(prName);
        debugPrint('  ${i + 1}. 원본: "$prName" (정규화: "$prNormalized") vs 프론티어: "${widget.frontier.name}" (정규화: "$normalizedFrontierName")');
      }
    }
    
    // 포인트 순위정보 CSV에서 찾기 - [FIX] 연월 파싱 보강
    // 1차: 성명만으로 매칭 (가장 간단하고 확실한 방법)
    var matchingPointRank = <Map<String, dynamic>>[];
    for (final pr in _pointRankData) {
      final prYmInt = parseYearMonthToInt(pr['yearMonth'] as String);
      final prName = pr['name'] as String;
      final normalizedPName = _normalizeName(prName);
      
      final yearMonthMatch = prYmInt != null && prYmInt == targetYmInt;
      final nameMatch = normalizedPName == normalizedFrontierName;
      
      if (yearMonthMatch && nameMatch) {
        debugPrint('포인트/순위 매칭 성공: 원본이름="$prName" (정규화: $normalizedPName), 연월=${pr['yearMonth']} (정규화: $prYmInt), point=${pr['point']}, rank=${pr['rank']}');
        matchingPointRank.add(pr);
      } else if (yearMonthMatch) {
        // 연월은 맞지만 이름이 안 맞는 경우 디버그
        debugPrint('포인트/순위 매칭 실패 (이름 불일치): 원본="$prName" (정규화: $normalizedPName) vs 프론티어="${widget.frontier.name}" (정규화: $normalizedFrontierName)');
      }
    }
    
    // 2차: 본부/센터도 함께 매칭 시도 (동명이인 방지, 선택사항)
    if (matchingPointRank.length > 1) {
      debugPrint('_getPointAndRank: 동명이인 발견 (${matchingPointRank.length}명), 본부/센터로 재필터링');
      matchingPointRank = matchingPointRank.where((pr) {
        final normalizedPHq = _normalizeName(pr['hq'] as String? ?? '');
        final normalizedPCenter = _normalizeName(pr['center'] as String? ?? '');
        
        final hqMatch = normalizedPHq.isEmpty || normalizedFrontierHq.isEmpty || normalizedPHq == normalizedFrontierHq;
        final centerMatch = normalizedPCenter.isEmpty || normalizedFrontierCenter.isEmpty || normalizedPCenter == normalizedFrontierCenter;
        
        if (hqMatch && centerMatch) {
          debugPrint('포인트/순위 매칭 (본부/센터 포함): ${pr['name']}, ${pr['yearMonth']}, point=${pr['point']}, rank=${pr['rank']}');
        }
        return hqMatch && centerMatch;
      }).toList();
    }

    if (matchingPointRank.isNotEmpty) {
      final pr = matchingPointRank.first;
      
      // 전체 인원수 계산 (해당 연월의 포인트 순위정보에서, 본부/센터 필터 없이 전체) - [FIX] 연월 파싱 보강
      final allPointRankInMonth = _pointRankData.where((pr) {
        final prYmInt = parseYearMonthToInt(pr['yearMonth'] as String);
        return prYmInt != null && prYmInt == targetYmInt;
      }).toList();
      final uniqueNames = allPointRankInMonth.map((pr) => _normalizeName(pr['name'] as String)).toSet();
      final totalCount = uniqueNames.length;

      debugPrint('_getPointAndRank: 전체 인원수 계산 - 연월=$targetYmInt, 전체 인원=$totalCount명');

      return {
        'point': pr['point'],
        'rank': pr['rank'],
        'totalCount': totalCount,
      };
    }

    // 매칭 실패 시 상세 디버그
    debugPrint('_getPointAndRank: 매칭되는 데이터가 없음');
    debugPrint('_getPointAndRank: 검색 조건 - 프론티어="${widget.frontier.name}" (정규화: $normalizedFrontierName), 연월=$targetYmInt');
    debugPrint('_getPointAndRank: 전체 포인트 순위정보에서 이름이 비슷한 항목 찾기:');
    final similarNames = _pointRankData.where((pr) {
      final prName = pr['name'] as String? ?? '';
      final normalizedPName = _normalizeName(prName);
      return normalizedPName.contains(normalizedFrontierName) || normalizedFrontierName.contains(normalizedPName);
    }).take(5).toList();
    if (similarNames.isNotEmpty) {
      for (final pr in similarNames) {
        debugPrint('  유사 이름: "${pr['name']}" (정규화: ${_normalizeName(pr['name'] as String)}), 연월=${pr['yearMonth']}');
      }
    } else {
      debugPrint('  유사한 이름도 없음');
    }
    
    return {'point': null, 'rank': null, 'totalCount': null};
  }

  // 차트용 기간별 데이터 필터링 (최근 N개월)
  List<PerformanceData> _getPeriodDataForChart() {
    // 모든 데이터에서 최신 연월 찾기
    final normalizedFrontierName = _normalizeName(widget.frontier.name);
    final frontierData = _allPerformances.where((p) {
      return _normalizeName(p.name) == normalizedFrontierName;
    }).toList();
    
    if (frontierData.isEmpty) {
      debugPrint('_getPeriodDataForChart: 프론티어 데이터가 없습니다');
      return [];
    }

    // 최신 연월 찾기
    final yearMonths = frontierData.map((p) => _normalizeYearMonth(p.yearMonth)).toSet().toList()
      ..sort((a, b) => b.compareTo(a)); // 최신순 정렬
    
    if (yearMonths.isEmpty) {
      debugPrint('_getPeriodDataForChart: 연월 데이터가 없습니다');
      return [];
    }

    final latestYearMonth = yearMonths.first;
    final int? latestInt = int.tryParse(latestYearMonth);
    if (latestInt == null || latestYearMonth.length != 6) {
      debugPrint('_getPeriodDataForChart: 최신 연월 파싱 실패 - $latestYearMonth');
      return [];
    }

    // 선택된 기간에 따라 개월 수 결정
    int months = 3;
    if (_selectedPeriod == '6개월') months = 6;
    if (_selectedPeriod == '1년') months = 12;

    // 최근 N개월 연월 목록 생성
    final Set<String> periodYearMonthsSet = {};
    for (int i = 0; i < months; i++) {
      int year = latestInt ~/ 100;
      int month = latestInt % 100;
      month -= i;
      while (month <= 0) {
        month += 12;
        year -= 1;
      }
      final ym = '$year${month.toString().padLeft(2, '0')}';
      periodYearMonthsSet.add(ym);
    }

    debugPrint('_getPeriodDataForChart: 기간 연월 목록: $periodYearMonthsSet (최신: $latestYearMonth, 기간: $_selectedPeriod)');

    final result = frontierData.where((p) {
      final normalizedPYearMonth = _normalizeYearMonth(p.yearMonth);
      return periodYearMonthsSet.contains(normalizedPYearMonth);
    }).toList();

    debugPrint('_getPeriodDataForChart: 결과 ${result.length}건');
    return result;
  }

  // 모든 실적 데이터 가져오기
  List<PerformanceData> _getAllPerformanceData() {
    final normalizedFrontierName = _normalizeName(widget.frontier.name);
    final result = _allPerformances.where((p) {
      return _normalizeName(p.name) == normalizedFrontierName;
    }).toList();

    debugPrint('_getAllPerformanceData: 결과 ${result.length}건');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.frontier.name,
          style: const TextStyle(
                                  fontSize: 18,
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFF6F61),
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: const Color(0xFFFF6F61),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: '프론티어 정보'),
            Tab(text: '실적현황'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFrontierInfoTab(),
                _buildPerformanceTab(),
              ],
            ),
    );
  }

  Widget _buildFrontierInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 인력정보 카드
          _InfoCard(
            title: '프론티어 정보',
            items: [
              _InfoRow(label: '성명', value: widget.frontier.name),
              _InfoRow(label: '직급', value: widget.frontier.position),
              _InfoRow(label: '본부', value: widget.frontier.hq),
              _InfoRow(label: '센터', value: widget.frontier.center),
              _InfoRow(label: '등급', value: widget.frontier.grade),
              if (_workStartDate != null)
                _InfoRow(label: '업무시작일', value: _workStartDate!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceTab() {
    // 데이터가 없는 경우 Empty State 표시
    if (_allPerformances.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '실적 데이터가 없습니다',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '데이터를 불러올 수 없거나\n실적 데이터가 없습니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 선택된 기간에 따라 실적 추이 차트용 데이터 (최근 N개월)
    final chartPeriodData = _getPeriodDataForChart();
    
    // 모든 데이터 (월별 상세용)
    final allData = _getAllPerformanceData();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 실적현황 타이틀 및 기간 선택
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '실적현황',
                    style: TextStyle(
                      fontSize: 20,
                                  fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  Row(
                    children: ['3개월', '6개월', '1년'].map((period) {
                      final isSelected = _selectedPeriod == period;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text(period),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedPeriod = period;
                              });
                            }
                          },
                          selectedColor: const Color(0xFFFF6F61).withOpacity(0.2),
                          labelStyle: TextStyle(
                            color: isSelected
                                      ? const Color(0xFFFF6F61)
                                : Colors.grey[700],
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 요약 박스 2개
          _buildSummaryBoxes(allData),
          const SizedBox(height: 16),
          // 차트 섹션 (선택한 기간의 최근 N개월 데이터)
          _buildChartSection(chartPeriodData),
          const SizedBox(height: 16),
          // 월별 상세 데이터 (모든 데이터)
          _buildMonthlyDetail(allData),
        ],
      ),
    );
  }

  // 요약 박스 2개 (최근월 실적, 기간 누적) - [FIX] 연월 파싱 보강
  Widget _buildSummaryBoxes(List<PerformanceData> allData) {
    final categories = ['무선', '유선순신규', '유선약정갱신', '기타상품'];
    
    // [FIX] 연월 파싱 보강 - int 기반으로 최신 연월 찾기
    int? latestYm;
    if (allData.isNotEmpty) {
      final parsedList = allData
          .map((e) => parseYearMonthToInt(e.yearMonth))
          .whereType<int>()
          .toList();
      
      if (parsedList.isNotEmpty) {
        latestYm = parsedList.reduce((a, b) => a > b ? a : b);
      }
    }

    // 최근 연월 문자열 생성
    String? latestYearMonthStr;
    if (latestYm != null) {
      final year = latestYm ~/ 100;
      final month = latestYm % 100;
      latestYearMonthStr = '$year년 ${month.toString().padLeft(2, '0')}월';
    }

    // 최근월 실적 계산 (가장 최근 월의 실적) - 총계 유형만 합산
    final Map<String, int> latestMonthActuals = {};
    if (latestYm != null) {
      for (final cat in categories) {
        final catData = allData.where((p) {
          final ymInt = parseYearMonthToInt(p.yearMonth);
          if (ymInt == null || ymInt != latestYm || p.category != cat) return false;
          // 총계 유형만 필터링
          final type = p.type ?? '';
          if (cat == '무선') {
            return type.contains('무선총계');
          } else if (cat == '유선순신규') {
            return type.contains('유선순신규총계');
          } else if (cat == '유선약정갱신') {
            return type.contains('유선약정갱신총계');
          } else if (cat == '기타상품') {
            return type.contains('기타상품') && type.contains('총계');
          }
          return false;
        }).toList();
        latestMonthActuals[cat] = catData.fold<int>(0, (sum, p) => sum + (p.actual ?? 0));
      }
    }

    // 선택된 기간 누적 실적 계산 (가장 최근 N개월) - [FIX] 연월 파싱 보강
    final Map<String, int> recentMonthsActuals = {};
    
    // 선택된 기간에 따라 개월 수 결정
    int months = 3;
    if (_selectedPeriod == '6개월') months = 6;
    if (_selectedPeriod == '1년') months = 12;
    
    if (latestYm != null) {
      // 최근 N개월 연월 목록 생성 (int 기반)
      final Set<int> recentMonthsSet = {};
      for (int i = 0; i < months; i++) {
        int year = latestYm ~/ 100;
        int month = latestYm % 100;
        month -= i;
        while (month <= 0) {
          month += 12;
          year -= 1;
        }
        final ym = year * 100 + month;
        recentMonthsSet.add(ym);
      }
      
      for (final cat in categories) {
        final catData = allData.where((p) {
          final ymInt = parseYearMonthToInt(p.yearMonth);
          if (ymInt == null || !recentMonthsSet.contains(ymInt) || p.category != cat) return false;
          // 총계 유형만 필터링
          final type = p.type ?? '';
          if (cat == '무선') {
            return type.contains('무선총계');
          } else if (cat == '유선순신규') {
            return type.contains('유선순신규총계');
          } else if (cat == '유선약정갱신') {
            return type.contains('유선약정갱신총계');
          } else if (cat == '기타상품') {
            return type.contains('기타상품') && type.contains('총계');
          }
          return false;
        }).toList();
        recentMonthsActuals[cat] = catData.fold<int>(0, (sum, p) => sum + (p.actual ?? 0));
      }
    }

    return Column(
      children: [
        // 첫 번째 박스: 가장 최근월 실적
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestYearMonthStr != null ? '$latestYearMonthStr 실적' : '최근월 실적',
                              style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: categories.map((cat) {
                    final actual = latestMonthActuals[cat] ?? 0;
                    return Container(
                      width: (MediaQuery.of(context).size.width - 100) / 2,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            actual.toString(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$cat건',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        // 두 번째 박스: 선택 기간 누적 실적
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '최근 $_selectedPeriod 누적',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: categories.map((cat) {
                    final total = recentMonthsActuals[cat] ?? 0;
                    return Container(
                      width: (MediaQuery.of(context).size.width - 100) / 2,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            total.toString(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$cat건',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartSection(List<PerformanceData> periodData) {
    return Column(
      children: [
        _buildLineChart(periodData, '무선 실적 추이', ['무선']),
        const SizedBox(height: 16),
        _buildLineChart(periodData, '유선순신규 실적 추이', ['유선순신규']),
        const SizedBox(height: 16),
        _buildLineChart(periodData, '유선약정갱신 실적 추이', ['유선약정갱신']),
        const SizedBox(height: 16),
        _buildLineChart(periodData, '기타 실적 추이', ['기타상품']),
      ],
    );
  }

  Widget _buildLineChart(
      List<PerformanceData> periodData, String title, List<String> categories) {
    // 유형별 데이터 수집: yearMonth -> type -> actual
    final chartData = <String, Map<String, int>>{}; // yearMonth -> {type: actual}
    final yearMonths = <String>[];
    final types = <String>{};

    for (final cat in categories) {
      final catData = periodData.where((p) => p.category == cat).toList();
      
      for (final data in catData) {
        // [FIX] 연월 파싱 보강 - int 기반으로 정규화
        final ymInt = parseYearMonthToInt(data.yearMonth);
        if (ymInt == null) continue;
        final normalizedYm = ymInt.toString();
        final typeKey = data.type ?? cat; // 유형이 없으면 카테고리명 사용
        
        if (!yearMonths.contains(normalizedYm)) {
          yearMonths.add(normalizedYm);
        }
        
        if (!chartData.containsKey(normalizedYm)) {
          chartData[normalizedYm] = <String, int>{};
        }
        
        // 동일 월, 동일 유형이면 합산
        chartData[normalizedYm]![typeKey] = (chartData[normalizedYm]![typeKey] ?? 0) + (data.actual ?? 0);
        types.add(typeKey);
      }
    }

    // [FIX] 연월 파싱 보강 - int 기반 정렬
    yearMonths.sort((a, b) {
      final aInt = int.tryParse(a) ?? 0;
      final bInt = int.tryParse(b) ?? 0;
      return aInt.compareTo(bInt);
    });
    
    // 상위 5개 유형만 표시하고 나머지는 "기타"로 묶기
    final sortedTypes = types.toList();
    final typeTotals = <String, int>{};
    for (final ym in yearMonths) {
      final monthData = chartData[ym] ?? {};
      for (final type in sortedTypes) {
        typeTotals[type] = (typeTotals[type] ?? 0) + (monthData[type] ?? 0);
      }
    }
    sortedTypes.sort((a, b) => (typeTotals[b] ?? 0).compareTo(typeTotals[a] ?? 0));
    
    final displayTypes = sortedTypes.take(5).toList(); // 상위 5개
    final otherTypes = sortedTypes.skip(5).toSet();
    
    // "기타" 합산
    if (otherTypes.isNotEmpty) {
      for (final ym in yearMonths) {
        final monthData = chartData[ym] ?? {};
        int otherTotal = 0;
        for (final type in otherTypes) {
          otherTotal += monthData[type] ?? 0;
        }
        if (otherTotal > 0) {
          monthData['기타'] = otherTotal;
        }
      }
      if (otherTypes.any((t) => (typeTotals[t] ?? 0) > 0)) {
        displayTypes.add('기타');
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: yearMonths.isEmpty
                  ? Center(
                      child: Text(
                        '데이터 없음',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : CustomPaint(
                      painter: _LineChartPainter(
                        data: chartData,
                        yearMonths: yearMonths,
                        types: displayTypes,
                      ),
                      size: Size.infinite,
                    ),
            ),
            // 범례 표시
            if (displayTypes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: displayTypes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final type = entry.value;
                  final colors = [
                    const Color(0xFFFF6F61),
                    Colors.blue,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.teal,
                  ];
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors[index % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                  );
                }).toList(),
              ),
            ],
          ],
                      ),
                    ),
                  );
  }

  Widget _buildMonthlyDetail(List<PerformanceData> periodData) {
    // 연월을 int로 변환하여 내림차순 정렬
    final yearMonthInts = periodData
        .map((p) => parseYearMonthToInt(p.yearMonth))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a)); // 내림차순 (최신순)

    // 년도별로 그룹화 (예: 2024 -> 24년, 2025 -> 25년)
    final Map<int, List<int>> yearGroups = {};
    for (final ymInt in yearMonthInts) {
      final year = ymInt ~/ 100;
      final yearShort = year % 100; // 24, 25 등
      yearGroups.putIfAbsent(yearShort, () => []);
      yearGroups[yearShort]!.add(ymInt);
    }

    // 년도 내림차순 정렬 (25년 -> 24년)
    final sortedYears = yearGroups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '월별 상세 데이터',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 16),
        // 년도별 ExpansionTile
        ...sortedYears.map((yearShort) {
          final yearMonthIntsInYear = yearGroups[yearShort]!..sort((a, b) => b.compareTo(a)); // 내림차순
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
            ),
          ],
        ),
            child: ExpansionTile(
              title: Text(
                '$yearShort년',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              children: [
                // 해당 년도의 월별 데이터
                ...yearMonthIntsInYear.map((ymInt) {
                  final ymStr = ymInt.toString();
                  final year = ymInt ~/ 100;
                  final month = ymInt % 100;
                  final ym = '$year${month.toString().padLeft(2, '0')}';
                  
                  final monthData = periodData.where((p) {
                    final pYmInt = parseYearMonthToInt(p.yearMonth);
                    return pYmInt != null && pYmInt == ymInt;
                  }).toList();
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ExpansionTile(
                      title: Text(
                        '$year년 $month월',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      children: [
                        ...['무선', '유선순신규', '유선약정갱신', '기타상품']
                            .map((cat) {
                  // 카테고리별 총계 유형 이름 결정
                  String totalTypeName;
                  String totalTypeFilter;
                  if (cat == '무선') {
                    totalTypeName = '무선총계';
                    totalTypeFilter = '무선총계';
                  } else if (cat == '유선순신규') {
                    totalTypeName = '유선순신규총계';
                    totalTypeFilter = '유선순신규총계';
                  } else if (cat == '유선약정갱신') {
                    totalTypeName = '유선약정갱신총계';
                    totalTypeFilter = '유선약정갱신총계';
                  } else if (cat == '기타상품') {
                    totalTypeName = '기타상품총계';
                    totalTypeFilter = '기타상품총계';
                  } else {
                    totalTypeName = cat;
                    totalTypeFilter = '';
                  }
                  
                  // 총계 유형의 실적만 가져오기
                  final totalData = monthData.where((p) {
                    if (p.category != cat) return false;
                    final type = p.type ?? '';
                    if (cat == '기타상품') {
                      // 기타상품의 경우 '기타상품'과 '총계'가 모두 포함된 유형 찾기
                      return type.contains('기타상품') && type.contains('총계');
                    }
                    return type.contains(totalTypeFilter);
                  }).toList();
                  
                  // 총계 유형 실적 계산
                  final totalActual = totalData.fold<int>(0, (sum, p) => sum + (p.actual ?? 0));
                  
                  // 전체 카테고리 데이터 (유형별 상세 표시용)
                  final catData = monthData.where((p) => p.category == cat).toList();
                  
                  // 유형별로 그룹화
                  final typeGroups = <String, List<PerformanceData>>{};
                  for (final data in catData) {
                    final type = data.type ?? '전체';
                    typeGroups.putIfAbsent(type, () => []);
                    typeGroups[type]!.add(data);
                  }
                  
                  if (catData.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 카테고리 헤더 (총계 유형 이름과 실적 표시)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              totalTypeName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            Text(
                              '실적: $totalActual건',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        // 유형별 상세 데이터 (총계 유형 제외)
                        if (typeGroups.length > 1) ...[
                          const SizedBox(height: 8),
                          ...typeGroups.entries.where((entry) {
                            final type = entry.key;
                            // 총계 유형 제외 (기타상품총계는 '기타상품'과 '총계'가 모두 포함된 경우)
                            final isTotalType = type.contains('무선총계') || 
                                                type.contains('유선순신규총계') || 
                                                type.contains('유선약정갱신총계') ||
                                                (type.contains('기타상품') && type.contains('총계'));
                            return !isTotalType;
                          }).map((entry) {
                            final type = entry.key;
                            final typeDataList = entry.value;
                            final typeActual = typeDataList.fold<int>(0, (sum, p) => sum + (p.actual ?? 0));
                            return Padding(
                              padding: const EdgeInsets.only(left: 16, top: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '  • $type',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    '$typeActual건',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                        }),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// 라인 차트 CustomPainter
class _LineChartPainter extends CustomPainter {
  final Map<String, Map<String, int>> data; // yearMonth -> {type: actual}
  final List<String> yearMonths;
  final List<String> types; // 유형 리스트

  _LineChartPainter({
    required this.data,
    required this.yearMonths,
    required this.types,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (yearMonths.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final textStyle = TextStyle(
      fontSize: 10,
      color: Colors.grey[700],
    );

    final maxValue = data.values
        .expand((map) => map.values)
        .fold<int>(0, (max, val) => val > max ? val : max);

    if (maxValue == 0) return;

    final padding = 40.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final stepX = yearMonths.length > 1
        ? chartWidth / (yearMonths.length - 1)
        : chartWidth;

    final colors = [
      const Color(0xFFFF6F61),
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
    ];

    // Y축 눈금 표시
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    
    // 그리드 라인 및 Y축 라벨
    for (int i = 0; i <= 5; i++) {
      final value = (maxValue * i / 5).round();
      final y = padding + chartHeight - (i / 5 * chartHeight);
      
      // 그리드 라인
      final gridPaint = Paint()
        ..color = Colors.grey[200]!
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + chartWidth, y),
        gridPaint,
      );
      
      // Y축 라벨
      textPainter.text = TextSpan(
        text: value.toString(),
        style: textStyle,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(padding - textPainter.width - 5, y - textPainter.height / 2));
    }

    for (int typeIndex = 0; typeIndex < types.length; typeIndex++) {
      final type = types[typeIndex];
      final path = Path();
      bool isFirst = true;

      for (int i = 0; i < yearMonths.length; i++) {
        final ym = yearMonths[i];
        final monthData = data[ym] ?? {};
        final value = monthData[type] ?? 0;
        final x = padding + (i * stepX);
        final y = padding + chartHeight - (value / maxValue * chartHeight);

        if (isFirst) {
          path.moveTo(x, y);
          isFirst = false;
        } else {
          path.lineTo(x, y);
        }
      }

      paint.color = colors[typeIndex % colors.length];
      paint.strokeWidth = 2.5;
      canvas.drawPath(path, paint);
      
      // 데이터 포인트 표시
      for (int i = 0; i < yearMonths.length; i++) {
        final ym = yearMonths[i];
        final monthData = data[ym] ?? {};
        final value = monthData[type] ?? 0;
        if (value > 0) {
          final x = padding + (i * stepX);
          final y = padding + chartHeight - (value / maxValue * chartHeight);
          
          final pointPaint = Paint()
            ..color = colors[typeIndex % colors.length]
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(x, y), 4, pointPaint);
        }
      }
    }

    // 월 라벨
    for (int i = 0; i < yearMonths.length; i++) {
      final ym = yearMonths[i];
      final x = padding + (i * stepX);
      final displayText = ym.length > 6 ? ym.substring(2, 7) : ym;
      final textSpan = TextSpan(
        text: displayText,
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - padding + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ========================================
// 대시보드 화면 - KPI 카드
// ========================================
// ========================================
// 대시보드 화면 - 카드형 KPI 대시보드
// ========================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  // [DASH] KPI CSV 로딩/캐싱
  List<Map<String, dynamic>> _allKpiData = [];
  Set<String> _availableYearMonths = {};
  Set<String> _selectedYearMonths = {};
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;
  
  // [CSV_RELOAD] 이벤트 구독 및 debounce
  StreamSubscription<String>? _csvReloadSubscription;
  Timer? _reloadDebounceTimer;
  bool _isReloading = false;

  // [DASH] 전체현황 KPI 집계
  Map<String, int> _overallKpi = {'무선': 0, '유선': 0, '약갱': 0, '기타': 0};
  
  // [DASH] 본부/센터 카드 리스트
  List<Map<String, dynamic>> _hqList = [];
  List<Map<String, dynamic>> _centerList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadKpiData();
    _setupCsvReloadListener();
  }

  @override
  void dispose() {
    _csvReloadSubscription?.cancel();
    _reloadDebounceTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
  
  // [CSV_RELOAD] CSV 재로드 이벤트 구독 설정
  void _setupCsvReloadListener() {
    _csvReloadSubscription = CsvReloadBus().stream.listen((filename) {
      // KPI 파일인 경우에만 재로드
      if (isKpiFile(filename)) {
        debugPrint('[DASH] KPI 파일 재로드 이벤트 수신: $filename');
        _handleCsvReload(filename);
      }
    });
  }
  
  // [CSV_RELOAD] CSV 재로드 처리 (debounce 300ms)
  void _handleCsvReload(String filename) {
    // 중복 로딩 방지
    if (_isReloading || _isLoading) {
      debugPrint('[DASH] 이미 로딩 중이므로 재로드 건너뜀');
      return;
    }
    
    // debounce: 300ms 대기
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isReloading && !_isLoading) {
        debugPrint('[DASH] CSV 재로드 시작: $filename');
        _loadKpiData();
      }
    });
  }

  // [DASH] KPI CSV 로딩/캐싱
  Future<void> _loadKpiData() async {
    // 중복 로딩 방지
    if (_isReloading || _isLoading) {
      debugPrint('[DASH] 이미 로딩 중이므로 건너뜀');
      return;
    }
    
    try {
      setState(() {
        _isReloading = true;
        _isLoading = true;
        _errorMessage = null;
      });

      debugPrint('[DASH] KPI CSV 파일 로딩 시작...');
      
      // [CSV] 4개 CSV 파일 병렬 로드
      final csvResults = await CsvService.loadMultiple([
        'kpi_mobile.csv',
        'kpi_it.csv',
        'kpi_itr.csv',
        'kpi_etc.csv',
      ]);
      
      final String mobileCsv = csvResults['kpi_mobile.csv'] ?? '';
      final String itCsv = csvResults['kpi_it.csv'] ?? '';
      final String itrCsv = csvResults['kpi_itr.csv'] ?? '';
      final String etcCsv = csvResults['kpi_etc.csv'] ?? '';

      // CSV 파싱
      final List<Map<String, dynamic>> allData = [];
      allData.addAll(_parseKpiCsv(mobileCsv, '무선'));
      allData.addAll(_parseKpiCsv(itCsv, '유선'));
      allData.addAll(_parseKpiCsv(itrCsv, '약갱'));
      allData.addAll(_parseKpiCsv(etcCsv, '기타'));

      // 연월 목록 추출 (합집합, 정규화하여 중복 제거)
      final yearMonthSet = <String>{};
      final yearMonthIntMap = <int, String>{}; // int -> 원본 문자열 매핑
      for (final data in allData) {
        final ym = data['yearMonth'] as String?;
        if (ym != null && ym.isNotEmpty) {
          final ymInt = parseYearMonthToInt(ym);
          if (ymInt != null) {
            // 정규화된 연월을 키로 사용하되, 원본 문자열 저장
            if (!yearMonthIntMap.containsKey(ymInt)) {
              yearMonthIntMap[ymInt] = ym;
              yearMonthSet.add(ym);
            }
          } else {
            // 파싱 실패한 경우 원본 그대로 추가
            yearMonthSet.add(ym);
          }
        }
      }

      // 연월 정렬 (최신순)
      final sortedYearMonths = yearMonthSet.toList()..sort((a, b) {
        final aInt = parseYearMonthToInt(a) ?? 0;
        final bInt = parseYearMonthToInt(b) ?? 0;
        return bInt.compareTo(aInt); // 내림차순
      });

      if (mounted) {
        setState(() {
          _allKpiData = allData;
          _availableYearMonths = sortedYearMonths.toSet();
          // [FIX] 초기: 가장 최근 연월 1개만 선택
          _selectedYearMonths = sortedYearMonths.isNotEmpty 
              ? {sortedYearMonths.first} 
              : <String>{};
          _isLoading = false;
          _isReloading = false;
        });

        _calculateKpi();
        debugPrint('[DASH] KPI 데이터 로딩 완료: ${allData.length}건, 연월 ${sortedYearMonths.length}개');
      }
    } catch (e, stackTrace) {
      debugPrint('[DASH] ❌ CSV 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isReloading = false;
          _errorMessage = '대시보드 데이터를 불러올 수 없습니다: ${e.toString()}';
        });
      }
    }
  }

  // [DASH] KPI CSV 파싱
  List<Map<String, dynamic>> _parseKpiCsv(String csvData, String category) {
    final List<Map<String, dynamic>> dataList = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return dataList;

    // BOM 제거 및 구분자 감지
    final firstLine = _removeBOM(lines[0]);
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';
    
    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    
    final int yearMonthIndex = _findHeaderIndex(headers, ['연월', '기준연월', 'yearMonth', 'YYYYMM']);
    final int hqIndex = _findHeaderIndex(headers, ['본부', 'hq']);
    final int centerIndex = _findHeaderIndex(headers, ['센터', 'center', '프론티어센터']);
    final int nameIndex = _findHeaderIndex(headers, ['성명', '이름', 'name']);
    final int typeIndex = _findHeaderIndex(headers, ['유형', 'type']);
    final int actualIndex = _findHeaderIndex(headers, ['실적', 'actual', '달성']);

    if (yearMonthIndex == -1 || actualIndex == -1) {
      debugPrint('[DASH] $category CSV: 필수 헤더를 찾을 수 없습니다');
      return dataList;
    }

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
      if (values.length < headers.length) continue;

      try {
        final actual = int.tryParse(values[actualIndex]) ?? 0;
        dataList.add({
          'yearMonth': values[yearMonthIndex],
          'hq': hqIndex != -1 && hqIndex < values.length ? values[hqIndex] : '',
          'center': centerIndex != -1 && centerIndex < values.length ? values[centerIndex] : '',
          'name': nameIndex != -1 && nameIndex < values.length ? values[nameIndex] : '',
          'type': typeIndex != -1 && typeIndex < values.length ? values[typeIndex] : '',
          'category': category,
          'actual': actual,
        });
      } catch (e) {
        continue;
      }
    }

    return dataList;
  }

  int _findHeaderIndex(List<String> headers, List<String> keywords) {
    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase();
      for (final keyword in keywords) {
        if (header.contains(keyword.toLowerCase())) {
          return i;
        }
      }
    }
    return -1;
  }

  String _removeBOM(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  // [DASH] 전체현황 KPI 집계
  void _calculateKpi() {
    // 선택된 연월로 필터링 (연월 정규화하여 비교)
    final selectedYearMonthInts = _selectedYearMonths
        .map((ym) => parseYearMonthToInt(ym))
        .whereType<int>()
        .toSet();
    
    final filteredData = _allKpiData.where((data) {
      final ym = data['yearMonth'] as String? ?? '';
      if (ym.isEmpty) return false;
      final ymInt = parseYearMonthToInt(ym);
      if (ymInt == null) return false;
      return selectedYearMonthInts.contains(ymInt);
    }).toList();
    
    debugPrint('[DASH] 필터링: 선택된 연월 ${_selectedYearMonths.length}개, 필터링된 데이터 ${filteredData.length}건');

    // 전체현황 집계 (유형 필터링)
    final Map<String, int> overall = {'무선': 0, '유선': 0, '약갱': 0, '기타': 0};
    for (final data in filteredData) {
      final category = data['category'] as String;
      final type = data['type'] as String? ?? '';
      final actual = data['actual'] as int? ?? 0;
      
      // 유형 필터링
      if (category == '무선' && type.contains('무선총계')) {
        overall['무선'] = (overall['무선'] ?? 0) + actual;
      } else if (category == '유선' && type.contains('유선순신규총계')) {
        overall['유선'] = (overall['유선'] ?? 0) + actual;
      } else if (category == '약갱' && type.contains('유선약정갱신총계')) {
        overall['약갱'] = (overall['약갱'] ?? 0) + actual;
      } else if (category == '기타' && type.contains('기타상품') && type.contains('총계')) {
        overall['기타'] = (overall['기타'] ?? 0) + actual;
      }
    }

    // 본부별 집계 (유형 필터링)
    final Map<String, Map<String, int>> hqMap = {};
    for (final data in filteredData) {
      final hq = data['hq'] as String? ?? '';
      if (hq.isEmpty) continue;
      final category = data['category'] as String;
      final type = data['type'] as String? ?? '';
      final actual = data['actual'] as int? ?? 0;
      
      hqMap.putIfAbsent(hq, () => {'무선': 0, '유선': 0, '약갱': 0, '기타': 0});
      
      // 유형 필터링
      if (category == '무선' && type.contains('무선총계')) {
        hqMap[hq]!['무선'] = (hqMap[hq]!['무선'] ?? 0) + actual;
      } else if (category == '유선' && type.contains('유선순신규총계')) {
        hqMap[hq]!['유선'] = (hqMap[hq]!['유선'] ?? 0) + actual;
      } else if (category == '약갱' && type.contains('유선약정갱신총계')) {
        hqMap[hq]!['약갱'] = (hqMap[hq]!['약갱'] ?? 0) + actual;
      } else if (category == '기타' && type.contains('기타상품') && type.contains('총계')) {
        hqMap[hq]!['기타'] = (hqMap[hq]!['기타'] ?? 0) + actual;
      }
    }

    // 센터별 집계 (유형 필터링)
    final Map<String, Map<String, int>> centerMap = {};
    for (final data in filteredData) {
      final center = data['center'] as String? ?? '';
      if (center.isEmpty) continue;
      final category = data['category'] as String;
      final type = data['type'] as String? ?? '';
      final actual = data['actual'] as int? ?? 0;
      
      centerMap.putIfAbsent(center, () => {'무선': 0, '유선': 0, '약갱': 0, '기타': 0});
      
      // 유형 필터링
      if (category == '무선' && type.contains('무선총계')) {
        centerMap[center]!['무선'] = (centerMap[center]!['무선'] ?? 0) + actual;
      } else if (category == '유선' && type.contains('유선순신규총계')) {
        centerMap[center]!['유선'] = (centerMap[center]!['유선'] ?? 0) + actual;
      } else if (category == '약갱' && type.contains('유선약정갱신총계')) {
        centerMap[center]!['약갱'] = (centerMap[center]!['약갱'] ?? 0) + actual;
      } else if (category == '기타' && type.contains('기타상품') && type.contains('총계')) {
        centerMap[center]!['기타'] = (centerMap[center]!['기타'] ?? 0) + actual;
      }
    }

    // 본부 리스트 생성 (강북, 강남, 강서, 동부, 서부 순서)
    final hqOrder = ['강북', '강남', '강서', '동부', '서부'];
    _hqList = hqMap.entries.map((entry) {
      final total = (entry.value['무선'] ?? 0) + (entry.value['유선'] ?? 0) + 
                     (entry.value['약갱'] ?? 0) + (entry.value['기타'] ?? 0);
      return {
        'hq': entry.key,
        'kpi': entry.value,
        'total': total,
      };
    }).toList()..sort((a, b) {
      final aIndex = hqOrder.indexOf(a['hq'] as String);
      final bIndex = hqOrder.indexOf(b['hq'] as String);
      if (aIndex == -1 && bIndex == -1) return 0;
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    // 센터 리스트 생성 (지정된 순서)
    final centerOrder = ['강북센터', '강동센터', '강원센터', '강남센터', '남부센터', '강서센터', 
                         '인천센터', '부산센터', '경남센터', '대구센터', '충청센터', '광주센터', '전남센터'];
    _centerList = centerMap.entries.map((entry) {
      final total = (entry.value['무선'] ?? 0) + (entry.value['유선'] ?? 0) + 
                     (entry.value['약갱'] ?? 0) + (entry.value['기타'] ?? 0);
      return {
        'center': entry.key,
        'kpi': entry.value,
        'total': total,
      };
    }).toList()..sort((a, b) {
      final aCenter = a['center'] as String;
      final bCenter = b['center'] as String;
      final aIndex = centerOrder.indexWhere((c) => aCenter.contains(c.replaceAll('센터', '')) || aCenter == c);
      final bIndex = centerOrder.indexWhere((c) => bCenter.contains(c.replaceAll('센터', '')) || bCenter == c);
      if (aIndex == -1 && bIndex == -1) return 0;
      if (aIndex == -1) return 1;
      if (bIndex == -1) return -1;
      return aIndex.compareTo(bIndex);
    });

    setState(() {
      _overallKpi = overall;
    });
  }

  // [DASH] 연월 멀티 선택 UI
  void _showYearMonthSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sortedYearMonths = _availableYearMonths.toList()..sort((a, b) {
              final aInt = parseYearMonthToInt(a) ?? 0;
              final bInt = parseYearMonthToInt(b) ?? 0;
              return bInt.compareTo(aInt); // 내림차순
            });

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '연월 선택',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  _selectedYearMonths = _availableYearMonths.toSet();
                                });
                              },
                              child: const Text('전체 선택'),
                            ),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  _selectedYearMonths.clear();
                                });
                              },
                              child: const Text('전체 해제'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: sortedYearMonths.length,
                      itemBuilder: (context, index) {
                        final ym = sortedYearMonths[index];
                        final isSelected = _selectedYearMonths.contains(ym);
                        return CheckboxListTile(
                          title: Text(ym),
                          value: isSelected,
                          onChanged: (value) {
                            setModalState(() {
                              if (value == true) {
                                _selectedYearMonths.add(ym);
                              } else {
                                _selectedYearMonths.remove(ym);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {});
                              _calculateKpi();
                              Navigator.pop(context);
                            },
                            child: const Text('확인'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getYearMonthSummary() {
    if (_selectedYearMonths.length == _availableYearMonths.length) {
      return '전체';
    } else if (_selectedYearMonths.isEmpty) {
      return '선택 없음';
    } else {
      return '선택 ${_selectedYearMonths.length}개';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 타이틀
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '대시보드',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                                const SizedBox(height: 16),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.red[700], fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadKpiData,
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // [DASH] 연월 멀티 선택 UI
                              _YearMonthFilterCard(
                                summary: _getYearMonthSummary(),
                                onTap: _showYearMonthSelector,
                    ),
                    const SizedBox(height: 16),
                              // [DASH] 전체현황 KPI 집계
                              Row(
                                children: [
                                  const Text(
                                    '전체현황',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '선택 연월 기준',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                    ),
                  ],
                ),
                              const SizedBox(height: 12),
                              _OverallKpiGrid(kpi: _overallKpi),
                              const SizedBox(height: 24),
                              // [DASH] 본부/센터 카드 리스트
                              TabBar(
                                controller: _tabController,
                                tabs: const [
                                  Tab(text: '본부별'),
                                  Tab(text: '프론티어센터별'),
                                ],
                              ),
                              SizedBox(
                                height: 400,
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _HqListTab(hqList: _hqList, allData: _allKpiData, selectedYearMonths: _selectedYearMonths),
                                    _CenterListTab(centerList: _centerList, allData: _allKpiData, selectedYearMonths: _selectedYearMonths),
                                  ],
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// [DASH] 연월 멀티 선택 UI
class _YearMonthFilterCard extends StatelessWidget {
  final String summary;
  final VoidCallback onTap;

  const _YearMonthFilterCard({
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
      child: Padding(
            padding: const EdgeInsets.all(16),
        child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '연월 선택',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right, color: Color(0xFFFF6F61)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// [DASH] 전체현황 KPI 집계 - 2x2 그리드
class _OverallKpiGrid extends StatelessWidget {
  final Map<String, int> kpi;

  const _OverallKpiGrid({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final kpiItems = [
      {'label': '무선', 'value': kpi['무선'] ?? 0, 'color': const Color(0xFFFF6F61)},
      {'label': '유선', 'value': kpi['유선'] ?? 0, 'color': Colors.blue},
      {'label': '약갱', 'value': kpi['약갱'] ?? 0, 'color': Colors.green},
      {'label': '기타', 'value': kpi['기타'] ?? 0, 'color': Colors.orange},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.4, // 높이 절반으로 줄임 (1.2 -> 2.4)
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final item = kpiItems[index];
        return Container(
              decoration: BoxDecoration(
            color: Colors.white,
                borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatNumber(item['value'] as int),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: item['color'] as Color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatNumber(int value) {
    // 1000단위 콤마 표시
    return value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

// [DASH] 본부/센터 카드 리스트
class _HqListTab extends StatelessWidget {
  final List<Map<String, dynamic>> hqList;
  final List<Map<String, dynamic>> allData;
  final Set<String> selectedYearMonths;

  const _HqListTab({
    required this.hqList,
    required this.allData,
    required this.selectedYearMonths,
  });

  @override
  Widget build(BuildContext context) {
    if (hqList.isEmpty) {
      return const Center(
        child: Text(
          '데이터가 없습니다',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: hqList.length,
      itemBuilder: (context, index) {
        final hq = hqList[index];
        final kpi = hq['kpi'] as Map<String, int>;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _HqDetailScreen(
                      hqName: hq['hq'] as String,
                      allData: allData,
                      selectedYearMonths: selectedYearMonths,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                            hq['hq'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _MiniTile(label: '무선', value: kpi['무선'] ?? 0),
                              _MiniTile(label: '유선', value: kpi['유선'] ?? 0),
                              _MiniTile(label: '약갱', value: kpi['약갱'] ?? 0),
                              _MiniTile(label: '기타', value: kpi['기타'] ?? 0),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFFF6F61)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CenterListTab extends StatelessWidget {
  final List<Map<String, dynamic>> centerList;
  final List<Map<String, dynamic>> allData;
  final Set<String> selectedYearMonths;

  const _CenterListTab({
    required this.centerList,
    required this.allData,
    required this.selectedYearMonths,
  });

  @override
  Widget build(BuildContext context) {
    if (centerList.isEmpty) {
      return const Center(
        child: Text(
          '데이터가 없습니다',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: centerList.length,
      itemBuilder: (context, index) {
        final center = centerList[index];
        final kpi = center['kpi'] as Map<String, int>;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => _CenterDetailScreen(
                      centerName: center['center'] as String,
                      allData: allData,
                      selectedYearMonths: selectedYearMonths,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            center['center'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _MiniTile(label: '무선', value: kpi['무선'] ?? 0),
                              _MiniTile(label: '유선', value: kpi['유선'] ?? 0),
                              _MiniTile(label: '약갱', value: kpi['약갱'] ?? 0),
                              _MiniTile(label: '기타', value: kpi['기타'] ?? 0),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFFFF6F61)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// 미니 타일 위젯
class _MiniTile extends StatelessWidget {
  final String label;
  final int value;

  const _MiniTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${_formatNumber(value)}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[700],
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    // 1000단위 콤마 표시
    return value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

// [DASH] 상세 화면 - 본부 상세
class _HqDetailScreen extends StatelessWidget {
  final String hqName;
  final List<Map<String, dynamic>> allData;
  final Set<String> selectedYearMonths;

  const _HqDetailScreen({
    required this.hqName,
    required this.allData,
    required this.selectedYearMonths,
  });

  Map<String, int> _calculateHqKpi() {
    final selectedYearMonthInts = selectedYearMonths
        .map((ym) => parseYearMonthToInt(ym))
        .whereType<int>()
        .toSet();
    
    final filtered = allData.where((data) {
      final hq = data['hq'] as String? ?? '';
      final ym = data['yearMonth'] as String? ?? '';
      if (hq != hqName) return false;
      if (ym.isEmpty) return false;
      final ymInt = parseYearMonthToInt(ym);
      if (ymInt == null) return false;
      return selectedYearMonthInts.contains(ymInt);
    }).toList();

    final Map<String, int> kpi = {'무선': 0, '유선': 0, '약갱': 0, '기타': 0};
    for (final data in filtered) {
      final category = data['category'] as String;
      final type = data['type'] as String? ?? '';
      final actual = data['actual'] as int? ?? 0;
      
      // 유형 필터링
      if (category == '무선' && type.contains('무선총계')) {
        kpi['무선'] = (kpi['무선'] ?? 0) + actual;
      } else if (category == '유선' && type.contains('유선순신규총계')) {
        kpi['유선'] = (kpi['유선'] ?? 0) + actual;
      } else if (category == '약갱' && type.contains('유선약정갱신총계')) {
        kpi['약갱'] = (kpi['약갱'] ?? 0) + actual;
      } else if (category == '기타' && type.contains('기타상품') && type.contains('총계')) {
        kpi['기타'] = (kpi['기타'] ?? 0) + actual;
      }
    }
    return kpi;
  }

  List<Map<String, dynamic>> _getYearMonthBreakdown() {
    final selectedYearMonthInts = selectedYearMonths
        .map((ym) => parseYearMonthToInt(ym))
        .whereType<int>()
        .toSet();
    
    final Map<String, Map<String, Map<String, int>>> breakdown = {};
    for (final data in allData) {
      final hq = data['hq'] as String? ?? '';
      final ym = data['yearMonth'] as String? ?? '';
      if (hq != hqName) continue;
      if (ym.isEmpty) continue;
      final ymInt = parseYearMonthToInt(ym);
      if (ymInt == null || !selectedYearMonthInts.contains(ymInt)) continue;

      // 유형 필터링 (총계 유형은 제외하고 세부 유형만 포함)
      final category = data['category'] as String;
      final type = data['type'] as String? ?? '';
      final actual = data['actual'] as int? ?? 0;
      
      // 총계 유형은 제외하고 세부 유형만 포함
      final isTotalType = type.contains('무선총계') || 
                          type.contains('유선순신규총계') || 
                          type.contains('유선약정갱신총계') ||
                          (type.contains('기타상품') && type.contains('총계'));
      if (isTotalType) continue;
      
      String? targetCategory;
      if (category == '무선') {
        targetCategory = '무선';
      } else if (category == '유선') {
        targetCategory = '유선';
      } else if (category == '약갱') {
        targetCategory = '약갱';
      } else if (category == '기타') {
        targetCategory = '기타';
      }
      
      if (targetCategory != null) {
        breakdown.putIfAbsent(ym, () => <String, Map<String, int>>{});
        breakdown[ym]!.putIfAbsent(targetCategory, () => <String, int>{});
        final currentValue = breakdown[ym]![targetCategory]![type] ?? 0;
        breakdown[ym]![targetCategory]![type] = currentValue + actual;
      }
    }

    return breakdown.entries.map((entry) {
      return {
        'yearMonth': entry.key,
        'categoryData': entry.value,
      };
    }).toList()..sort((a, b) {
      final aInt = parseYearMonthToInt(a['yearMonth'] as String) ?? 0;
      final bInt = parseYearMonthToInt(b['yearMonth'] as String) ?? 0;
      return bInt.compareTo(aInt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final kpi = _calculateHqKpi();
    final breakdown = _getYearMonthBreakdown();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(hqName),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverallKpiGrid(kpi: kpi),
              const SizedBox(height: 24),
              const Text(
                '연월별 상세',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              ...breakdown.map((item) {
                final ym = item['yearMonth'] as String;
                final categoryData = item['categoryData'] as Map<String, Map<String, int>>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ExpansionTile(
                    title: Text(
                      ym,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    children: [
                      ...['무선', '유선', '약갱', '기타'].map((cat) {
                        // 카테고리별 총계 유형 이름 결정
                        String totalTypeName;
                        String totalTypeFilter;
                        if (cat == '무선') {
                          totalTypeName = '무선총계';
                          totalTypeFilter = '무선총계';
                        } else if (cat == '유선') {
                          totalTypeName = '유선순신규총계';
                          totalTypeFilter = '유선순신규총계';
                        } else if (cat == '약갱') {
                          totalTypeName = '유선약정갱신총계';
                          totalTypeFilter = '유선약정갱신총계';
                        } else if (cat == '기타') {
                          totalTypeName = '기타상품총계';
                          totalTypeFilter = '기타상품총계';
                        } else {
                          totalTypeName = cat;
                          totalTypeFilter = '';
                        }
                        
                        // 해당 연월의 원본 데이터에서 총계 유형 실적 가져오기
                        final selectedYearMonthInts = selectedYearMonths
                            .map((ym) => parseYearMonthToInt(ym))
                            .whereType<int>()
                            .toSet();
                        final ymInt = parseYearMonthToInt(ym);
                        final totalData = allData.where((data) {
                          final dataHq = data['hq'] as String? ?? '';
                          final dataYm = data['yearMonth'] as String? ?? '';
                          final dataCategory = data['category'] as String;
                          final dataType = data['type'] as String? ?? '';
                          if (dataHq != hqName) return false;
                          if (dataYm.isEmpty) return false;
                          final dataYmInt = parseYearMonthToInt(dataYm);
                          if (dataYmInt == null || dataYmInt != ymInt) return false;
                          if (dataCategory != cat) return false;
                          if (cat == '기타') {
                            return dataType.contains('기타상품') && dataType.contains('총계');
                          }
                          return dataType.contains(totalTypeFilter);
                        }).toList();
                        
                        // 총계 유형 실적 계산
                        final totalActual = totalData.fold<int>(0, (sum, p) => sum + (p['actual'] as int? ?? 0));
                        
                        final catData = categoryData[cat];
                        if (catData == null || catData.isEmpty) {
                          // 총계 유형 실적이 있으면 표시
                          if (totalActual > 0) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    totalTypeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '실적: $totalActual건',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 카테고리 헤더 (총계 유형 이름과 실적 표시)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    totalTypeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '실적: $totalActual건',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                              // 유형별 상세 데이터 (총계 유형 제외)
                              if (catData.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...catData.entries.map((entry) {
                                  final type = entry.key;
                                  final typeActual = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '  • $type',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        Text(
                                          '$typeActual건',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// [DASH] 상세 화면 - 센터 상세
class _CenterDetailScreen extends StatelessWidget {
  final String centerName;
  final List<Map<String, dynamic>> allData;
  final Set<String> selectedYearMonths;

  const _CenterDetailScreen({
    required this.centerName,
    required this.allData,
    required this.selectedYearMonths,
  });

  Map<String, int> _calculateCenterKpi() {
    final selectedYearMonthInts = selectedYearMonths
        .map((ym) => parseYearMonthToInt(ym))
        .whereType<int>()
        .toSet();
    
    final filtered = allData.where((data) {
      final center = data['center'] as String? ?? '';
      final ym = data['yearMonth'] as String? ?? '';
      if (center != centerName) return false;
      if (ym.isEmpty) return false;
      final ymInt = parseYearMonthToInt(ym);
      if (ymInt == null) return false;
      return selectedYearMonthInts.contains(ymInt);
    }).toList();

    final Map<String, int> kpi = {'무선': 0, '유선': 0, '약갱': 0, '기타': 0};
    for (final data in filtered) {
      final category = data['category'] as String;
      final type = data['type'] as String? ?? '';
      final actual = data['actual'] as int? ?? 0;
      
      // 유형 필터링
      if (category == '무선' && type.contains('무선총계')) {
        kpi['무선'] = (kpi['무선'] ?? 0) + actual;
      } else if (category == '유선' && type.contains('유선순신규총계')) {
        kpi['유선'] = (kpi['유선'] ?? 0) + actual;
      } else if (category == '약갱' && type.contains('유선약정갱신총계')) {
        kpi['약갱'] = (kpi['약갱'] ?? 0) + actual;
      } else if (category == '기타' && type.contains('기타상품') && type.contains('총계')) {
        kpi['기타'] = (kpi['기타'] ?? 0) + actual;
      }
    }
    return kpi;
  }

  List<Map<String, dynamic>> _getYearMonthBreakdown() {
    final selectedYearMonthInts = selectedYearMonths
        .map((ym) => parseYearMonthToInt(ym))
        .whereType<int>()
        .toSet();
    
    // 연월별로 데이터 그룹화 (유형별 상세 포함)
    final Map<String, List<Map<String, dynamic>>> yearMonthData = {};
    for (final data in allData) {
      final center = data['center'] as String? ?? '';
      final ym = data['yearMonth'] as String? ?? '';
      if (center != centerName) continue;
      if (ym.isEmpty) continue;
      final ymInt = parseYearMonthToInt(ym);
      if (ymInt == null || !selectedYearMonthInts.contains(ymInt)) continue;

      yearMonthData.putIfAbsent(ym, () => []);
      yearMonthData[ym]!.add(data);
    }

    // 연월별로 카테고리/유형별 집계
    final List<Map<String, dynamic>> breakdown = [];
    for (final entry in yearMonthData.entries) {
      final ym = entry.key;
      final dataList = entry.value;
      
      // 카테고리별로 그룹화
      final Map<String, Map<String, int>> categoryMap = {};
      for (final data in dataList) {
        final category = data['category'] as String;
        final type = data['type'] as String? ?? '';
        final actual = data['actual'] as int? ?? 0;
        
        // 유형 필터링 (총계 유형은 제외하고 세부 유형만 포함)
        final isTotalType = type.contains('무선총계') || 
                            type.contains('유선순신규총계') || 
                            type.contains('유선약정갱신총계') ||
                            (type.contains('기타상품') && type.contains('총계'));
        if (isTotalType) continue;
        
        String? targetCategory;
        if (category == '무선') {
          targetCategory = '무선';
        } else if (category == '유선') {
          targetCategory = '유선';
        } else if (category == '약갱') {
          targetCategory = '약갱';
        } else if (category == '기타') {
          targetCategory = '기타';
        }
        
        if (targetCategory != null) {
          categoryMap.putIfAbsent(targetCategory, () => {});
          categoryMap[targetCategory]![type] = (categoryMap[targetCategory]![type] ?? 0) + actual;
        }
      }
      
      breakdown.add({
        'yearMonth': ym,
        'categoryData': categoryMap,
      });
    }

    breakdown.sort((a, b) {
      final aInt = parseYearMonthToInt(a['yearMonth'] as String) ?? 0;
      final bInt = parseYearMonthToInt(b['yearMonth'] as String) ?? 0;
      return bInt.compareTo(aInt);
    });
    
    return breakdown;
  }

  @override
  Widget build(BuildContext context) {
    final kpi = _calculateCenterKpi();
    final breakdown = _getYearMonthBreakdown();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(centerName),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OverallKpiGrid(kpi: kpi),
              const SizedBox(height: 24),
              const Text(
                '연월별 상세',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              ...breakdown.map((item) {
                final ym = item['yearMonth'] as String;
                final categoryData = item['categoryData'] as Map<String, Map<String, int>>;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ExpansionTile(
                    title: Text(
                      ym,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    children: [
                      ...['무선', '유선', '약갱', '기타'].map((cat) {
                        // 카테고리별 총계 유형 이름 결정
                        String totalTypeName;
                        String totalTypeFilter;
                        if (cat == '무선') {
                          totalTypeName = '무선총계';
                          totalTypeFilter = '무선총계';
                        } else if (cat == '유선') {
                          totalTypeName = '유선순신규총계';
                          totalTypeFilter = '유선순신규총계';
                        } else if (cat == '약갱') {
                          totalTypeName = '유선약정갱신총계';
                          totalTypeFilter = '유선약정갱신총계';
                        } else if (cat == '기타') {
                          totalTypeName = '기타상품총계';
                          totalTypeFilter = '기타상품총계';
                        } else {
                          totalTypeName = cat;
                          totalTypeFilter = '';
                        }
                        
                        // 해당 연월의 원본 데이터에서 총계 유형 실적 가져오기
                        final selectedYearMonthInts = selectedYearMonths
                            .map((ym) => parseYearMonthToInt(ym))
                            .whereType<int>()
                            .toSet();
                        final ymInt = parseYearMonthToInt(ym);
                        final totalData = allData.where((data) {
                          final dataCenter = data['center'] as String? ?? '';
                          final dataYm = data['yearMonth'] as String? ?? '';
                          final dataCategory = data['category'] as String;
                          final dataType = data['type'] as String? ?? '';
                          if (dataCenter != centerName) return false;
                          if (dataYm.isEmpty) return false;
                          final dataYmInt = parseYearMonthToInt(dataYm);
                          if (dataYmInt == null || dataYmInt != ymInt) return false;
                          if (dataCategory != cat) return false;
                          if (cat == '기타') {
                            return dataType.contains('기타상품') && dataType.contains('총계');
                          }
                          return dataType.contains(totalTypeFilter);
                        }).toList();
                        
                        // 총계 유형 실적 계산
                        final totalActual = totalData.fold<int>(0, (sum, p) => sum + (p['actual'] as int? ?? 0));
                        
                        final catData = categoryData[cat];
                        if (catData == null || catData.isEmpty) {
                          // 총계 유형 실적이 있으면 표시
                          if (totalActual > 0) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    totalTypeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '실적: $totalActual건',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 카테고리 헤더 (총계 유형 이름과 실적 표시)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    totalTypeName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    '실적: $totalActual건',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                              // 유형별 상세 데이터 (총계 유형 제외)
                              if (catData.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...catData.entries.map((entry) {
                                  final type = entry.key;
                                  final typeActual = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '  • $type',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        Text(
                                          '$typeActual건',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================
// 즐겨찾기 화면 - 즐겨찾기한 고객사 리스트
// ========================================
// [FAV] 즐겨찾기 탭 필터링
class FavoritesScreen extends StatefulWidget {
  final Set<String> favoriteKeys;
  final Future<void> Function(String) onToggleFavorite;
  final bool Function(String) isFavorite;

  const FavoritesScreen({
    super.key,
    required this.favoriteKeys,
    required this.onToggleFavorite,
    required this.isFavorite,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<CustomerData> _favoriteCustomers = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadFavoriteCustomers();
  }
  
  @override
  void didUpdateWidget(FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [FAV] 즐겨찾기 키 변경 시 목록 갱신
    if (oldWidget.favoriteKeys != widget.favoriteKeys) {
      _loadFavoriteCustomers();
    }
  }
  
  // [FAV] [RBAC] 즐겨찾기 고객사 로드 (Repository + RBAC)
  Future<void> _loadFavoriteCustomers() async {
    try {
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final currentUser = authService.currentUser;
      
      // RBAC 필터링된 고객 목록 가져오기
      final customers = await customerRepo.getFiltered(currentUser);
      final customerDataList = CustomerConverter.toCustomerDataList(customers);
      
      // [FAV] 즐겨찾기 키에 해당하는 고객사만 필터링
      final favorites = customerDataList.where((customer) {
        return widget.favoriteKeys.contains(customer.customerKey);
      }).toList();
      
      // 즐겨찾기 상태 설정
      for (final customer in favorites) {
        customer.isFavorite = true;
      }
      
      // 고객사명 오름차순 정렬
      favorites.sort((a, b) => a.customerName.compareTo(b.customerName));
      
      setState(() {
        _favoriteCustomers = favorites;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('즐겨찾기 고객사 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // BOM 제거
  String _removeBOM(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      return text.substring(1);
    }
    return text;
  }

  // CSV 파싱 로직
  Future<List<CustomerData>> _parseCsv(String csvData) async {
    final List<CustomerData> customers = [];
    final List<String> lines = csvData.split('\n');

    if (lines.isEmpty) return customers;

    final firstLine = _removeBOM(lines[0]);
    final bool isTabDelimited = firstLine.contains('\t');
    final String delimiter = isTabDelimited ? '\t' : ',';

    final List<String> headers = firstLine.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    
    final int hqIndex = headers.indexWhere((h) => h.contains('본부'));
    final int branchIndex = headers.indexWhere((h) => h.contains('지사'));
    final int customerNameIndex = headers.indexWhere((h) => h.contains('고객명'));
    final int openedAtIndex = headers.indexWhere((h) => h.contains('개통일자') || h.contains('개통일'));
    final int productTypeIndex = headers.indexWhere((h) => h.contains('상품유형') || h.contains('유형'));
    final int productNameIndex = headers.indexWhere((h) => h.contains('상품명'));
    final int sellerIndex = headers.indexWhere((h) => h.contains('실판매자') || h.contains('판매자') || h.contains('MATE'));
    final int buildingIndex = headers.indexWhere((h) => h.contains('건물명') || h.contains('건물'));

    if (hqIndex == -1 || branchIndex == -1 || customerNameIndex == -1 ||
        openedAtIndex == -1 || productTypeIndex == -1 || productNameIndex == -1 ||
        sellerIndex == -1 || buildingIndex == -1) {
      return customers;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    for (int i = 1; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;

      final List<String> values = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();

      if (values.length < headers.length) continue;

      try {
        final customer = CustomerData(
          customerName: values[customerNameIndex],
          openedAt: values[openedAtIndex],
          productName: values[productNameIndex],
          productType: values[productTypeIndex],
          hq: values[hqIndex],
          branch: values[branchIndex],
          seller: values[sellerIndex],
          building: values[buildingIndex],
          salesStatus: '영업전',
          memo: '',
        );

        final String? savedStatus = prefs.getString('${customer.customerKey}_status');
        final String? savedMemo = prefs.getString('${customer.customerKey}_memo');

        if (savedStatus != null) {
          customer.salesStatus = savedStatus;
        }
        if (savedMemo != null) {
          customer.memo = savedMemo;
        }

        customers.add(customer);
      } catch (e) {
        continue;
      }
    }

    return customers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '즐겨찾기 고객사 ${_favoriteCustomers.length}건',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
            // 즐겨찾기 리스트 또는 안내 문구
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _favoriteCustomers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star_border,
                                size: 64,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '즐겨찾기한 고객사가 없습니다',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          itemCount: _favoriteCustomers.length,
                          itemBuilder: (context, index) {
                            final customer = _favoriteCustomers[index];
                            return _CustomerCard(
                              customer: customer,
                              isFavorite: widget.isFavorite(customer.customerKey),
                              onFavoriteToggle: () async {
                                await widget.onToggleFavorite(customer.customerKey);
                                // [FAV] 즐겨찾기 해제 시 목록 갱신
                                _loadFavoriteCustomers();
                              },
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CustomerDetailScreen(
                                      customer: customer,
                                      onFavoriteChanged: () {
                                        _loadFavoriteCustomers();
                                      },
                                    ),
                                  ),
                                );
                                // 상세 화면에서 돌아올 때 목록 갱신
                                _loadFavoriteCustomers();
                              },
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

// ========================================
// OD 화면 - 웹뷰
// [FIX] OD WebView ERR_CACHE_MISS 대응
// ========================================
class ODScreen extends StatefulWidget {
  const ODScreen({super.key});

  @override
  State<ODScreen> createState() => _ODScreenState();
}

class _ODScreenState extends State<ODScreen> {
  // [WEB] 웹에서는 WebViewController를 사용하지 않음
  dynamic _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  final String _targetUrl = 'https://kimyoung-gi.github.io/11/';
  int _retryCount = 0;
  final int _maxRetries = 1;
  final UniqueKey _webViewKey = UniqueKey(); // [FIX] OD WebView ERR_CACHE_MISS 대응 - WebView 재생성을 위한 키

  @override
  void initState() {
    super.initState();
    // [WEB] 웹이 아닌 경우에만 WebView 초기화
    if (!kIsWeb) {
      _initializeWebView();
    } else {
      // [WEB] 웹에서는 즉시 로딩 완료로 표시
      setState(() {
        _isLoading = false;
      });
    }
  }

  // [FIX] OD WebView ERR_CACHE_MISS 대응 - WebView 초기화 및 캐시 클리어
  // [WEB] 웹에서는 호출되지 않음
  void _initializeWebView() {
    if (kIsWeb) return; // [WEB] 웹에서는 실행하지 않음
    // [WEB] 웹이 아닌 경우에만 WebViewController 생성
    _controller = WebViewController()
      // [FIX] OD WebView ERR_CACHE_MISS 대응 - JavaScript 활성화
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // [FIX] OD WebView ERR_CACHE_MISS 대응 - NavigationDelegate 설정 (에러 처리 포함)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
              _errorMessage = null;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _hasError = false;
              _retryCount = 0; // 성공 시 재시도 카운터 리셋
              _hasLoadedOnce = true; // [FIX] OD WebView ERR_CACHE_MISS 대응 - 로드 완료 플래그 설정
              _lastLoadedUrl = url; // [FIX] OD WebView ERR_CACHE_MISS 대응 - 마지막 로드 URL 저장
            });
          },
          // [FIX] OD WebView ERR_CACHE_MISS 대응 - 웹 리소스 에러 처리
          onWebResourceError: (WebResourceError error) {
            debugPrint('OD WebView 에러: ${error.description}, errorCode: ${error.errorCode}');
            
            // ERR_CACHE_MISS 또는 네트워크 오류 감지
            final errorCode = error.errorCode;
            final isCacheMiss = error.description.toLowerCase().contains('cache_miss') || 
                               error.description.toLowerCase().contains('err_cache_miss') ||
                               errorCode == -2 || 
                               errorCode == -10 || 
                               (errorCode >= -1000 && errorCode <= -999);
            
            if (isCacheMiss && _retryCount < _maxRetries) {
              // [FIX] OD WebView ERR_CACHE_MISS 대응 - 자동 재시도 (최대 1회)
              _retryCount++;
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  _reloadWebView();
                }
              });
            } else {
              // [FIX] OD WebView ERR_CACHE_MISS 대응 - 재시도 실패 시 에러 UI 표시
              setState(() {
                _isLoading = false;
                _hasError = true;
                _errorMessage = error.description.isNotEmpty 
                    ? error.description 
                    : '페이지를 불러올 수 없습니다 (오류 코드: $errorCode)';
              });
            }
          },
        ),
      );

    // [FIX] OD WebView ERR_CACHE_MISS 대응 - 캐시 클리어 후 GET 방식으로 로드
    _loadUrl();
  }

  // [FIX] OD WebView ERR_CACHE_MISS 대응 - URL 로드 (캐시 클리어 포함)
  // [WEB] 웹에서는 호출되지 않음
  Future<void> _loadUrl() async {
    if (kIsWeb || _controller == null) return; // [WEB] 웹에서는 실행하지 않음
    try {
      // [FIX] OD WebView ERR_CACHE_MISS 대응 - 캐시 클리어
      await _controller!.clearCache();
      try {
        await _controller!.clearLocalStorage();
      } catch (e) {
        debugPrint('clearLocalStorage 실패 (iOS에서는 지원되지 않을 수 있음): $e');
      }
      
      // [FIX] OD WebView ERR_CACHE_MISS 대응 - GET 방식으로 강제 로드 (loadRequest는 기본적으로 GET 사용)
      await _controller!.loadRequest(Uri.parse(_targetUrl));
    } catch (e) {
      debugPrint('OD WebView 로드 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = '페이지를 불러올 수 없습니다: $e';
        });
      }
    }
  }

  // [FIX] OD WebView ERR_CACHE_MISS 대응 - WebView 재로드
  void _reloadWebView() {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });
    _loadUrl();
  }

  // [FIX] OD WebView ERR_CACHE_MISS 대응 - 외부 브라우저로 열기
  // [WEB] 웹에서는 새 탭에서 열기
  Future<void> _openInExternalBrowser() async {
    try {
      final Uri uri = Uri.parse(_targetUrl);
      if (kIsWeb) {
        // [WEB] 웹에서는 url_launcher 사용
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } else {
        // 모바일에서는 url_launcher 사용
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // 대체: 클립보드에 복사
          await Clipboard.setData(ClipboardData(text: _targetUrl));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('URL이 클립보드에 복사되었습니다: $_targetUrl'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('외부 브라우저 열기 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URL 열기 실패: $_targetUrl'),
          ),
        );
      }
    }
  }

  // [FIX] OD WebView ERR_CACHE_MISS 대응 - OD 탭 재진입 시 항상 새로 로드
  bool _hasLoadedOnce = false;
  String? _lastLoadedUrl;
  
  // [WEB] 웹에서 iframe 위젯 빌드
  Widget _buildWebIframe() {
    if (!kIsWeb) return const SizedBox();
    // [WEB] 웹에서는 universal_html을 사용하여 iframe 생성
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Builder(
        builder: (context) {
          // [WEB] 웹에서는 외부 브라우저로 열거나 iframe을 직접 렌더링
          // 여기서는 간단하게 외부 브라우저로 열도록 안내
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.language,
                  size: 64,
                  color: Color(0xFFFF6F61),
                ),
                const SizedBox(height: 16),
                const Text(
                  'OD 페이지',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _targetUrl,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _openInExternalBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('브라우저에서 열기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F61),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // [WEB] 웹에서는 실행하지 않음
    if (kIsWeb) return;
    // [FIX] OD WebView ERR_CACHE_MISS 대응 - 화면 재진입 시 새로 로드 (한 번 로드 완료 후 재진입 시)
    // 무한 루프 방지: 로드 완료 후 한 번만 체크
    if (_hasLoadedOnce && !_isLoading && !_hasError && _lastLoadedUrl != _targetUrl) {
      // 재진입 시 URL이 변경되었거나 재로드가 필요한 경우에만 새로 로드
      _lastLoadedUrl = _targetUrl;
      Future.microtask(() {
        if (mounted) {
          _reloadWebView();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'OD',
          style: TextStyle(
            fontSize: 18,
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w600,
          ),
        ),
        // [FIX] OD WebView ERR_CACHE_MISS 대응 - AppBar 액션 버튼 (새로고침, 외부 브라우저 열기)
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF1A1A1A)),
            onPressed: () {
              _retryCount = 0; // 수동 새로고침 시 재시도 카운터 리셋
              _reloadWebView();
            },
            tooltip: '새로고침',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Color(0xFF1A1A1A)),
            onPressed: _openInExternalBrowser,
            tooltip: '외부 브라우저로 열기',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // [WEB] 웹에서는 iframe 사용, 모바일에서는 WebView 사용
            if (!_hasError)
              kIsWeb
                  ? _buildWebIframe()
                  : (!kIsWeb && _controller != null)
                      ? WebViewWidget(
                          key: _webViewKey,
                          controller: _controller as WebViewController,
                        )
                      : const SizedBox(),
            
            // 로딩 인디케이터
            if (_isLoading && !_hasError)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            
            // [FIX] OD WebView ERR_CACHE_MISS 대응 - 에러 UI
            if (_hasError)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '페이지를 불러올 수 없습니다',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        if (_errorMessage != null)
                          Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        const SizedBox(height: 24),
                        // [FIX] OD WebView ERR_CACHE_MISS 대응 - 재시도 버튼
                        ElevatedButton.icon(
                          onPressed: () {
                            _retryCount = 0;
                            _reloadWebView();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('새로고침'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6F61),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // [FIX] OD WebView ERR_CACHE_MISS 대응 - 외부 브라우저 열기 버튼
                        OutlinedButton.icon(
                          onPressed: _openInExternalBrowser,
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('외부 브라우저로 열기'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6F61),
                            side: const BorderSide(color: Color(0xFFFF6F61)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================
// 더보기 화면
// ========================================
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 타이틀
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '더보기',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
            // 사용자 정보 표시
            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6F61).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Color(0xFFFF6F61),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${currentUser.id} (${currentUser.roleLabel} / ${currentUser.scopeLabel})',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 더보기 메뉴 리스트
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    _MoreCardButton(
                      title: '설정',
                      subtitle: '앱 설정을 변경합니다',
                      icon: Icons.settings,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('설정 기능')),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _MoreCardButton(
                      title: '도움말',
                      subtitle: '앱 사용 방법을 확인합니다',
                      icon: Icons.help_outline,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('도움말 기능')),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _MoreCardButton(
                      title: '정보',
                      subtitle: '앱 정보 및 버전을 확인합니다',
                      icon: Icons.info_outline,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('정보 기능')),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // 로그아웃 버튼
                    _MoreCardButton(
                      title: '로그아웃',
                      subtitle: '로그아웃하고 로그인 화면으로 돌아갑니다',
                      icon: Icons.logout,
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('로그아웃'),
                            content: const Text('로그아웃하시겠습니까?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('취소'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6F61),
                                ),
                                child: const Text('로그아웃'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await authService.logout();
                          if (context.mounted) {
                            context.go('/');
                          }
                        }
                      },
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 더보기 카드 버튼 위젯
class _MoreCardButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MoreCardButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // 아이콘
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F61).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFFFF6F61),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // 텍스트
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDestructive ? Colors.red : const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // 화살표
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
