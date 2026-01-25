import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/merge_result.dart';
import '../models/performance.dart';

/// 실적포인트순위 저장소
class PerformanceRepository {
  static const _key = 'sos_performance';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<List<Performance>> getAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      return list.map((e) => Performance.fromJson((e as Map).cast<String, dynamic>())).toList();
    } catch (e) {
      debugPrint('PerformanceRepository.getAll: $e');
      return [];
    }
  }

  Future<void> _saveAll(List<Performance> list) async {
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  /// CSV 병합: upsert 방식 (employeeId + yyyymm 기준)
  Future<MergeResult> mergeFromCsv(List<Performance> parsed, {required bool updateOnDuplicate}) async {
    final existing = await getAll();
    final existingMap = {for (final p in existing) '${p.employeeId}|${p.yyyymm}': p};

    int success = 0;
    int skipped = 0;
    int updated = 0;
    final failReasons = <String, int>{};

    final merged = <String, Performance>{};
    for (final p in existing) merged['${p.employeeId}|${p.yyyymm}'] = p;

    for (final p in parsed) {
      final key = '${p.employeeId}|${p.yyyymm}';
      if (merged.containsKey(key)) {
        if (updateOnDuplicate) {
          merged[key] = p;
          updated++;
        } else {
          skipped++;
        }
        continue;
      }
      merged[key] = p;
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
  Future<void> replaceAll(List<Performance> list) async {
    await _saveAll(list);
  }
}
