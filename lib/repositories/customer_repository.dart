import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/merge_result.dart';
import '../models/user.dart';
import '../services/permission_service.dart';

/// 고객 저장소 (로컬 SharedPreferences). 나중에 서버 구현체로 교체 가능.
class CustomerRepository {
  static const _key = 'sos_customers';
  static const _keyStatus = 'sos_customer_status';
  static const _keyMemo = 'sos_customer_memo';
  static const _keyFavorites = 'favorite_customer_keys';
  /// 고객사 등록 화면에서 직접 등록한 고객의 customerKey 목록 (엑셀 다운로드 시 등록구분 표시용)
  static const _keyRegisteredKeys = 'sos_customer_registered_keys';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<List<Customer>> _loadAll() async {
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
          ? (jsonDecode(statusMap) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
          : {};
      final Map<String, String> memo = memoMap != null && memoMap.isNotEmpty
          ? (jsonDecode(memoMap) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
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
      debugPrint('CustomerRepository._loadAll: $e');
      return [];
    }
  }

  Future<void> _saveAll(List<Customer> customers) async {
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(customers.map((e) => e.toJson()).toList()));
  }

  /// RBAC: 고객사 기능 접근레벨 적용 (일반/스탭=본부, 관리자=전체)
  Future<List<Customer>> getFiltered(User? user) async {
    final all = await _loadAll();
    debugPrint('🔍 [RBAC] getFiltered(고객사) - 전체: ${all.length}건, 사용자: ${user?.id ?? "null"}, Role: ${user?.role}');
    final filtered = PermissionService.filterByScope(user, all, feature: AccessFeature.customer);
    debugPrint('🔍 [RBAC] filterByScope(고객사) 결과: ${filtered.length}건');
    return filtered;
  }

  Future<List<Customer>> getAll() => _loadAll();

  Future<void> saveAll(List<Customer> list) => _saveAll(list);

