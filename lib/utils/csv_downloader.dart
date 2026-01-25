import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

/// CSV 다운로드 유틸리티 (Flutter Web)
class CsvDownloader {
  /// CSV 파일 다운로드 (UTF-8 BOM 포함하여 Excel 호환성 확보)
  static void download(String csvContent, String filename) {
    if (!kIsWeb) {
      debugPrint('CsvDownloader: Web only');
      return;
    }
    try {
      // UTF-8 BOM 추가 (Excel에서 한글 깨짐 방지)
      final withBom = '\uFEFF$csvContent';
      final bytes = utf8.encode(withBom);
      
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      debugPrint('CsvDownloader.download error: $e');
    }
  }

  /// 에러 행만 포함한 CSV 다운로드
  static void downloadErrorCsv(List<Map<String, dynamic>> errorRows, String filename) {
    if (errorRows.isEmpty) return;
    final headers = errorRows.first.keys.toList();
    final csv = StringBuffer();
    csv.writeln(headers.join(','));
    for (final row in errorRows) {
      csv.writeln(headers.map((h) => _escapeCsvValue(row[h]?.toString() ?? '')).join(','));
    }
    download(csv.toString(), filename);
  }

  static String _escapeCsvValue(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
