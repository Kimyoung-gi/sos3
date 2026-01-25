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

/// 관리자 홈 페이지: 사이드바 + 3개 탭 (CSV 업로드, 사용자 관리, 권한 미리보기)
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
        return AdminCsvUploadPage();
      case 1:
        return const _UserManagementTab();
      case 2:
        return const _PermissionPreviewTab();
      default:
        return AdminCsvUploadPage();
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
              Tab(icon: Icon(Icons.cloud_upload), text: 'CSV 업로드'),
              Tab(icon: Icon(Icons.people), text: '사용자 관리'),
              Tab(icon: Icon(Icons.visibility), text: '권한 미리보기'),
            ],
          ),
        ),
        actions: [
          Text('${auth.currentUser?.name ?? ''} (${auth.currentUser?.roleLabel ?? ''})', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 16),
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
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('사용자 생성'),
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
                            DataColumn(label: Text('지사')),
                            DataColumn(label: Text('역할')),
                            DataColumn(label: Text('권한')),
                            DataColumn(label: Text('판매자명')),
                            DataColumn(label: Text('상태')),
                            DataColumn(label: Text('작업')),
                          ],
                          rows: _filteredUsers.map((u) {
                            return DataRow(
                              color: !u.isActive ? MaterialStateProperty.all(Colors.grey.shade200) : null,
                              cells: [
                                DataCell(Text(u.id)),
                                DataCell(Text(u.name)),
                                DataCell(Text(u.hq)),
                                DataCell(Text(u.branch)),
                                DataCell(Text(u.roleLabel)),
                                DataCell(Text(u.scopeLabel)),
                                DataCell(Text(u.sellerName ?? '-')),
                                DataCell(Text(u.isActive ? '활성' : '비활성')),
                                DataCell(
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _showEditDialog(u),
                                    tooltip: '수정',
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
  late TextEditingController _hqController;
  late TextEditingController _branchController;
  late TextEditingController _sellerNameController;
  late TextEditingController _pwController;
  UserRole _role = UserRole.user;
  UserScope _scope = UserScope.self;
  bool _isActive = true;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.user != null;
    _idController = TextEditingController(text: widget.user?.id ?? '');
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _hqController = TextEditingController(text: widget.user?.hq ?? '');
    _branchController = TextEditingController(text: widget.user?.branch ?? '');
    _sellerNameController = TextEditingController(text: widget.user?.sellerName ?? '');
    _pwController = TextEditingController();
    _role = widget.user?.role ?? UserRole.user;
    _scope = widget.user?.scope ?? UserScope.self;
    _isActive = widget.user?.isActive ?? true;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _hqController.dispose();
    _branchController.dispose();
    _sellerNameController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _pwController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호를 입력하세요.'), backgroundColor: Colors.red),
      );
      return;
    }
    try {
      final repo = widget.userRepo;
      final user = User(
        id: _idController.text.trim(),
        name: _nameController.text.trim(),
        hq: _hqController.text.trim(),
        branch: _branchController.text.trim(),
        role: _role,
        scope: _scope,
        isActive: _isActive,
        sellerName: _sellerNameController.text.trim().isEmpty ? null : _sellerNameController.text.trim(),
      );
      if (_isEdit) {
        await repo.update(user, newPassword: _pwController.text.isEmpty ? null : _pwController.text);
      } else {
        await repo.create(user, _pwController.text);
      }
      if (mounted) Navigator.of(context).pop({'success': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '사용자 수정' : '사용자 생성'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _idController,
                  decoration: const InputDecoration(labelText: '아이디 *'),
                  enabled: !_isEdit,
                  validator: (v) => v?.isEmpty ?? true ? '필수' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '이름 *'),
                  validator: (v) => v?.isEmpty ?? true ? '필수' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hqController,
                  decoration: const InputDecoration(labelText: '본부'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _branchController,
                  decoration: const InputDecoration(labelText: '지사'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sellerNameController,
                  decoration: const InputDecoration(labelText: '판매자명 (SELF 권한용)'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  value: _role,
                  decoration: const InputDecoration(labelText: '역할 *'),
                  items: UserRole.values.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r == UserRole.user ? 'USER' : r == UserRole.manager ? 'MANAGER' : 'ADMIN'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _role = v ?? UserRole.user),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserScope>(
                  value: _scope,
                  decoration: const InputDecoration(labelText: '권한 범위 *'),
                  items: UserScope.values.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(s == UserScope.self ? 'SELF' : s == UserScope.branch ? 'BRANCH' : s == UserScope.hq ? 'HQ' : 'ALL'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _scope = v ?? UserScope.self),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwController,
                  decoration: InputDecoration(labelText: _isEdit ? '비밀번호 (변경 시만 입력)' : '비밀번호 *'),
                  obscureText: true,
                  validator: _isEdit ? null : (v) => v?.isEmpty ?? true ? '필수' : null,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('활성'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v ?? true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEdit ? '수정' : '생성'),
        ),
      ],
    );
  }
}

/// 권한 미리보기 탭
class _PermissionPreviewTab extends StatefulWidget {
  const _PermissionPreviewTab();

  @override
  State<_PermissionPreviewTab> createState() => _PermissionPreviewTabState();
}

class _PermissionPreviewTabState extends State<_PermissionPreviewTab> {
  User? _selectedUser;
  List<User> _users = [];
  List<Customer> _previewCustomers = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final repo = context.read<UserRepository>();
      final list = await repo.list();
      if (!mounted) return;
      setState(() => _users = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로드 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _preview() async {
    if (_selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자를 선택하세요.'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = context.read<CustomerRepository>();
      final filtered = await repo.getFiltered(_selectedUser);
      if (!mounted) return;
      setState(() {
        _previewCustomers = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('미리보기 실패: $e'), backgroundColor: Colors.red),
      );
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
                  const Text('권한 미리보기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 300,
                  child: DropdownButtonFormField<User?>(
                    value: _selectedUser,
                    decoration: const InputDecoration(labelText: '사용자 선택', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('선택하세요')),
                      ..._users.map((u) => DropdownMenuItem(value: u, child: Text('${u.name} (${u.id}) - ${u.roleLabel}/${u.scopeLabel}'))),
                    ],
                    onChanged: (v) => setState(() => _selectedUser = v),
                  ),
                ),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: _loading ? null : _preview,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('미리보기'),
                ),
                if (_selectedUser != null) ...[
                  const SizedBox(width: 16),
                  Text('권한: ${_selectedUser!.roleLabel} / ${_selectedUser!.scopeLabel}'),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _previewCustomers.isNotEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('조회 가능한 고객: ${_previewCustomers.length}건', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Card(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('고객명')),
                                    DataColumn(label: Text('개통일자')),
                                    DataColumn(label: Text('상품명')),
                                    DataColumn(label: Text('본부')),
                                    DataColumn(label: Text('지사')),
                                    DataColumn(label: Text('판매자')),
                                  ],
                                  rows: _previewCustomers.map((c) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(c.customerName)),
                                        DataCell(Text(c.openDate)),
                                        DataCell(Text(c.productName)),
                                        DataCell(Text(c.hq)),
                                        DataCell(Text(c.branch)),
                                        DataCell(Text(c.sellerName)),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Text('사용자를 선택하고 미리보기를 클릭하세요.', style: TextStyle(color: Colors.grey)),
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
