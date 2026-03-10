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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'dart:convert';
// [WEB] iframe을 위한 import
import 'package:universal_html/html.dart' as html;
import 'dart:ui_web' show platformViewRegistry;

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
import 'services/permission_service.dart';
import 'utils/customer_converter.dart';
import 'utils/csv_parser_extended.dart';
import 'ui/pages/login_page.dart';
import 'ui/pages/admin_login_page.dart';
import 'ui/pages/admin_home_page.dart';
import 'ui/pages/customer_register_page.dart';
import 'ui/pages/customer_list_page.dart';
import 'ui/pages/calendar_view_page.dart';
import 'ui/pages/od_list_page.dart';
import 'ui/pages/home/home_page.dart';
import 'ui/theme/app_colors.dart';
import 'ui/theme/app_dimens.dart';
import 'ui/widgets/custom_bottom_nav.dart';
import 'ui/widgets/page_menu_title.dart';
import 'ui/widgets/frame_shell.dart';

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
  
  // [DEBUG] Firestore users 컬렉션 조회
  try {
    final firestore = FirebaseFirestore.instance;
    final usersSnapshot = await firestore.collection('users').get();
    debugPrint('📋 ===== Firestore users 컬렉션 조회 =====');
    debugPrint('📋 총 ${usersSnapshot.docs.length}개의 사용자 문서');
    for (final doc in usersSnapshot.docs) {
      final data = doc.data();
      debugPrint('  👤 [${doc.id}] id=${data['id']}, name=${data['name']}, role=${data['role']}, scope=${data['scope']}');
    }
    debugPrint('📋 ========================================');
  } catch (e) {
    debugPrint('⚠️ Firestore users 조회 실패: $e');
  }
  
  // [HOME] 홈 전체보기 → 더보기 탭 특정 메뉴 연동용
  final moreNavIntent = MoreNavIntent();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: moreNavIntent),
        Provider.value(value: UserRepository()),
        Provider(create: (c) => CustomerRepository(authService: c.read<AuthService>())),
        Provider.value(value: SalesStatusRepository()),
        Provider.value(value: PerformanceRepository()),
        Provider.value(value: UploadHistoryRepository()),
      ],
      child: const SOSApp(),
    ),
  );
}

/// [HOME] 홈에서 "전체보기" 탭 시 더보기 탭으로 이동 후 특정 서브 메뉴 열기용
class MoreNavIntent extends ChangeNotifier {
  String? _pendingRoute;
  String? get pendingRoute => _pendingRoute;
  void goToMore(String route) {
    _pendingRoute = route;
    notifyListeners();
  }
  void clear() {
    _pendingRoute = null;
    notifyListeners();
  }
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
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authService.isLoggedIn;
      final isAdmin = authService.isAdmin;
      final path = state.uri.path;
      
      // 루트(/)는 로그인 페이지(/login)로 보낸다.
      // (웹에서 첫 진입이 / 인 경우가 많아서, /login을 표준 경로로 사용)
      if (path == '/') {
        if (isLoggedIn) {
          return isAdmin ? '/admin' : '/main/0';
        }
        return '/login';
      }

      // 일반 로그인(/login): 로그인 성공 시 항상 메인 페이지로 (ADMIN 권한이어도 메인으로)
      if (path == '/login') {
        if (isLoggedIn) return '/main/0';
        return null;
      }
      // 관리자 로그인(/admin-login): 로그인 성공 시 ADMIN이면 관리자 페이지, 아니면 메인
      if (path == '/admin-login') {
        if (isLoggedIn) return isAdmin ? '/admin' : '/main/0';
        return null;
      }
      
      // 보호된 경로: 로그인 필요
      if (path.startsWith('/main') || path.startsWith('/admin')) {
        if (!isLoggedIn) return '/login';
        // Admin은 /admin과 /main 모두 접근 가능
        // 일반 사용자는 /main만 접근 가능
        if (path.startsWith('/admin') && !isAdmin) return '/main';
      }
      
      return null;
    },
    refreshListenable: authService,
    routes: [
      GoRoute(
        path: '/admin-login',
        builder: (context, state) => const AdminLoginPage(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomePage(),
      ),
      // 관리자 사이트는 기존 UI/동작을 유지해야 하므로 ShellRoute(프레임) 밖에 둔다.
      // 그 외(일반 사용자/로그인 등)만 PC 웹에서 394×811 모바일 프레임으로 렌더링.
      ShellRoute(
        builder: (context, state, child) => FrameShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const LoginPage(),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginPage(),
          ),
          GoRoute(
            path: '/main',
            builder: (context, state) {
              final intent = context.read<MoreNavIntent>();
              final pending = intent.pendingRoute;
              return MainNavigationScreen(
                initialTab: pending != null ? 5 : 0,
                pendingMoreRoute: pending,
                onClearPendingRoute: intent.clear,
              );
            },
          ),
          GoRoute(
            path: '/main/:tab',
            builder: (context, state) {
              final tab = state.pathParameters['tab'] ?? '0';
              final intent = context.read<MoreNavIntent>();
              final extra = state.extra as String?;
              if (extra != null && extra.isNotEmpty) intent.goToMore(extra);
              final pending = intent.pendingRoute;
              final salesStatus = state.uri.queryParameters['salesStatus'];
              return MainNavigationScreen(
                initialTab: pending != null ? 5 : (int.tryParse(tab) ?? 0),
                pendingMoreRoute: pending,
                onClearPendingRoute: intent.clear,
                customerListInitialSalesStatus: salesStatus,
              );
            },
          ),
        ],
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
  /// [HOME] 홈 전체보기에서 더보기 탭으로 진입 시 열 서브 메뉴 (favorites / recent / contract_expiring)
  final String? pendingMoreRoute;
  final VoidCallback? onClearPendingRoute;
  /// 고객사 탭 진입 시 초기 영업상태 필터 (예: 영업중)
  final String? customerListInitialSalesStatus;

  const MainNavigationScreen({
    super.key,
    this.initialTab = 0,
    this.pendingMoreRoute,
    this.onClearPendingRoute,
    this.customerListInitialSalesStatus,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex; // 최초 진입은 고객사 탭

  // [MORE] 더보기 탭 누를 때마다 메뉴만 보이도록 중첩 Navigator 제어
  final GlobalKey<NavigatorState> _moreNavigatorKey = GlobalKey<NavigatorState>();
  
  // [FAV] 즐겨찾기 상태 관리
  Set<String> _favoriteCustomerKeys = {};
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    _loadFavorites();
  }

  @override
  void didUpdateWidget(MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _currentIndex = widget.initialTab;
      });
    }
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
        _currentIndex = 0; // 홈 탭
      });
    }
  }
  
  // [FAV] 즐겨찾기 Firestore 로드 (PC/모바일 동기화)
  Future<void> _loadFavorites() async {
    try {
      final repo = context.read<CustomerRepository>();
      final keys = await repo.getFavorites();
      if (mounted) setState(() => _favoriteCustomerKeys = keys);
    } catch (e) {
      debugPrint('즐겨찾기 로드 오류: $e');
    }
  }
  
  // [FAV] 즐겨찾기 토글 (Firestore 저장)
  Future<void> toggleFavorite(String customerKey) async {
    setState(() {
      if (_favoriteCustomerKeys.contains(customerKey)) {
        _favoriteCustomerKeys.remove(customerKey);
      } else {
        _favoriteCustomerKeys.add(customerKey);
      }
    });
    try {
      await context.read<CustomerRepository>().setFavorites(_favoriteCustomerKeys);
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
          const HomePage(), // 홈
          CustomerListPage(initialSalesStatusFilter: widget.customerListInitialSalesStatus), // 고객사
          FrontierHqSelectionScreen(), // 프론티어
          DashboardScreen(), // 대시보드
          const OdListPage(), // OD
          MoreScreen(
            navigatorKey: _moreNavigatorKey,
            pendingRoute: widget.pendingMoreRoute,
            onClearPendingRoute: widget.onClearPendingRoute,
            onGlobalRefresh: _loadFavorites,
          ), // 더보기
        ],
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          // [MORE] 더보기 탭 누르면 무조건 더보기 메뉴(첫 화면)만 표시
          if (index == 5) {
            _moreNavigatorKey.currentState?.popUntil((route) => route.isFirst);
          }
          setState(() {
            _currentIndex = index;
          });
          // [WEB] URL 업데이트
          context.go('/main/$index');
        },
      ),
      floatingActionButton: _currentIndex == 1
          ? Transform.scale(
              scale: 0.85,
              child: FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CustomerRegisterPage(),
                    ),
                  ).then((result) {
                    if (result == true) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        CsvReloadBus().reload('customerlist.csv');
                      });
                    }
                  });
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  '고객사 등록',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                backgroundColor: const Color(0xFFFF6F61),
                foregroundColor: Colors.white,
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
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
  String personInCharge;
  /// 영업활동 로그 (Firestore 동기화)
  List<Map<String, dynamic>> salesActivities;

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
    this.personInCharge = '',
    this.salesActivities = const [],
  });

  // [FAV] 고유 키 생성 (고객사명|개통일자|상품명)
  String get customerKey => '$customerName|$openedAt|$productName';
}

