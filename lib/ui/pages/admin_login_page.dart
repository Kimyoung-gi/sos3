import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 관리자 로그인 페이지.
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _idController = TextEditingController();
  final _pwController = TextEditingController();
  final _idFocus = FocusNode();
  final _pwFocus = FocusNode();

  String? _idError;
  String? _pwError;
  bool _loading = false;

  @override
  void dispose() {
    _idController.dispose();
    _pwController.dispose();
    _idFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = _idController.text.trim();
    final pw = _pwController.text;

    setState(() {
      _idError = null;
      _pwError = null;
      if (id.isEmpty) _idError = '아이디를 입력하세요.';
      if (pw.isEmpty) _pwError = '비밀번호를 입력하세요.';
    });
    if (_idError != null || _pwError != null) return;

    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final result = await auth.adminLogin(id, pw);
    setState(() => _loading = false);

    if (!mounted) return;
    if (result.isSuccess) {
      context.go('/admin');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message), backgroundColor: Colors.red.shade700),
    );
    setState(() {
      _idError = result.message;
      _pwError = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('관리자 로그인', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: AppDimens.pagePadding + 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/sos_logo.png',
                    height: 44,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 20),
                  // 로그인 폼 카드 (사이트 카드 스타일)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _idController,
                          focusNode: _idFocus,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: '아이디',
                            hintText: '관리자 아이디',
                            hintStyle: TextStyle(color: AppColors.textSecondary),
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            errorText: _idError,
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
                            filled: true,
                            fillColor: AppColors.card,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _pwFocus.requestFocus(),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pwController,
                          focusNode: _pwFocus,
                          obscureText: true,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            hintText: '비밀번호',
                            hintStyle: TextStyle(color: AppColors.textSecondary),
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            errorText: _pwError,
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
                            filled: true,
                            fillColor: AppColors.card,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _loading ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.customerRed,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('관리자 로그인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('일반 로그인으로 돌아가기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
