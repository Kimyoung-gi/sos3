/// 실적/포인트/순위 모델
class Performance {
  final String employeeId;
  final String employeeName;
  final String yyyymm; // YYYYMM 형식 (예: 202512)
  final int? point;
  final int? rank;

  const Performance({
    required this.employeeId,
    required this.employeeName,
    required this.yyyymm,
    this.point,
    this.rank,
  });

  Map<String, dynamic> toJson() => {
        'employeeId': employeeId,
        'employeeName': employeeName,
        'yyyymm': yyyymm,
        'point': point,
        'rank': rank,
      };

  factory Performance.fromJson(Map<String, dynamic> j) => Performance(
        employeeId: j['employeeId'] as String? ?? '',
        employeeName: j['employeeName'] as String? ?? '',
        yyyymm: j['yyyymm'] as String? ?? '',
        point: j['point'] as int?,
        rank: j['rank'] as int?,
      );

  Performance copyWith({
    String? employeeId,
    String? employeeName,
    String? yyyymm,
    int? point,
    int? rank,
  }) =>
      Performance(
        employeeId: employeeId ?? this.employeeId,
        employeeName: employeeName ?? this.employeeName,
        yyyymm: yyyymm ?? this.yyyymm,
        point: point ?? this.point,
        rank: rank ?? this.rank,
      );
}
