import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';

/// 사용자 저장소 (Firestore 기반 - 모든 기기에서 동기화)
class UserRepository {
  static const _collection = 'users';
  
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _usersRef => 
      _firestore.collection(_collection);

  /// Firestore 문서 ID 생성 (id_role 형태)
  String _docId(String userId, bool isAdmin) => 
      '${userId}_${isAdmin ? 'admin' : 'user'}';

  /// Firestore에서 모든 사용자 로드
  Future<List<User>> _load() async {
    try {
      final snapshot = await _usersRef.get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return User.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('UserRepository._load: $e');
      return [];
    }
  }

  /// 기본 계정 생성: USER 1111/1111 SELF, ADMIN 1111/1111
  Future<void> ensureDefaults() async {
    try {
      // 기본 사용자 존재 여부 확인
      final userDoc = await _usersRef.doc('1111_user').get();
      final adminDoc = await _usersRef.doc('1111_admin').get();
      
      if (!userDoc.exists) {
        await _usersRef.doc('1111_user').set({
          'id': '1111',
          'name': '일반사용자',
          'hq': '',
          'branch': '',
          'role': 'user',
          'scope': 'self',
          'isActive': true,
          'sellerName': null,
          'password': '1111',
        });
        debugPrint('✅ 기본 사용자(1111_user) 생성 완료');
      }
      
      if (!adminDoc.exists) {
        await _usersRef.doc('1111_admin').set({
          'id': '1111',
          'name': '관리자',
          'hq': '',
          'branch': '',
          'role': 'admin',
          'scope': 'all',
          'isActive': true,
          'sellerName': null,
          'password': '1111',
        });
        debugPrint('✅ 기본 관리자(1111_admin) 생성 완료');
      }
    } catch (e) {
      debugPrint('⚠️ ensureDefaults 오류: $e');
    }
  }

  /// id/pw로 사용자 조회. 일반 로그인용 (USER 우선)
  Future<User?> findByCredentials(String id, String password) async {
    try {
      // 일반 사용자 먼저 확인
      final userDoc = await _usersRef.doc('${id}_user').get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        if (data['password'] == password && data['isActive'] == true) {
          return User.fromJson(data);
        }
      }
      
      // 관리자 확인
      final adminDoc = await _usersRef.doc('${id}_admin').get();
      if (adminDoc.exists) {
        final data = adminDoc.data()!;
        if (data['password'] == password && data['isActive'] == true) {
          return User.fromJson(data);
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('findByCredentials 오류: $e');
      return null;
    }
  }

  /// 관리자 로그인: id/pw 일치하는 ADMIN만
  Future<User?> findAdminByCredentials(String id, String password) async {
    try {
      final adminDoc = await _usersRef.doc('${id}_admin').get();
      if (!adminDoc.exists) return null;
      
      final data = adminDoc.data()!;
      if (data['password'] != password) return null;
      if (data['isActive'] != true) return null;
      
      return User.fromJson(data);
    } catch (e) {
      debugPrint('findAdminByCredentials 오류: $e');
      return null;
    }
  }

  Future<User?> getById(String id) async {
    try {
      // 일반 사용자 먼저
      final userDoc = await _usersRef.doc('${id}_user').get();
      if (userDoc.exists) return User.fromJson(userDoc.data()!);
      
      // 관리자
      final adminDoc = await _usersRef.doc('${id}_admin').get();
      if (adminDoc.exists) return User.fromJson(adminDoc.data()!);
      
      return null;
    } catch (e) {
      debugPrint('getById 오류: $e');
      return null;
    }
  }

  Future<List<User>> list() async => _load();

  Future<void> create(User user, String password) async {
    final docId = _docId(user.id, user.isAdmin);
    
    // 중복 체크
    final existing = await _usersRef.doc(docId).get();
    if (existing.exists) {
      throw Exception('이미 존재하는 아이디/역할입니다.');
    }
    
    // Firestore에 저장
    await _usersRef.doc(docId).set({
      ...user.toJson(),
      'password': password,
    });
    debugPrint('✅ 사용자 생성 완료: $docId');
  }

  Future<void> update(User user, {String? newPassword}) async {
    final docId = _docId(user.id, user.isAdmin);
    
    // 존재 여부 확인
    final existing = await _usersRef.doc(docId).get();
    if (!existing.exists) {
      throw Exception('사용자를 찾을 수 없습니다.');
    }
    
    // 업데이트
    final updateData = user.toJson();
    if (newPassword != null) {
      updateData['password'] = newPassword;
    } else {
      // 기존 비밀번호 유지
      updateData['password'] = existing.data()!['password'];
    }
    
    await _usersRef.doc(docId).set(updateData);
    debugPrint('✅ 사용자 수정 완료: $docId');
  }

  Future<void> delete(User user) async {
    final docId = _docId(user.id, user.isAdmin);
    
    // 존재 여부 확인
    final existing = await _usersRef.doc(docId).get();
    if (!existing.exists) {
      throw Exception('사용자를 찾을 수 없습니다.');
    }
    
    await _usersRef.doc(docId).delete();
    debugPrint('✅ 사용자 삭제 완료: $docId');
  }
}
