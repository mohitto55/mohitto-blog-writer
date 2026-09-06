# Mohitto Blog Writer

Jekyll(minimal-mistakes) 블로그 글을 쓰는 앱. Windows / Android / 웹(PWA) 에서 같은 코드로 동작한다.

- **Windows**: 로컬에 clone 한 블로그 폴더에 저장하고, Jekyll 서버 미리보기와 git push 를 앱에서 처리
- **Android / 웹**: GitHub API 로 저장소를 직접 읽고, 저장 = 커밋. GitHub Pages 가 자동으로 다시 빌드
- 블로그의 SCSS 를 스캔해 커스텀 콜아웃(`callout-*`, `Reference`)을 툴바 버튼과 미리보기 색상으로 반영
- 라이브 편집: 블로그 모양으로 렌더링된 페이지에서 클릭한 문단만 원문으로 편집

## 개발

```bash
flutter pub get
flutter run -d windows        # 데스크톱
flutter run -d chrome         # 웹
flutter build apk --release   # Android (android/key.properties 가 있으면 릴리스 키로 서명)
flutter test
```

> 이 PC 에서는 Visual Studio 2026 때문에 `flutter build windows` 가 실패한다. VS 2022 의 CMake 로 직접 빌드한다:
> `cmake -G "Visual Studio 17 2022" -A x64 -S windows -B build\windows\x64` →
> `cmake --build build\windows\x64 --config Release --target INSTALL`

## 배포 / 자동 업데이트

앱 소스를 GitHub 저장소 `AppConstants.appRepo` (`lib/core/constants/app_constants.dart`) 에 올리면
`.github/workflows/release.yml` 이 다음을 자동으로 한다.

1. `git tag v1.0.1 && git push --tags` → Windows zip, Android APK 를 **GitHub Release** 에 첨부
2. 웹 빌드를 `gh-pages` 브랜치에 배포 → `https://<owner>.github.io/<repo>/` 에서 PWA 로 사용 (폰에서 "홈 화면에 추가")
3. 앱은 시작할 때 `releases/latest` 를 확인해 새 버전이 있으면 상단 배너로 알린다.
   - Windows: 배너의 "업데이트" 를 누르면 zip 을 받아 설치 폴더에 덮어쓰고 재시작
   - Android: APK 다운로드 페이지가 열리고 설치하면 됨 (같은 서명 키여야 덮어쓰기 설치 가능)
   - 웹: 새로고침이 곧 업데이트

### 처음 한 번 해야 할 것

```bash
cd obsidian_github_publisher
git init
git add .
git commit -m "Mohitto Blog Writer"
gh repo create mohitto55/mohitto-blog-writer --private --source=. --push   # 이름을 바꾸면 AppConstants.appRepo 도 수정
```

GitHub 저장소 설정:

- **Settings → Pages**: Source = Deploy from a branch, Branch = `gh-pages` (첫 릴리스 워크플로가 브랜치를 만든 뒤 설정)
- **Settings → Secrets and variables → Actions**: `powershell -File tool/print_android_secrets.ps1` 가 출력하는
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS` 등록.
  `android/app/upload-keystore.jks` 와 `android/key.properties` 는 `.gitignore` 에 있으므로 잃어버리지 않게 따로 백업한다.

### 폰(Android)에서 설정

1. GitHub → Settings → Developer settings → **Fine-grained personal access token** 생성.
   Repository access: 블로그 저장소만, Permissions: **Contents: Read and write**.
2. 앱 설정에서 사용자명 `mohitto55`, 저장소 `mohitto55.github.io`, 토큰 입력 → "연결 테스트" → 저장.
3. 첫 목록 로딩은 포스트 수만큼 API 요청을 하지만, 이후에는 sha 기준 캐시 덕분에 바뀐 파일만 다시 받는다.
