import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../models/user.dart';
import '../../models/customer.dart';
import '../../models/sales_status.dart';
import '../../models/performance.dart';
import '../../models/upload_history.dart';
import '../../services/auth_service.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/customer_repository.dart';
import '../../repositories/sales_status_repository.dart';
import '../../repositories/performance_repository.dart';
import '../../repositories/upload_history_repository.dart';
import '../../utils/csv_parser_extended.dart';
import '../../utils/csv_template_generator.dart';
import '../../utils/csv_downloader.dart';
import 'admin_csv_upload_page.dart';
import 'admin_promotions_page.dart';

/// 관리자 홈 페이지: 사이드바 + 3개 탭 (사용자 관리, CSV 업로드, 홈 프로모션)
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _selectedIndex = _tabController.index);
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildSelectedTab() {
    switch (_selectedIndex) {
      case 0:
        return const _UserManagementTab();
      case 1:
        return AdminCsvUploadPage();
      case 2:
        return const AdminPromotionsPage();
      default:
        return const _UserManagementTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 대시보드'),
        backgroundColor: Colors.white,
        elevation: 1,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            onTap: (index) {
              _tabController.animateTo(index);
              setState(() => _selectedIndex = index);
            },
            tabs: const [
              Tab(icon: Icon(Icons.people), text: '사용자 관리'),
              Tab(icon: Icon(Icons.cloud_upload), text: 'CSV 업로드'),
              Tab(icon: Icon(Icons.image), text: '홈 프로모션'),
            ],
          ),
        ),
        actions: [
          Text('${auth.currentUser?.name ?? ''} (${auth.currentUser?.roleLabel ?? ''})', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 16),
          // 일반 페이지로 이동 버튼 (Admin만 표시)
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: '일반 페이지로 이동',
              onPressed: () {
                context.go('/main');
              },
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () async {
              await auth.logout();
              if (mounted) context.go('/');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: _buildSelectedTab(),
            );
          },
        ),
      ),
    );
  }
}

/// CSV 업로드 탭 (타입별 분리)
class _CsvUploadTab extends StatefulWidget {
  const _CsvUploadTab();

  @override
  State<_CsvUploadTab> createState() => _CsvUploadTabState();
}

class _CsvUploadTabState extends State<_CsvUploadTab> with SingleTickerProviderStateMixin {
  late TabController _typeTabController;

  @override
  void initState() {
    super.initState();
    _typeTabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _typeTabController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            minHeight: constraints.maxHeight,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CSV 업로드 센터', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      '각 CSV 종류별로 파일을 업로드하여 데이터를 시스템에 반영합니다.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    TabBar(
                      controller: _typeTabController,
                      isScrollable: true,
                      tabs: UploadType.values.map((t) => Tab(text: t.label)).toList(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _typeTabController,
                  children: UploadType.values.map((type) => _UploadCard(type: type)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 타입별 업로드 카드
class _UploadCard extends StatefulWidget {
  final UploadType type;

  const _UploadCard({required this.type});

  @override
  State<_UploadCard> createState() => _UploadCardState();
}

class _UploadCardState extends State<_UploadCard> {
  static const int _maxFileSizeBytes = 10 * 1024 * 1024; // 10MB

  dynamic _previewRows; // 미리보기용 상위 10행
  String? _selectedCsvText; // 업로드 시 전체 파싱용
  bool _updateOnDuplicate = true;
  bool _replaceAll = false; // 전체 덮어쓰기 옵션
  bool _loading = false;
  String? _selectedFilename;
  List<UploadHistory> _history = [];
  List<Map<String, dynamic>>? _lastErrorRows; // 실패 시 에러 CSV 다운로드용
  bool _lastUploadHadErrors = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final repo = context.read<UploadHistoryRepository>();
      final h = await repo.getAll(type: widget.type, limit: 20);
      if (mounted) {
        setState(() => _history = h);
      }
    } catch (e) {
      debugPrint('히스토리 로드 오류: $e');
    }
  }

  Future<void> _pickAndPreview() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: '${widget.type.label} CSV 파일 선택',
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 읽을 수 없습니다.'), backgroundColor: Colors.red),
        );
        return;
      }
      if (file.bytes!.length > _maxFileSizeBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일 크기는 10MB 이하여야 합니다.'), backgroundColor: Colors.red),
        );
        return;
      }
      final csvText = String.fromCharCodes(file.bytes!);
      setState(() {
        _selectedFilename = file.name;
        _selectedCsvText = csvText;
        _lastErrorRows = null;
        _lastUploadHadErrors = false;
      });

