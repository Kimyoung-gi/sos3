import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// CSV 로딩 서비스 (Firestore 우선, assets fallback)
class CsvService {
  static final CsvService _instance = CsvService._internal();
  factory CsvService() => _instance;
  CsvService._internal();

  final Map<String, String> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 5);

  /// 파일명을 assets 경로로 변환
  String _getAssetsPath(String filename) {
    // Firebase Storage 파일명 -> assets 파일명 매핑
    final Map<String, String> filenameMap = {
      'customerlist.csv': '고객사list.csv',
      'kpi-info.csv': 'kpi_info.csv',
      'kpi_it.csv': 'kpi_it.csv',
      'kpi_itr.csv': 'kpi_itr.csv',
      'kpi_mobile.csv': 'kpi_mobile.csv',
      'kpi_etc.csv': 'kpi_etc.csv',
      'OD.CSV': 'OD.CSV',
    };
    
    final assetsFilename = filenameMap[filename] ?? filename;
    return 'assets/$assetsFilename';
  }

  /// CSV 파일 로드 (Firestore 우선, assets fallback)
  /// 
  /// [filename]: CSV 파일명 (예: 'customerlist.csv', 'kpi-info.csv')
  /// 
  /// 반환: CSV 텍스트 내용
  static Future<String> load(String filename) async {
    return _instance._loadInternal(filename);
  }

  Future<String> _loadInternal(String filename) async {
    final cacheKey = filename;
    
    // 캐시 확인 (만료되지 않은 경우)
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && 
          DateTime.now().difference(timestamp) < _cacheExpiry) {
        debugPrint('📦 CSV 캐시 히트: $filename');
        return _cache[cacheKey]!;
      }
    }

    String? csvText;
    
    // 1) Firestore에서 로드 시도 (1순위) - CORS 문제 없음
    try {
      debugPrint('🔥 Firestore에서 CSV 로드 시도: csv_files/$filename');
      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('csv_files').doc(filename).get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        csvText = data['content'] as String?;
        if (csvText == null || csvText.isEmpty) {
          final storagePath = data['storagePath'] as String?;
          if (storagePath != null && storagePath.isNotEmpty) {
            debugPrint('📥 Storage에서 CSV 로드: $storagePath');
            final ref = FirebaseStorage.instance.ref(storagePath);
            final bytes = await ref.getData();
            if (bytes != null && bytes.isNotEmpty) {
              csvText = utf8.decode(bytes);
              if (csvText.trim().isEmpty) csvText = null;
              if (csvText != null) debugPrint('✅ Storage에서 로드 성공: $filename (${csvText.length} chars)');
            }
          }
        }
        if (csvText != null && csvText.isNotEmpty) {
          if (data['content'] != null) debugPrint('✅ Firestore에서 로드 성공: $filename (${csvText.length} bytes)');
        } else if (csvText == null || csvText.isEmpty) {
          debugPrint('⚠️ Firestore: content/storagePath 없거나 비어있음');
        }
      } else {
        debugPrint('⚠️ Firestore: 문서가 존재하지 않음 (csv_files/$filename)');
      }
    } catch (e) {
      debugPrint('⚠️ Firestore 로드 실패 (fallback으로 전환): $e');
    }

    // 2) Firestore 실패 시 assets에서 fallback
    if (csvText == null || csvText.isEmpty) {
      try {
        final assetsPath = _getAssetsPath(filename);
        debugPrint('📦 Assets에서 로드 시도: $assetsPath');
        csvText = await rootBundle.loadString(assetsPath);
        debugPrint('✅ Assets에서 로드 성공: $filename');
      } catch (e) {
        debugPrint('❌ Assets 로드도 실패: $e');
        throw Exception('CSV 파일을 로드할 수 없습니다: $filename');
      }
    }

    // 캐시에 저장
    _cache[cacheKey] = csvText;
    _cacheTimestamps[cacheKey] = DateTime.now();

    return csvText;
  }

  /// 특정 CSV 캐시 무효화
  /// 
  /// [filename]: 캐시를 무효화할 CSV 파일명
  static void invalidate(String filename) {
    _instance._invalidateInternal(filename);
  }

  void _invalidateInternal(String filename) {
    final cacheKey = filename;
    _cache.remove(cacheKey);
    _cacheTimestamps.remove(cacheKey);
    debugPrint('🗑️ CSV 캐시 무효화: $filename');
  }

  /// 모든 캐시 무효화
  static void clearAll() {
    _instance._cache.clear();
    _instance._cacheTimestamps.clear();
    debugPrint('🗑️ 모든 CSV 캐시 무효화');
  }

  /// 여러 CSV를 병렬로 로드
  /// 
  /// [filenames]: 로드할 CSV 파일명 리스트
  /// 
  /// 반환: 파일명을 키로 하는 Map
  static Future<Map<String, String>> loadMultiple(List<String> filenames) async {
    final futures = filenames.map((filename) async {
      try {
        final text = await load(filename);
        return MapEntry(filename, text);
      } catch (e) {
        debugPrint('❌ $filename 로드 실패: $e');
        return MapEntry<String, String>(filename, ''); // 빈 문자열 반환
      }
    });
    
    final results = await Future.wait(futures);
    return Map.fromEntries(results);
  }
}
