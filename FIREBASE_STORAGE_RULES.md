# Firebase Storage 보안 규칙 및 CORS 설정

## ⚠️ 중요: Flutter Web CORS 설정 필수

Flutter Web에서 Firebase Storage를 사용할 때는 **CORS 설정이 반드시 필요**합니다.
`getData()` 메서드도 내부적으로 HTTP 요청을 사용하므로 CORS 헤더가 없으면 차단됩니다.

### CORS 설정 방법

#### 방법 1: gsutil 사용 (권장)

1. **Google Cloud SDK 설치** (gsutil 포함)
   - Windows: https://cloud.google.com/sdk/docs/install
   - 또는 Firebase CLI 사용: `firebase init storage`

2. **프로젝트 루트에 `cors.json` 파일 생성** (이미 생성됨)

3. **CORS 설정 적용**:
```bash
# 프로젝트 루트에서 실행
gsutil cors set cors.json gs://sos2-49d94.firebasestorage.app
```

#### 방법 2: Firebase Console 사용

1. Firebase Console > Storage > Settings 이동
2. CORS 탭 클릭
3. 다음 JSON 입력:
```json
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD", "PUT", "POST", "DELETE"],
    "maxAgeSeconds": 3600,
    "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"]
  }
]
```
4. 저장

#### 방법 3: gcloud CLI 사용

```bash
# gcloud CLI 설치 후
gcloud storage buckets update gs://sos2-49d94.firebasestorage.app --cors-file=cors.json
```

**주의**: 
- `origin: ["*"]`는 모든 도메인을 허용합니다. 프로덕션에서는 특정 도메인만 허용하세요.
- 예: `"origin": ["https://yourdomain.com", "http://localhost:5173"]`

### 임시 테스트 규칙 (업로드 문제 해결용)

업로드가 `unauthorized` 오류로 실패하는 경우, 먼저 아래 임시 규칙을 적용하여 테스트하세요:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

**주의**: 이 규칙은 모든 인증된 사용자에게 읽기/쓰기 권한을 부여합니다. 테스트 후 반드시 아래 프로덕션 규칙으로 변경하세요.

## CSV 파일 업로드/다운로드 규칙 (프로덕션)

Firebase Console > Storage > Rules에서 다음 규칙을 적용하세요:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // CSV 파일 경로
    match /csv/{filename} {
      // 읽기: 모든 인증된 사용자 허용
      allow read: if request.auth != null;
      
      // 쓰기: 관리자만 허용
      allow write: if request.auth != null 
        && request.auth.token.role == 'admin';
      
      // 삭제: 관리자만 허용
      allow delete: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
    
    // 기타 파일 경로는 기본적으로 거부
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

## Firestore 보안 규칙

Firebase Console > Firestore > Rules에서 다음 규칙을 적용하세요:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
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
    
    // 기타 컬렉션 규칙...
  }
}
```

## 참고사항

1. **Custom Claims 설정**: Firebase Authentication에서 사용자에게 `role` custom claim을 설정해야 합니다.
   - 관리자: `{ role: 'admin' }`
   - 일반 사용자: `{ role: 'user' }`

2. **테스트 환경**: 개발 중에는 다음 규칙으로 모든 인증된 사용자에게 허용할 수 있습니다:
   ```javascript
   allow read, write: if request.auth != null;
   ```

3. **프로덕션 환경**: 반드시 role 기반 접근 제어를 적용하세요.
