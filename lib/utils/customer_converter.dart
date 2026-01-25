import '../models/customer.dart';
import '../main.dart' show CustomerData;

/// Customer와 CustomerData 간 변환 헬퍼
class CustomerConverter {
  /// Customer -> CustomerData
  static CustomerData toCustomerData(Customer c) {
    return CustomerData(
      customerName: c.customerName,
      openedAt: c.openDate,
      productName: c.productName,
      productType: c.productType,
      hq: c.hq,
      branch: c.branch,
      seller: c.sellerName,
      building: c.building,
      isFavorite: c.isFavorite,
      salesStatus: c.salesStatus,
      memo: c.memo,
    );
  }

  /// CustomerData -> Customer
  static Customer toCustomer(CustomerData cd) {
    return Customer(
      customerName: cd.customerName,
      openDate: cd.openedAt,
      productName: cd.productName,
      productType: cd.productType,
      hq: cd.hq,
      branch: cd.branch,
      sellerName: cd.seller,
      building: cd.building,
      isFavorite: cd.isFavorite,
      salesStatus: cd.salesStatus,
      memo: cd.memo,
    );
  }

  /// List 변환
  static List<CustomerData> toCustomerDataList(List<Customer> list) {
    return list.map((c) => toCustomerData(c)).toList();
  }

  static List<Customer> toCustomerList(List<CustomerData> list) {
    return list.map((cd) => toCustomer(cd)).toList();
  }
}
