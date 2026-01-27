import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/csv_service.dart';

/// CSV 업로드 결과
class CsvUploadResult {
  final bool success;
  final String? errorMessage;
  final String? downloadUrl;
  final int fileSize;
  final DateTime uploadedAt;

  CsvUploadResult({
    required this.success,
    this.errorMessage,
    this.downloadUrl,
    required this.fileSize,
    required this.uploadedAt,
  });
}

/// CSV 업로드 서비스
class CsvUploadService {
  static final CsvUploadService _instance = CsvUploadService._internal();
  factory CsvUploadService() => _instance;
  CsvUploadService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// CSV 파일 업로드
  /// 
  /// [fileBytes]: 파일 바이트 데이터
  /// [filename]: CSV 파일명 (예: 'customerlist.csv')
  /// [uploadedBy]: 업로더 UID 또는 이메일
  /// 
  /// 반환: 업로드 결과
  Future<CsvUploadResult> uploadCsv({
    required List<int> fileBytes,
    required String filename,
    required String uploadedBy,
  }) async {
    try {
      // 파일 크기 검증 (10MB 제한)
      const maxSize = 10 * 1024 * 1024; // 10MB
      if (fileBytes.length > maxSize) {
        return CsvUploadResult(
          success: false,
          errorMessage: '파일 크기가 10MB를 초과합니다. (현재: ${(fileBytes.length / 1024 / 1024).toStringAsFixed(2)}MB)',
          fileSize: fileBytes.length,
          uploadedAt: DateTime.now(),
        );
      }

      // Firebase Storage 경로 생성
      final storagePath = 'csv_files/$filename';
      final storageRef = _storage.ref(storagePath);
      
      debugPrint('📤 Firebase Storage 업로드 시작: $storagePath');
      
      // 메타데이터 설정 (캐시 방지를 위해 업로드 시간 포함)
      final metadata = SettableMetadata(
        contentType: 'text/csv',
        customMetadata: {
          'uploadedAt': DateTime.now().toIso8601String(),
          'uploadedBy': uploadedBy,
        },
      );

      final uploadTask = storageRef.putData(
        Uint8List.fromList(fileBytes),
        metadata,
      );

      // 업로드 진행률 모니터링 (선택사항)
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        debugPrint('📤 업로드 진행률: ${progress.toStringAsFixed(1)}%');
      });

      // 업로드 완료 대기
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('✅ Firebase Storage 업로드 완료: $downloadUrl');

      // Firestore에 업로드 히스토리 기록
      try {
        await _firestore.collection('csv_upload_history').add({
          'type': filename,
          'filename': filename,
          'storagePath': storagePath,
          'downloadUrl': downloadUrl,
          'uploadedBy': uploadedBy,
          'uploadedAt': FieldValue.serverTimestamp(),
          'size': fileBytes.length,
          'status': 'success',
          'resultMessage': '업로드 성공',
        });
        debugPrint('✅ Firestore 히스토리 기록 완료');
      } catch (e) {
        debugPrint('⚠️ Firestore 히스토리 기록 실패 (업로드는 성공): $e');
      }

      // CSV 캐시 무효화
      CsvService.invalidate(filename);

      return CsvUploadResult(
        success: true,
        downloadUrl: downloadUrl,
        fileSize: fileBytes.length,
        uploadedAt: DateTime.now(),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ CSV 업로드 실패: $e');
      debugPrint('스택 트레이스: $stackTrace');

      // Firestore에 실패 기록
      try {
        final storagePath = 'csv_files/$filename';
        await _firestore.collection('csv_upload_history').add({
          'type': filename,
          'filename': filename,
          'storagePath': storagePath,
          'uploadedBy': uploadedBy,
          'uploadedAt': FieldValue.serverTimestamp(),
          'size': fileBytes.length,
          'status': 'fail',
          'resultMessage': e.toString(),
        });
      } catch (firestoreError) {
        debugPrint('⚠️ Firestore 실패 기록도 실패: $firestoreError');
      }

      return CsvUploadResult(
        success: false,
        errorMessage: e.toString(),
        fileSize: fileBytes.length,
        uploadedAt: DateTime.now(),
      );
    }
  }

  /// 업로드 히스토리 조회
  Future<List<Map<String, dynamic>>> getUploadHistory({
    String? fileType,
    int limit = 10,
  }) async {
    try {
      Query query = _firestore
          .collection('csv_upload_history')
          .orderBy('uploadedAt', descending: true)
          .limit(limit);

      if (fileType != null) {
        query = query.where('type', isEqualTo: fileType);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
    } catch (e) {
      debugPrint('❌ 업로드 히스토리 조회 실패: $e');
      return [];
    }
  }
}
