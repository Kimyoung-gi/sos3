# Firestore 권한 오류 해결 가이드

## 🚨 CSV 업로드 권한 오류 (Missing or insufficient permissions)

**증상**: 관리자로 로그인 후 `customerlist.csv` 등 CSV 업로드 시  
`[cloud_firestore/permission-denied] Missing or insufficient permissions` 발생.

**원인**: Firestore 규칙에서 `request.auth.token.role == 'admin'`을 요구하는데,  
Firebase Auth **커스텀 클레임(role)** 이 설정되어 있지 않아 거부됨.

**해결**: 아래 "Firebase Console에서 Firestore 규칙 수정"을 따라  
**개발/테스트용 규칙**을 한 번 적용하면 CSV 업로드·이력·홈 프로모션이 동작합니다.

---

## 🚨 문제: 홈 화면에 배너가 표시되지 않음

관리자 사이트에서 이미지를 등록했는데 홈 화면에 표시되지 않는 경우, Firestore 보안 규칙에 `home_promotions` 컬렉션 규칙이 없어서 발생할 수 있습니다.

## 빠른 해결 방법

### Firebase Console에서 Firestore 규칙 수정

1. **Firebase Console 접속**: https://console.firebase.google.com
2. **프로젝트 선택**: SOS 2.0 프로젝트
3. **Firestore Database 메뉴 클릭**
4. **Rules 탭 클릭**
5. **기존 Rules 내용을 전부 지우고**, 아래 규칙을 **통째로** 복사해 붙여넣기 (개발/테스트용):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // CSV 파일 저장소 (업로드 시 permission-denied 해결)
    match /csv_files/{filename} {
      allow read, write: if true;
    }
    
    // CSV 업로드 이력
    match /csv_upload_history/{document} {
      allow read, write: if true;
    }
    
    // 홈 프로모션 배너
    match /home_promotions/{document} {
      allow read, write: if true;
    }
    
    // users 컬렉션 (앱에서 사용 시)
    match /users/{userId} {
      allow read, write: if true;
    }
  }
}
```

6. **"게시" 버튼 클릭**
7. 1~2분 후 앱에서 CSV 업로드 다시 시도

## ⚠️ 보안 주의사항

위 규칙(`if true`)은 **모든 사용자(인증 없이도)**에게 읽기/쓰기 권한을 부여합니다. 
**개발/테스트 환경에서만 사용**하세요.

### 프로덕션 규칙 (Firebase Authentication 연동 후 사용)

프로덕션 환경에서는 Firebase Authentication을 연동한 후 다음 규칙을 사용하세요:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // 홈 프로모션 배너
    match /home_promotions/{document} {
      // 읽기: 모든 인증된 사용자 허용
      allow read: if request.auth != null;
      
      // 쓰기: 관리자만 허용
      allow write: if request.auth != null 
        && request.auth.token.role == 'admin';
    }
  }
}
```

## 확인 사항

규칙 적용 후:
1. 앱을 재시작하거나 새로고침
2. 홈 화면으로 이동
3. 콘솔 로그 확인:
   - `📡 배너 스트림 구독 시작`
   - `📦 배너 스냅샷 수신: 문서 개수=X`
   - `📋 배너 데이터: docId=..., imageUrl=...`
   - `✅ 배너 URL 목록: X개`

로그가 정상적으로 출력되면 Firestore 연결은 성공한 것입니다.
