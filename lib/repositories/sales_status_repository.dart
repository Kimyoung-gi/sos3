import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/merge_result.dart';
import '../models/sales_status.dart';

/// 영업현황 저장소
class SalesStatusRepository {
  static const _key = 'sos_sales_status';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<List<SalesStatus>> getAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => SalesStatus.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      debugPrint('SalesStatusRepository.getAll: $e');
      return [];
    }
  }

  Future<void> _saveAll(List<SalesStatus> list) async {
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  /// CSV 병합: upsert 방식 (customerId 기준)
  Future<MergeResult> mergeFromCsv(List<SalesStatus> parsed, {required bool updateOnDuplicate}) async {
    final existing = await getAll();
    final existingMap = {for (final s in existing) s.customerId: s};

    int success = 0;
    int skipped = 0;
    int updated = 0;
    final failReasons = <String, int>{};

    final merged = <String, SalesStatus>{};
    for (final s in existing) merged[s.customerId] = s;

    for (final s in parsed) {
      if (merged.containsKey(s.customerId)) {
        if (updateOnDuplicate) {
          merged[s.customerId] = s;
          updated++;
        } else {
          skipped++;
        }
        continue;
      }
      merged[s.customerId] = s;
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

  /// 전체 덮어쓰기
  Future<void> replaceAll(List<SalesStatus> list) async {
    await _saveAll(list);
  }
}
