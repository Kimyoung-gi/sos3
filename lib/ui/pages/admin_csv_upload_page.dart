import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../services/csv_service.dart';
import '../../services/csv_reload_bus.dart';
import '../../utils/csv_template_generator.dart';
import '../../utils/csv_downloader.dart';

/// CSV 파일 목록 (고정)
const List<String> _csvFiles = [
  'customerlist.csv',
  'kpi-info.csv',
  'kpi_it.csv',
  'kpi_itr.csv',
  'kpi_mobile.csv',
  'kpi_etc.csv',
];

/// 관리자 CSV 업로드 페이지
class AdminCsvUploadPage extends StatefulWidget {
  const AdminCsvUploadPage({super.key});

  @override
  State<AdminCsvUploadPage> createState() => _AdminCsvUploadPageState();
}

class _AdminCsvUploadPageState extends State<AdminCsvUploadPage> {
  List<Map<String, dynamic>> _uploadHistory = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _isLoadingHistory = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('csv_upload_history')
          .orderBy('uploadedAt', descending: true)
          .limit(10)
          .get();
      
      if (!mounted) return;
      setState(() {
        _uploadHistory = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            ...data,
          };
        }).toList();
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('업로드 이력 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoadingHistory = false);
    }
  }

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return '-';
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return timestamp.toString();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CSV 파일 업로드',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '업로드한 CSV는 즉시 반영됩니다. 각 파일을 개별적으로 업로드하세요.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          // CSV 파일별 업로드 카드 (Grid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
            ),
            itemCount: _csvFiles.length,
            itemBuilder: (context, index) {
              return _CsvUploadCard(
                filename: _csvFiles[index],
                onUploadSuccess: _loadHistory,
              );
            },
          ),
          // 업로드 이력
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '최근 업로드 이력 (최대 10건)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingHistory)
            const Center(child: CircularProgressIndicator())
          else if (_uploadHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  '업로드 이력이 없습니다.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            Card(
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                  4: FlexColumnWidth(1),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey)),
                    ),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('파일명', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('업로드 시간', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('업로더', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('크기', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('상태', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  ..._uploadHistory.map((item) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(item['filename'] ?? '-'),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_formatDateTime(item['uploadedAt'])),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(item['uploader'] ?? '-'),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_formatFileSize(item['size'] ?? 0)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              item['success'] == true ? Icons.check_circle : Icons.error,
                              color: item['success'] == true ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item['success'] == true ? '성공' : '실패',
                                style: TextStyle(
                                  color: item['success'] == true ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 개별 CSV 파일 업로드 카드
class _CsvUploadCard extends StatefulWidget {
  final String filename;
  final VoidCallback onUploadSuccess;

  const _CsvUploadCard({
    required this.filename,
    required this.onUploadSuccess,
  });

  @override
  State<_CsvUploadCard> createState() => _CsvUploadCardState();
}

class _CsvUploadCardState extends State<_CsvUploadCard> {
  Uint8List? _selectedFileBytes;
  String? _selectedFileName;
  bool _isUploading = false;
  String? _uploadMessage;
  bool _uploadSuccess = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: '${widget.filename} 선택',
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _selectedFileBytes = result.files.single.bytes;
          _selectedFileName = result.files.single.name;
          _uploadMessage = null;
          _uploadSuccess = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('파일 선택 오류: $e')),
        );
      }
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFileBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('파일을 선택해주세요.')),
      );
      return;
    }

    // 관리자 권한 확인
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;
    if (currentUser == null || currentUser.role != UserRole.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('관리자 권한이 필요합니다.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isUploading = true;
      _uploadMessage = null;
      _uploadSuccess = false;
      _uploadProgress = 0.0;
    });

    try {
      // 디버그: 현재 로그인 사용자 정보
      debugPrint('🔍 [업로드 디버그] 현재 로그인 사용자:');
      debugPrint('  - UID: ${currentUser.id}');
      debugPrint('  - Name: ${currentUser.name}');
      debugPrint('  - Role: ${currentUser.role}');
      debugPrint('  - 파일명: ${widget.filename}');
      debugPrint('  - 파일 크기: ${_selectedFileBytes!.length} bytes');
      
      // 파일 bytes를 UTF-8 텍스트로 디코딩
      if (!mounted) return;
      setState(() => _uploadProgress = 10.0);
      
      debugPrint('📤 파일 디코딩 중...');
      final csvContent = utf8.decode(_selectedFileBytes!);
      
      if (!mounted) return;
      setState(() => _uploadProgress = 50.0);
      
      debugPrint('📤 Firestore에 저장 중: csv_files/${widget.filename}');
      
      // Firestore에 CSV 내용 저장
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('csv_files').doc(widget.filename).set({
        'content': csvContent,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUser.id,
        'size': _selectedFileBytes!.length,
      }, SetOptions(merge: true));
      
      debugPrint('✅ Firestore 저장 완료: csv_files/${widget.filename}');

      // Firestore에 업로드 이력 기록
      try {
        await firestore.collection('csv_upload_history').add({
          'filename': widget.filename,
          'uploadedAt': FieldValue.serverTimestamp(),
          'uploader': currentUser.id,
          'size': _selectedFileBytes!.length,
          'success': true,
          'message': '업로드 성공',
        });
        debugPrint('✅ Firestore 히스토리 기록 완료');
      } catch (e) {
        debugPrint('⚠️ Firestore 히스토리 기록 실패 (저장은 성공): $e');
      }

      if (!mounted) return;
      setState(() => _uploadProgress = 100.0);
      
      // CSV 캐시 무효화
      CsvService.invalidate(widget.filename);
      
      // 전역 이벤트 발행 (화면 자동 갱신)
      CsvReloadBus().reload(widget.filename);
      debugPrint('📢 CSV 재로드 이벤트 발행: ${widget.filename}');

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadSuccess = true;
        _uploadProgress = 0.0;
        _uploadMessage = '✅ 업로드 완료 (Firestore)';
      });

      // 성공 콜백 호출
      widget.onUploadSuccess();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 업로드 완료 (Firestore)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ CSV 업로드 실패: $e');
      debugPrint('❌ 오류 타입: ${e.runtimeType}');
      debugPrint('❌ 스택 트레이스: $stackTrace');
      
      // Firestore 오류 상세 정보
      if (e.toString().contains('unauthorized') || e.toString().contains('permission')) {
        debugPrint('⚠️ 권한 오류 감지!');
        debugPrint('  - Firestore Rules를 확인하세요.');
        debugPrint('  - 임시 규칙 적용: FIREBASE_FIRESTORE_RULES.md 참고');
        debugPrint('  - 현재 사용자 UID: ${currentUser.id}');
        debugPrint('  - 저장 경로: csv_files/${widget.filename}');
      }

      // Firestore에 실패 기록
      try {
        final firestore = FirebaseFirestore.instance;
        await firestore.collection('csv_upload_history').add({
          'filename': widget.filename,
          'uploadedAt': FieldValue.serverTimestamp(),
          'uploader': currentUser.id,
          'size': _selectedFileBytes!.length,
          'success': false,
          'message': e.toString(),
        });
      } catch (firestoreError) {
        debugPrint('⚠️ Firestore 실패 기록도 실패: $firestoreError');
      }

      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploadSuccess = false;
        _uploadProgress = 0.0;
        _uploadMessage = '업로드 실패: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업로드 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _downloadTemplate() {
    try {
      // 파일명으로 템플릿 생성
      final template = CsvTemplateGenerator.generateByFilename(widget.filename);
      
      final filename = '${widget.filename.replaceAll('.csv', '')}_양식.csv';
      CsvDownloader.download(template, filename);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('양식 파일 다운로드가 시작되었습니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('양식 다운로드 오류: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _testReload() {
    // CSV 캐시 무효화 및 재로딩 테스트
    CsvService.invalidate(widget.filename);
    
    // 비동기로 재로딩 테스트
    CsvService.load(widget.filename).then((csvText) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재로딩 성공! (${csvText.length} bytes)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재로딩 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 파일명 헤더
            Row(
              children: [
                Icon(
                  Icons.description,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.filename,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // 양식 다운로드 버튼
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('양식 다운로드', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // 파일 선택 버튼
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading ? null : _pickFile,
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(
                  _selectedFileName ?? '파일 선택',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // 업로드 버튼
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_isUploading || _selectedFileBytes == null) ? null : _uploadFile,
                icon: _isUploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload, size: 16),
                label: Text(
                  _isUploading ? '업로드 중... ${_uploadProgress.toStringAsFixed(0)}%' : '업로드',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            
            // 업로드 진행률 표시
            if (_isUploading && _uploadProgress > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _uploadProgress / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            
            // 업로드 메시지
            if (_uploadMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _uploadSuccess ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _uploadSuccess ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _uploadSuccess ? Icons.check_circle : Icons.error,
                      color: _uploadSuccess ? Colors.green : Colors.red,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _uploadMessage!,
                        style: TextStyle(
                          color: _uploadSuccess ? Colors.green[900] : Colors.red[900],
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // 즉시 반영 테스트 버튼
            if (_uploadSuccess) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testReload,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('즉시 반영 테스트', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
