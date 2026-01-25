import 'package:flutter/foundation.dart';

import '../models/customer.dart';

/// CSV 파싱 결과 행. error != null 이면 오류 행.
class CsvRow {
  final Customer? customer;
  final String? error;
  final int lineIndex;

  const CsvRow({this.customer, this.error, required this.lineIndex});
}

/// 고객 CSV 파서. 컬럼: customerName, openDate, product, hq, branch, sellerName, salesStatus(optional), building(optional)
class CsvParser {
  static const _defaultStatus = '영업전';
  static const _delimiters = [',', '\t'];

  static String _removeBOM(String s) {
    if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) return s.substring(1);
    return s;
  }

  static bool _isValidDate(String s) {
    if (s.isEmpty) return false;
    final t = s.trim().replaceAll('-', '').replaceAll('/', '');
    if (t.length != 8) return false;
    final y = int.tryParse(t.substring(0, 4));
    final m = int.tryParse(t.substring(4, 6));
    final d = int.tryParse(t.substring(6, 8));
    if (y == null || m == null || d == null) return false;
    if (m < 1 || m > 12 || d < 1 || d > 31) return false;
    return true;
  }

  static String _normalizeDate(String s) {
    final t = s.trim().replaceAll('/', '-');
    if (t.length == 8 && t.contains('-') == false) {
      return '${t.substring(0, 4)}-${t.substring(4, 6)}-${t.substring(6, 8)}';
    }
    return t;
  }

  /// 헤더 매핑: 한글(본부,지사,고객명,개통일자,상품유형,상품명,실판매자,건물명) 또는 영문
  static Map<String, int> _headerIndices(List<String> headers) {
    final h = headers.map((e) => _removeBOM(e.trim().replaceAll('"', '')).toLowerCase()).toList();
    int idx(List<String> aliases) {
      for (final a in aliases) {
        final i = h.indexWhere((x) => x.contains(a));
        if (i >= 0) return i;
      }
      return -1;
    }

    return {
      'hq': idx(['본부']),
      'branch': idx(['지사']),
      'customerName': idx(['고객명']),
      'openDate': idx(['개통일자', '개통일']),
      'productType': idx(['상품유형', '유형']),
      'productName': idx(['상품명']),
      'sellerName': idx(['실판매자', '판매자', 'mate']),
      'building': idx(['건물명', '건물']),
      'salesStatus': idx(['영업상태', 'salesstatus']),
    };
  }

  /// 전체 파싱. 상위 [previewLimit]개만 반환 시 preview=true.
  static List<CsvRow> parse(String csv, {int? previewLimit}) {
    final limit = previewLimit ?? 0;
    final result = <CsvRow>[];
    final lines = csv.split('\n');
    if (lines.isEmpty) return result;

    final first = _removeBOM(lines[0]);
    String delimiter = ',';
    for (final d in _delimiters) {
      if (first.contains(d)) {
        delimiter = d;
        break;
      }
    }

    final rawHeaders = first.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    final hi = _headerIndices(rawHeaders);

    final hqIdx = hi['hq'] ?? -1;
    final branchIdx = hi['branch'] ?? -1;
    final cnIdx = hi['customerName'] ?? -1;
    final odIdx = hi['openDate'] ?? -1;
    final ptIdx = hi['productType'] ?? -1;
    final pnIdx = hi['productName'] ?? -1;
    final snIdx = hi['sellerName'] ?? -1;
    final buildIdx = hi['building'] ?? -1;
    final ssIdx = hi['salesStatus'] ?? -1;

    final requiredOk = hqIdx >= 0 && branchIdx >= 0 && cnIdx >= 0 && odIdx >= 0 && (ptIdx >= 0 || pnIdx >= 0);
    if (!requiredOk) {
      result.add(CsvRow(error: '필수 헤더 누락: 본부, 지사, 고객명, 개통일자, 상품유형/상품명, 판매자', lineIndex: 0));
      return result;
    }

    for (int i = 1; i < lines.length; i++) {
      if (limit > 0 && result.length >= limit) break;
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final vals = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
      if (vals.length < rawHeaders.length) {
        result.add(CsvRow(error: '컬럼 수 부족', lineIndex: i + 1));
        continue;
      }

      String v(int idx) => idx >= 0 && idx < vals.length ? vals[idx] : '';
      final customerName = v(cnIdx);
      final openDateRaw = v(odIdx);
      final productType = v(ptIdx);
      final productName = v(pnIdx);
      final hq = v(hqIdx);
      final branch = v(branchIdx);
      final sellerName = v(snIdx);
      final building = buildIdx >= 0 && buildIdx < vals.length ? v(buildIdx) : '';
      String salesStatus = ssIdx >= 0 ? v(ssIdx).trim() : _defaultStatus;
      if (salesStatus.isEmpty) salesStatus = _defaultStatus;

      final errs = <String>[];
      if (customerName.isEmpty) errs.add('고객명 누락');
      if (openDateRaw.isEmpty) errs.add('개통일자 누락');
      else if (!_isValidDate(openDateRaw)) errs.add('개통일자 형식 오류');
      if (productName.isEmpty && productType.isEmpty) errs.add('상품명/상품유형 누락');

      if (errs.isNotEmpty) {
        result.add(CsvRow(error: errs.join('; '), lineIndex: i + 1));
        continue;
      }

      final openDate = _normalizeDate(openDateRaw);
      final pn = productName.isEmpty ? productType : productName;
      final pt = productType.isEmpty ? productName : productType;

      result.add(CsvRow(
        customer: Customer(
          customerName: customerName,
          openDate: openDate,
          productName: pn,
          productType: pt,
          hq: hq,
          branch: branch,
          sellerName: sellerName,
          building: building,
          salesStatus: salesStatus,
        ),
        lineIndex: i + 1,
      ));
    }
    return result;
  }
}
