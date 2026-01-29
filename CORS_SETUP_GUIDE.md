# Firebase Storage CORS 설정 가이드

## ⚠️ 배너 이미지가 안 나오고 "statusCode: 0" 에러가 날 때

웹에서 Firebase Storage 이미지를 불러올 때 **CORS** 때문에 브라우저가 요청을 막으면 `statusCode: 0`이 납니다.  
아래 **방법 1(Google Cloud Shell)** 또는 **방법 2(gsutil)** 로 버킷에 CORS를 한 번 적용하면 됩니다.

---

## 현재 상태
- ❌ CORS 오류 발생 중
- ✅ Assets fallback으로 정상 동작 중
- ⚠️ Firebase Storage에서 직접 로드하려면 CORS 설정 필요

## CORS 설정 방법

### 방법 1: Google Cloud Shell 사용 (설치 없음, 권장)

1. **Google Cloud Console** 접속: https://console.cloud.google.com  
2. 상단에서 프로젝트 **sos2-49d94** 선택  
3. 오른쪽 상단 **터미널 아이콘(>_)** 클릭 → **Cloud Shell** 열기  
4. 아래 명령을 **한 번에** 복사해서 붙여넣고 실행:

```bash
echo '[{"origin": ["*"],"method": ["GET", "HEAD", "PUT", "POST", "DELETE"],"maxAgeSeconds": 3600,"responseHeader": ["Content-Type", "Access-Control-Allow-Origin"]}]' > cors.json && gsutil cors set cors.json gs://sos2-49d94.firebasestorage.app && gsutil cors get gs://sos2-49d94.firebasestorage.app
```

5. `CORS configuration updated` 비슷한 메시지가 나오면 성공  
6. 브라우저 **캐시 삭제**(Ctrl+Shift+Delete) 후 앱 새로고침

### 방법 2: gsutil 사용 (PC에 SDK 설치)

#### 1단계: Google Cloud SDK 설치
- Windows: https://cloud.google.com/sdk/docs/install
- 설치 후 PowerShell 또는 CMD에서 `gsutil version` 명령으로 확인

#### 2단계: 인증 설정
```bash
gcloud auth login
gcloud config set project sos2-49d94
```

#### 3단계: CORS 설정 적용
프로젝트 루트 디렉토리(`C:\flutter\project\first_app`)에서 실행:
```bash
gsutil cors set cors.json gs://sos2-49d94.firebasestorage.app
```

#### 4단계: 확인
```bash
gsutil cors get gs://sos2-49d94.firebasestorage.app
```

### 방법 3: Firebase Console 사용 (간단하지만 제한적)

1. Firebase Console 접속: https://console.firebase.google.com
2. 프로젝트 선택: `sos2-49d94`
3. 왼쪽 메뉴에서 **Storage** 클릭
4. **Settings** (톱니바퀴 아이콘) 클릭
5. **CORS** 탭 클릭
6. `cors.json` 파일 내용을 복사하여 붙여넣기:
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
7. **Save** 버튼 클릭

**주의**: Firebase Console의 CORS 설정은 일부 기능이 제한될 수 있습니다. gsutil 사용을 권장합니다.

### 방법 4: gcloud CLI 사용

```bash
# gcloud CLI 설치 후
gcloud storage buckets update gs://sos2-49d94.firebasestorage.app --cors-file=cors.json
```

## 설정 후 확인

1. 브라우저 캐시 클리어 (Ctrl+Shift+Delete)
2. 앱 재시작: `flutter run -d chrome --web-port 5173`
3. 콘솔에서 다음 로그 확인:
   ```
   ✅ Firebase Storage SDK에서 로드 성공: customerlist.csv (xxx bytes)
   ```
4. `📦 Assets에서 로드 시도` 메시지가 나오지 않으면 성공

## 프로덕션 환경 권장 설정

개발 환경에서는 `origin: ["*"]`를 사용해도 되지만, 프로덕션에서는 특정 도메인만 허용하세요:

```json
[
  {
    "origin": [
      "https://yourdomain.com",
      "https://www.yourdomain.com",
      "http://localhost:5173"
    ],
    "method": ["GET", "HEAD", "PUT", "POST", "DELETE"],
    "maxAgeSeconds": 3600,
    "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"]
  }
]
```

## 문제 해결

### CORS 설정이 적용되지 않는 경우

1. **설정 확인**:
   ```bash
   gsutil cors get gs://sos2-49d94.firebasestorage.app
   ```

2. **브라우저 캐시 클리어**: CORS 설정은 브라우저에 캐시될 수 있습니다.

3. **설정 재적용**:
   ```bash
   gsutil cors set cors.json gs://sos2-49d94.firebasestorage.app
   ```

4. **Firebase Storage Rules 확인**: Rules에서 읽기 권한이 있는지 확인

### 여전히 CORS 오류가 발생하는 경우

1. `cors.json` 파일 형식 확인 (JSON 유효성)
2. Firebase 프로젝트 ID 확인 (`sos2-49d94`)
3. Storage 버킷 이름 확인 (`gs://sos2-49d94.firebasestorage.app`)

## 참고

- CORS 설정은 Storage 버킷 레벨에서 적용됩니다.
- 설정 변경 후 즉시 반영되지만, 브라우저 캐시로 인해 지연될 수 있습니다.
- 현재는 assets fallback으로 정상 동작하므로, CORS 설정은 선택사항입니다.
- 하지만 Firebase Storage를 사용하려면 반드시 필요합니다.
