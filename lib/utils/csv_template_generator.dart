import '../models/upload_history.dart';

/// CSV 템플릿 생성기
class CsvTemplateGenerator {
  /// 고객기본정보 CSV 템플릿
  static String generateCustomerBase() {
    return '''본부,지사,고객명,개통일자,상품유형,상품명,실판매자,건물명,담당자,영업상태
강북,강북센터,홍길동,2025-01-15,무선,5G 요금제,김철수,강북빌딩,홍담당,영업전
강남,강남센터,이영희,2025-01-20,유선,인터넷 100M,박민수,강남타워,이담당,영업중''';
  }

  /// 영업현황 CSV 템플릿 (customer_id = 고객명|개통일자|상품명)
  static String generateSalesStatus() {
    return '''customer_id,sales_status,memo,updated_at
홍길동|2025-01-15|5G 요금제,개통완료,고객 만족,2025-01-25
이영희|2025-01-20|인터넷 100M,영업중,추가 상담 필요,''';
  }

  /// 실적포인트순위 CSV 템플릿
  static String generatePerformance() {
    return '''employee_id,employee_name,yyyymm,point,rank
1228150,최성은,202512,1500,1
1228151,김철수,202512,1200,2
1228152,박민수,202512,1000,3''';
  }

  /// 타입별 템플릿 생성
  static String generate(UploadType type) {
    switch (type) {
      case UploadType.customerBase:
        return generateCustomerBase();
      case UploadType.salesStatus:
        return generateSalesStatus();
      case UploadType.performance:
        return generatePerformance();
      case UploadType.other:
        return '컬럼1,컬럼2,컬럼3\n값1,값2,값3';
    }
  }

  /// 파일명별 템플릿 생성
  /// 
  /// [filename]: CSV 파일명 (예: 'customerlist.csv', 'kpi-info.csv')
  /// 
  /// 반환: CSV 템플릿 내용
  static String generateByFilename(String filename) {
    switch (filename) {
      case 'customerlist.csv':
        // 고객기본정보 CSV 템플릿
        return '''본부,지사,고객명,개통일자,상품유형,상품명,실판매자,건물명,담당자,영업상태
강북,강북센터,홍길동,2025-01-15,무선,5G 요금제,김철수,강북빌딩,홍담당,영업전
강남,강남센터,이영희,2025-01-20,유선,인터넷 100M,박민수,강남타워,이담당,영업중''';
      
      case 'kpi-info.csv':
      case 'kpi_it.csv':
      case 'kpi_itr.csv':
      case 'kpi_mobile.csv':
      case 'kpi_etc.csv':
        // KPI 실적 CSV 템플릿 (employee_id, employee_name, yyyymm, point, rank)
        return '''employee_id,employee_name,yyyymm,point,rank
1228150,최성은,202512,1500,1
1228151,김철수,202512,1200,2
1228152,박민수,202512,1000,3''';
      
      default:
        return '컬럼1,컬럼2,컬럼3\n값1,값2,값3';
    }
  }
}
