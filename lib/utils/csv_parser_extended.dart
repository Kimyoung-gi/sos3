import '../models/customer.dart';
import '../models/sales_status.dart';
import '../models/performance.dart';
import '../models/upload_history.dart';
import '../models/od_item.dart';

/// CSV 파싱 결과 행 (확장)
class CsvRowExtended<T> {
  final T? data;
  final String? error;
  final int lineIndex;
  final Map<String, dynamic> rawRow; // 원본 행 데이터

  const CsvRowExtended({
    this.data,
    this.error,
    required this.lineIndex,
    this.rawRow = const {},
  });
}

/// 타입별 CSV 파서
class CsvParserExtended {
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
    if (t.length == 8 && !t.contains('-')) {
      return '${t.substring(0, 4)}-${t.substring(4, 6)}-${t.substring(6, 8)}';
    }
    return t;
  }

  /// 고객기본정보 CSV 파싱
  static List<CsvRowExtended<Customer>> parseCustomerBase(String csv) {
    final result = <CsvRowExtended<Customer>>[];
    final lines = csv.split('\n');
    if (lines.isEmpty) return result;

    final first = _removeBOM(lines[0]);
    String delimiter = ',';
    for (final d in [',', '\t']) {
      if (first.contains(d)) {
        delimiter = d;
        break;
      }
    }

    final rawHeaders = first.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    final h = rawHeaders.map((e) => e.toLowerCase()).toList();
    
    int idx(List<String> aliases) {
      for (final a in aliases) {
        final i = h.indexWhere((x) => x.contains(a));
        if (i >= 0) return i;
      }
      return -1;
    }

    final cnIdx = idx(['고객명', 'customername']);
    final odIdx = idx(['개통일자', '개통일', 'opendate']);
    final ptIdx = idx(['상품유형', '유형', 'producttype']);
    final pnIdx = idx(['상품명', 'productname']);
    final hqIdx = idx(['본부', 'hq']);
    final branchIdx = idx(['지사', 'branch']);
    final snIdx = idx(['실판매자', '판매자', 'sellername', 'mate']);
    final buildIdx = idx(['건물명', '건물', 'building']);
    final ssIdx = idx(['영업상태', 'salesstatus']);
    final picIdx = idx(['담당자', 'personincharge']);

    if (cnIdx < 0 || odIdx < 0 || (ptIdx < 0 && pnIdx < 0)) {
      result.add(CsvRowExtended<Customer>(
        error: '필수 헤더 누락: 고객명, 개통일자, 상품명/상품유형',
        lineIndex: 0,
      ));
      return result;
    }

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final vals = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
      if (vals.length < rawHeaders.length) {
        result.add(CsvRowExtended<Customer>(
          error: '컬럼 수 부족',
          lineIndex: i + 1,
          rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
        ));
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
      final building = v(buildIdx);
      final personInCharge = v(picIdx);
      String salesStatus = v(ssIdx).trim();
      if (salesStatus.isEmpty) salesStatus = '영업전';

      final errs = <String>[];
      if (customerName.isEmpty) errs.add('고객명 누락');
      if (openDateRaw.isEmpty) errs.add('개통일자 누락');
      else if (!_isValidDate(openDateRaw)) errs.add('개통일자 형식 오류');
      if (productName.isEmpty && productType.isEmpty) errs.add('상품명/상품유형 누락');

      if (errs.isNotEmpty) {
        result.add(CsvRowExtended<Customer>(
          error: errs.join('; '),
          lineIndex: i + 1,
          rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
        ));
        continue;
      }

      final openDate = _normalizeDate(openDateRaw);
      final pn = productName.isEmpty ? productType : productName;
      final pt = productType.isEmpty ? productName : productType;

      result.add(CsvRowExtended<Customer>(
        data: Customer(
          customerName: customerName,
          openDate: openDate,
          productName: pn,
          productType: pt,
          hq: hq,
          branch: branch,
          sellerName: sellerName,
          building: building,
          salesStatus: salesStatus,
          personInCharge: personInCharge,
        ),
        lineIndex: i + 1,
        rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
      ));
    }
    return result;
  }

  /// 영업현황 CSV 파싱
  static List<CsvRowExtended<SalesStatus>> parseSalesStatus(String csv) {
    final result = <CsvRowExtended<SalesStatus>>[];
    final lines = csv.split('\n');
    if (lines.isEmpty) return result;

    final first = _removeBOM(lines[0]);
    String delimiter = ',';
    for (final d in [',', '\t']) {
      if (first.contains(d)) {
        delimiter = d;
        break;
      }
    }

    final rawHeaders = first.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    final h = rawHeaders.map((e) => e.toLowerCase()).toList();
    
    int idx(List<String> aliases) {
      for (final a in aliases) {
        final i = h.indexWhere((x) => x.contains(a));
        if (i >= 0) return i;
      }
      return -1;
    }

    final cidIdx = idx(['customer_id', '고객id', 'customerid']);
    final ssIdx = idx(['sales_status', '영업상태', 'salesstatus']);
    final memoIdx = idx(['memo', '메모']);
    final uaIdx = idx(['updated_at', 'updatedat', '업데이트일']);

    if (cidIdx < 0 || ssIdx < 0) {
      result.add(CsvRowExtended<SalesStatus>(
        error: '필수 헤더 누락: customer_id, sales_status',
        lineIndex: 0,
      ));
      return result;
    }

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final vals = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
      if (vals.length < rawHeaders.length) {
        result.add(CsvRowExtended<SalesStatus>(
          error: '컬럼 수 부족',
          lineIndex: i + 1,
          rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
        ));
        continue;
      }

      String v(int idx) => idx >= 0 && idx < vals.length ? vals[idx] : '';
      final customerId = v(cidIdx);
      final salesStatus = v(ssIdx).trim();
      final memo = v(memoIdx);
      final updatedAt = uaIdx >= 0 ? v(uaIdx).trim() : null;

      final errs = <String>[];
      if (customerId.isEmpty) errs.add('customer_id 누락');
      if (salesStatus.isEmpty) errs.add('sales_status 누락');
      else if (!['영업전', '영업중', '개통완료', '실패'].contains(salesStatus)) {
        errs.add('sales_status 값 오류 (영업전|영업중|개통완료|실패)');
      }

      if (errs.isNotEmpty) {
        result.add(CsvRowExtended<SalesStatus>(
          error: errs.join('; '),
          lineIndex: i + 1,
          rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
        ));
        continue;
      }

      result.add(CsvRowExtended<SalesStatus>(
        data: SalesStatus(
          customerId: customerId,
          salesStatus: salesStatus,
          memo: memo,
          updatedAt: updatedAt?.isNotEmpty == true ? updatedAt : null,
        ),
        lineIndex: i + 1,
        rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
      ));
    }
    return result;
  }

  /// 실적포인트순위 CSV 파싱
  static List<CsvRowExtended<Performance>> parsePerformance(String csv) {
    final result = <CsvRowExtended<Performance>>[];
    final lines = csv.split('\n');
    if (lines.isEmpty) return result;

    final first = _removeBOM(lines[0]);
    String delimiter = ',';
    for (final d in [',', '\t']) {
      if (first.contains(d)) {
        delimiter = d;
        break;
      }
    }

    final rawHeaders = first.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
    final h = rawHeaders.map((e) => e.toLowerCase()).toList();
    
    int idx(List<String> aliases) {
      for (final a in aliases) {
        final i = h.indexWhere((x) => x.contains(a));
        if (i >= 0) return i;
      }
      return -1;
    }

    final eidIdx = idx(['employee_id', 'employeeid', '직원id']);
    final enIdx = idx(['employee_name', 'employeename', '직원명', '이름']);
    final ymIdx = idx(['yyyymm', '연월', 'yearmonth']);
    final pointIdx = idx(['point', '포인트', '점수']);
    final rankIdx = idx(['rank', '순위']);

    if (eidIdx < 0 || enIdx < 0 || ymIdx < 0) {
      result.add(CsvRowExtended<Performance>(
        error: '필수 헤더 누락: employee_id, employee_name, yyyymm',
        lineIndex: 0,
      ));
      return result;
    }

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final vals = line.split(delimiter).map((e) => _removeBOM(e.trim().replaceAll('"', ''))).toList();
      if (vals.length < rawHeaders.length) {
        result.add(CsvRowExtended<Performance>(
          error: '컬럼 수 부족',
          lineIndex: i + 1,
          rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
        ));
        continue;
      }

      String v(int idx) => idx >= 0 && idx < vals.length ? vals[idx] : '';
      final employeeId = v(eidIdx);
      final employeeName = v(enIdx);
      final yyyymm = v(ymIdx).trim();
      final pointStr = v(pointIdx).trim();
      final rankStr = v(rankIdx).trim();

      final errs = <String>[];
      if (employeeId.isEmpty) errs.add('employee_id 누락');
      if (employeeName.isEmpty) errs.add('employee_name 누락');
      if (yyyymm.isEmpty) errs.add('yyyymm 누락');
      else if (yyyymm.length != 6 || int.tryParse(yyyymm) == null) {
        errs.add('yyyymm 형식 오류 (YYYYMM)');
      }

      if (errs.isNotEmpty) {
        result.add(CsvRowExtended<Performance>(
          error: errs.join('; '),
          lineIndex: i + 1,
          rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
        ));
        continue;
      }

      result.add(CsvRowExtended<Performance>(
        data: Performance(
          employeeId: employeeId,
          employeeName: employeeName,
          yyyymm: yyyymm,
          point: pointStr.isNotEmpty ? int.tryParse(pointStr) : null,
          rank: rankStr.isNotEmpty ? int.tryParse(rankStr) : null,
        ),
        lineIndex: i + 1,
        rawRow: {for (int j = 0; j < rawHeaders.length && j < vals.length; j++) rawHeaders[j]: vals[j]},
      ));
    }
    return result;
  }

  /// OD CSV 한 줄 파싱 (쉼표 구분, 따옴표로 감싼 필드 지원)
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    var i = 0;
    while (i < line.length) {
      if (line[i] == '"') {
        i++;
        final sb = StringBuffer();
        while (i < line.length) {
          if (line[i] == '"') {
            i++;
            if (i < line.length && line[i] == '"') {
              sb.write('"');
              i++;
            } else {
              break;
            }
          } else {
            sb.write(line[i]);
            i++;
          }
        }
        fields.add(sb.toString().trim());
      } else {
        final sb = StringBuffer();
        while (i < line.length && line[i] != ',') {
          sb.write(line[i]);
          i++;
        }
        fields.add(sb.toString().trim());
        if (i < line.length) i++;
      }
    }
    return fields;
  }

  /// OD CSV 파싱 — 표준: 회사명, 사이트명, 직무, 일정, 업종, 연락처, 주소, 링크(상세링크는 이 컬럼만 사용, 다른 연동 금지), 지역, 본부
  /// 모바일/PC 동일: 줄바꿈 정규화(\r\n→\n) 및 필드 내 \r 제거로 열 밀림 방지
  static List<OdItem> parseOd(String csv) {
    final result = <OdItem>[];
    final normalized = csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) return result;

    final first = _removeBOM(lines[0]);
    final headers = _parseCsvLine(first).map((e) => _removeBOM(e).trim().replaceAll(RegExp(r'\r'), '').toLowerCase()).toList();
    int idx(String name) {
      final n = name.toLowerCase().trim();
      final i = headers.indexWhere((h) {
        final t = h.trim();
        return t.contains(n) || n.contains(t) || t == n;
      });
      return i >= 0 ? i : -1;
    }
    int idxAny(List<String> names) {
      for (final name in names) {
        final i = idx(name);
        if (i >= 0) return i;
      }
      return -1;
    }

    final siteIdx = idxAny(['사이트명', 'site', 'sitename']);
    final companyIdx = idxAny(['회사명', '회사', 'company', '기업명']);
    final jobIdx = idxAny(['직무', 'job', '채용직무']); // 직종은 업종용으로 둠
    final scheduleIdx = idxAny(['일정', '마감일', 'schedule', '채용일정']);
    final addressIdx = idxAny(['주소', 'address', '상세주소', '근무지']);
    final industryIdx = idxAny(['업종', '직종', 'industry', '업태']); // 알바몬·사람인 등 직종/업종 통일
    final contactIdx = idxAny(['연락처', '전화', 'contact', 'phone', '연락처번호']);
    int linkIdx = idxAny(['링크', '상세링크', 'url', '공고링크', '링크주소', '상세 링크', '공고 링크']);
    if (linkIdx < 0 && headers.length >= 8) linkIdx = 7;
    final regionIdx = idxAny(['지역', 'region', 'area']);
    final hqIdx = idxAny(['본부', 'hq', '본부명']);

    bool looksLikePhone(String s) {
      if (s.isEmpty) return false;
      final digits = s.replaceAll(RegExp(r'[^\d]'), '');
      return digits.length >= 8 && RegExp(r'01[0-9]|02|0[3-9]\d{2}').hasMatch(s);
    }
    bool looksLikeIndustry(String s) {
      if (s.isEmpty) return false;
      return s.contains('·') || (s.contains(',') && RegExp(r'[\uac00-\ud7a3]').hasMatch(s)) || s.contains('가능') || s.contains('초보');
    }
    String clean(String s) => s.trim().replaceAll(RegExp(r'[\r\uFEFF\u200B-\u200D\u2060]'), '');
    for (int i = 1; i < lines.length; i++) {
      final raw = _parseCsvLine(_removeBOM(lines[i])).map((f) => f.trim().replaceAll(RegExp(r'\r'), '')).toList();
      String v(int fi) => fi >= 0 && fi < raw.length ? clean(raw[fi]) : '';
      String industry = v(industryIdx);
      String contact = v(contactIdx);
      // 알바몬 등: 연락처 컬럼에 직종/업종 텍스트가 들어온 경우(쉼표·따옴표 파싱 차이 등) 업종으로 보정
      if (contact.isNotEmpty && looksLikeIndustry(contact) && !looksLikePhone(contact)) {
        if (industry.isEmpty || industry == '없음') industry = contact;
        contact = '';
      }
      // 같은 행에서 전화번호 형식이 다른 컬럼에 있으면 연락처로 사용 (열 밀림 보정)
      if (contact.isEmpty) {
        for (final f in raw) {
          final c = clean(f);
          if (c.isNotEmpty && looksLikePhone(c)) {
            contact = c;
            break;
          }
        }
      }
      String link = v(linkIdx);
      String region = v(regionIdx);
      String hq = v(hqIdx);
      bool isUrl(String s) {
        final t = s.trim();
        return t.startsWith('http://') || t.startsWith('https://');
      }
      // 연락처 컬럼에 URL이 들어온 경우(열 밀림): 링크로 옮기고 연락처 비움
      if (contact.isNotEmpty && isUrl(contact)) {
        if (link.isEmpty) link = contact;
        contact = '';
      }
      // 알바몬 등: "본부" 또는 "지역" 컬럼에 상세링크 URL이 들어온 경우 링크로만 쓰고 해당 칸은 비움 (모바일 동일)
      if (link.isEmpty && isUrl(hq)) {
        link = hq;
        hq = '';
      }
      if (link.isEmpty && isUrl(region)) {
        link = region;
        region = '';
      }
      // 모바일 등에서 열이 밀려 link에 본부/지역 값이 들어간 경우: URL이 있는 쪽을 link로 보정
      if (link.isNotEmpty && !isUrl(link)) {
        if (isUrl(hq)) {
          link = hq;
          hq = '';
        } else if (isUrl(region)) {
          link = region;
          region = '';
        }
      }
      result.add(OdItem(
        siteName: v(siteIdx),
        companyName: v(companyIdx),
        jobTitle: v(jobIdx),
        schedule: v(scheduleIdx),
        address: v(addressIdx),
        industry: industry,
        contact: contact,
        link: link,
        region: region,
        hq: hq,
      ));
    }
    return result;
  }
}
