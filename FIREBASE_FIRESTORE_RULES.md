# Firebase Firestore 보안 규칙

## CSV 파일 저장소 및 업로드 이력 규칙

Firebase Console > Firestore > Rules에서 다음 규칙을 적용하세요:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // CSV 파일 저장소
    match /csv_files/{filename} {
      // 읽기: 모든 인증된 사용자 허용
      allow read: if request.auth != null;
      
      // 쓰기: 관리자만 허용
      allow write: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
    
    // CSV 업로드 이력
    match /csv_upload_history/{document} {
      // 읽기: 관리자만 허용
      allow read: if request.auth != null 
        && request.auth.token.role == 'admin';
      
      // 쓰기: 관리자만 허용
      allow create: if request.auth != null 
        && request.auth.token.role == 'admin';
      
      // 수정/삭제: 관리자만 허용
      allow update, delete: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
    
    // 홈 프로모션 배너
    match /home_promotions/{document} {
      // 읽기: 모든 사용자 허용 (홈 화면에서 표시)
      allow read: if true;
      
      // 쓰기: 관리자만 허용 (현재는 Firebase Auth 미사용이므로 임시로 true)
      allow write: if true;
    }
    
    // 기타 컬렉션 규칙...
  }
}
```

## ⚠️ 임시 테스트 규칙 (개발용)

개발 중에는 다음 규칙으로 모든 인증된 사용자에게 허용할 수 있습니다:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // CSV 파일 저장소
    match /csv_files/{filename} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
    
    // CSV 업로드 이력
    match /csv_upload_history/{document} {
      allow read, write: if request.auth != null;
    }
    
    // 홈 프로모션 배너 (개발용 - 모든 사용자 허용)
    match /home_promotions/{document} {
      allow read, write: if true;
    }
  }
}
```

**주의**: 이 규칙은 모든 인증된 사용자에게 읽기/쓰기 권한을 부여합니다. 테스트 후 반드시 위의 프로덕션 규칙으로 변경하세요.

## Firestore 컬렉션 구조

### csv_files 컬렉션

**경로**: `csv_files/{filename}`

**문서 ID**: CSV 파일명 (예: `customerlist.csv`, `kpi-info.csv`)

**필드**:
- `content` (string): CSV 전체 텍스트 내용
- `updatedAt` (timestamp): 서버 타임스탬프
- `updatedBy` (string): 업로더 UID
- `size` (number): 파일 크기 (bytes)

**예시 문서**:
```
csv_files/customerlist.csv
{
  content: "본부,지사,고객명,...\n강북,강북센터,홍길동,...",
  updatedAt: Timestamp(2025-01-25 10:30:00),
  updatedBy: "1111",
  size: 129030
}
```

### csv_upload_history 컬렉션

**경로**: `csv_upload_history/{documentId}`

**자동 생성 ID**: Firestore가 자동 생성

**필드**:
- `filename` (string): 업로드한 파일명
- `uploadedAt` (timestamp): 서버 타임스탬프
- `uploader` (string): 업로더 UID
- `size` (number): 파일 크기 (bytes)
- `success` (boolean): 업로드 성공 여부
- `message` (string): 결과 메시지

## 참고사항

1. **Custom Claims 설정**: Firebase Authentication에서 사용자에게 `role` custom claim을 설정해야 합니다.
   - 관리자: `{ role: 'admin' }`
   - 일반 사용자: `{ role: 'user' }`

2. **문서 크기 제한**: Firestore 문서는 최대 1MB입니다.
   - CSV 파일이 1MB를 초과하면 Firebase Storage를 사용해야 합니다.
   - 현재는 대부분의 CSV가 1MB 이하이므로 Firestore 사용 가능

3. **프로덕션 환경**: 반드시 role 기반 접근 제어를 적용하세요.
