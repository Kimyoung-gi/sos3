import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/home_promotion.dart';

/// 홈 프로모션 배너 리포지토리
class PromotionBannerRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const String _collection = 'home_promotions';
  static const int _maxCount = 3;

  /// 프로모션 배너 이미지 URL 목록 스트림 (최대 3개)
  Stream<List<String>> watchPromotionImageUrls({int limit = 3}) {
    try {
      debugPrint('📡 배너 스트림 구독 시작: collection=$_collection');
      return _firestore
          .collection(_collection)
          .snapshots()
          .map((snapshot) {
        debugPrint('📦 배너 스냅샷 수신: 문서 개수=${snapshot.docs.length}');
        
        final urls = <String>[];
        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final url = data['imageUrl'] as String? ?? '';
            debugPrint('📋 배너 데이터: docId=${doc.id}, imageUrl=$url, source=${data['source']}');
            if (url.isNotEmpty) {
              urls.add(url);
            }
          } catch (e) {
            debugPrint('⚠️ 배너 문서 파싱 오류 (docId=${doc.id}): $e');
          }
        }
        
        debugPrint('✅ 배너 URL 목록: ${urls.length}개 - $urls');
        
        // 최대 limit개만 반환
        return urls.take(limit).toList();
      }).handleError((error, stackTrace) {
        debugPrint('❌ 배너 스트림 오류: $error');
        debugPrint('스택 트레이스: $stackTrace');
        return <String>[];
      });
    } catch (e, stackTrace) {
      debugPrint('❌ 배너 스트림 생성 실패: $e');
      debugPrint('스택 트레이스: $stackTrace');
      return Stream.value(<String>[]);
    }
  }

  /// 프로모션 배너 전체 목록 스트림 (관리자용)
  Stream<List<HomePromotion>> watchPromotions({int limit = 3}) {
    try {
      return _firestore
          .collection(_collection)
          .snapshots()
          .map((snapshot) {
        final promotions = snapshot.docs
            .map((doc) {
              try {
                return HomePromotion.fromFirestore(doc.id, doc.data());
              } catch (e) {
                debugPrint('❌ 배너 파싱 오류 (docId=${doc.id}): $e');
                return null;
              }
            })
            .whereType<HomePromotion>()
            .toList();
        
        // createdAt 기준으로 정렬 (내림차순)
        promotions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        // 최대 limit개만 반환
        return promotions.take(limit).toList();
      }).handleError((error) {
        debugPrint('❌ 배너 목록 스트림 오류: $error');
        return <HomePromotion>[];
      });
    } catch (e) {
      debugPrint('❌ 배너 목록 스트림 생성 실패: $e');
      return Stream.value(<HomePromotion>[]);
    }
  }

  /// 현재 배너 개수 확인
  Future<int> getCurrentCount() async {
    try {
      final snapshot = await _firestore.collection(_collection).get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ 배너 개수 확인 실패: $e');
      return 0;
    }
  }

  /// 이미지 파일 업로드 방식으로 배너 등록 (File)
  Future<void> addByUpload(File imageFile) async {
    final fileSize = await imageFile.length();
    final extension = imageFile.path.split('.').last.toLowerCase();
    final bytes = await imageFile.readAsBytes();
    return addByUploadBytes(bytes, extension, fileSize);
  }

  /// 이미지 파일 업로드 방식으로 배너 등록 (Bytes - 웹 지원)
  Future<void> addByUploadBytes(List<int> bytes, String extension, int fileSize) async {
    try {
      // 최대 개수 확인
      final currentCount = await getCurrentCount();
      if (currentCount >= _maxCount) {
        throw Exception('배너는 최대 $_maxCount개까지 등록 가능합니다. 기존 배너를 삭제 후 등록해주세요.');
      }

      // 파일 크기 확인 (2MB 권장, 초과 시 경고만)
      if (fileSize > 2 * 1024 * 1024) {
        debugPrint('⚠️ 파일 크기가 2MB를 초과합니다: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
      }

      // Storage 업로드
      final docId = _firestore.collection(_collection).doc().id;
      final storagePath = 'home_promotions/$docId.$extension';
      final storageRef = _storage.ref(storagePath);

      debugPrint('📤 배너 이미지 업로드 시작: $storagePath');

      final uploadTask = storageRef.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(
          contentType: _getContentType(extension),
          cacheControl: 'public, max-age=31536000',
        ),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('✅ 배너 이미지 업로드 완료: $downloadUrl');

      // Firestore 문서 생성
      await _firestore.collection(_collection).doc(docId).set({
        'imageUrl': downloadUrl,
        'source': 'upload',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Firestore 문서 생성 완료: $docId');
    } catch (e) {
      debugPrint('❌ 배너 업로드 실패: $e');
      rethrow;
    }
  }

  /// 이미지 URL 직접 입력 방식으로 배너 등록
  Future<void> addByUrl(String imageUrl) async {
    try {
      // URL 유효성 검사
      if (imageUrl.trim().isEmpty) {
        throw Exception('이미지 URL을 입력해주세요.');
      }

      final uri = Uri.tryParse(imageUrl);
      if (uri == null || !uri.hasScheme) {
        throw Exception('유효한 이미지 URL 형식이 아닙니다.');
      }

      // 최대 개수 확인
      final currentCount = await getCurrentCount();
      if (currentCount >= _maxCount) {
        throw Exception('배너는 최대 $_maxCount개까지 등록 가능합니다. 기존 배너를 삭제 후 등록해주세요.');
      }

      // Firestore 문서 생성
      final docId = _firestore.collection(_collection).doc().id;
      await _firestore.collection(_collection).doc(docId).set({
        'imageUrl': imageUrl.trim(),
        'source': 'url',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ 배너 URL 등록 완료: $docId');
    } catch (e) {
      debugPrint('❌ 배너 URL 등록 실패: $e');
      rethrow;
    }
  }

  /// 배너 삭제
  Future<void> deletePromotion(String docId, {String? storagePath}) async {
    try {
      // Firestore 문서 삭제
      await _firestore.collection(_collection).doc(docId).delete();

      // Storage 파일도 삭제 (업로드 방식인 경우)
      if (storagePath?.isNotEmpty ?? false) {
        try {
          await _storage.ref(storagePath).delete();
          debugPrint('✅ Storage 파일 삭제 완료: $storagePath');
        } catch (e) {
          debugPrint('⚠️ Storage 파일 삭제 실패 (무시): $e');
        }
      }

      debugPrint('✅ 배너 삭제 완료: $docId');
    } catch (e) {
      debugPrint('❌ 배너 삭제 실패: $e');
      rethrow;
    }
  }

  /// 파일 확장자에 따른 Content-Type 반환
  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}
