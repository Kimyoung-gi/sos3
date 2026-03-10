# Firebase Storage 권한 오류 해결 가이드

## 🚨 오류: `[firebase_storage/unauthorized] User is not authorized`

이 오류는 Firebase Storage 보안 규칙에서 해당 경로에 대한 쓰기 권한이 없어서 발생합니다.
- **CSV 대용량 업로드**(1MB 초과) 시 사용하는 경로: `csv_files/파일명`
- 배너 이미지 경로: `home_promotions/파일명`

**⚠️ 중요**: 현재 프로젝트는 Firebase Authentication을 사용하지 않고 SharedPreferences 기반 인증을 사용합니다. 따라서 `request.auth != null` 조건이 항상 false가 됩니다.

## 빠른 해결 방법 (개발/테스트용)

### Firebase Console에서 Storage 규칙 수정

1. **Firebase Console 접속**: https://console.firebase.google.com
2. **프로젝트 선택**: SOS 2.0 프로젝트
3. **Storage 메뉴 클릭**
4. **Rules 탭 클릭**
5. **다음 규칙을 복사하여 붙여넣기** (인증 없이 허용 - 개발용):

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // CSV 파일 경로 (관리자 업로드 - 1MB 초과 시 사용)
    match /csv_files/{filename} {
      allow read, write: if true;
    }
    // 레거시 CSV 경로
    match /csv/{filename} {
      allow read, write: if true;
    }
    
    // 홈 프로모션 배너 이미지 경로
    match /home_promotions/{filename} {
      allow read: if true;
      allow write: if true;
      allow delete: if true;
    }
    
    // 기타 경로는 거부
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

6. **"게시" 버튼 클릭**

**⚠️ 보안 주의**: 위 규칙은 모든 사용자에게 읽기/쓰기 권한을 부여합니다. 개발/테스트 환경에서만 사용하세요.

## ⚠️ 보안 주의사항

위 규칙(`if true`)은 **모든 사용자(인증 없이도)**에게 읽기/쓰기 권한을 부여합니다. 
**개발/테스트 환경에서만 사용**하세요.

### 프로덕션 규칙 (Firebase Authentication 연동 후 사용)

프로덕션 환경에서는 Firebase Authentication을 연동한 후 다음 규칙을 사용하세요:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // CSV 파일 경로 (1MB 초과 대용량 업로드)
    match /csv_files/{filename} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
    match /csv/{filename} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
    
    // 홈 프로모션 배너 이미지 경로
    match /home_promotions/{filename} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
        && request.auth.token.role == 'admin';
      allow delete: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
    
    // 기타 경로는 거부
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

**참고**: 프로덕션 규칙을 사용하려면:
1. Firebase Authentication을 프로젝트에 연동
2. 사용자에게 Custom Claims로 `role: 'admin'` 설정
3. AuthService를 Firebase Auth와 연동

현재는 개발 환경이므로 `if true` 규칙을 사용하세요.
