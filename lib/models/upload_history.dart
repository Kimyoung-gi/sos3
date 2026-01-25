/// CSV 업로드 히스토리 모델
enum UploadType {
  customerBase, // 고객기본정보
  salesStatus, // 영업현황
  performance, // 실적포인트순위
  other, // 기타
}

extension UploadTypeExtension on UploadType {
  String get label {
    switch (this) {
      case UploadType.customerBase:
        return '고객기본정보';
      case UploadType.salesStatus:
        return '영업현황';
      case UploadType.performance:
        return '실적포인트순위';
      case UploadType.other:
        return '기타';
    }
  }
}

enum UploadStatus {
  success,
  partial,
  failed,
}

class UploadHistory {
  final String id; // 타임스탬프 기반 고유 ID
  final UploadType type;
  final String filename;
  final String uploader; // 사용자 ID 또는 이름
  final DateTime createdAt;
  final UploadStatus status;
  final int totalRows;
  final int inserted;
  final int updated;
  final int failed;
  final List<String> errorSamples; // 최대 20개
  final String? errorFileId; // 에러 CSV 파일 ID (선택)

  const UploadHistory({
    required this.id,
    required this.type,
    required this.filename,
    required this.uploader,
    required this.createdAt,
    required this.status,
    required this.totalRows,
    required this.inserted,
    required this.updated,
    required this.failed,
    this.errorSamples = const [],
    this.errorFileId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'filename': filename,
        'uploader': uploader,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'totalRows': totalRows,
        'inserted': inserted,
        'updated': updated,
        'failed': failed,
        'errorSamples': errorSamples,
        'errorFileId': errorFileId,
      };

  factory UploadHistory.fromJson(Map<String, dynamic> j) {
    final typeStr = j['type'] as String? ?? 'other';
    UploadType type;
    switch (typeStr) {
      case 'customerBase':
        type = UploadType.customerBase;
        break;
      case 'salesStatus':
        type = UploadType.salesStatus;
        break;
      case 'performance':
        type = UploadType.performance;
        break;
      default:
        type = UploadType.other;
    }

    final statusStr = j['status'] as String? ?? 'failed';
    UploadStatus status;
    switch (statusStr) {
      case 'success':
        status = UploadStatus.success;
        break;
      case 'partial':
        status = UploadStatus.partial;
        break;
      default:
        status = UploadStatus.failed;
    }

    return UploadHistory(
      id: j['id'] as String? ?? '',
      type: type,
      filename: j['filename'] as String? ?? '',
      uploader: j['uploader'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      status: status,
      totalRows: j['totalRows'] as int? ?? 0,
      inserted: j['inserted'] as int? ?? 0,
      updated: j['updated'] as int? ?? 0,
      failed: j['failed'] as int? ?? 0,
      errorSamples: (j['errorSamples'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      errorFileId: j['errorFileId'] as String?,
    );
  }
}
