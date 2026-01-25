import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../models/user.dart';
import '../../models/customer.dart';
import '../../services/auth_service.dart';
import '../../repositories/user_repository.dart';
import '../../repositories/customer_repository.dart';
import '../../utils/csv_parser.dart';

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
        return const _CsvUploadTab();
      case 1:
        return const _UserManagementTab();
      case 2:
        return const _PermissionPreviewTab();
      default:
        return const _CsvUploadTab();
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
              Tab(icon: Icon(Icons.upload_file), text: 'CSV 업로드'),
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

/// CSV 업로드 탭
class _CsvUploadTab extends StatefulWidget {
  const _CsvUploadTab();

  @override
  State<_CsvUploadTab> createState() => _CsvUploadTabState();
}

class _CsvUploadTabState extends State<_CsvUploadTab> {
  List<CsvRow> _previewRows = [];
  bool _updateOnDuplicate = true;
  bool _loading = false;

  Future<void> _pickAndPreview() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'CSV 파일 선택',
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 읽을 수 없습니다.'), backgroundColor: Colors.red),
        );
        return;
      }
      final csvText = String.fromCharCodes(file.bytes!);
      final rows = CsvParser.parse(csvText, previewLimit: 20);
      setState(() => _previewRows = rows);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _upload() async {
    if (_previewRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 CSV 파일을 선택하고 미리보기를 확인하세요.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final validCustomers = _previewRows.where((r) => r.customer != null).map((r) => r.customer!).toList();
    if (validCustomers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 데이터가 없습니다.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = context.read<CustomerRepository>();
      final result = await repo.mergeFromCsv(validCustomers, updateOnDuplicate: _updateOnDuplicate);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _previewRows = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('업로드 완료: 총 ${result.total}건, 성공 ${result.success}건, 업데이트 ${result.updated}건, 스킵 ${result.skipped}건'),
          backgroundColor: Colors.green,
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
                  const Text('CSV 업로드', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _loading ? null : _pickAndPreview,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('CSV 파일 선택'),
                ),
                const SizedBox(width: 16),
                if (_previewRows.isNotEmpty) ...[
                  Checkbox(
                    value: _updateOnDuplicate,
                    onChanged: (v) => setState(() => _updateOnDuplicate = v ?? true),
                  ),
                  const Text('중복 시 업데이트'),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: _loading ? null : _upload,
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('업로드 확정'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),
            _previewRows.isNotEmpty
                ? Card(
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
                          rows: _previewRows.map((r) {
                            final c = r.customer;
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
                  )
                : const Center(
                    child: Text('CSV 파일을 선택하면 미리보기가 표시됩니다.', style: TextStyle(color: Colors.grey)),
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
