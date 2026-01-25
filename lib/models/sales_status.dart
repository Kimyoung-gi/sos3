/// 영업현황 모델
class SalesStatus {
  final String customerId; // customerName|openDate|productName 조합 또는 별도 ID
  final String salesStatus; // 영업전|영업중|개통완료|실패
  final String memo;
  final String? updatedAt; // YYYY-MM-DD

  const SalesStatus({
    required this.customerId,
    required this.salesStatus,
    this.memo = '',
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'salesStatus': salesStatus,
        'memo': memo,
        'updatedAt': updatedAt,
      };

  factory SalesStatus.fromJson(Map<String, dynamic> j) => SalesStatus(
        customerId: j['customerId'] as String? ?? '',
        salesStatus: j['salesStatus'] as String? ?? '영업전',
        memo: j['memo'] as String? ?? '',
        updatedAt: j['updatedAt'] as String?,
      );

  SalesStatus copyWith({
    String? customerId,
    String? salesStatus,
    String? memo,
    String? updatedAt,
  }) =>
      SalesStatus(
        customerId: customerId ?? this.customerId,
        salesStatus: salesStatus ?? this.salesStatus,
        memo: memo ?? this.memo,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
