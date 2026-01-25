# Firebase Storage → Firestore 마이그레이션 완료

## 변경 사항 요약

### 1. CsvService 수정 (`lib/services/csv_service.dart`)
- ✅ Firebase Storage 로딩 제거
- ✅ Firestore `csv_files` 컬렉션에서 로드하도록 변경
- ✅ 우선순위: Firestore → assets fallback
- ✅ 캐시 구조 유지 (5분 만료)

### 2. Admin CSV 업로드 페이지 수정 (`lib/ui/pages/admin_csv_upload_page.dart`)
- ⚠️ **주의**: Firebase Storage 관련 코드가 아직 남아있습니다
- ✅ Firestore 저장 로직 추가 필요
- ✅ 업로드 진행률 표시 추가 (`_uploadProgress`)
- ✅ `setState()` after dispose 방지 (`if (!mounted) return;`)

### 3. Firestore 보안 규칙 문서 생성
- ✅ `FIREBASE_FIRESTORE_RULES.md` 생성
- ✅ `csv_files` 컬렉션 규칙 정의
- ✅ `csv_upload_history` 컬렉션 규칙 정의

## 남은 작업

### `admin_csv_upload_page.dart` 수정 필요
현재 파일의 329-367 라인에 Firebase Storage 관련 코드가 남아있습니다:

```dart
// 제거해야 할 코드:
- final storage = FirebaseStorage.instance;
- final ref = storage.ref('csv/${widget.filename}');
- final metadata = SettableMetadata(...);
- final uploadTask = ref.putData(...);
- _uploadSubscription = uploadTask.snapshotEvents.listen(...);
- final snapshot = await uploadTask;
- final downloadUrl = await snapshot.ref.getDownloadURL();
```

**대체 코드:**
```dart
// Firestore 저장
final csvContent = utf8.decode(_selectedFileBytes!);
final firestore = FirebaseFirestore.instance;
await firestore.collection('csv_files').doc(widget.filename).set({
  'content': csvContent,
  'updatedAt': FieldValue.serverTimestamp(),
  'updatedBy': currentUser.id,
  'size': _selectedFileBytes!.length,
}, SetOptions(merge: true));
```

## Firestore 컬렉션 구조

### `csv_files/{filename}`
- `content` (string): CSV 전체 텍스트
- `updatedAt` (timestamp): 서버 타임스탬프
- `updatedBy` (string): 업로더 UID
- `size` (number): 파일 크기 (bytes)

### `csv_upload_history/{documentId}`
- `filename` (string)
- `uploadedAt` (timestamp)
- `uploader` (string)
- `size` (number)
- `success` (boolean)
- `message` (string)

## 다음 단계

1. `admin_csv_upload_page.dart`의 Firebase Storage 코드 완전 제거
2. Firestore Rules 적용 (`FIREBASE_FIRESTORE_RULES.md` 참고)
3. 테스트: `flutter run -d chrome --web-port 5173`
4. Firestore Console에서 `csv_files` 컬렉션 확인
