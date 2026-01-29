import 'package:cloud_firestore/cloud_firestore.dart';

/// 홈 프로모션 배너 모델
class HomePromotion {
  final String id;
  final String imageUrl;
  final String source; // 'upload' | 'url'
  final DateTime createdAt;

  HomePromotion({
    required this.id,
    required this.imageUrl,
    required this.source,
    required this.createdAt,
  });

  factory HomePromotion.fromFirestore(String id, Map<String, dynamic> data) {
    return HomePromotion(
      id: id,
      imageUrl: data['imageUrl'] as String? ?? '',
      source: data['source'] as String? ?? 'url',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'imageUrl': imageUrl,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