  /// 고객 데이터 완전 삭제 (CSV 교체 시 사용)
  Future<void> clearCustomers() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
    debugPrint('🗑️ CustomerRepository: 모든 고객 데이터 삭제 완료');
  }

  /// CSV 파싱 결과로 완전 교체 (기존 데이터 삭제 후 새 데이터 저장)
  /// status, memo, favorites는 유지 (기존 키와 매칭되는 경우)
  Future<MergeResult> replaceFromCsv(List<Customer> parsed) async {
    // 로딩 전 기존 count
    final existingBefore = await _loadAll();
    final beforeCount = existingBefore.length;
    debugPrint('📊 [REPLACE] 로딩 전 기존 고객 수: $beforeCount건');

    // 기존 status, memo, favorites 백업
    final statusRaw = await _prefs().then((p) => p.getString(_keyStatus));
    final memoRaw = await _prefs().then((p) => p.getString(_keyMemo));
    final favList = await getFavorites();
    final statusMap = statusRaw != null && statusRaw.isNotEmpty
        ? (jsonDecode(statusRaw) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
        : <String, String>{};
    final memoMap = memoRaw != null && memoRaw.isNotEmpty
        ? (jsonDecode(memoRaw) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
        : <String, String>{};

    // 기존 데이터 완전 삭제
    await clearCustomers();
    debugPrint('🗑️ [REPLACE] clear 후 고객 수: 0건');

    // 새 데이터에 기존 status, memo, favorites 적용
    final replaced = parsed.map((c) {
      var next = c;
      final k = c.customerKey;
      if (statusMap[k] != null) next = next.copyWith(salesStatus: statusMap[k]!);
      if (memoMap[k] != null) next = next.copyWith(memo: memoMap[k]!);
      if (favList.contains(k)) next = next.copyWith(isFavorite: true);
      return next;
    }).toList();

    // 새 데이터 저장
    await _saveAll(replaced);
    
    final afterCount = replaced.length;
    debugPrint('✅ [REPLACE] 로딩 후 고객 수: $afterCount건 (기존: $beforeCount건 → 새: $afterCount건)');

    return MergeResult(
      total: parsed.length,
      success: replaced.length,
      fail: 0,
      skipped: 0,
      updated: 0,
      failReasonsTop3: [],
    );
  }

  Future<void> setStatus(String customerKey, String status) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_keyStatus);
    final m = raw != null && raw.isNotEmpty ? (jsonDecode(raw) as Map<String, dynamic>?) ?? {} : <String, dynamic>{};
    m[customerKey] = status;
    await prefs.setString(_keyStatus, jsonEncode(m));
  }

  Future<void> setMemo(String customerKey, String memo) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_keyMemo);
    final m = raw != null && raw.isNotEmpty ? (jsonDecode(raw) as Map<String, dynamic>?) ?? {} : <String, dynamic>{};
    m[customerKey] = memo;
    await prefs.setString(_keyMemo, jsonEncode(m));
  }

  Future<void> setFavorites(Set<String> keys) async {
    final prefs = await _prefs();
    await prefs.setStringList(_keyFavorites, keys.toList());
  }

  Future<Set<String>> getFavorites() async {
    final prefs = await _prefs();
    final list = prefs.getStringList(_keyFavorites);
    return list != null ? list.toSet() : {};
  }

  /// 직접 고객사 등록으로 추가/수정된 고객의 customerKey 집합 (엑셀 다운로드 등록구분용)
  Future<Set<String>> getRegisteredCustomerKeys() async {
    final prefs = await _prefs();
    final list = prefs.getStringList(_keyRegisteredKeys);
    return list != null ? list.toSet() : {};
  }

  /// 고객사 등록 화면에서 저장 시 해당 키를 직접등록 집합에 추가
  Future<void> addRegisteredCustomerKey(String customerKey) async {
    final prefs = await _prefs();
    final set = await getRegisteredCustomerKeys();
    if (set.contains(customerKey)) return;
    set.add(customerKey);
    await prefs.setStringList(_keyRegisteredKeys, set.toList());
  }

  /// 중복 키: customerName|openDate|productName|sellerName
  static String _dupKey(Customer c) =>
      '${c.customerName}|${c.openDate}|${c.productName}|${c.sellerName}';

  /// CSV 파싱 결과 병합. updateOnDuplicate: true=업데이트, false=스킵.
  Future<MergeResult> mergeFromCsv(List<Customer> parsed, {required bool updateOnDuplicate}) async {
    final existing = await _loadAll();
    final existingMap = {for (final c in existing) _dupKey(c): c};
    final statusRaw = await _prefs().then((p) => p.getString(_keyStatus));
    final memoRaw = await _prefs().then((p) => p.getString(_keyMemo));
    final favList = await getFavorites();
    final statusMap = statusRaw != null && statusRaw.isNotEmpty
        ? (jsonDecode(statusRaw) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
        : <String, String>{};
    final memoMap = memoRaw != null && memoRaw.isNotEmpty
        ? (jsonDecode(memoRaw) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
        : <String, String>{};

    int success = 0;
    int skipped = 0;
    int updated = 0;
    final failReasons = <String, int>{};

    final merged = <String, Customer>{};
    for (final c in existing) merged[_dupKey(c)] = c;

    for (final c in parsed) {
      final k = _dupKey(c);
      if (merged.containsKey(k)) {
        if (updateOnDuplicate) {
          final prev = merged[k]!;
          merged[k] = c.copyWith(
            salesStatus: statusMap[prev.customerKey] ?? prev.salesStatus,
            memo: memoMap[prev.customerKey] ?? prev.memo,
            isFavorite: favList.contains(prev.customerKey),
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

    final list = merged.values.toList();
    await _saveAll(list);

    return MergeResult(
      total: parsed.length,
      success: success,
      fail: 0,
      skipped: skipped,
      updated: updated,
      failReasonsTop3: failReasons.entries.take(3).map((e) => '${e.key}: ${e.value}').toList(),
    );
  }

  /// 단일 고객 생성 또는 업데이트
  /// customerKey 기반으로 중복 체크
  /// forceUpdate: true면 중복 시 덮어쓰기, false면 중복 체크만 반환
  /// 반환값: (성공 여부, 중복 여부, 생성된/업데이트된 Customer)
  Future<(bool success, bool isDuplicate, Customer? customer)> createOrUpdateCustomer(
    Customer newCustomer, {
    bool forceUpdate = false,
  }) async {
    try {
      final existing = await _loadAll();
      final customerKey = newCustomer.customerKey;
      
      // 중복 체크 (customerKey 기반)
      final existingCustomer = existing.firstWhere(
        (c) => c.customerKey == customerKey,
        orElse: () => Customer(
          customerName: '',
          openDate: '',
          productName: '',
          productType: '',
          hq: '',
          branch: '',
          sellerName: '',
          building: '',
          personInCharge: '',
        ),
      );
      
      final isDuplicate = existingCustomer.customerName.isNotEmpty;
      
      if (isDuplicate && !forceUpdate) {
        // 중복이지만 덮어쓰기 안 함
        return (false, true, null);
      }
      
      // 기존 status, memo, favorites 백업
      final statusRaw = await _prefs().then((p) => p.getString(_keyStatus));
      final memoRaw = await _prefs().then((p) => p.getString(_keyMemo));
      final favList = await getFavorites();
      final statusMap = statusRaw != null && statusRaw.isNotEmpty
          ? (jsonDecode(statusRaw) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
          : <String, String>{};
      final memoMap = memoRaw != null && memoRaw.isNotEmpty
          ? (jsonDecode(memoRaw) as Map<String, dynamic>?)?.map((k, v) => MapEntry(k as String, v?.toString() ?? '')) ?? {}
          : <String, String>{};
      
      Customer customerToSave;
      if (isDuplicate && forceUpdate) {
        // 기존 데이터의 status, memo, favorite 유지하면서 업데이트
        customerToSave = newCustomer.copyWith(
          salesStatus: statusMap[customerKey] ?? existingCustomer.salesStatus,
          memo: memoMap[customerKey] ?? existingCustomer.memo,
          isFavorite: favList.contains(customerKey) || existingCustomer.isFavorite,
        );
      } else {
        // 신규 생성 (등록 시 입력한 초기값 사용)
        customerToSave = newCustomer;
      }
      
      // 기존 리스트에서 중복 제거 후 새 고객 추가/업데이트
      final updatedList = existing.where((c) => c.customerKey != customerKey).toList();
      updatedList.add(customerToSave);
      
      await _saveAll(updatedList);

      // 직접 고객사 등록으로 등록된 키 기록 (엑셀 다운로드 시 등록구분 표시용)
      await addRegisteredCustomerKey(customerKey);
      
      // status와 memo도 함께 저장 (등록 시 입력한 값 저장)
      if (newCustomer.salesStatus.isNotEmpty) {
        await setStatus(customerKey, newCustomer.salesStatus);
      }
      if (newCustomer.memo.isNotEmpty) {
        await setMemo(customerKey, newCustomer.memo);
      }
      
      debugPrint('✅ 고객 ${isDuplicate ? "업데이트" : "생성"} 완료: $customerKey');
      return (true, isDuplicate, customerToSave);
    } catch (e) {
      debugPrint('❌ 고객 생성/업데이트 실패: $e');
      return (false, false, null);
    }
  }

  /// customerKey로 고객 조회
  Future<Customer?> getCustomerByKey(String customerKey) async {
    final all = await _loadAll();
    try {
      return all.firstWhere((c) => c.customerKey == customerKey);
    } catch (e) {
      return null;
    }
  }
}
