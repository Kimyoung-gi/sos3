import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/customer.dart';
import '../../repositories/customer_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 고객사 등록 페이지
class CustomerRegisterPage extends StatefulWidget {
  const CustomerRegisterPage({super.key});

  @override
  State<CustomerRegisterPage> createState() => _CustomerRegisterPageState();
}

class _CustomerRegisterPageState extends State<CustomerRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  
  // 폼 컨트롤러
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _openDateController = TextEditingController();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _sellerController = TextEditingController();
  final TextEditingController _buildingController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _personInChargeController = TextEditingController();
  
  // 선택값
  String? _selectedProductType;
  String? _selectedHq;
  String? _selectedSalesStatus = '영업전';
  
  // 날짜
  DateTime? _selectedDate;
  
  // 로딩 상태
  bool _isLoading = false;
  
  // 옵션 리스트 (기존 데이터에서 추출하거나 기본값 사용)
  List<String> _productTypeOptions = [];
  static const List<String> _hqOptions = ['강북', '강남', '강서', '동부', '서부'];
  static const List<String> _salesStatusOptions = ['영업전', '영업중', '영업실패', '영업성공'];
  
  @override
  void initState() {
    super.initState();
    _loadProductTypes();
  }
  
  @override
  void dispose() {
    _customerNameController.dispose();
    _openDateController.dispose();
    _productNameController.dispose();
    _branchController.dispose();
    _sellerController.dispose();
    _buildingController.dispose();
    _memoController.dispose();
    _personInChargeController.dispose();
    super.dispose();
  }
  
  /// 기존 고객 데이터에서 상품유형 리스트 추출
  Future<void> _loadProductTypes() async {
    try {
      final repo = context.read<CustomerRepository>();
      final allCustomers = await repo.getAll();
      final productTypes = allCustomers
          .map((c) => c.productType)
          .where((type) => type.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      
      if (mounted) {
        setState(() {
          _productTypeOptions = productTypes.isNotEmpty ? productTypes : ['Internet', 'Mobile', 'IPTV'];
        });
      }
    } catch (e) {
      debugPrint('상품유형 로드 오류: $e');
      if (mounted) {
        setState(() {
          _productTypeOptions = ['Internet', 'Mobile', 'IPTV'];
        });
      }
    }
  }
  
  /// 날짜 선택
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _openDateController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }
  
  /// 폼 검증
  bool get _isFormValid {
    return _customerNameController.text.trim().isNotEmpty &&
        _openDateController.text.trim().isNotEmpty &&
        _selectedProductType != null &&
        _productNameController.text.trim().isNotEmpty &&
        _selectedHq != null &&
        _selectedSalesStatus != null;
  }
  
  /// 저장
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (!_isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('필수 항목을 모두 입력해주세요.'),
          backgroundColor: AppColors.statusProgress,
        ),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final repo = context.read<CustomerRepository>();
      
      // Customer 모델 생성
      final newCustomer = Customer(
        customerName: _customerNameController.text.trim(),
        openDate: _openDateController.text.trim(),
        productName: _productNameController.text.trim(),
        productType: _selectedProductType!,
        hq: _selectedHq!,
        branch: _branchController.text.trim(),
        sellerName: _sellerController.text.trim(),
        building: _buildingController.text.trim(),
        salesStatus: _selectedSalesStatus!,
        memo: _memoController.text.trim(),
        isFavorite: false,
        personInCharge: _personInChargeController.text.trim(),
      );
      
      // 중복 체크
      final (success, isDuplicate, savedCustomer) = await repo.createOrUpdateCustomer(
        newCustomer,
        forceUpdate: false,
      );
      
      if (!mounted) return;
      
      if (isDuplicate && !success) {
        // 중복 다이얼로그 표시
        final shouldOverwrite = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('중복 고객', style: TextStyle(color: AppColors.textPrimary)),
            content: Text(
              '이미 등록된 고객입니다. 덮어쓰시겠습니까?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('취소', style: TextStyle(color: AppColors.textSecondary)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.customerRed),
                child: const Text('덮어쓰기'),
              ),
            ],
          ),
        );
        
        if (shouldOverwrite == true) {
          // 덮어쓰기
          final (overwriteSuccess, _, overwrittenCustomer) = await repo.createOrUpdateCustomer(
            newCustomer,
            forceUpdate: true,
          );
          
          if (!mounted) return;
          
          if (overwriteSuccess && overwrittenCustomer != null) {
            _navigateToDetail(overwrittenCustomer);
          } else {
            _showError('저장에 실패했습니다.');
          }
        }
        setState(() => _isLoading = false);
        return;
      }
      
      if (success && savedCustomer != null) {
        _navigateToDetail(savedCustomer);
      } else {
        _showError('저장에 실패했습니다.');
      }
    } catch (e) {
      debugPrint('고객 등록 오류: $e');
      if (mounted) {
        _showError('오류가 발생했습니다: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  /// 등록 후 목록 화면으로 돌아가기
  void _navigateToDetail(Customer customer) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('등록 완료'),
        backgroundColor: AppColors.statusComplete,
        duration: const Duration(seconds: 2),
      ),
    );
    
    // 등록 화면 닫고 이전 화면(고객사 리스트)으로 돌아가기
    // 리스트 화면에서 자동으로 리로드됨
    Navigator.of(context).pop(true); // true를 반환하여 등록 완료를 알림
  }
  
  /// 에러 표시
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.customerRed,
      ),
    );
  }
  
  InputDecoration _inputDecoration({
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: TextStyle(color: AppColors.textSecondary),
      labelStyle: TextStyle(color: AppColors.textSecondary),
      suffixIcon: suffixIcon,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.inputRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.inputRadius),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.inputRadius),
        borderSide: const BorderSide(color: AppColors.customerRed, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.inputRadius),
        borderSide: const BorderSide(color: AppColors.customerRed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '고객사 등록',
          style: TextStyle(
            fontSize: 18,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(AppDimens.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 섹션 1: 고객사 기본 정보
              _InfoCard(
                title: '고객사 기본 정보',
                children: [
                  TextFormField(
                    controller: _customerNameController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(labelText: '고객명 *'),
                    validator: (value) => value?.trim().isEmpty ?? true ? '고객명을 입력하세요' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _openDateController,
                    readOnly: true,
                    onTap: _selectDate,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(
                      labelText: '개통일자 *',
                      suffixIcon: Icon(Icons.calendar_today, size: 20, color: AppColors.textSecondary),
                    ),
                    validator: (value) => value?.trim().isEmpty ?? true ? '개통일자를 선택하세요' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _personInChargeController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(labelText: '담당자', hintText: '담당자 이름'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedProductType,
                    decoration: _inputDecoration(labelText: '상품유형 *'),
                    dropdownColor: AppColors.card,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    items: _productTypeOptions.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type, style: TextStyle(color: AppColors.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedProductType = value),
                    validator: (value) => value == null ? '상품유형을 선택하세요' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _productNameController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(labelText: '상품명 *'),
                    validator: (value) => value?.trim().isEmpty ?? true ? '상품명을 입력하세요' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _buildingController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(labelText: '건물명'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 섹션 2: 판매자 정보
              _InfoCard(
                title: '판매자 정보',
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedHq,
                    decoration: _inputDecoration(labelText: '본부 *'),
                    dropdownColor: AppColors.card,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    items: _hqOptions.map((hq) {
                      return DropdownMenuItem(
                        value: hq,
                        child: Text(hq, style: TextStyle(color: AppColors.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedHq = value),
                    validator: (value) => value == null ? '본부를 선택하세요' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _branchController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(labelText: '지사'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _sellerController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(
                      labelText: '실판매자(MATE)',
                      hintText: '예: 1108713/조태호',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 섹션 3: 영업현황
              _InfoCard(
                title: '영업현황',
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedSalesStatus,
                    decoration: _inputDecoration(labelText: '영업상태 *'),
                    dropdownColor: AppColors.card,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    items: _salesStatusOptions.map((status) {
                      return DropdownMenuItem(
                        value: status,
                        child: Text(status, style: TextStyle(color: AppColors.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedSalesStatus = value),
                    validator: (value) => value == null ? '영업상태를 선택하세요' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _memoController,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                    decoration: _inputDecoration(labelText: '메모', alignLabelWithHint: true),
                    maxLines: 4,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // 저장 버튼
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: (_isLoading || !_isFormValid) ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.customerRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '저장',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 정보 카드 위젯 (섹션 카드 - 톤앤매너)
class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppDimens.customerCardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
