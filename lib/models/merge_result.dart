/// CSV 병합 결과 공통 모델
class MergeResult {
  final int total;
  final int success;
  final int fail;
  final int skipped;
  final int updated;
  final List<String> failReasonsTop3;

  MergeResult({
    required this.total,
    required this.success,
    required this.fail,
    required this.skipped,
    required this.updated,
    required this.failReasonsTop3,
  });
}
