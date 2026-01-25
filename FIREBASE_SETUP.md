# Firebase 설정 가이드

## 1. Firebase 프로젝트 생성

1. [Firebase Console](https://console.firebase.google.com/)에 접속
2. "프로젝트 추가" 클릭
3. 프로젝트 이름 입력 (예: `sos2-0`)
4. Google Analytics 설정 (선택사항)

## 2. Firebase Web App 추가

1. Firebase 프로젝트 대시보드에서 "웹" 아이콘 클릭 (`</>`)
2. 앱 닉네임 입력 (예: `SOS2.0 Web`)
3. "Firebase Hosting도 설정" 체크 해제 (선택사항)
4. "앱 등록" 클릭
5. **Firebase 구성 정보 복사** (다음 단계에서 사용)

## 3. Flutter 앱에 Firebase 구성 정보 추가

### 방법 1: `lib/main.dart`에 직접 추가 (개발용)

`lib/main.dart`의 `main()` 함수에서 Firebase 초기화 부분을 찾아 실제 값으로 교체:

```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: 'YOUR_API_KEY',              // 실제 API 키로 교체
    appId: 'YOUR_APP_ID',                // 실제 App ID로 교체
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',  // 실제 Sender ID로 교체
    projectId: 'YOUR_PROJECT_ID',        // 실제 Project ID로 교체
    storageBucket: 'YOUR_STORAGE_BUCKET', // 실제 Storage Bucket으로 교체 (예: sos2-0.appspot.com)
  ),
);
```

### 방법 2: 환경 변수 사용 (프로덕션 권장)

`.env` 파일을 사용하거나 빌드 시점에 주입하는 방식으로 구성 정보를 관리하는 것을 권장합니다.

## 4. Firebase Storage 설정

### 4.1 Storage 버킷 생성

1. Firebase Console > Storage
2. "시작하기" 클릭
3. 보안 규칙 선택 (다음 단계에서 수정)
4. 위치 선택 (가장 가까운 리전)

### 4.2 Storage 폴더 구조 생성

Storage 콘솔에서 다음 폴더 구조를 생성:

```
/csv/
  ├── customerlist.csv
  ├── kpi-info.csv
  ├── kpi_it.csv
  ├── kpi_itr.csv
  ├── kpi_mobile.csv
  └── kpi_etc.csv
```

**참고**: 실제 파일은 관리자 페이지에서 업로드하므로, 빈 폴더만 생성하거나 초기 샘플 파일을 업로드할 수 있습니다.

### 4.3 Storage Security Rules

Firebase Console > Storage > Rules 탭에서 다음 규칙 적용:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // CSV 파일 읽기: 인증된 사용자 모두 가능
    match /csv/{fileName} {
      allow read: if request.auth != null;
      
      // CSV 파일 쓰기: 관리자만 가능
      allow write: if request.auth != null 
                   && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'ADMIN';
    }
    
    // 기타 파일은 기본적으로 거부
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

**참고**: 위 규칙은 Firestore에 `users` 컬렉션이 있고 각 문서에 `role` 필드가 있다고 가정합니다. 
현재 프로젝트는 `shared_preferences`를 사용하므로, 실제로는 Firebase Authentication과 Firestore를 연동하거나 
별도의 인증 체계를 구축해야 합니다.

**임시 규칙 (개발용 - 보안 주의)**:
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /csv/{fileName} {
      allow read: if true;  // 모든 사용자 읽기 가능 (개발용)
      allow write: if request.auth != null;  // 인증된 사용자만 쓰기 (프로덕션에서는 관리자만)
    }
  }
}
```

## 5. Firestore 설정

### 5.1 Firestore 데이터베이스 생성

1. Firebase Console > Firestore Database
2. "데이터베이스 만들기" 클릭
3. "프로덕션 모드에서 시작" 선택 (또는 "테스트 모드" - 개발용)
4. 위치 선택 (Storage와 동일한 리전 권장)

### 5.2 Firestore Security Rules

Firebase Console > Firestore Database > Rules 탭에서 다음 규칙 적용:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // CSV 업로드 히스토리
    match /csv_upload_history/{historyId} {
      // 읽기: 관리자만
      allow read: if request.auth != null 
                  && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'ADMIN';
      
      // 쓰기: 관리자만
      allow write: if request.auth != null 
                   && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'ADMIN';
    }
    
    // 기타 문서는 기본적으로 거부
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

**임시 규칙 (개발용 - 보안 주의)**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /csv_upload_history/{historyId} {
      allow read, write: if request.auth != null;  // 인증된 사용자만 (프로덕션에서는 관리자만)
    }
  }
}
```

## 6. Firebase Authentication 설정 (선택사항)

현재 프로젝트는 `shared_preferences` 기반 인증을 사용하지만, 
Firebase Storage/Firestore 규칙에서 `request.auth`를 사용하려면 
Firebase Authentication을 활성화해야 합니다.

