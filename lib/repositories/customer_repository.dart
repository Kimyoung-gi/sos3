import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/merge_result.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/permission_service.dart';

/// 고객 저장소 (Firestore 기반 — PC/모바일 동기화). 실패 시 로컬 SharedPreferences 폴백/마이그레이션.
class CustomerRepository {
  static const _key = 'sos_customers';
  static const _keyStatus = 'sos_customer_status';
  static const _keyMemo = 'sos_customer_memo';
  static const _keyFavorites = 'favorite_customer_keys';

  static const _collectionCustomers = 'customers';
  static const _collectionUserFavorites = 'user_favorites';

  final AuthService? _authService;

  CustomerRepository({AuthService? authService}) : _authService = authService;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _customersRef =>
      _firestore.collection(_collectionCustomers);

  /// Firestore 문서 ID (customerKey는 | 포함 가능 → base64url 인코딩)
  static String _docId(String customerKey) {
    final encoded = base64UrlEncode(utf8.encode(customerKey));
    return encoded.replaceAll('=', '_');
  }

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  /// Firestore에서 고객 목록 로드 (동기화된 단일 소스 — 로컬 폴백 없음)
  Future<List<Customer>> _loadAll() async {
    final snapshot = await _customersRef.get();
    if (snapshot.docs.isEmpty) {
      return await _migrateFromLocalIfAny();
    }
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Customer.fromJson(Map<String, dynamic>.from(data));
    }).toList();
  }

  /// Firestore가 비어 있을 때 로컬 데이터가 있으면 Firestore로 이전
  Future<List<Customer>> _migrateFromLocalIfAny() async {
    final local = await _loadAllLocal();
    if (local.isEmpty) return [];
    try {
      final chunks = _batchChunk(local, 500);
      for (final chunk in chunks) {
        final writeBatch = _firestore.batch();
        for (final c in chunk) {
          writeBatch.set(_customersRef.doc(_docId(c.customerKey)), _toFirestoreData(c, source: 'csv'));
        }
        await writeBatch.commit();
      }
      final prefs = await _prefs();
      await prefs.remove(_key);
      await prefs.remove(_keyStatus);
      await prefs.remove(_keyMemo);
      final favList = await getFavorites();
      for (final k in favList) {
        await _setFavoriteInFirestore(k, true);
      }
      debugPrint('✅ 로컬 고객 데이터 Firestore 마이그레이션 완료: ${local.length}건');
      return local;
    } catch (e) {
      debugPrint('CustomerRepository 마이그레이션 실패: $e');
      return local;
    }
  }

  List<List<Customer>> _batchChunk(List<Customer> list, int size) {
    final result = <List<Customer>>[];
    for (var i = 0; i < list.length; i += size) {
      result.add(list.sublist(i, (i + size).clamp(0, list.length)));
    }
    return result;
  }

  Map<String, dynamic> _toFirestoreData(Customer c, {String source = 'csv', bool setCreatedAt = false}) {
    final map = c.toJson();
    map['customerKey'] = c.customerKey;
    map['source'] = source;
    if (setCreatedAt) {
      map['createdAt'] = c.createdAt != null
          ? Timestamp.fromDate(c.createdAt!)
          : FieldValue.serverTimestamp();
    }
    return map;
  }

  Future<List<Customer>> _loadAllLocal() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      var customers = list.map((e) => Customer.fromJson((e as Map).cast<String, dynamic>())).toList();
      final statusMap = prefs.getString(_keyStatus);
      final memoMap = prefs.getString(_keyMemo);
      final favList = prefs.getStringList(_keyFavorites);
      final favSet = favList != null ? favList.toSet() : <String>{};
      final Map<String, String> status = statusMap != null && statusMap.isNotEmpty
          ? (jsonDecode(statusMap) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ?? {}
          : {};
      final Map<String, String> memo = memoMap != null && memoMap.isNotEmpty
          ? (jsonDecode(memoMap) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ?? {}
          : {};
      customers = customers.map((c) {
        var next = c;
        final k = c.customerKey;
        if (status[k] != null) next = next.copyWith(salesStatus: status[k]!);
        if (memo[k] != null) next = next.copyWith(memo: memo[k]!);
        if (favSet.contains(k)) next = next.copyWith(isFavorite: true);
        return next;
      }).toList();
      return customers;
    } catch (e) {
      debugPrint('CustomerRepository._loadAllLocal: $e');
      return [];
    }
  }

  /// Firestore에 고객 목록 저장 (전체 교체 — 서버만 사용, 로컬 폴백 없음)
  Future<void> _saveAll(List<Customer> customers) async {
    if (customers.isEmpty) {
      final snapshot = await _customersRef.limit(1).get();
      if (snapshot.docs.isNotEmpty) {
        final docs = (await _customersRef.get()).docs;
        for (var i = 0; i < docs.length; i += 500) {
          final batch = _firestore.batch();
          final end = (i + 500).clamp(0, docs.length);
          for (var j = i; j < end; j++) batch.delete(docs[j].reference);
          await batch.commit();
        }
      }
      return;
    }
    final chunks = _batchChunk(customers, 500);
    for (final chunk in chunks) {
      final batch = _firestore.batch();
      for (final c in chunk) {
        final docId = _docId(c.customerKey);
        batch.set(_customersRef.doc(docId), _toFirestoreData(c, source: 'csv', setCreatedAt: true));
      }
      await batch.commit();
    }
  }

  /// RBAC: 고객사 기능 접근레벨 적용 (일반/스탭=본부, 관리자=전체)
  Future<List<Customer>> getFiltered(User? user) async {
    var all = await _loadAll();
    final userId = _authService?.currentUser?.id;
    if (userId != null) {
      final favKeys = await _getFavoritesFromFirestore(userId);
      all = all.map((c) => favKeys.contains(c.customerKey) ? c.copyWith(isFavorite: true) : c).toList();
    }
    debugPrint('🔍 [RBAC] getFiltered(고객사) - 전체: ${all.length}건, 사용자: ${user?.id ?? "null"}, Role: ${user?.role}');
    final filtered = PermissionService.filterByScope(user, all, feature: AccessFeature.customer);
    debugPrint('🔍 [RBAC] filterByScope(고객사) 결과: ${filtered.length}건');
    return filtered;
  }

  Future<List<Customer>> getAll() => _loadAll();

  Future<void> saveAll(List<Customer> list) => _saveAll(list);

  /// 고객 데이터 완전 삭제 — Firestore에서만 삭제 (500건 단위 배치)
  Future<void> clearCustomers() async {
    final snapshot = await _customersRef.get();
    final docs = snapshot.docs;
    for (var i = 0; i < docs.length; i += 500) {
      final batch = _firestore.batch();
      final end = (i + 500).clamp(0, docs.length);
      for (var j = i; j < end; j++) batch.delete(docs[j].reference);
      await batch.commit();
    }
    debugPrint('🗑️ CustomerRepository: Firestore 고객 데이터 삭제 완료');
  }

  /// CSV 파싱 결과로 완전 교체 (Firestore에 저장, status/memo/favorites 유지)
  Future<MergeResult> replaceFromCsv(List<Customer> parsed) async {
    final existingBefore = await _loadAll();
    final beforeCount = existingBefore.length;
    debugPrint('📊 [REPLACE] 로딩 전 기존 고객 수: $beforeCount건');

    final statusMap = <String, String>{};
    final memoMap = <String, String>{};
    final favSet = await getFavorites();
    for (final c in existingBefore) {
      statusMap[c.customerKey] = c.salesStatus;
      memoMap[c.customerKey] = c.memo;
    }

    await clearCustomers();

    final replaced = parsed.map((c) {
      var next = c;
      final k = c.customerKey;
      if (statusMap[k] != null) next = next.copyWith(salesStatus: statusMap[k]!);
      if (memoMap[k] != null) next = next.copyWith(memo: memoMap[k]!);
      if (favSet.contains(k)) next = next.copyWith(isFavorite: true);
      return next;
    }).toList();

    await _saveAll(replaced);
    debugPrint('✅ [REPLACE] Firestore 고객 수: ${replaced.length}건');

    return MergeResult(
      total: parsed.length,
      success: replaced.length,
      fail: 0,
      skipped: 0,
      updated: 0,
      failReasonsTop3: [],
    );
  }

  /// 영업상태 변경 — Firestore에만 저장 (동기화)
  Future<void> setStatus(String customerKey, String status) async {
    final docId = _docId(customerKey);
    await _customersRef.doc(docId).set({'salesStatus': status}, SetOptions(merge: true));
  }

  /// 메모 변경 — Firestore에만 저장 (동기화)
  Future<void> setMemo(String customerKey, String memo) async {
    final docId = _docId(customerKey);
    await _customersRef.doc(docId).set({'memo': memo}, SetOptions(merge: true));
  }

  Future<void> _setFavoriteInFirestore(String customerKey, bool value) async {
    final userId = _authService?.currentUser?.id;
    if (userId == null) return;
    final ref = _firestore.collection(_collectionUserFavorites).doc(userId);
    final snapshot = await ref.get();
    final Set<String> keys = snapshot.exists && snapshot.data() != null
        ? (snapshot.data()!['keys'] as List<dynamic>?)?.map((e) => e.toString()).toSet() ?? {}
        : {};
    if (value) keys.add(customerKey); else keys.remove(customerKey);
    await ref.set({'keys': keys.toList()});
  }

  Future<Set<String>> _getFavoritesFromFirestore(String userId) async {
    try {
      final snapshot = await _firestore.collection(_collectionUserFavorites).doc(userId).get();
      if (!snapshot.exists || snapshot.data() == null) return {};
      final list = snapshot.data()!['keys'] as List<dynamic>?;
      return list?.map((e) => e.toString()).toSet() ?? {};
    } catch (e) {
      return {};
    }
  }

  /// 즐겨찾기 저장 — Firestore에만 저장 (동기화)
  Future<void> setFavorites(Set<String> keys) async {
    final userId = _authService?.currentUser?.id;
    if (userId == null) return;
    await _firestore.collection(_collectionUserFavorites).doc(userId).set({'keys': keys.toList()});
  }

  /// 즐겨찾기 로드 — Firestore에서만 조회
  Future<Set<String>> getFavorites() async {
    final userId = _authService?.currentUser?.id;
    if (userId == null) return {};
    return _getFavoritesFromFirestore(userId);
  }

  /// 직접 등록 고객 키 집합 — Firestore에서 source=='direct' 조회
  Future<Set<String>> getRegisteredCustomerKeys() async {
    final snapshot = await _customersRef.where('source', isEqualTo: 'direct').get();
    return snapshot.docs
        .map((d) => d.data()['customerKey'] as String? ?? '')
        .where((k) => k.isNotEmpty)
        .toSet();
  }

  Future<void> addRegisteredCustomerKey(String customerKey) async {
    final docId = _docId(customerKey);
    await _customersRef.doc(docId).set({'source': 'direct'}, SetOptions(merge: true));
  }

  static String _dupKey(Customer c) =>
      '${c.customerName}|${c.openDate}|${c.productName}|${c.sellerName}';

  Future<MergeResult> mergeFromCsv(List<Customer> parsed, {required bool updateOnDuplicate}) async {
    final existing = await _loadAll();
    final favList = await getFavorites();

    int success = 0, skipped = 0, updated = 0;
    final failReasons = <String, int>{};
    final merged = <String, Customer>{};
    for (final c in existing) merged[_dupKey(c)] = c;

    for (final c in parsed) {
      final k = _dupKey(c);
      if (merged.containsKey(k)) {
        if (updateOnDuplicate) {
          final prev = merged[k]!;
          merged[k] = c.copyWith(
            salesStatus: prev.salesStatus,
            memo: prev.memo,
            isFavorite: favList.contains(prev.customerKey),
            createdAt: prev.createdAt,
          );
          updated++;
        } else {
          skipped++;
        }
        continue;
      }
      merged[k] = c;
      success++;
    }

    await _saveAll(merged.values.toList());
    return MergeResult(
      total: parsed.length,
      success: success,
      fail: 0,
      skipped: skipped,
      updated: updated,
      failReasonsTop3: failReasons.entries.take(3).map((e) => '${e.key}: ${e.value}').toList(),
    );
  }

  Future<(bool success, bool isDuplicate, Customer? customer)> createOrUpdateCustomer(
    Customer newCustomer, {
    bool forceUpdate = false,
  }) async {
    try {
      final existing = await _loadAll();
      final customerKey = newCustomer.customerKey;
      Customer? existingCustomer;
      try {
        existingCustomer = existing.firstWhere((c) => c.customerKey == customerKey);
      } catch (_) {}

      final isDuplicate = existingCustomer != null;

      if (isDuplicate && !forceUpdate) return (false, true, null);

      final favList = await getFavorites();
      Customer customerToSave;
      if (isDuplicate && forceUpdate) {
        customerToSave = newCustomer.copyWith(
          salesStatus: existingCustomer.salesStatus,
          memo: existingCustomer.memo,
          isFavorite: favList.contains(customerKey) || existingCustomer.isFavorite,
        );
      } else {
        customerToSave = newCustomer;
      }

      final docId = _docId(customerKey);
      await _customersRef.doc(docId).set(
        _toFirestoreData(customerToSave, source: 'direct', setCreatedAt: !isDuplicate),
        isDuplicate ? SetOptions(merge: true) : SetOptions(),
      );

      if (newCustomer.salesStatus.isNotEmpty) await setStatus(customerKey, newCustomer.salesStatus);
      if (newCustomer.memo.isNotEmpty) await setMemo(customerKey, newCustomer.memo);

      debugPrint('✅ 고객 ${isDuplicate ? "업데이트" : "생성"} 완료 (Firestore): $customerKey');
      return (true, isDuplicate, customerToSave);
    } catch (e) {
      debugPrint('❌ 고객 생성/업데이트 실패: $e');
      return (false, false, null);
    }
  }

  Future<Customer?> getCustomerByKey(String customerKey) async {
    final all = await _loadAll();
    try {
      return all.firstWhere((c) => c.customerKey == customerKey);
    } catch (e) {
      return null;
    }
  }
}
