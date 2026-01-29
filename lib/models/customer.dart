/// 고객(개통) 모델 — Repository/Admin CSV 업로드용
/// 기존 CustomerData와 필드 매핑: customerName, openedAt→openDate, productName, productType, hq, branch, seller→sellerName, building, salesStatus
class Customer {
  final String customerName;
  final String openDate;
  final String productName;
  final String productType;
  final String hq;
  final String branch;
  final String sellerName;
  final String building;
  final String salesStatus;
  final String memo;
  final bool isFavorite;
  final String personInCharge;

  const Customer({
    required this.customerName,
    required this.openDate,
    required this.productName,
    required this.productType,
    required this.hq,
    required this.branch,
    required this.sellerName,
    required this.building,
    this.salesStatus = '영업전',
    this.memo = '',
    this.isFavorite = false,
    this.personInCharge = '',
  });

  String get customerKey => '$customerName|$openDate|$productName';

  Map<String, dynamic> toJson() => {
        'customerName': customerName,
        'openDate': openDate,
        'productName': productName,
        'productType': productType,
        'hq': hq,
        'branch': branch,
        'sellerName': sellerName,
        'building': building,
        'salesStatus': salesStatus,
        'memo': memo,
        'isFavorite': isFavorite,
        'personInCharge': personInCharge,
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        customerName: j['customerName'] as String? ?? '',
        openDate: j['openDate'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        productType: j['productType'] as String? ?? '',
        hq: j['hq'] as String? ?? '',
        branch: j['branch'] as String? ?? '',
        sellerName: j['sellerName'] as String? ?? '',
        building: j['building'] as String? ?? '',
        salesStatus: j['salesStatus'] as String? ?? '영업전',
        memo: j['memo'] as String? ?? '',
        isFavorite: j['isFavorite'] as bool? ?? false,
        personInCharge: j['personInCharge'] as String? ?? '',
      );

  Customer copyWith({
    String? customerName,
    String? openDate,
    String? productName,
    String? productType,
    String? hq,
    String? branch,
    String? sellerName,
    String? building,
    String? salesStatus,
    String? memo,
    bool? isFavorite,
    String? personInCharge,
  }) =>
      Customer(
        customerName: customerName ?? this.customerName,
        openDate: openDate ?? this.openDate,
        productName: productName ?? this.productName,
        productType: productType ?? this.productType,
        hq: hq ?? this.hq,
        branch: branch ?? this.branch,
        sellerName: sellerName ?? this.sellerName,
        building: building ?? this.building,
        salesStatus: salesStatus ?? this.salesStatus,
        memo: memo ?? this.memo,
        isFavorite: isFavorite ?? this.isFavorite,
        personInCharge: personInCharge ?? this.personInCharge,
      );
}
