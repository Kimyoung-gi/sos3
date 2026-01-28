import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../repositories/promotion_banner_repository.dart';
import '../../models/home_promotion.dart';

/// 관리자 홈 프로모션 배너 관리 페이지
class AdminPromotionsPage extends StatefulWidget {
  const AdminPromotionsPage({super.key});

  @override
  State<AdminPromotionsPage> createState() => _AdminPromotionsPageState();
}

class _AdminPromotionsPageState extends State<AdminPromotionsPage> {
  bool _isUploading = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _handleFileUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 읽을 수 없습니다.'), backgroundColor: Colors.red),
        );
        return;
      }

      // 파일 크기 확인 (2MB 권장)
      if (file.bytes!.length > 2 * 1024 * 1024) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('파일 크기 경고'),
            content: Text(
              '파일 크기가 2MB를 초과합니다 (${(file.bytes!.length / 1024 / 1024).toStringAsFixed(2)}MB).\n계속 진행하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('계속'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      setState(() => _isUploading = true);

      final repo = context.read<PromotionBannerRepository>();
      
      // 최대 개수 확인
      final currentCount = await repo.getCurrentCount();
      if (currentCount >= 3) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('배너는 최대 3개까지 등록 가능합니다. 기존 배너를 삭제 후 등록해주세요.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _isUploading = false);
        return;
      }

      // 웹/모바일 모두 지원
      if (kIsWeb) {
        // 웹: bytes 사용
        if (file.bytes == null) {
          setState(() => _isUploading = false);
          return;
        }
        final extension = file.extension ?? 'jpg';
        await repo.addByUploadBytes(file.bytes!, extension, file.bytes!.length);
      } else {
        // 모바일: File 사용
        if (file.path == null) {
          setState(() => _isUploading = false);
          return;
        }
        final imageFile = File(file.path!);
        await repo.addByUpload(imageFile);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('배너가 등록되었습니다.'), backgroundColor: Colors.green),
      );
      setState(() => _isUploading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }


  Future<void> _handleDelete(HomePromotion promotion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('배너 삭제'),
        content: const Text('이 배너를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final repo = context.read<PromotionBannerRepository>();
      String? storagePath;
      
      // 업로드 방식인 경우 Storage 경로 추출
      if (promotion.source == 'upload' && promotion.imageUrl.contains('/home_promotions/')) {
        final uri = Uri.parse(promotion.imageUrl);
        final pathSegments = uri.pathSegments;
        final index = pathSegments.indexOf('home_promotions');
        if (index != -1 && index + 1 < pathSegments.length) {
          storagePath = 'home_promotions/${pathSegments[index + 1]}';
        }
      }

      await repo.deletePromotion(promotion.id, storagePath: storagePath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('배너가 삭제되었습니다.'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<PromotionBannerRepository>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 설명 문구
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '홈 배너는 최대 3개까지 등록 가능합니다.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '권장 이미지 크기: 1080×420(px)',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 현재 등록된 배너 리스트
          const Text(
            '현재 등록된 배너',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<HomePromotion>>(
            stream: repo.watchPromotions(limit: 3),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final promotions = snapshot.data ?? [];
              if (promotions.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('등록된 배너가 없습니다.', style: TextStyle(color: Colors.grey)),
                  ),
                );
              }

              return Column(
                children: promotions.map((promotion) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // 썸네일
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              promotion.imageUrl,
                              width: 120,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 120,
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  promotion.source == 'upload' ? '이미지 업로드' : '이미지 URL',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  promotion.imageUrl,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // 삭제 버튼
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _handleDelete(promotion),
                            tooltip: '삭제',
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 32),

          // 등록 영역
          const Text(
            '배너 등록',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isUploading ? null : _handleFileUpload,
            icon: _isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_isUploading ? '업로드 중...' : '이미지 파일 선택 및 업로드'),
          ),
        ],
      ),
    );
  }
}
