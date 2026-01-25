import '../models/user.dart';
import '../models/customer.dart';

/// 권한 서비스: RBAC 기반 조회 범위 판단
class PermissionService {
  /// 현재 사용자 기준으로 고객 목록 필터링 (Repository에서 사용)
  static List<Customer> filterByScope(User? user, List<Customer> list) {
    if (user == null) return [];
    switch (user.scope) {
      case UserScope.self:
        final sn = user.sellerName?.trim();
        if (sn == null || sn.isEmpty) return [];
        return list.where((c) => _containsSeller(c.sellerName, sn)).toList();
      case UserScope.branch:
        return list.where((c) => _normalize(c.branch) == _normalize(user.branch)).toList();
      case UserScope.hq:
        return list.where((c) => _normalizeHq(c.hq) == _normalizeHq(user.hq)).toList();
      case UserScope.all:
        return List<Customer>.from(list);
    }
  }

  static String _normalize(String s) => s.trim().toLowerCase();
  static bool _containsSeller(String sellerField, String userSeller) {
    final u = userSeller.trim().toLowerCase();
    final s = sellerField.trim().toLowerCase();
    if (u.isEmpty) return false;
    return s.contains(u) || u.contains(s);
  }
  static String _normalizeHq(String s) {
    final t = s.trim();
    if (t.length >= 2) return t.substring(0, 2).toLowerCase();
    return t.toLowerCase();
  }

  /// 관리자 페이지 접근 가능 여부
  static bool canAccessAdmin(User? user) => user?.isAdmin ?? false;
}
