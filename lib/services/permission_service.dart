import '../models/user.dart';
import '../models/customer.dart';

/// 권한 서비스: RBAC 기반 조회 범위 판단 (기능별 접근레벨 적용)
class PermissionService {
  /// 기능별 접근레벨에 따른 조회 범위
  /// 일반: 고객사=담당자 본인만, 프론티어=본인만, 대시보드=전체
  /// 스탭: 고객사=소속 본부, 프론티어=소속 본부, 대시보드=전체
  /// 관리자: 고객사=전체, 프론티어=전체, 대시보드=전체
  static UserScope effectiveScopeFor(UserRole role, AccessFeature feature) {
    switch (feature) {
      case AccessFeature.dashboard:
        return UserScope.all;
      case AccessFeature.customer:
        if (role == UserRole.admin) return UserScope.all;
        if (role == UserRole.user) return UserScope.self;
        return UserScope.hq;
      case AccessFeature.frontier:
        switch (role) {
          case UserRole.admin:
            return UserScope.all;
          case UserRole.manager:
            return UserScope.hq;
          case UserRole.user:
            return UserScope.self;
        }
    }
  }

  /// 고객 목록 필터링. [feature]를 주면 해당 기능의 접근레벨로 적용 (고객사/프론티어/대시보드)
  static List<Customer> filterByScope(User? user, List<Customer> list, {AccessFeature? feature}) {
    if (user == null) return [];
    final scope = feature != null ? effectiveScopeFor(user.role, feature) : user.scope;
    if (scope == UserScope.all) return List<Customer>.from(list);
    switch (scope) {
      case UserScope.self:
        if (feature == AccessFeature.customer) {
          final userName = user.name.trim();
          if (userName.isEmpty) return [];
          return list.where((c) => _normalize(c.personInCharge) == _normalize(userName)).toList();
        }
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
  /// 본부 비교용 정규화 (앞 2글자 등). 프론티어 필터 등에서 사용
  static String normalizeHq(String s) {
    final t = s.trim();
    if (t.length >= 2) return t.substring(0, 2).toLowerCase();
    return t.toLowerCase();
  }
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