// ========================================
// 영업활동 로그 항목 (영업현황 섹션 전용)
// ========================================
class SalesActivityItem {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;
  /// 메모 기입자 표시: "이름(본부)"
  final String? writer;

  SalesActivityItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.updatedAt,
    this.writer,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'writer': writer,
      };

  static SalesActivityItem fromJson(Map<String, dynamic> j) {
    return SalesActivityItem(
      id: j['id'] as String? ?? '',
      text: j['text'] as String? ?? '',
      createdAt: _parseDateTime(j['createdAt']),
      updatedAt: j['updatedAt'] != null ? _parseDateTime(j['updatedAt']) : null,
      writer: j['writer'] as String?,
    );
  }

  static DateTime _parseDateTime(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  SalesActivityItem copyWith({String? id, String? text, DateTime? createdAt, DateTime? updatedAt, String? writer}) =>
      SalesActivityItem(
        id: id ?? this.id,
        text: text ?? this.text,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        writer: writer ?? this.writer,
      );
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
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CustomerRegisterPage(),
                ),
              );
            },
            icon: const Icon(Icons.add, color: Color(0xFFFF6F61)),
            label: const Text(
              '고객사 등록',
              style: TextStyle(
                color: Color(0xFFFF6F61),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
  final bool skipCsvLoad; // CSV 로드 건너뛰기 (등록 후 목록 화면 이동 시 사용)

  const CustomerListByHqScreen({
    super.key,
    required this.selectedHq,
    this.skipCsvLoad = false,
  });

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
  bool _isInitialLoad = true; // 초기 로딩 여부
  
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
    // 초기 로딩 중에는 재로드 이벤트 무시
    if (_isInitialLoad) {
      debugPrint('[고객사] 초기 로딩 중이므로 재로드 이벤트 무시: $filename');
      return;
    }
    
    // 중복 로딩 방지
    if (_isReloading || _isLoading) {
      debugPrint('[고객사] 이미 로딩 중이므로 재로드 건너뜀');
      return;
    }
    
    // debounce: 300ms 대기
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isReloading && !_isLoading && !_isInitialLoad) {
        debugPrint('[고객사] CSV 재로드 시작: $filename');
        _loadCsvData();
      }
    });
  }

  // [RBAC] Repository에서 로드 및 권한 필터링
  Future<void> _loadCsvData() async {
    // 중복 로딩 방지 (초기 로딩이 아닌 경우에만)
    if (!_isInitialLoad && (_isReloading || _isLoading)) {
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
      debugPrint('🔍 [RBAC] getFiltered 호출 전 - 사용자: ${currentUser?.id ?? "없음"}, Role: ${currentUser?.role}, Scope: ${currentUser?.scope}');
      
      // 고객 목록은 Firestore만 사용. CSV 반영은 관리자 CSV 업로드 시에만 덮어쓰기(replaceFromCsv) 수행.
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
          _isInitialLoad = false; // 초기 로딩 완료
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
          _isInitialLoad = false; // 초기 로딩 완료 (에러 발생 시에도)
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
    final int personInChargeIndex = headers.indexWhere((h) => h.contains('담당자'));

    debugPrint('고객사 CSV 인덱스 - 본부:$hqIndex, 지사:$branchIndex, 고객명:$customerNameIndex, 개통일자:$openedAtIndex, 상품유형:$productTypeIndex, 상품명:$productNameIndex, 실판매자:$sellerIndex, 건물명:$buildingIndex, 담당자:$personInChargeIndex');

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
          personInCharge: personInChargeIndex >= 0 && personInChargeIndex < values.length ? values[personInChargeIndex] : '',
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
          final bool matchesPersonInCharge = customer.personInCharge.toLowerCase().contains(query);
          if (!matchesName && !matchesSeller && !matchesHq && !matchesPersonInCharge) {
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
                        style: TextStyle(color: AppColors.textSecondary),
                        decoration: InputDecoration(
                          hintText: '고객사명, 실판매자 검색',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
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
  bool _isInitialLoad = true; // 초기 로딩 여부
  
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
      debugPrint('🔍 [RBAC] getFiltered 호출 전 - 사용자: ${currentUser?.id ?? "없음"}, Role: ${currentUser?.role}, Scope: ${currentUser?.scope}');
      
      // 고객 목록은 Firestore만 사용. CSV 반영은 관리자 CSV 업로드 시에만 덮어쓰기(replaceFromCsv) 수행.
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
        _isInitialLoad = false; // 초기 로딩 완료
        _errorMessage = null;
      });
      _filterCustomers();
    } catch (e, stackTrace) {
      debugPrint('❌ 데이터 로딩 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _isInitialLoad = false; // 초기 로딩 완료 (에러 발생 시에도)
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
    final int personInChargeIndex = headers.indexWhere((h) => h.contains('담당자'));

    debugPrint('고객사 CSV 인덱스 - 본부:$hqIndex, 지사:$branchIndex, 고객명:$customerNameIndex, 개통일자:$openedAtIndex, 상품유형:$productTypeIndex, 상품명:$productNameIndex, 실판매자:$sellerIndex, 건물명:$buildingIndex, 담당자:$personInChargeIndex');

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
          personInCharge: personInChargeIndex >= 0 && personInChargeIndex < values.length ? values[personInChargeIndex] : '',
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
                        style: TextStyle(color: AppColors.textSecondary),
                        decoration: InputDecoration(
                          hintText: '고객사명, 실판매자, 본부 검색',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
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
                // [FAV] 둘째줄: 개통일자(좌) + 담당자 + 본부 칩(우)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '개통일자: ${widget.customer.openedAt}  ${widget.customer.personInCharge.isEmpty ? "담당자 없음" : widget.customer.personInCharge}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
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
  final List<String> _salesStatusOptions = ['영업전', '영업중', '영업실패', '영업성공'];

  // 영업현황 임시 편집 상태 (저장 버튼 클릭 시에만 반영)
  late String _salesStatusDraft;
  late List<SalesActivityItem> _activitiesDraft;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _activitiesLoaded = false;

  @override
  void initState() {
    super.initState();
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    _isFavorite = mainState?.isFavorite(widget.customer.customerKey) ?? false;
    _salesStatusDraft = widget.customer.salesStatus;
    _activitiesDraft = [];
    _loadActivities();
    // 상세 화면이 다른 네비게이터에서 열린 경우(더보기 등) Firestore에서 즐겨찾기 상태 로드
    if (mainState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFavoriteFromRepo());
    }
  }

  Future<void> _loadFavoriteFromRepo() async {
    if (!mounted) return;
    try {
      final keys = await context.read<CustomerRepository>().getFavorites();
      if (mounted) setState(() => _isFavorite = keys.contains(widget.customer.customerKey));
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Firestore에서 영업활동 로드 (PC/모바일 동기화). 없으면 SharedPreferences 마이그레이션 시도.
  Future<void> _loadActivities() async {
    final List<SalesActivityItem> list = [];
    // 1) Firestore (동기화된 데이터) 우선
    final activities = widget.customer.salesActivities;
    if (activities.isNotEmpty) {
      for (final e in activities) {
        try {
          final m = Map<String, dynamic>.from(e);
          list.add(SalesActivityItem.fromJson(m));
        } catch (_) {}
      }
    }
    // 2) 마이그레이션: SharedPreferences에만 있던 데이터 → Firestore로 이전 시도
    if (list.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${widget.customer.customerKey}_sales_activities');
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>?;
          if (decoded != null) {
            for (final e in decoded) {
              if (e is Map<String, dynamic>) list.add(SalesActivityItem.fromJson(e));
            }
          }
        } catch (_) {}
      }
    }
    // 3) 기존 memo가 있고 활동이 없으면 1회 마이그레이션
    if (list.isEmpty && widget.customer.memo.trim().isNotEmpty) {
      list.add(SalesActivityItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: widget.customer.memo.trim(),
        createdAt: DateTime.now(),
        updatedAt: null,
      ));
    }
    if (mounted) {
      setState(() {
        _activitiesDraft = list;
        _activitiesLoaded = true;
      });
    }
  }

  void _markDirty() {
    if (!_isDirty && mounted) setState(() => _isDirty = true);
  }

  void _onSalesStatusChanged(String? value) {
    if (value != null) {
      setState(() => _salesStatusDraft = value);
      _markDirty();
    }
  }

  String get _writerLabel {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return '';
    final name = user.name.isNotEmpty ? user.name : user.id;
    final hq = user.hq.isNotEmpty ? user.hq : '';
    return hq.isNotEmpty ? '$name($hq)' : name;
  }

  void _onAddActivity(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _activitiesDraft.insert(
        0,
        SalesActivityItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text.trim(),
          createdAt: DateTime.now(),
          updatedAt: null,
          writer: _writerLabel.isNotEmpty ? _writerLabel : null,
        ),
      );
      _isDirty = true;
    });
  }

  void _onEditActivity(String id, String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      final now = DateTime.now();
      _activitiesDraft = _activitiesDraft.map((a) {
        if (a.id == id) return a.copyWith(
          text: text.trim(),
          updatedAt: now,
          writer: _writerLabel.isNotEmpty ? _writerLabel : null,
        );
        return a;
      }).toList();
      _isDirty = true;
    });
  }

  void _onDeleteActivity(String id) {
    setState(() {
      _activitiesDraft.removeWhere((a) => a.id == id);
      _isDirty = true;
    });
  }

  /// 저장 버튼: status + activities — Firestore (PC/모바일 동기화)
  Future<void> _saveDraft() async {
    if (_isSaving || !_isDirty) return;
    setState(() => _isSaving = true);
    try {
      final key = widget.customer.customerKey;
      final repo = context.read<CustomerRepository>();

      // 영업상태·메모·영업활동 — Firestore에 저장 (PC/모바일 동기화)
      await repo.setStatus(key, _salesStatusDraft);
      final memoToSync = _activitiesDraft.isNotEmpty ? _activitiesDraft.first.text : '';
      await repo.setMemo(key, memoToSync);
      final activitiesToSync = _activitiesDraft.map((a) => a.toJson()).toList();
      await repo.setSalesActivities(key, activitiesToSync);

      widget.customer.salesStatus = _salesStatusDraft;
      widget.customer.memo = memoToSync;
      widget.customer.salesActivities = activitiesToSync;

      if (mounted) {
        setState(() {
          _isDirty = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      debugPrint('영업현황 저장 오류: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장에 실패했습니다. $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // [FAV] 즐겨찾기 토글 — MainNavigationScreenState 또는 Firestore와 연동
  void _toggleFavorite() async {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    if (mainState != null) {
      await mainState.toggleFavorite(widget.customer.customerKey);
      setState(() {
        _isFavorite = mainState.isFavorite(widget.customer.customerKey);
      });
      widget.onFavoriteChanged();
      return;
    }
    // 더보기 등 다른 경로에서 열린 경우 Firestore에 직접 저장
    try {
      final repo = context.read<CustomerRepository>();
      final keys = await repo.getFavorites();
      final key = widget.customer.customerKey;
      if (keys.contains(key)) {
        keys.remove(key);
      } else {
        keys.add(key);
      }
      await repo.setFavorites(keys);
      if (mounted) {
        setState(() => _isFavorite = keys.contains(key));
        widget.onFavoriteChanged();
      }
    } catch (e) {
      debugPrint('즐겨찾기 토글 오류: $e');
    }
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
                _InfoRow(label: '담당자', value: widget.customer.personInCharge.isEmpty ? '담당자 없음' : widget.customer.personInCharge),
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
            // 섹션 3: 영업현황 (임시 편집 + 저장 버튼 일괄 저장)
            _SalesStatusCard(
              salesStatus: _salesStatusDraft,
              activities: _activitiesDraft,
              salesStatusOptions: _salesStatusOptions,
              onSalesStatusChanged: _onSalesStatusChanged,
              onAddActivity: _onAddActivity,
              onEditActivity: _onEditActivity,
              onDeleteActivity: _onDeleteActivity,
              onSave: _saveDraft,
              isDirty: _isDirty,
              isSaving: _isSaving,
              activitiesLoaded: _activitiesLoaded,
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
// 영업현황 카드 위젯 (영업상태 + 영업활동 리스트 + 저장 버튼)
// ========================================
class _SalesStatusCard extends StatefulWidget {
  final String salesStatus;
  final List<SalesActivityItem> activities;
  final List<String> salesStatusOptions;
  final ValueChanged<String?> onSalesStatusChanged;
  final ValueChanged<String> onAddActivity;
  final void Function(String id, String text) onEditActivity;
  final ValueChanged<String> onDeleteActivity;
  final VoidCallback onSave;
  final bool isDirty;
  final bool isSaving;
  final bool activitiesLoaded;

  const _SalesStatusCard({
    required this.salesStatus,
    required this.activities,
    required this.salesStatusOptions,
    required this.onSalesStatusChanged,
    required this.onAddActivity,
    required this.onEditActivity,
    required this.onDeleteActivity,
    required this.onSave,
    required this.isDirty,
    required this.isSaving,
    required this.activitiesLoaded,
  });

  @override
  State<_SalesStatusCard> createState() => _SalesStatusCardState();
}

class _SalesStatusCardState extends State<_SalesStatusCard> {
  final TextEditingController _activityController = TextEditingController();
  final FocusNode _activityFocus = FocusNode();
  String? _editingActivityId;
  bool _sortNewestFirst = true;

  @override
  void dispose() {
    _activityController.dispose();
    _activityFocus.dispose();
    super.dispose();
  }

  void _submitActivity() {
    final text = _activityController.text.trim();
    if (text.isEmpty) return;
    if (_editingActivityId != null) {
      widget.onEditActivity(_editingActivityId!, text);
      setState(() {
        _editingActivityId = null;
        _activityController.clear();
      });
    } else {
      widget.onAddActivity(text);
      _activityController.clear();
    }
  }

  void _startEdit(SalesActivityItem item) {
    setState(() {
      _editingActivityId = item.id;
      _activityController.text = item.text;
      _activityController.selection = TextSelection.collapsed(offset: item.text.length);
    });
    _activityFocus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingActivityId = null;
      _activityController.clear();
    });
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sortedActivities = List<SalesActivityItem>.from(widget.activities);
    sortedActivities.sort((a, b) => _sortNewestFirst
        ? b.createdAt.compareTo(a.createdAt)
        : a.createdAt.compareTo(b.createdAt));

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
            // 변경사항 있음 표시
            if (widget.isDirty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.orange[700]),
                    const SizedBox(width: 6),
                    Text(
                      '변경사항 있음',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
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
                    value: widget.salesStatus,
                    isExpanded: true,
                    underline: Container(),
                    items: widget.salesStatusOptions.map((String status) {
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
                    onChanged: widget.onSalesStatusChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 영업활동
            Text(
              '영업활동',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _activityController,
                    focusNode: _activityFocus,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: 3,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: _editingActivityId != null
                          ? '내용 수정 후 "수정 완료"를 누르세요'
                          : '영업활동 내용을 입력하세요',
                      hintStyle: TextStyle(color: Colors.grey[400]),
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
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _submitActivity(),
                  icon: Icon(_editingActivityId != null ? Icons.check : Icons.add, size: 18),
                  label: Text(_editingActivityId != null ? '수정 완료' : '추가'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6F61),
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_editingActivityId != null) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _cancelEdit,
                    child: const Text('취소'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // 영업활동 리스트 (최신순/오래된순 토글)
            if (widget.activitiesLoaded) ...[
              if (sortedActivities.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '기록 (${sortedActivities.length}건)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _sortNewestFirst = !_sortNewestFirst),
                      icon: Icon(
                        _sortNewestFirst ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 16,
                      ),
                      label: Text(
                        _sortNewestFirst ? '최신순' : '오래된순',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...sortedActivities.map((a) => _ActivityCard(
                      item: a,
                      onEdit: () => _startEdit(a),
                      onDelete: () => widget.onDeleteActivity(a.id),
                      formatDateTime: _formatDateTime,
                    )),
                const SizedBox(height: 16),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
              ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFE0E0E0)),
            const SizedBox(height: 12),
            // 저장 버튼
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (widget.isDirty && !widget.isSaving) ? widget.onSave : null,
                icon: widget.isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(widget.isSaving ? '저장 중...' : '저장'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6F61),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 영업활동 카드 한 건 (날짜/시간, 내용, 편집/삭제 아이콘)
class _ActivityCard extends StatelessWidget {
  final SalesActivityItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String Function(DateTime) formatDateTime;

  const _ActivityCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final displayTime = item.updatedAt != null ? item.updatedAt! : item.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      formatDateTime(displayTime),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (item.writer != null && item.writer!.isNotEmpty) ...[
                      Text(
                        ' · ',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        item.writer!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFFFF6F61)),
                onPressed: onEdit,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey[700]),
                onPressed: onDelete,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
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
// 프론티어 본부 선택 화면 (필터 칩 형태로 변경)
// ========================================
class FrontierHqSelectionScreen extends StatefulWidget {
  const FrontierHqSelectionScreen({super.key});

  @override
  State<FrontierHqSelectionScreen> createState() => _FrontierHqSelectionScreenState();
}

class _FrontierHqSelectionScreenState extends State<FrontierHqSelectionScreen> {
  static const List<String> _hqList = ['전체', '강북', '강남', '강서', '동부', '서부'];
  String? _selectedHq;
  List<FrontierData> _allFrontiers = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadCsvData();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q == _searchQuery) return;
    setState(() => _searchQuery = q);
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // CSV 파일들 로드
  Future<void> _loadCsvData() async {
    try {
      debugPrint('프론티어 CSV 파일 로딩 시작...');
      final String staffCsv = await CsvService.load('kpi-info.csv');
      final List<FrontierData> frontiers = _parseStaffCsv(staffCsv);
      
      setState(() {
        _allFrontiers = frontiers;
        _isLoading = false;
        _errorMessage = null;
      });
      _applyFilters();
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

  void _applyFilters() {
    setState(() {});
  }

  /// 접근레벨(일반=본인, 스탭=본부, 관리자=전체) + 검색 + 본부 칩 적용한 표시 목록
  List<FrontierData> _getDisplayedFrontiers(BuildContext context) {
    final user = context.read<AuthService>().currentUser;
    final scope = user != null
        ? PermissionService.effectiveScopeFor(user.role, AccessFeature.frontier)
        : UserScope.all;
    List<FrontierData> list = List.from(_allFrontiers);
    if (user != null) {
      if (scope == UserScope.self) {
        list = list.where((f) => _normalizeName(f.name) == _normalizeName(user.name)).toList();
      } else if (scope == UserScope.hq) {
        list = list.where((f) => PermissionService.normalizeHq(f.hq) == PermissionService.normalizeHq(user.hq)).toList();
      }
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((f) => f.name.toLowerCase().contains(q)).toList();
    }
    if (_selectedHq != null && _selectedHq != '전체') {
      list = list.where((f) {
        final hqPrefix = f.hq.length >= 2 ? f.hq.substring(0, 2) : f.hq;
        return hqPrefix == _selectedHq;
      }).toList();
    }
    return list;
  }

  static String _normalizeName(String s) => s.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final displayedFrontiers = _getDisplayedFrontiers(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 1,
        automaticallyImplyLeading: false,
        leading: const PageMenuTitle(icon: Icons.groups_rounded, label: '프론티어'),
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
      body: Column(
        children: [
          // 검색바 (고객사 메뉴와 동일 스타일)
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
                  hintText: '이름 검색',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 22),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          // 본부 필터 Pills (고객사 메뉴와 동일: 전체 | 강북 | 강남 | 강서 | 동부 | 서부)
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
          // 프론티어 리스트
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
                                onPressed: _loadCsvData,
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : displayedFrontiers.isEmpty
                        ? Center(
                            child: Text(
                              '프론티어가 없습니다',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDimens.pagePadding,
                              vertical: 8,
                            ),
                            itemCount: displayedFrontiers.length,
                            itemBuilder: (context, index) {
                              final frontier = displayedFrontiers[index];
                              return _KTStyleFrontierCard(
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
    );
  }
}

// KT 느낌 기업형 프론티어 카드 (이름 앞 사람 아이콘, 슬림·단정)
class _KTStyleFrontierCard extends StatelessWidget {
  final FrontierData frontier;
  final VoidCallback onTap;

  const _KTStyleFrontierCard({
    required this.frontier,
    required this.onTap,
  });

  Color _getGradeColor(String grade) {
    if (grade.isEmpty) return Colors.grey;
    final firstChar = grade[0].toUpperCase();
    switch (firstChar) {
      case 'A': return Colors.green;
      case 'B': return Colors.blue;
      case 'C': return Colors.grey;
      case 'D': return Colors.orange;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradeColor = _getGradeColor(frontier.grade);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F61).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: Color(0xFFFF6F61),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        frontier.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (frontier.position.isNotEmpty)
                        Text(
                          frontier.position,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (frontier.position.isNotEmpty) const SizedBox(height: 2),
                      Text(
                        frontier.center.isNotEmpty
                            ? '${frontier.hq} / ${frontier.center}'
                            : (frontier.hq.isNotEmpty ? frontier.hq : '-'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (frontier.grade.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: gradeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      frontier.grade,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: gradeColor,
                      ),
                    ),
                  ),
                if (frontier.grade.isNotEmpty) const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: Colors.grey[500],
                      ),
                    ),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: AppColors.card,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: GestureDetector(
          onTap: () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
              (route) => false,
            );
          },
          child: Image.asset(
            'assets/images/sos_logo.png',
            height: 28,
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
            // 검색 영역 (시안: 화이트, radius 14, 그림자, 높이 50, 좌 검색 우 필터)
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
                  keyboardType: TextInputType.text,
                  enableInteractiveSelection: true,
                  style: TextStyle(color: AppColors.textSecondary),
                  decoration: InputDecoration(
                    hintText: '성명, 본부, 센터 검색',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 22),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.tune, color: AppColors.textSecondary, size: 22),
                      onPressed: _showFilterDialog,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDimens.pagePadding,
                                vertical: 8,
                              ),
                              itemCount: _filteredFrontiers.length,
                              itemBuilder: (context, index) {
                                final frontier = _filteredFrontiers[index];
                                return _KTStyleFrontierCard(
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
                        style: TextStyle(color: AppColors.textSecondary),
                        decoration: InputDecoration(
                          hintText: '성명, 본부, 센터 검색',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
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
                                return _KTStyleFrontierCard(
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
          // 실적현황 타이틀 및 기간 선택 (전체/강북/... pill 스타일)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '실적현황',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['3개월', '6개월', '1년'].map((period) {
                      final isSelected = _selectedPeriod == period;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Material(
                          color: isSelected ? AppColors.pillSelectedBg : AppColors.pillUnselectedBg,
                          borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                          child: InkWell(
                            onTap: () => setState(() => _selectedPeriod = period),
                            borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Center(
                                child: Text(
                                  period,
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
                    }).toList(),
                  ),
                ),
              ),
            ],
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

    // 카드 스타일: 아이콘(연한 배경) + 라벨(회색) + 숫자(강조색) — 2x2 그리드
    (String label, IconData icon, Color iconBg, Color valueColor) _style(String cat) {
      switch (cat) {
        case '무선':
          return ('무선', Icons.smartphone, const Color(0xFFE3F2FD), const Color(0xFF1976D2));
        case '유선순신규':
          return ('유선순신규', Icons.add_circle_outline, const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
        case '유선약정갱신':
          return ('유선약정갱신', Icons.refresh, const Color(0xFFFFF3E0), const Color(0xFFE65100));
        case '기타상품':
          return ('기타상품', Icons.category_outlined, const Color(0xFFF3E5F5), const Color(0xFF7B1FA2));
        default:
          return (cat, Icons.bar_chart, AppColors.pillUnselectedBg, AppColors.textPrimary);
      }
    }

    Widget _metricCard({required String label, required IconData icon, required Color iconBg, required Color valueColor, required String value}) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withOpacity(0.8), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 22, color: valueColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
    }

    // 한 열: 1) 해당월 실적 2x2, 2) 최근 N개월 누적 2x2
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          latestYearMonthStr != null ? '$latestYearMonthStr 실적' : '최근월 실적',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: categories.map((cat) {
            final actual = latestMonthActuals[cat] ?? 0;
            final s = _style(cat);
            return _metricCard(
              label: s.$1,
              icon: s.$2,
              iconBg: s.$3,
              valueColor: s.$4,
              value: '$actual건',
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        Text(
          '최근 $_selectedPeriod 누적',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: categories.map((cat) {
            final total = recentMonthsActuals[cat] ?? 0;
            final s = _style(cat);
            return _metricCard(
              label: s.$1,
              icon: s.$2,
              iconBg: s.$3,
              valueColor: s.$4,
              value: '$total건',
            );
          }).toList(),
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
  bool _isInitialLoad = true; // 초기 로딩 여부

  // [DASH] 전체현황 KPI 집계
  Map<String, int> _overallKpi = {'무선': 0, '유선': 0, '약갱': 0, '기타': 0};
  
  // [DASH] 본부/센터 카드 리스트
  List<Map<String, dynamic>> _hqList = [];
  List<Map<String, dynamic>> _centerList = [];
  
  // [DASH] 본부 필터
  static const List<String> _hqFilterList = ['전체', '강북', '강남', '강서', '동부', '서부'];
  String? _selectedHqFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    // 초기 로딩 중에는 재로드 이벤트 무시
    if (_isInitialLoad) {
      debugPrint('[DASH] 초기 로딩 중이므로 재로드 이벤트 무시: $filename');
      return;
    }
    
    // 중복 로딩 방지
    if (_isReloading || _isLoading) {
      debugPrint('[DASH] 이미 로딩 중이므로 재로드 건너뜀');
      return;
    }
    
    // debounce: 300ms 대기
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_isReloading && !_isLoading && !_isInitialLoad) {
        debugPrint('[DASH] CSV 재로드 시작: $filename');
        _loadKpiData();
      }
    });
  }

  // [DASH] KPI CSV 로딩/캐싱
  Future<void> _loadKpiData() async {
    // 중복 로딩 방지 (초기 로딩이 아닌 경우에만)
    if (!_isInitialLoad && (_isReloading || _isLoading)) {
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
          _isInitialLoad = false; // 초기 로딩 완료
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
          _isInitialLoad = false; // 초기 로딩 완료 (에러 발생 시에도)
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
    
    // 본부 필터 적용
    _applyHqFilter();
  }
  
  // [DASH] 본부 필터 적용
  void _applyHqFilter() {
    // 필터링은 _hqList와 _centerList를 직접 수정하지 않고,
    // TabBar의 본부/센터 탭에서 필터링된 데이터를 표시하도록 함
    setState(() {
      // 상태 업데이트로 리빌드 트리거
    });
  }
  
  // [DASH] 필터링된 본부 리스트 반환
  List<Map<String, dynamic>> get _filteredHqList {
    if (_selectedHqFilter == null) {
      return _hqList;
    }
    return _hqList.where((hq) => hq['hq'] == _selectedHqFilter).toList();
  }
  
  // [DASH] 필터링된 센터 리스트 반환
  List<Map<String, dynamic>> get _filteredCenterList {
    // 센터는 본부 정보가 없으므로 전체 리스트 반환
    // 필요시 센터-본부 매핑 데이터 추가 후 필터링 가능
    return _centerList;
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: false,
        leading: const PageMenuTitle(icon: Icons.bar_chart_rounded, label: '조직별 실적'),
        leadingWidth: 140,
        centerTitle: true,
        title: Image.asset(
          'assets/images/sos_logo.png',
          height: 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        actions: const [SizedBox(width: 140)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // [DASH] 메인 탭 3개: 전체현황 / 본부별 / 프론티어센터별
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '전체현황'),
                  Tab(text: '본부별'),
                  Tab(text: '프론티어센터별'),
                ],
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
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            // 전체현황
                            ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              children: [
                                YearMonthPickerCard(
                                  selectedYearMonths: _selectedYearMonths,
                                  availableYearMonths: _availableYearMonths,
                                  onTap: _showYearMonthSelector,
                                ),
                                const SizedBox(height: 16),
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
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _OverallKpiGrid(kpi: _overallKpi),
                                const SizedBox(height: 24),
                              ],
                            ),

                            // 본부별
                            Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                                  child: YearMonthPickerCard(
                                    selectedYearMonths: _selectedYearMonths,
                                    availableYearMonths: _availableYearMonths,
                                    onTap: _showYearMonthSelector,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 56,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  color: Colors.white,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: _hqFilterList.length,
                                    itemBuilder: (context, index) {
                                      final hq = _hqFilterList[index];
                                      final isSelected =
                                          (hq == '전체' && _selectedHqFilter == null) || _selectedHqFilter == hq;

                                      return Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: FilterChip(
                                          label: Text(hq),
                                          selected: isSelected,
                                          onSelected: (selected) {
                                            setState(() {
                                              _selectedHqFilter = hq == '전체' ? null : hq;
                                            });
                                            _applyHqFilter();
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
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: _HqListTab(
                                      hqList: _filteredHqList,
                                      allData: _allKpiData,
                                      selectedYearMonths: _selectedYearMonths,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // 프론티어센터별
                            Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                                  child: YearMonthPickerCard(
                                    selectedYearMonths: _selectedYearMonths,
                                    availableYearMonths: _availableYearMonths,
                                    onTap: _showYearMonthSelector,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: _CenterListTab(
                                      centerList: _filteredCenterList,
                                      allData: _allKpiData,
                                      selectedYearMonths: _selectedYearMonths,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// [DASH] 연월 멀티 선택 UI - 리디자인된 세련된 카드
class YearMonthPickerCard extends StatelessWidget {
  final Set<String> selectedYearMonths;
  final Set<String> availableYearMonths;
  final VoidCallback onTap;

  const YearMonthPickerCard({
    super.key,
    required this.selectedYearMonths,
    required this.availableYearMonths,
    required this.onTap,
  });

  String _getSummary() {
    if (selectedYearMonths.length == availableYearMonths.length) {
      return '전체';
    } else if (selectedYearMonths.isEmpty) {
      return '선택 없음';
    } else {
      return '선택 ${selectedYearMonths.length}개';
    }
  }

  String? _getFirstYearMonth() {
    if (selectedYearMonths.isEmpty) return null;
    final sorted = selectedYearMonths.toList()..sort();
    return sorted.first;
  }

  bool get _hasSelection => selectedYearMonths.isNotEmpty && selectedYearMonths.length != availableYearMonths.length;

  @override
  Widget build(BuildContext context) {
    final summary = _getSummary();
    final firstYearMonth = _getFirstYearMonth();
    final hasSelection = _hasSelection;

    return Container(
      decoration: BoxDecoration(
        gradient: hasSelection
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFE8E6), Color(0xFFFFFFFF)],
              )
            : null,
        color: hasSelection ? null : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: hasSelection
            ? null
            : Border.all(
                color: const Color(0xFFE5E7EB),
                width: 1,
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 좌측: 아이콘 + 텍스트
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: hasSelection ? const Color(0xFFFF6B63) : const Color(0xFFFF6B63).withOpacity(0.7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '연월 선택',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: TextStyle(
                          fontSize: 13,
                          color: hasSelection ? Colors.grey[700] : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 우측: pill badge + chevron 버튼
                if (hasSelection && firstYearMonth != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B63),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      selectedYearMonths.length == 1
                          ? firstYearMonth
                          : '$firstYearMonth 외 ${selectedYearMonths.length - 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: hasSelection ? const Color(0xFFFFE8E6) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: hasSelection ? const Color(0xFFFF6B63) : Colors.grey[400],
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
        // [FIX] KPI 카드 높이 확보 + BOTTOM OVERFLOW 방지
        childAspectRatio: 2.2,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatNumber(item['value'] as int),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: item['color'] as Color,
                    ),
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
    final int personInChargeIndex = headers.indexWhere((h) => h.contains('담당자'));

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
          personInCharge: personInChargeIndex >= 0 && personInChargeIndex < values.length ? values[personInChargeIndex] : '',
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        automaticallyImplyLeading: false,
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
      ),
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
  
  // [WEB] 웹에서 iframe 위젯 빌드 (선택 옵션: 앱 내부에서 보기)
  Widget _buildWebIframe() {
    if (!kIsWeb) return const SizedBox();
    
    // 플랫폼 뷰 ID 생성
    final String viewId = 'od-iframe-${_webViewKey.hashCode}';
    
    // 플랫폼 뷰 등록 (한 번만)
    if (!_hasLoadedOnce) {
      platformViewRegistry.registerViewFactory(
        viewId,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src = _targetUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          return iframe;
        },
      );
      _hasLoadedOnce = true;
    }
    
    return HtmlElementView(viewType: viewId);
  }
  
  // iframe 새로고침
  void _reloadIframe() {
    if (!kIsWeb) return;
    setState(() {
      _isLoading = true;
      _hasLoadedOnce = false; // 재등록을 위해 리셋
    });
    // iframe을 다시 생성하여 새로고침 효과
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
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
        // AppBar 액션 버튼 (새로고침)
        actions: [
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF1A1A1A)),
              onPressed: _reloadIframe,
              tooltip: '새로고침',
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF1A1A1A)),
              onPressed: () {
                _retryCount = 0;
                _reloadWebView();
              },
              tooltip: '새로고침',
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
// 약정만료 예정 화면 (당일 기준 -1개월 ~ +1개월, 개통일+36개월 기준)
// ========================================
class ContractExpiringScreen extends StatefulWidget {
  const ContractExpiringScreen({super.key});

  @override
  State<ContractExpiringScreen> createState() => _ContractExpiringScreenState();
}

class _ContractExpiringScreenState extends State<ContractExpiringScreen> {
  List<CustomerData> _customers = [];
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

  static DateTime addMonths(DateTime d, int months) {
    return DateTime(d.year, d.month + months, d.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final user = authService.currentUser;
      final list = await customerRepo.getFiltered(user);
      final dataList = CustomerConverter.toCustomerDataList(list);
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1).subtract(const Duration(days: 31));
      final end = now.add(const Duration(days: 31));
      final withExpiry = <CustomerData>[];
      for (final c in dataList) {
        final open = _parseOpenDate(c.openedAt);
        if (open == null) continue;
        final expiry = addMonths(open, 36);
        if (!expiry.isBefore(start) && !expiry.isAfter(end)) {
          withExpiry.add(c);
        }
      }
      withExpiry.sort((a, b) {
        final ea = addMonths(_parseOpenDate(a.openedAt) ?? DateTime(0), 36);
        final eb = addMonths(_parseOpenDate(b.openedAt) ?? DateTime(0), 36);
        return ea.compareTo(eb);
      });
      if (mounted) setState(() {
        _customers = withExpiry;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('약정만료 예정 로드 오류: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text('약정만료 예정', style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
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
                '약정만료 예정 고객 ${_customers.length}건',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text('해당 기간 약정만료 예정 고객이 없습니다', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: _customers.length,
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            return _CustomerCard(
                              customer: customer,
                              isFavorite: mainState?.isFavorite(customer.customerKey) ?? false,
                              onFavoriteToggle: () {
                                mainState?.toggleFavorite(customer.customerKey).then((_) => setState(() {}));
                              },
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => CustomerDetailScreen(
                                      customer: customer,
                                      onFavoriteChanged: _load,
                                    ),
                                  ),
                                ).then((_) => _load());
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
// 최근 등록한 고객사 전체 화면
// ========================================
class RecentRegisteredScreen extends StatefulWidget {
  const RecentRegisteredScreen({super.key});

  @override
  State<RecentRegisteredScreen> createState() => _RecentRegisteredScreenState();
}

class _RecentRegisteredScreenState extends State<RecentRegisteredScreen> {
  List<CustomerData> _customers = [];
  bool _isLoading = true;

  static int _parseOpenDate(String openedAt) {
    if (openedAt.isEmpty) return 0;
    final normalized = openedAt.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length >= 8) return int.tryParse(normalized.substring(0, 8)) ?? 0;
    return int.tryParse(normalized.padRight(8, '0')) ?? 0;
  }

  static DateTime _openDateToDateTime(String openedAt) {
    final n = _parseOpenDate(openedAt);
    if (n == 0) return DateTime(0);
    final y = n ~/ 10000;
    final m = (n % 10000) ~/ 100;
    final d = n % 100;
    return DateTime(y, m, d);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final authService = context.read<AuthService>();
      final customerRepo = context.read<CustomerRepository>();
      final user = authService.currentUser;
      final list = await customerRepo.getFiltered(user);
      // 수기 등록(source=='direct')만 표시
      final registeredKeys = await customerRepo.getRegisteredCustomerKeys();
      final directOnly = list.where((c) => registeredKeys.contains(c.customerKey)).toList();
      // 최근 등록(createdAt) 우선, 없으면 개통일(openDate) 기준 내림차순 (최신이 위로)
      directOnly.sort((a, b) {
        final ta = a.createdAt ?? _openDateToDateTime(a.openDate);
        final tb = b.createdAt ?? _openDateToDateTime(b.openDate);
        return tb.compareTo(ta);
      });
      // 전체보기에서는 최대 20개만 표시
      final limited = directOnly.take(20).toList();
      final dataList = CustomerConverter.toCustomerDataList(limited);
      if (mounted) setState(() {
        _customers = dataList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('최근 등록 고객사 로드 오류: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mainState = context.findAncestorStateOfType<_MainNavigationScreenState>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text('최근 등록한 고객사', style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
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
                '최근 등록한 고객사 ${_customers.length}건',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? Center(
                          child: Text('등록된 고객이 없습니다', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: _customers.length,
                          itemBuilder: (context, index) {
                            final customer = _customers[index];
                            return _CustomerCard(
                              customer: customer,
                              isFavorite: mainState?.isFavorite(customer.customerKey) ?? false,
                              onFavoriteToggle: () {
                                mainState?.toggleFavorite(customer.customerKey).then((_) => setState(() {}));
                              },
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => CustomerDetailScreen(
                                      customer: customer,
                                      onFavoriteChanged: _load,
                                    ),
                                  ),
                                ).then((_) => _load());
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
// 더보기 화면
// ========================================
class MoreScreen extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final String? pendingRoute;
  final VoidCallback? onClearPendingRoute;
  /// 홈/고객사 등 전역 데이터 갱신 (즐겨찾기 등)
  final Future<void> Function()? onGlobalRefresh;

  const MoreScreen({
    super.key,
    this.navigatorKey,
    this.pendingRoute,
    this.onClearPendingRoute,
    this.onGlobalRefresh,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  Set<String> _favoriteCustomerKeys = {};
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await widget.onGlobalRefresh?.call();
      await _loadFavorites();
      CsvReloadBus().reload('customerlist.csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('데이터를 새로고침했습니다.'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('새로고침 실패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  void didUpdateWidget(MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pendingRoute != null && widget.pendingRoute != oldWidget.pendingRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushPendingRoute());
    }
  }

  void _pushPendingRoute() {
    final route = widget.pendingRoute;
    if (route == null) return;
    widget.onClearPendingRoute?.call();
    widget.navigatorKey?.currentState?.pushNamed(route);
  }

  Future<void> _loadFavorites() async {
    try {
      final repo = context.read<CustomerRepository>();
      final keys = await repo.getFavorites();
      if (mounted) setState(() => _favoriteCustomerKeys = keys);
    } catch (e) {
      debugPrint('즐겨찾기 로드 오류: $e');
    }
  }

  Future<void> toggleFavorite(String customerKey) async {
    setState(() {
      if (_favoriteCustomerKeys.contains(customerKey)) {
        _favoriteCustomerKeys.remove(customerKey);
      } else {
        _favoriteCustomerKeys.add(customerKey);
      }
    });
    try {
      await context.read<CustomerRepository>().setFavorites(_favoriteCustomerKeys);
    } catch (e) {
      debugPrint('즐겨찾기 저장 오류: $e');
    }
  }

  bool isFavorite(String customerKey) {
    return _favoriteCustomerKeys.contains(customerKey);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pendingRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushPendingRoute());
    }
    return Navigator(
      key: widget.navigatorKey ?? ValueKey('more_tab'),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (_) => _MoreMenuContent(
              favoriteKeys: _favoriteCustomerKeys,
              toggleFavorite: toggleFavorite,
              isFavorite: isFavorite,
              onLoadFavorites: _loadFavorites,
              onRefresh: _onRefresh,
              isRefreshing: _isRefreshing,
            ),
          );
        }
        if (settings.name == 'favorites') {
          return MaterialPageRoute(
            builder: (_) => FavoritesScreen(
              favoriteKeys: _favoriteCustomerKeys,
              onToggleFavorite: toggleFavorite,
              isFavorite: isFavorite,
            ),
          );
        }
        if (settings.name == 'recent') {
          return MaterialPageRoute(builder: (_) => const RecentRegisteredScreen());
        }
        if (settings.name == 'contract_expiring') {
          return MaterialPageRoute(builder: (_) => const ContractExpiringScreen());
        }
        if (settings.name == 'calendar_view') {
          return MaterialPageRoute(builder: (_) => const CalendarViewPage());
        }
        return null;
      },
    );
  }
}

// 더보기 메뉴 목록 (중첩 Navigator의 첫 화면)
class _MoreMenuContent extends StatelessWidget {
  final Set<String> favoriteKeys;
  final Future<void> Function(String) toggleFavorite;
  final bool Function(String) isFavorite;
  final Future<void> Function() onLoadFavorites;
  final Future<void> Function() onRefresh;
  final bool isRefreshing;

  const _MoreMenuContent({
    required this.favoriteKeys,
    required this.toggleFavorite,
    required this.isFavorite,
    required this.onLoadFavorites,
    required this.onRefresh,
    this.isRefreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 상단: 좌측 아이콘+메뉴명(작게), 정가운데 로고
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.more_horiz_rounded, color: AppColors.textPrimary, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '더보기',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Center(
                      child: Image.asset(
                        'assets/images/sos_logo.png',
                        height: 28,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(width: 90),
                ],
              ),
            ),
            // [계정 영역] 내 아이디 정보 — 메뉴와 구분된 표현
            if (currentUser != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        '내 계정',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_outline, size: 20, color: Colors.grey[600]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentUser.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${currentUser.id} · ${currentUser.roleLabel} · ${currentUser.scopeLabel}',
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
                  ],
                ),
              ),
            // 더보기 메뉴 리스트
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: [
                    _MoreCardButton(
                      title: '새로고침',
                      icon: Icons.refresh,
                      onTap: () { if (!isRefreshing) onRefresh(); },
                      trailing: isRefreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _MoreCardButton(
                      title: '즐겨찾기',
                      icon: Icons.star,
                      onTap: () {
                        Navigator.of(context).pushNamed('favorites').then((_) => onLoadFavorites());
                      },
                    ),
                    const SizedBox(height: 16),
                    _MoreCardButton(
                      title: '약정만료 예정',
                      icon: Icons.event_busy,
                      onTap: () {
                        Navigator.of(context).pushNamed('contract_expiring');
                      },
                    ),
                    const SizedBox(height: 16),
                    _MoreCardButton(
                      title: '캘린더뷰',
                      icon: Icons.calendar_month,
                      onTap: () {
                        Navigator.of(context).pushNamed('calendar_view');
                      },
                    ),
                    const SizedBox(height: 16),
                    _MoreCardButton(
                      title: '최근 등록한 고객사',
                      icon: Icons.person_add_alt_1,
                      onTap: () {
                        Navigator.of(context).pushNamed('recent');
                      },
                    ),
                    // 관리자 페이지 이동 버튼 (Admin만 표시)
                    if (authService.isAdmin) ...[
                      const SizedBox(height: 16),
                      _MoreCardButton(
                        title: '관리자 페이지',
                        icon: Icons.admin_panel_settings,
                        onTap: () {
                          context.go('/admin');
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // [계정 영역] 로그아웃 — 메뉴와 구분된 하단 고정
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Center(
                child: TextButton(
                  onPressed: () async {
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
                        context.go('/login');
                      }
                    }
                  },
                  child: Text(
                    '로그아웃',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
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

// 더보기 카드 버튼 위젯
class _MoreCardButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? trailing;

  const _MoreCardButton({
    required this.title,
    required this.icon,
    required this.onTap,
    this.trailing,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F61).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: const Color(0xFFFF6F61),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                trailing ?? Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
