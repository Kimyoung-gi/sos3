/// 사용자 모델 (로그인/관리자용)
class User {
  final String id;
  final String name;
  final String hq;
  final String branch;
  final UserRole role;
  final UserScope scope;
  final bool isActive;
  /// SELF 조회 시 사용. 실판매자(예: 1228150/최성은)와 매칭
  final String? sellerName;

  const User({
    required this.id,
    required this.name,
    required this.hq,
    required this.branch,
    required this.role,
    required this.scope,
    this.isActive = true,
    this.sellerName,
  });

  /// 접근레벨 표시: 일반 / 스탭 / 관리자
  String get roleLabel {
    switch (role) {
      case UserRole.user:
        return '일반';
      case UserRole.manager:
        return '스탭';
      case UserRole.admin:
        return '관리자';
    }
  }

  String get scopeLabel {
    switch (scope) {
      case UserScope.self:
        return 'SELF';
      case UserScope.branch:
        return 'BRANCH';
      case UserScope.hq:
        return 'HQ';
      case UserScope.all:
        return 'ALL';
    }
  }

  bool get isAdmin => role == UserRole.admin;
  bool get isManager => role == UserRole.manager;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hq': hq,
        'branch': branch,
        'role': role.name,
        'scope': scope.name,
        'isActive': isActive,
        'sellerName': sellerName,
      };

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        hq: j['hq'] as String? ?? '',
        branch: j['branch'] as String? ?? '',
        role: _roleFrom(j['role']),
        scope: _scopeFrom(j['scope']),
        isActive: j['isActive'] as bool? ?? true,
        sellerName: j['sellerName'] as String?,
      );

  static UserRole _roleFrom(dynamic v) {
    if (v == null) return UserRole.user;
    final s = v.toString().toUpperCase();
    if (s == 'ADMIN') return UserRole.admin;
    if (s == 'MANAGER') return UserRole.manager;
    return UserRole.user;
  }

  static UserScope _scopeFrom(dynamic v) {
    if (v == null) return UserScope.self;
    final s = v.toString().toUpperCase();
    if (s == 'ALL') return UserScope.all;
    if (s == 'HQ') return UserScope.hq;
    if (s == 'BRANCH') return UserScope.branch;
    return UserScope.self;
  }

  User copyWith({
    String? id,
    String? name,
    String? hq,
    String? branch,
    UserRole? role,
    UserScope? scope,
    bool? isActive,
    String? sellerName,
  }) =>
      User(
        id: id ?? this.id,
        name: name ?? this.name,
        hq: hq ?? this.hq,
        branch: branch ?? this.branch,
        role: role ?? this.role,
        scope: scope ?? this.scope,
        isActive: isActive ?? this.isActive,
        sellerName: sellerName ?? this.sellerName,
      );
}

enum UserRole { user, manager, admin }
enum UserScope { self, branch, hq, all }

/// 기능별 접근 범위 구분 (고객사/프론티어/대시보드)
/// 접근레벨 정의:
/// - 일반: 고객사(소속 본부 단위 조회), 프론티어(본인만 조회), 대시보드(전체 조회)
/// - 스탭: 고객사(소속 본부 단위 조회), 프론티어(소속 본부 단위 조회), 대시보드(전체 조회)
/// - 관리자: 고객사(전체 조회), 프론티어(전체 조회), 대시보드(전체 조회)
enum AccessFeature {
  customer,
  frontier,
  dashboard,
}
