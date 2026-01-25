import 'dart:async';
import 'package:flutter/foundation.dart';

/// CSV 재로드 이벤트 버스
/// CSV 업로드 성공 시 이벤트를 발행하여 화면들이 자동으로 데이터를 재로드하도록 함
class CsvReloadBus {
  static final CsvReloadBus _instance = CsvReloadBus._internal();
  factory CsvReloadBus() => _instance;
  CsvReloadBus._internal();

  final _controller = StreamController<String>.broadcast();
  
  /// CSV 파일명 재로드 이벤트 스트림
  Stream<String> get stream => _controller.stream;
  
  /// CSV 파일 재로드 이벤트 발행
  /// 
  /// [filename]: 재로드할 CSV 파일명 (예: 'customerlist.csv', 'kpi_mobile.csv')
  void reload(String filename) {
    debugPrint('📢 CsvReloadBus: $filename 재로드 이벤트 발행');
    _controller.add(filename);
  }
  
  /// 리소스 정리 (앱 종료 시 호출)
  void dispose() {
    _controller.close();
  }
}

/// KPI 파일 목록 (대시보드에서 사용)
const List<String> kpiFiles = [
  'kpi_mobile.csv',
  'kpi_it.csv',
  'kpi_itr.csv',
  'kpi_etc.csv',
  'kpi-info.csv',
];

/// 고객사 파일 목록
const List<String> customerFiles = [
  'customerlist.csv',
];

/// 특정 파일이 KPI 파일인지 확인
bool isKpiFile(String filename) {
  return kpiFiles.contains(filename);
}

/// 특정 파일이 고객사 파일인지 확인
bool isCustomerFile(String filename) {
  return customerFiles.contains(filename);
}
