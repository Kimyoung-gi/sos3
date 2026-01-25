import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// 사용자 저장소 (로컬 SharedPreferences). 나중에 서버 구현체로 교체 가능.
class UserRepository {
  static const _key = 'sos_users';
  static const _keyPasswords = 'sos_user_passwords'; // id -> pw (평문, 개발용)

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<List<User>> _load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => User.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      debugPrint('UserRepository._load: $e');
      return [];
    }
  }

  Future<Map<String, String>> _loadPasswords() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_keyPasswords);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>?;
      if (map == null) return {};
      return map.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    } catch (e) {
      debugPrint('UserRepository._loadPasswords: $e');
      return {};
    }
  }

  Future<void> _save(List<User> users, Map<String, String> passwords) async {
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(users.map((e) => e.toJson()).toList()));
    await prefs.setString(_keyPasswords, jsonEncode(passwords));
  }

  /// 기본 계정 생성: USER 1111/1111 SELF, ADMIN 1111/1111
  Future<void> ensureDefaults() async {
    final users = await _load();
    final passwords = await _loadPasswords();
    final hasUser = users.any((u) => u.id == '1111');
    if (hasUser) return;

    final defaultUser = User(
      id: '1111',
      name: '일반사용자',
      hq: '',
      branch: '',
      role: UserRole.user,
      scope: UserScope.self,
      isActive: true,
    );
    final defaultAdmin = User(
      id: '1111',
      name: '관리자',
      hq: '',
      branch: '',
      role: UserRole.admin,
      scope: UserScope.all,
      isActive: true,
    );
    users.addAll([defaultUser, defaultAdmin]);
    passwords['1111_user'] = '1111';
    passwords['1111_admin'] = '1111';
    await _save(users, passwords);
  }

  /// id/pw로 사용자 조회. 일반 로그인용 (USER 우선)
  Future<User?> findByCredentials(String id, String password) async {
    final users = await _load();
    final passwords = await _loadPasswords();
    final nonAdmin = users.where((e) => e.id == id && !e.isAdmin).toList();
    final key = '${id}_user';
    if (passwords[key] == password && nonAdmin.isNotEmpty) return nonAdmin.first;
    final admin = users.where((e) => e.id == id && e.isAdmin).firstOrNull;
    if (admin != null && passwords['${id}_admin'] == password) return admin;
    return null;
  }

  /// 관리자 로그인: id/pw 일치하는 ADMIN만
  Future<User?> findAdminByCredentials(String id, String password) async {
    final users = await _load();
    final passwords = await _loadPasswords();
    final admin = users.where((e) => e.id == id && e.isAdmin).firstOrNull;
    if (admin == null) return null;
    if (passwords['${id}_admin'] != password) return null;
    return admin;
  }

  Future<User?> getById(String id) async {
    final users = await _load();
    return users.where((e) => e.id == id).firstOrNull;
  }

  Future<List<User>> list() async => _load();

  Future<void> create(User user, String password) async {
    final users = await _load();
    final passwords = await _loadPasswords();
    if (users.any((e) => e.id == user.id && e.isAdmin == user.isAdmin)) {
      throw Exception('이미 존재하는 아이디/역할입니다.');
    }
    users.add(user);
    final key = user.isAdmin ? '${user.id}_admin' : '${user.id}_user';
    passwords[key] = password;
    await _save(users, passwords);
  }

  Future<void> update(User user, {String? newPassword}) async {
    final users = await _load();
    final passwords = await _loadPasswords();
    final i = users.indexWhere((e) => e.id == user.id && e.isAdmin == user.isAdmin);
    if (i < 0) throw Exception('사용자를 찾을 수 없습니다.');
    users[i] = user;
    if (newPassword != null) {
      final key = user.isAdmin ? '${user.id}_admin' : '${user.id}_user';
      passwords[key] = newPassword;
    }
    await _save(users, passwords);
  }
}
