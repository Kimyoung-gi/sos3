import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/upload_history.dart';

/// 업로드 히스토리 저장소
class UploadHistoryRepository {
  static const _key = 'sos_upload_history';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<List<UploadHistory>> getAll({UploadType? type, int? limit}) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null) return [];
      var histories = list
          .map((e) => UploadHistory.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (type != null) {
        histories = histories.where((h) => h.type == type).toList();
      }
      histories.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 최신순
      if (limit != null && limit > 0) {
        histories = histories.take(limit).toList();
      }
      return histories;
    } catch (e) {
      debugPrint('UploadHistoryRepository.getAll: $e');
      return [];
    }
  }

  Future<void> add(UploadHistory history) async {
    final all = await getAll();
    all.insert(0, history); // 최신을 맨 앞에
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }
}
