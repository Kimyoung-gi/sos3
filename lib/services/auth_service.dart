import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../repositories/user_repository.dart';

/// 인증 서비스: 로그인/로그아웃, 세션 유지 (SharedPreferences)
class AuthService extends ChangeNotifier {
  AuthService({UserRepository? userRepository}) : _userRepository = userRepository ?? UserRepository();

  final UserRepository _userRepository;

  User? _currentUser;
  bool _initialized = false;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get initialized => _initialized;

  /// 앱 시작 시 세션 복원하지 않음 — 접속은 항상 로그인 페이지를 통해 입력 후 진입
  Future<void> init() async {
    if (_initialized) return;
    // 세션 자동 복원 비활성화: 매번 로그인 화면에서 아이디/비밀번호 입력 후 접속
    _currentUser = null;
    _initialized = true;
    notifyListeners();
  }

  /// 일반 로그인 (id/pw)
  Future<AuthResult> login(String id, String password) async {
    await _userRepository.ensureDefaults();
    final user = await _userRepository.findByCredentials(id, password);
    if (user == null) return AuthResult.fail('아이디 또는 비밀번호를 확인해주세요.');
    if (!user.isActive) return AuthResult.fail('비활성화된 계정입니다.');
    _currentUser = user;
    await _persistSession();
    notifyListeners();
    return AuthResult.success();
  }

  /// 관리자 전용 로그인
  Future<AuthResult> adminLogin(String id, String password) async {
    await _userRepository.ensureDefaults();
    final user = await _userRepository.findAdminByCredentials(id, password);
    if (user == null) return AuthResult.fail('아이디 또는 비밀번호를 확인해주세요.');
    if (!user.isActive) return AuthResult.fail('비활성화된 계정입니다.');
    _currentUser = user;
    await _persistSession();
    notifyListeners();
    return AuthResult.success();
  }

  Future<void> _persistSession() async {
    if (_currentUser == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_session', jsonEncode(_currentUser!.toJson()));
    } catch (e) {
      debugPrint('AuthService._persistSession: $e');
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_session');
    } catch (e) {
      debugPrint('AuthService.logout: $e');
    }
    notifyListeners();
  }
}

enum AuthResultType { success, fail }

class AuthResult {
  final AuthResultType type;
  final String message;

  AuthResult._(this.type, this.message);

  factory AuthResult.success() => AuthResult._(AuthResultType.success, '');
  factory AuthResult.fail(String msg) => AuthResult._(AuthResultType.fail, msg);

  bool get isSuccess => type == AuthResultType.success;
}
