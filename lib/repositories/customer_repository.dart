import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/user.dart';
import '../services/permission_service.dart';

/// 고객 저장소 (로컬 SharedPreferences). 나중에 서버 구현체로 교체 가능.
class CustomerRepository {
  static const _key = 'sos_customers';
  static const _keyStatus = 'sos_customer_status';
  static const _keyMemo = 'sos_customer_memo';
  static const _keyFavorites = 'favorite_customer_keys';

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

  /// RBAC: 로그인 사용자 권한에 따라 조회 범위 적용
  Future<List<Customer>> getFiltered(User? user) async {
    final all = await _loadAll();
    return PermissionService.filterByScope(user, all);
  }

  Future<List<Customer>> getAll() => _loadAll();

  Future<void> saveAll(List<Customer> list) => _saveAll(list);

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
}

class MergeResult {
  final int total;
  final int success;
  final int fail;
  final int skipped;
  final int updated;
  final List<String> failReasonsTop3;

  MergeResult({
    required this.total,
    required this.success,
    required this.fail,
    required this.skipped,
    required this.updated,
    required this.failReasonsTop3,
  });
}
