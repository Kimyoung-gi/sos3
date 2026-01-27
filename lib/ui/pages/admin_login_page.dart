import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

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
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('관리자 로그인'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/sos_logo.png',
                    height: 64,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _idController,
                    focusNode: _idFocus,
                    decoration: InputDecoration(
                      labelText: '아이디',
                      hintText: '관리자 아이디',
                      errorText: _idError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _pwFocus.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pwController,
                    focusNode: _pwFocus,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: '비밀번호',
                      hintText: '비밀번호',
                      errorText: _pwError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: const Color(0xFFFF6F61),
                      ),
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('관리자 로그인'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/login'),
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
