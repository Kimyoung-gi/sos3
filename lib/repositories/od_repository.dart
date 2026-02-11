import 'package:flutter/foundation.dart' show debugPrint;

import '../models/od_item.dart';
import '../services/csv_service.dart';
import '../utils/csv_parser_extended.dart';

/// OD(오디) 데이터 — Firestore csv_files/OD.CSV 로드 후 파싱
class OdRepository {
  static const String odCsvFilename = 'OD.CSV';

  Future<List<OdItem>> loadAll() async {
    try {
      final csvText = await CsvService.load(odCsvFilename);
      final list = CsvParserExtended.parseOd(csvText);
      debugPrint('OD.CSV 로드: ${list.length}건');
      return list;
    } catch (e) {
      debugPrint('OD.CSV 로드 실패: $e');
      return [];
    }
  }
}