### 6.1 Authentication 활성화

1. Firebase Console > Authentication
2. "시작하기" 클릭
3. "이메일/비밀번호" 제공업체 활성화 (또는 필요한 인증 방식)

### 6.2 Flutter 앱에서 Firebase Auth 연동

`lib/services/auth_service.dart`를 수정하여 Firebase Auth와 연동하거나,
현재 인증 시스템을 유지하면서 Storage/Firestore 규칙을 조정해야 합니다.

**임시 해결책**: Storage/Firestore 규칙을 개발용으로 완화 (위의 "임시 규칙" 참조)

## 7. 테스트 절차

### 7.1 패키지 설치

```bash
flutter pub get
```

### 7.2 Firebase 초기화 확인

앱 실행 시 콘솔에 다음 메시지가 표시되어야 합니다:
```
✅ Firebase 초기화 완료
```

### 7.3 CSV 업로드 테스트

1. 관리자 계정으로 로그인 (`id=1111/pw=1111/role=ADMIN`)
2. 관리자 대시보드 > "CSV 업로드" 탭 이동
3. 각 CSV 파일을 개별적으로 업로드:
   - `customerlist.csv`
   - `kpi-info.csv`
   - `kpi_it.csv`
   - `kpi_itr.csv`
   - `kpi_mobile.csv`
   - `kpi_etc.csv`
4. 업로드 성공 메시지 확인
5. "즉시 반영 테스트" 버튼 클릭하여 재로딩 확인

### 7.4 화면 반영 확인

1. **고객사 메뉴**: 업로드한 `customerlist.csv` 데이터가 표시되는지 확인
2. **프론티어 메뉴**: 업로드한 `kpi-info.csv`, `kpi_*.csv` 데이터가 표시되는지 확인
3. **대시보드**: 모든 CSV 데이터가 조합되어 표시되는지 확인

### 7.5 Fallback 동작 확인

1. Firebase Storage에서 CSV 파일 삭제
2. 앱 재시작 또는 해당 메뉴 진입
3. Assets의 기본 CSV가 로드되는지 확인 (콘솔 로그 확인)

## 8. 흔한 오류 및 대응

### 8.1 "Firebase.initializeApp()" 오류

**원인**: Firebase 구성 정보가 잘못되었거나 누락됨

**해결**:
- `lib/main.dart`의 Firebase 초기화 코드 확인
- Firebase Console에서 실제 구성 정보 복사하여 교체

### 8.2 "Permission denied" (Storage/Firestore)

**원인**: Security Rules가 너무 제한적이거나 인증이 안 됨

**해결**:
- Firebase Console > Storage/Firestore > Rules 확인
- 개발 단계에서는 임시 규칙 사용 (프로덕션에서는 반드시 제한적 규칙 적용)
- Firebase Authentication 활성화 및 로그인 확인

### 8.3 "CSV 파일을 로드할 수 없습니다"

**원인**: 
- Firebase Storage에 파일이 없고 assets에도 없음
- 네트워크 오류
- 파일 경로 오류

**해결**:
- Firebase Storage에 파일 업로드 확인
- `assets/` 폴더에 기본 CSV 파일 존재 확인
- 브라우저 콘솔에서 네트워크 오류 확인

### 8.4 CORS 오류 (웹)

**원인**: Firebase Storage CORS 설정 문제

**해결**:
- Firebase Storage는 기본적으로 CORS를 지원하므로 일반적으로 문제 없음
- 문제가 지속되면 Firebase Console > Storage > Settings에서 CORS 설정 확인

### 8.5 캐시 문제

**원인**: 브라우저가 이전 CSV를 캐시함

**해결**:
- `CsvService`가 자동으로 타임스탬프 쿼리 파라미터를 추가하여 캐시 방지
- 업로드 후 "즉시 반영 테스트" 버튼 사용
- 브라우저 강력 새로고침 (Ctrl+Shift+R 또는 Cmd+Shift+R)

## 9. 프로덕션 배포 전 체크리스트

- [ ] Firebase 구성 정보를 환경 변수로 관리
- [ ] Storage Security Rules를 관리자만 쓰기 가능하도록 제한
- [ ] Firestore Security Rules를 관리자만 접근 가능하도록 제한
- [ ] Firebase Authentication과 현재 인증 시스템 연동 (또는 규칙 조정)
- [ ] 모든 CSV 파일이 Firebase Storage에 업로드됨
- [ ] Fallback 동작 테스트 완료
- [ ] 업로드 히스토리가 Firestore에 정상 기록되는지 확인
- [ ] 에러 처리 및 사용자 피드백 확인

## 10. 추가 참고사항

- Firebase Storage 무료 할당량: 5GB 저장, 1GB/일 다운로드
- Firestore 무료 할당량: 1GB 저장, 50K 읽기/일, 20K 쓰기/일
- 프로덕션 환경에서는 반드시 보안 규칙을 엄격하게 설정하세요.