      // 타입별 파싱 (미리보기 상위 10행)
      switch (widget.type) {
        case UploadType.customerBase:
          final rows = CsvParserExtended.parseCustomerBase(csvText);
          setState(() => _previewRows = rows.take(10).toList());
          break;
        case UploadType.salesStatus:
          final rows = CsvParserExtended.parseSalesStatus(csvText);
          setState(() => _previewRows = rows.take(10).toList());
          break;
        case UploadType.performance:
          final rows = CsvParserExtended.parsePerformance(csvText);
          setState(() => _previewRows = rows.take(10).toList());
          break;
        case UploadType.other:
          setState(() => _previewRows = []);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기타 타입은 아직 지원하지 않습니다.'), backgroundColor: Colors.orange),
          );
          return;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// 전체 CSV 파싱 (미리보기 10행이 아닌 전체)
  List<dynamic> _parseFullCsv() {
    final csv = _selectedCsvText ?? '';
    switch (widget.type) {
      case UploadType.customerBase:
        return CsvParserExtended.parseCustomerBase(csv);
      case UploadType.salesStatus:
        return CsvParserExtended.parseSalesStatus(csv);
      case UploadType.performance:
        return CsvParserExtended.parsePerformance(csv);
      default:
        return [];
    }
  }

  List<Map<String, dynamic>> _buildErrorRowsForDownload(List<dynamic> rows) {
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (r is CsvRowExtended<dynamic> && r.error != null) {
        final m = <String, dynamic>{};
        for (final e in r.rawRow.entries) {
          m[e.key.toString()] = e.value;
        }
        m['행'] = r.lineIndex;
        m['오류'] = r.error!;
        out.add(m);
      }
    }
    return out;
  }

  void _downloadErrorCsv() {
    if (_lastErrorRows == null || _lastErrorRows!.isEmpty) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = '에러_${widget.type.label}_$ts.csv';
    CsvDownloader.downloadErrorCsv(_lastErrorRows!, name);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('에러 CSV를 다운로드했습니다.'), backgroundColor: Colors.blue),
    );
  }

  Future<void> _upload() async {
    if (_selectedCsvText == null || _selectedCsvText!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 CSV 파일을 선택하고 미리보기를 확인하세요.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final uploader = auth.currentUser?.name ?? auth.currentUser?.id ?? 'Unknown';

    try {
      int total = 0;
      int inserted = 0;
      int updated = 0;
      int failed = 0;
      List<String> errorSamples = [];
      List<Map<String, dynamic>>? errorRowsForDownload;

      switch (widget.type) {
        case UploadType.customerBase: {
          final rows = _parseFullCsv().cast<CsvRowExtended<Customer>>();
          final valid = rows.where((r) => r.data != null).map((r) => r.data!).toList();
          final errorRows = rows.where((r) => r.error != null).toList();
          total = rows.length;
          failed = errorRows.length;
          errorSamples = errorRows.take(20).map((r) => '행 ${r.lineIndex}: ${r.error}').toList();
          if (errorRows.isNotEmpty) errorRowsForDownload = _buildErrorRowsForDownload(rows);

          final repo = context.read<CustomerRepository>();
          if (_replaceAll) {
            await repo.saveAll(valid);
            inserted = valid.length;
            updated = 0;
          } else {
            final mr = await repo.mergeFromCsv(valid, updateOnDuplicate: _updateOnDuplicate);
            inserted = mr.success;
            updated = mr.updated;
          }
          break;
        }

        case UploadType.salesStatus: {
          final rows = _parseFullCsv().cast<CsvRowExtended<SalesStatus>>();
          final valid = rows.where((r) => r.data != null).map((r) => r.data!).toList();
          final errorRows = rows.where((r) => r.error != null).toList();
          total = rows.length;
          failed = errorRows.length;
          errorSamples = errorRows.take(20).map((r) => '행 ${r.lineIndex}: ${r.error}').toList();
          if (errorRows.isNotEmpty) errorRowsForDownload = _buildErrorRowsForDownload(rows);

          final repo = context.read<SalesStatusRepository>();
          if (_replaceAll) {
            await repo.replaceAll(valid);
            inserted = valid.length;
            updated = 0;
          } else {
            final mr = await repo.mergeFromCsv(valid, updateOnDuplicate: _updateOnDuplicate);
            inserted = mr.success;
            updated = mr.updated;
          }
          break;
        }

        case UploadType.performance: {
          final rows = _parseFullCsv().cast<CsvRowExtended<Performance>>();
          final valid = rows.where((r) => r.data != null).map((r) => r.data!).toList();
          final errorRows = rows.where((r) => r.error != null).toList();
          total = rows.length;
          failed = errorRows.length;
          errorSamples = errorRows.take(20).map((r) => '행 ${r.lineIndex}: ${r.error}').toList();
          if (errorRows.isNotEmpty) errorRowsForDownload = _buildErrorRowsForDownload(rows);

          final repo = context.read<PerformanceRepository>();
          if (_replaceAll) {
            await repo.replaceAll(valid);
            inserted = valid.length;
            updated = 0;
          } else {
            final mr = await repo.mergeFromCsv(valid, updateOnDuplicate: _updateOnDuplicate);
            inserted = mr.success;
            updated = mr.updated;
          }
          break;
        }

        case UploadType.other:
          throw UnimplementedError('기타 타입은 아직 지원하지 않습니다.');
      }

      // 히스토리 저장
      final historyRepo = context.read<UploadHistoryRepository>();
      final status = failed == 0
          ? UploadStatus.success
          : (inserted + updated > 0)
              ? UploadStatus.partial
              : UploadStatus.failed;
      final history = UploadHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: widget.type,
        filename: _selectedFilename ?? 'unknown.csv',
        uploader: uploader,
        createdAt: DateTime.now(),
        status: status,
        totalRows: total,
        inserted: inserted,
        updated: updated,
        failed: failed,
        errorSamples: errorSamples,
      );
      await historyRepo.add(history);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _previewRows = null;
        _selectedFilename = null;
        _selectedCsvText = null;
        _lastErrorRows = errorRowsForDownload;
        _lastUploadHadErrors = failed > 0;
      });

      await _loadHistory();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '업로드 완료: 총 $total건, 신규 $inserted건, 업데이트 $updated건, 실패 $failed건',
          ),
          backgroundColor: failed == 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _downloadTemplate() {
    final template = CsvTemplateGenerator.generate(widget.type);
    final filename = '${widget.type.label}_템플릿.csv';
    CsvDownloader.download(template, filename);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('템플릿 다운로드: $filename'), backgroundColor: Colors.blue),
    );
  }

  Widget _buildPreviewTable() {
    if (_previewRows == null || (_previewRows as List).isEmpty) {
      return const Center(
        child: Text('CSV 파일을 선택하면 미리보기가 표시됩니다.', style: TextStyle(color: Colors.grey)),
      );
    }

    switch (widget.type) {
      case UploadType.customerBase:
        final rows = _previewRows as List<CsvRowExtended<Customer>>;
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('행')),
                  DataColumn(label: Text('고객명')),
                  DataColumn(label: Text('개통일자')),
                  DataColumn(label: Text('상품명')),
                  DataColumn(label: Text('본부')),
                  DataColumn(label: Text('지사')),
                  DataColumn(label: Text('판매자')),
                  DataColumn(label: Text('상태')),
                  DataColumn(label: Text('오류')),
                ],
                rows: rows.map((r) {
                  final c = r.data;
                  return DataRow(
                    color: r.error != null ? MaterialStateProperty.all(Colors.red.shade50) : null,
                    cells: [
                      DataCell(Text('${r.lineIndex}')),
                      DataCell(Text(c?.customerName ?? '-')),
                      DataCell(Text(c?.openDate ?? '-')),
                      DataCell(Text(c?.productName ?? '-')),
                      DataCell(Text(c?.hq ?? '-')),
                      DataCell(Text(c?.branch ?? '-')),
                      DataCell(Text(c?.sellerName ?? '-')),
                      DataCell(Text(c?.salesStatus ?? '-')),
                      DataCell(Text(r.error ?? '')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );

      case UploadType.salesStatus:
        final rows = _previewRows as List<CsvRowExtended<SalesStatus>>;
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('행')),
                  DataColumn(label: Text('고객ID')),
                  DataColumn(label: Text('영업상태')),
                  DataColumn(label: Text('메모')),
                  DataColumn(label: Text('업데이트일')),
                  DataColumn(label: Text('오류')),
                ],
                rows: rows.map((r) {
                  final s = r.data;
                  return DataRow(
                    color: r.error != null ? MaterialStateProperty.all(Colors.red.shade50) : null,
                    cells: [
                      DataCell(Text('${r.lineIndex}')),
                      DataCell(Text(s?.customerId ?? '-')),
                      DataCell(Text(s?.salesStatus ?? '-')),
                      DataCell(Text(s?.memo ?? '-')),
                      DataCell(Text(s?.updatedAt ?? '-')),
                      DataCell(Text(r.error ?? '')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );

      case UploadType.performance:
        final rows = _previewRows as List<CsvRowExtended<Performance>>;
        return Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('행')),
                  DataColumn(label: Text('직원ID')),
                  DataColumn(label: Text('직원명')),
                  DataColumn(label: Text('연월')),
                  DataColumn(label: Text('포인트')),
                  DataColumn(label: Text('순위')),
                  DataColumn(label: Text('오류')),
                ],
                rows: rows.map((r) {
                  final p = r.data;
                  return DataRow(
                    color: r.error != null ? MaterialStateProperty.all(Colors.red.shade50) : null,
                    cells: [
                      DataCell(Text('${r.lineIndex}')),
                      DataCell(Text(p?.employeeId ?? '-')),
                      DataCell(Text(p?.employeeName ?? '-')),
                      DataCell(Text(p?.yyyymm ?? '-')),
                      DataCell(Text(p?.point?.toString() ?? '-')),
                      DataCell(Text(p?.rank?.toString() ?? '-')),
                      DataCell(Text(r.error ?? '')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );

      default:
        return const Center(child: Text('미리보기를 지원하지 않는 타입입니다.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.type.label,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download),
                  label: const Text('템플릿 다운로드'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _pickAndPreview,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('CSV 파일 선택'),
                ),
              ],
            ),
            if (_selectedFilename != null) ...[
              const SizedBox(height: 8),
              Text('선택된 파일: $_selectedFilename', style: TextStyle(color: Colors.grey[600])),
            ],
            const SizedBox(height: 16),
            if (_previewRows != null && (_previewRows as List).isNotEmpty) ...[
              Row(
                children: [
                  Checkbox(
                    value: _updateOnDuplicate,
                    onChanged: (v) => setState(() => _updateOnDuplicate = v ?? true),
                  ),
                  const Text('중복 시 업데이트'),
                  const SizedBox(width: 16),
                  Checkbox(
                    value: _replaceAll,
                    onChanged: (v) => setState(() => _replaceAll = v ?? true),
                  ),
                  const Text('전체 덮어쓰기'),
                  const Spacer(),
                  FilledButton(
                    onPressed: _loading ? null : _upload,
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('업로드 확정'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _buildPreviewTable(),
            if (_lastUploadHadErrors && _lastErrorRows != null && _lastErrorRows!.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _downloadErrorCsv,
                icon: const Icon(Icons.download),
                label: const Text('에러 CSV 다운로드'),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
            const SizedBox(height: 32),
            const Text('업로드 히스토리 (최근 20건)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _history.isEmpty
                ? const Center(child: Text('히스토리가 없습니다.', style: TextStyle(color: Colors.grey)))
                : Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('업로드 시각')),
                          DataColumn(label: Text('업로더')),
                          DataColumn(label: Text('파일명')),
                          DataColumn(label: Text('총 행')),
                          DataColumn(label: Text('신규')),
                          DataColumn(label: Text('업데이트')),
                          DataColumn(label: Text('실패')),
                          DataColumn(label: Text('상태')),
                        ],
                        rows: _history.map((h) {
                          return DataRow(
                            color: h.status == UploadStatus.failed
                                ? MaterialStateProperty.all(Colors.red.shade50)
                                : h.status == UploadStatus.partial
                                    ? MaterialStateProperty.all(Colors.orange.shade50)
                                    : null,
                            cells: [
                              DataCell(Text('${h.createdAt.year}-${h.createdAt.month.toString().padLeft(2, '0')}-${h.createdAt.day.toString().padLeft(2, '0')} ${h.createdAt.hour.toString().padLeft(2, '0')}:${h.createdAt.minute.toString().padLeft(2, '0')}')),
                              DataCell(Text(h.uploader)),
                              DataCell(Text(h.filename)),
                              DataCell(Text('${h.totalRows}')),
                              DataCell(Text('${h.inserted}')),
                              DataCell(Text('${h.updated}')),
                              DataCell(Text('${h.failed}')),
                              DataCell(Text(
                                h.status == UploadStatus.success
                                    ? '성공'
                                    : h.status == UploadStatus.partial
                                        ? '부분성공'
                                        : '실패',
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

/// 사용자 관리 탭
class _UserManagementTab extends StatefulWidget {
  const _UserManagementTab();

  @override
  State<_UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends State<_UserManagementTab> {
  List<User> _users = [];
  String _searchQuery = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<UserRepository>();
      final list = await repo.list();
      if (!mounted) return;
      setState(() {
        _users = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로드 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<User> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users.where((u) {
      return u.id.toLowerCase().contains(q) ||
          u.name.toLowerCase().contains(q) ||
          u.hq.toLowerCase().contains(q) ||
          u.branch.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _UserEditDialog(userRepo: context.read<UserRepository>()),
    );
    if (result != null) {
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자가 생성되었습니다.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _showEditDialog(User user) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _UserEditDialog(user: user, userRepo: context.read<UserRepository>()),
    );
    if (result != null) {
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자가 수정되었습니다.'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _showDeleteDialog(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사용자 삭제'),
        content: Text('정말 "${user.name}" 사용자를 삭제하시겠습니까?\n이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await context.read<UserRepository>().delete(user);
        await _loadUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('사용자가 삭제되었습니다.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 권한 라벨 변환
  String _roleToLabel(UserRole role) {
    return role == UserRole.admin ? '관리자' : '일반';
  }

  // 권한범위 라벨 변환
  String _scopeToLabel(UserScope scope) {
    switch (scope) {
      case UserScope.self:
        return '본인';
      case UserScope.branch:
        return '센터';
      case UserScope.hq:
        return '본부';
      case UserScope.all:
        return '전체';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: constraints.maxWidth,
            minHeight: constraints.maxHeight,
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('사용자 관리', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: _showCreateDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('사용자 생성'),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 240,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: '검색 (아이디/이름/본부/지사)',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 16),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : Card(
                    child: SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('아이디')),
                            DataColumn(label: Text('이름')),
                            DataColumn(label: Text('본부')),
                            DataColumn(label: Text('센터')),
                            DataColumn(label: Text('권한')),
                            DataColumn(label: Text('권한범위')),
                            DataColumn(label: Text('작업')),
                          ],
                          rows: _filteredUsers.map((u) {
                            return DataRow(
                              color: !u.isActive ? MaterialStateProperty.all(Colors.grey.shade200) : null,
                              cells: [
                                DataCell(Text(u.id)),
                                DataCell(Text(u.name)),
                                DataCell(Text(u.hq.isEmpty ? '-' : u.hq)),
                                DataCell(Text(u.branch.isEmpty ? '-' : u.branch)),
                                DataCell(Text(_roleToLabel(u.role))),
                                DataCell(Text(_scopeToLabel(u.scope))),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20),
                                        onPressed: () => _showEditDialog(u),
                                        tooltip: '수정',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                        onPressed: () => _showDeleteDialog(u),
                                        tooltip: '삭제',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
          ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 사용자 생성/수정 다이얼로그
class _UserEditDialog extends StatefulWidget {
  final User? user;
  final UserRepository userRepo;

  const _UserEditDialog({this.user, required this.userRepo});

  @override
  State<_UserEditDialog> createState() => _UserEditDialogState();
}

class _UserEditDialogState extends State<_UserEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _idController;
  late TextEditingController _nameController;
  late TextEditingController _passwordController;
  late TextEditingController _passwordConfirmController;
  
  // 선택값
  String? _selectedHq;
  String? _selectedCenter;
  String? _selectedRoleLabel; // '일반' 또는 '관리자'
  String? _selectedScopeLabel; // '본인', '센터', '본부', '전체'
  
  // 비밀번호 표시/숨김
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  
  bool _isEdit = false;
  bool _isLoading = false;

  // 옵션 리스트
  static const List<String> _hqOptions = ['강북', '강남', '강서', '동부', '서부'];
  static const List<String> _centerOptions = ['강북', '강동', '강원', '강남', '남부', '강서', '인천', '부산', '경남', '대구', '충청', '광주', '전남'];
  static const List<String> _roleLabels = ['일반', '관리자'];
  static const List<String> _scopeLabels = ['본인', '센터', '본부', '전체'];
  
  // 매핑
  static UserRole _roleFromLabel(String label) {
    return label == '관리자' ? UserRole.admin : UserRole.user;
  }
  
  static UserScope _scopeFromLabel(String label) {
    switch (label) {
      case '본인': return UserScope.self;
      case '센터': return UserScope.branch;
      case '본부': return UserScope.hq;
      case '전체': return UserScope.all;
      default: return UserScope.self;
    }
  }
  
  static String _roleToLabel(UserRole role) {
    return role == UserRole.admin ? '관리자' : '일반';
  }
  
  static String _scopeToLabel(UserScope scope) {
    switch (scope) {
      case UserScope.self: return '본인';
      case UserScope.branch: return '센터';
      case UserScope.hq: return '본부';
      case UserScope.all: return '전체';
    }
  }

  @override
  void initState() {
    super.initState();
    _isEdit = widget.user != null;
    _idController = TextEditingController(text: widget.user?.id ?? '');
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _passwordController = TextEditingController();
    _passwordConfirmController = TextEditingController();
    
    if (_isEdit && widget.user != null) {
      final u = widget.user!;
      _selectedHq = u.hq.isNotEmpty ? u.hq : null;
      _selectedCenter = u.branch.isNotEmpty ? u.branch : null;
      _selectedRoleLabel = _roleToLabel(u.role);
      // 관리자일 경우 권한범위는 항상 '전체'
      _selectedScopeLabel = u.role == UserRole.admin ? '전체' : _scopeToLabel(u.scope);
    } else {
      _selectedRoleLabel = '일반';
      _selectedScopeLabel = '본인';
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    if (!_isEdit && _idController.text.trim().isEmpty) return false;
    if (_nameController.text.trim().isEmpty) return false;
    if (_selectedRoleLabel == null) return false;
    // 관리자가 아닐 때만 권한범위 체크
    if (_selectedRoleLabel != '관리자' && _selectedScopeLabel == null) return false;
    if (!_isEdit) {
      if (_passwordController.text.length < 6) return false;
      if (_passwordController.text != _passwordConfirmController.text) return false;
    } else {
      if (_passwordController.text.isNotEmpty && _passwordController.text.length < 6) return false;
      if (_passwordController.text.isNotEmpty && _passwordController.text != _passwordConfirmController.text) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    // 비밀번호 검증
    if (!_isEdit) {
      if (_passwordController.text.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호는 6자 이상이어야 합니다.'), backgroundColor: Colors.red),
        );
        return;
      }
      if (_passwordController.text != _passwordConfirmController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호가 일치하지 않습니다.'), backgroundColor: Colors.red),
        );
        return;
      }
    } else {
      if (_passwordController.text.isNotEmpty) {
        if (_passwordController.text.length < 6) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('비밀번호는 6자 이상이어야 합니다.'), backgroundColor: Colors.red),
          );
          return;
        }
        if (_passwordController.text != _passwordConfirmController.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('비밀번호가 일치하지 않습니다.'), backgroundColor: Colors.red),
          );
          return;
        }
      }
    }
    
    setState(() => _isLoading = true);
    
    try {
      final repo = widget.userRepo;
      
      // 아이디 (수정 모드에서는 기존 아이디 유지)
      final userId = _isEdit ? widget.user!.id : _idController.text.trim();
      
      if (userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('아이디를 입력하세요.'), backgroundColor: Colors.red),
        );
        return;
      }
      
      // 관리자 권한일 경우 권한범위는 항상 ALL
      final scope = _roleFromLabel(_selectedRoleLabel!) == UserRole.admin
          ? UserScope.all
          : _scopeFromLabel(_selectedScopeLabel!);
      
      final user = User(
        id: userId,
        name: _nameController.text.trim(),
        hq: _selectedHq ?? '',
        branch: _selectedCenter ?? '',
        role: _roleFromLabel(_selectedRoleLabel!),
        scope: scope,
        isActive: true,
        sellerName: null,
      );
      
      if (_isEdit) {
        await repo.update(user, newPassword: _passwordController.text.isEmpty ? null : _passwordController.text);
      } else {
        await repo.create(user, _passwordController.text);
      }
      
      if (mounted) {
        Navigator.of(context).pop({'success': true});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEdit ? '사용자가 수정되었습니다.' : '사용자가 생성되었습니다.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('사용자 저장 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validatePassword(String? value) {
    if (!_isEdit && (value == null || value.isEmpty)) {
      return '비밀번호를 입력하세요';
    }
    if (value != null && value.isNotEmpty && value.length < 6) {
      return '비밀번호는 6자 이상이어야 합니다';
    }
    return null;
  }

  String? _validatePasswordConfirm(String? value) {
    if (!_isEdit && (value == null || value.isEmpty)) {
      return '비밀번호 확인을 입력하세요';
    }
    if (value != null && value.isNotEmpty && _passwordController.text != value) {
      return '비밀번호가 일치하지 않습니다';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: isDesktop ? 700 : MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isEdit ? '사용자 수정' : '사용자 생성',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // 폼 내용
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildFormLayout(),
                ),
              ),
              // 하단 버튼
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: (_isLoading || !_isFormValid) ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6F61),
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isEdit ? '수정' : '생성'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _idController,
          decoration: const InputDecoration(
            labelText: '아이디 *',
            border: OutlineInputBorder(),
          ),
          enabled: !_isEdit,
          validator: (v) => (!_isEdit && (v?.trim().isEmpty ?? true)) ? '아이디를 입력하세요' : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '이름 *',
            border: OutlineInputBorder(),
          ),
          validator: (v) => v?.trim().isEmpty ?? true ? '이름을 입력하세요' : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedHq,
          decoration: const InputDecoration(
            labelText: '본부',
            border: OutlineInputBorder(),
            hintText: '선택하세요',
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('선택 안 함'),
            ),
            ..._hqOptions.map((hq) {
              return DropdownMenuItem(
                value: hq,
                child: Text(hq),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _selectedHq = value;
            });
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedCenter,
          decoration: const InputDecoration(
            labelText: '센터',
            border: OutlineInputBorder(),
            hintText: '선택하세요',
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('선택 안 함'),
            ),
            ..._centerOptions.map((center) {
              return DropdownMenuItem(
                value: center,
                child: Text(center),
              );
            }),
          ],
          onChanged: (value) {
            setState(() {
              _selectedCenter = value;
            });
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedRoleLabel,
          decoration: const InputDecoration(
            labelText: '권한 *',
            border: OutlineInputBorder(),
            hintText: '선택하세요',
          ),
          items: _roleLabels.map((label) {
            return DropdownMenuItem(
              value: label,
              child: Text(label),
            );
          }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedRoleLabel = value;
                    // 관리자로 변경 시 권한범위를 '전체'로 자동 설정
                    if (value == '관리자') {
                      _selectedScopeLabel = '전체';
                    }
                  });
                },
                validator: (v) => v == null ? '권한을 선택하세요' : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedScopeLabel,
          decoration: InputDecoration(
            labelText: '권한범위 *',
            border: const OutlineInputBorder(),
            hintText: '선택하세요',
            enabled: _selectedRoleLabel != '관리자',
          ),
          items: _scopeLabels.map((label) {
            return DropdownMenuItem(
              value: label,
              child: Text(label),
            );
          }).toList(),
          onChanged: _selectedRoleLabel == '관리자' ? null : (value) {
            setState(() {
              _selectedScopeLabel = value;
            });
          },
          validator: (v) {
            // 관리자일 때는 권한범위 검증 건너뛰기
            if (_selectedRoleLabel == '관리자') return null;
            return v == null ? '권한범위를 선택하세요' : null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: _isEdit ? '비밀번호 (변경 시만)' : '비밀번호 *',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          obscureText: _obscurePassword,
          validator: _validatePassword,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordConfirmController,
          decoration: InputDecoration(
            labelText: _isEdit ? '비밀번호 확인 (변경 시만)' : '비밀번호 확인 *',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePasswordConfirm ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() {
                  _obscurePasswordConfirm = !_obscurePasswordConfirm;
                });
              },
            ),
          ),
          obscureText: _obscurePasswordConfirm,
          validator: _validatePasswordConfirm,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

