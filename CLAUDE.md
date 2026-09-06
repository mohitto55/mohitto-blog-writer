# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Obsidian to GitHub Blog Publisher는 Obsidian의 마크다운 파일을 GitHub 블로그(Jekyll/Hugo 등)용 포맷으로 변환하여 자동으로 게시하는 Flutter 데스크탑 애플리케이션입니다.

핵심 기능:
- Obsidian vault에서 마크다운 파일 읽기
- Obsidian 전용 문법(WikiLinks, 이미지 embeds, callouts 등)을 GitHub 블로그 호환 마크다운으로 변환
- GitHub API를 통한 파일 및 이미지 업로드
- Frontmatter 메타데이터 매핑 (Obsidian → GitHub Blog)

## Development Commands

```bash
# 의존성 설치
cd obsidian_github_publisher
flutter pub get

# 앱 실행 (Windows)
flutter run -d windows

# 빌드 (Windows release)
flutter build windows --release

# 테스트 실행
flutter test

# 단일 테스트 파일 실행
flutter test test/models test/editor test/services

# 코드 분석
flutter analyze
```

## Architecture

프로젝트는 **Layered Architecture**를 따릅니다. 2026-09 리뉴얼로 앱의 중심이 "블로그 글 에디터"로 바뀌었습니다.

### 0. UI 구조 (lib/ui/)

```
WorkspaceScreen (screens/workspace_screen.dart)   ← 메인 셸: NavigationRail + 포스트 목록 + 에디터
├── PostEditor (screens/post_editor_screen.dart)  ← 글 한 편 편집 (메타 바 + 툴바 + 편집기/미리보기 + 상태 바)
│   ├── editor/editor_toolbar.dart                ← 서식/색상/블로그 블록/템플릿 버튼
│   ├── editor/markdown_editor.dart               ← TextField + 단축키 (Tab, Enter 목록 이어가기, Alt+↑↓ 등)
│   ├── editor/editor_actions.dart                ← TextEditingValue 순수 함수 (감싸기, 제목 토글, 블록 삽입 …)
│   ├── editor/editor_snippets.dart               ← 블로그 커스텀 태그 스니펫 (콜아웃, Reference, 색상 span …)
│   └── editor/blog_preview.dart                  ← flutter_markdown + 커스텀 문법으로 블로그처럼 렌더링
├── ObsidianImportScreen (screens/obsidian_import_screen.dart) ← 기존 Obsidian → Jekyll 변환 흐름
└── SettingsScreen
```

- **BlogRepository** (services/blog_repository.dart): 블로그 저장소 추상화. 화면과 테마 스캔은 이것만 본다.
  - `LocalBlogRepository` (데스크톱): 로컬 Jekyll 폴더. git push 는 `git_publish_flow.dart` 로 별도.
  - `GitHubBlogRepository` (모바일/웹, 또는 설정에서 선택): 트리 API 로 경로+sha 를 받고, 파일 내용은 sha 기준으로 SharedPreferences 에 캐시. 저장/삭제는 Contents API 커밋.
  - `blogRepositoryProvider` 가 플랫폼과 설정(`storage_mode` auto/local/github)으로 구현을 고른다. null 이면 "미연결" 화면.
- **UpdateService** (services/update_service.dart): `AppConstants.appRepo` 의 GitHub Releases 최신 버전과 `package_info_plus` 버전을 비교. Windows 는 zip 을 받아 PowerShell 스크립트로 덮어쓰고 재시작, Android 는 APK 링크를 연다. CI 는 `.github/workflows/release.yml`.
- 반응형: `WorkspaceScreen` 은 폭 820 미만이면 하단 탭 + 전체 화면 에디터(`_MobileEditorPage`), 아니면 NavigationRail 3열. `PostEditor` 도 폭 760 미만이면 메타 바를 세로로 쌓는다.
- Android: 프로젝트 경로에 한글이 있어 `android/gradle.properties` 에 `android.overridePathCheck=true` 가 필요하다. 릴리스 서명은 `android/key.properties` (gitignore) 가 있을 때만.
- **JekyllThemeService** (services/jekyll_theme_service.dart): 연결된 지킬 폴더를 스캔해 `JekyllTheme`을 만든다.
  - `_sass/**/*.scss` 에서 `.callout-*`, `.Reference` 클래스와 색상(border/background/header) 추출 → 툴바 블록 버튼과 미리보기 색상
  - `_config.yml` 의 `minimal_mistakes_skin` + `skins/_<skin>.scss` → 미리보기 스킨 색상
  - `_pages/categories/*.md` 의 `permalink` → 카테고리 자동완성
  - `_posts/*.md` frontmatter → 태그 자동완성, 파일명에 `템플릿`이 들어간 파일 → 템플릿 메뉴
  - `jekyllThemeProvider` (FutureProvider) 로 제공, 목록 새로고침 버튼이 `ref.invalidate` 한다.
- **JekyllPost** (models/jekyll_post.dart): `_posts` 파일 파싱/직렬화와 파일명 규칙.
  - `YYYY-MM-DD-제목.md` 게시, `mYYYY-MM-DD-…` 는 Jekyll 이 날짜를 못 읽어 숨겨지는 초안, 날짜 없는 `*템플릿*.md` 는 템플릿
  - title / categories / tags 외의 frontmatter 줄은 `extraFrontmatterLines` 로 원문 보존
- 에디터 단축키: Ctrl+S 저장, Ctrl+B/I/E 굵게/기울임/코드, Ctrl+K 링크, Ctrl+Shift+K 코드블록, Ctrl+1~4 제목, Tab/Shift+Tab 들여쓰기, Enter 목록 이어가기, Alt+↑↓ 줄 이동, Ctrl+Shift+D 줄 복제.
- 한글 IME 조합 중(`composing` 유효)에는 커스텀 키 처리를 하지 않는다 (markdown_editor.dart).

### 1. Service Layer (lib/services/)

**ObsidianService** (obsidian_service.dart)
- 로컬 Obsidian vault에서 마크다운 파일 읽기
- 파일 메타데이터 추출 (생성일, 수정일)
- Obsidian 이미지 embed 구문(`![[image.png]]`)에서 이미지 파일 경로 추출
- 이미지 파일은 두 위치에서 탐색: 노트와 같은 디렉토리 또는 `attachments/` 폴더

**ConverterService** (converter_service.dart)
- Obsidian 마크다운을 GitHub 블로그 포맷으로 변환
- `ConversionRule` 시스템을 사용한 정규식 기반 변환:
  - WikiLinks: `[[Page]]` → `[Page](page.md)`
  - Image embeds: `![[img.png]]` → `![](/assets/images/img.png)`
  - Callouts: `> [!INFO]` → HTML div 태그
  - Highlights: `==text==` → `<mark>text</mark>`
- Frontmatter YAML 파싱 및 키 매핑 (`created` → `date`)
- 블로그 포스트 파일명 생성 (`YYYY-MM-DD-slug.md`)

**GitHubService** (github_service.dart)
- GitHub REST API v3 통신 (Dio 사용)
- 파일 CRUD: `getFile()`, `createOrUpdateFile()`, `deleteFile()`
- 이미지 업로드: Base64 인코딩 후 GitHub에 commit
- SHA 기반 파일 업데이트 (충돌 방지)

**GitService** (git_service.dart) + **git_publish_flow.dart**
- 로컬 지킬 저장소에서 `git add / commit / push` 실행
- `runGitPublishFlow(context, jekyllPath)` 가 상태 확인 → 커밋 메시지 다이얼로그 → push 까지 공통 처리 (에디터/가져오기 화면 모두 사용)

**PublisherService** (publisher_service.dart)
- 전체 워크플로우 오케스트레이션:
  1. ObsidianService로 파일 읽기
  2. 이미지를 먼저 GitHub에 업로드 (경로 매핑 생성)
  3. ConverterService로 마크다운 변환 (이미지 경로 치환 포함)
  4. GitHubService로 최종 마크다운 게시

**JekyllService** (jekyll_service.dart)
- 로컬 Jekyll 블로그 관리:
  - Jekyll 서버 시작/중지 (`bundle exec jekyll serve --livereload`), `ensureRunning()` 은 이미 떠 있는 서버를 재사용
  - 변환된 마크다운을 로컬 `_posts/` 폴더에 복사
  - 이미지를 로컬 `assets/images/` 폴더에 복사 (에디터의 이미지 삽입 버튼도 사용)
  - 서버 상태 확인 (localhost:4000)
- `jekyllServiceProvider` 로 앱 전체에서 인스턴스 하나만 유지 (프로세스 핸들 보존)

**LocalPreviewService** (local_preview_service.dart)
- 로컬 미리보기 워크플로우:
  1. ObsidianService로 파일 읽기
  2. 이미지를 Jekyll assets 폴더에 복사
  3. ConverterService로 마크다운 변환
  4. Jekyll _posts 폴더에 저장
  5. Jekyll 서버 자동 시작 (실행 중이 아닌 경우)
  6. 브라우저에서 localhost:4000 열기

### 2. Data Flow

#### GitHub 게시 프로세스

```
[Obsidian .md 파일]
        ↓
[ObsidianService.readBlogPost()]
        ↓
[PublisherService._uploadImages()]  ← 이미지 선행 업로드
        ↓
[ConverterService.convertPost()]    ← imagePathMapping 적용
        ↓
[GitHubService.publishPost()]
        ↓
[GitHub Repository]
```

#### 로컬 미리보기 프로세스

```
[Obsidian .md 파일]
        ↓
[ObsidianService.readBlogPost()]
        ↓
[JekyllService.copyImageToAssets()]  ← 이미지를 로컬 assets 폴더에 복사
        ↓
[ConverterService.convertPost()]     ← 로컬 경로로 변환
        ↓
[JekyllService.saveToPostsFolder()]  ← _posts 폴더에 저장
        ↓
[JekyllService.startServer()]        ← Jekyll 서버 시작 (필요시)
        ↓
[브라우저 열기: localhost:4000]
```

### 3. Models (lib/models/)

**BlogPost** (blog_post.dart)
- 블로그 포스트 데이터 구조
- `fromMarkdown()`: 마크다운 문자열에서 생성
- `toGitHubMarkdown()`: Frontmatter + 본문을 GitHub 포맷으로 직렬화

**ConversionRule** (conversion_rule.dart)
- `pattern`: 정규식 패턴
- `replacement`: 치환 함수
- `priority`: 적용 순서 (높을수록 먼저 실행)
- `DefaultConversionRules.all()`: 기본 규칙 세트 제공

### 4. State Management

Riverpod 사용:
- `sharedPreferencesProvider`: 앱 설정 저장소 (GitHub token, repo, vault path)
- `obsidianServiceProvider`: Vault 경로 기반 ObsidianService 인스턴스
- `githubServiceProvider`: GitHub 인증 정보 기반 GitHubService 인스턴스
- `publisherServiceProvider`: 전체 서비스 조합

설정은 `SharedPreferences`에 영구 저장되며, `AppConstants`에 정의된 키로 관리됩니다.

## Key Configuration

**Frontmatter 매핑** (app_constants.dart:14-20)
```dart
frontmatterKeyMapping = {
  'created': 'date',
  'updated': 'modified',
  // ...
}
```

**이미지 탐색 경로** (obsidian_service.dart:73-95)
1. 노트와 같은 디렉토리
2. `{vaultPath}/attachments/` 폴더

**GitHub 업로드 경로**
- 포스트: `_posts/YYYY-MM-DD-{slug}.md`
- 이미지: `assets/images/{filename}`

**Jekyll 로컬 블로그 경로**
- 기본 경로: `C:\Users\admin\git\blog`
- 설정 키: `AppConstants.settingsJekyllBlogPath`
- Jekyll 서버 URL: `http://localhost:4000`
- 자동 리로드: `--livereload` 옵션 사용

**Jekyll 미리보기 사용법**
1. 앱에서 "미리보기" 버튼 클릭
2. 변환된 파일이 로컬 Jekyll 블로그의 `_posts/`에 복사됨
3. Jekyll 서버가 자동으로 시작됨 (실행 중이 아닌 경우)
4. 브라우저가 localhost:4000으로 자동 열림
5. Jekyll livereload로 파일 변경 시 자동 새로고침

## Adding New Conversion Rules

`lib/models/conversion_rule.dart`의 `DefaultConversionRules` 클래스에 새 규칙 추가:

```dart
static final yourRule = ConversionRule(
  name: 'YourRule',
  pattern: RegExp(r'your-pattern'),
  replacement: (match) => 'replacement',
  priority: 5,  // 높을수록 먼저 실행
);
```

그리고 `all()` 메서드에 포함시킵니다.

## Platform Support

현재 Windows, macOS, Linux 데스크탑만 지원합니다 (`flutter create --platforms=windows,macos,linux`).

모바일 지원이 필요하면:
1. `file_picker` 패키지가 모바일에서 디렉토리 접근 제한이 있음
2. `path_provider`로 앱 전용 디렉토리만 접근 가능
3. Obsidian vault 접근을 위한 Storage Access Framework(Android) 또는 Document Picker(iOS) 연동 필요

---

# Agent Orchestrator (PM Agent)

프로젝트 루트의 `agent_orchestrator/` 디렉토리에는 **LangGraph 기반 Agent 오케스트레이션 시스템**이 포함되어 있습니다.

## 개념

**PM Agent**는 여러 AI Agent들을 조율하여 복잡한 워크플로우를 자동화하는 시스템입니다.

### LangGraph 핵심 개념

1. **State (상태)**: 워크플로우 전체에서 공유되는 정보 파라미터
2. **Node (노드)**: 하나의 독립적인 작업 단위
3. **Edge (엣지)**: 조건에 따른 분기 처리 (브랜치)

### Why LangGraph?

Claude Code만 사용하면 프롬프트에 모든 로직과 조건을 추가해야 하므로 토큰 사용량이 많아집니다. LangGraph를 사용하면:
- 워크플로우 로직을 코드로 명시적 정의
- Agent 실행 결과에 따른 분기 처리를 Python으로 구현
- 토큰 효율성 증가 및 워크플로우 재사용성 향상

## Architecture

### 워크플로우 구조

```
[read_files] → [convert] → [upload] → END
     ↓             ↓           ↓
  [error]      [error]     [error] → END
```

각 노드는 독립적인 Agent를 실행하며, 성공/실패에 따라 다음 단계로 진행하거나 에러 처리 노드로 분기합니다.

### Agent 통신 방식 (tmux)

PM Agent는 **tmux**를 사용하여 Claude Code Agent와 통신합니다:

1. **send_to_agent**: tmux send-keys로 명령 전송
   ```bash
   tmux send-keys -t agent-session '{"command": "..."}' Enter
   ```

2. **wait_for_response**: tmux capture-pane으로 Agent 응답 캡처 후 JSON 파싱
   ```bash
   tmux capture-pane -t agent-session -p
   ```

### State Management

`PublisherState` (graph/state.py)는 워크플로우 전체 상태를 관리합니다:

```python
{
    "vault_path": str,
    "github_repo": str,
    "selected_files": List[str],
    "conversion_results": dict,
    "upload_results": dict,
    "success": bool,
    "error": Optional[str],
    "current_step": str
}
```

## PM Agent Commands

```bash
# Agent Orchestrator로 이동
cd agent_orchestrator

# 의존성 설치
pip install -r requirements.txt

# 워크플로우 실행
python main.py \
  --vault "/path/to/obsidian/vault" \
  --repo "username/blog-repo" \
  --token "ghp_xxxxx"

# 또는 환경 변수 사용
export GITHUB_TOKEN=ghp_xxxxx
python main.py --vault "/path/to/vault" --repo "user/repo"

# 워크플로우 그래프 시각화
python main.py --visualize
```

## Agent Orchestrator 파일 구조

```
agent_orchestrator/
├── main.py                 # PM Agent 메인 스크립트
├── requirements.txt        # Python 의존성 (langgraph, langchain 등)
├── graph/
│   ├── state.py           # PublisherState 정의
│   └── workflow.py        # LangGraph 워크플로우 정의
│       - read_obsidian_files()
│       - convert_markdown()
│       - upload_to_github()
│       - handle_error()
│       - route_after_read/convert/upload()
└── agents/
    └── agent_utils.py     # Agent 통신 유틸리티
        - AgentCommunicator 클래스
        - send_to_agent()
        - wait_for_response()
```

## Workflow Nodes

각 노드는 `execute_agent_task()`를 호출하여 해당 Agent에게 작업을 위임합니다:

1. **read_files** (read_obsidian_files):
   - Obsidian vault에서 마크다운 파일 목록 읽기
   - Agent 세션: `obsidian-agent`

2. **convert** (convert_markdown):
   - Obsidian 마크다운을 GitHub 블로그 포맷으로 변환
   - Agent 세션: `converter-agent`

3. **upload** (upload_to_github):
   - 변환된 파일을 GitHub에 업로드
   - Agent 세션: `github-agent`

4. **error** (handle_error):
   - 에러 로깅 및 정리

## Conditional Edges

각 노드 실행 후 `route_after_*()` 함수가 다음 단계를 결정합니다:

```python
def route_after_read(state: PublisherState) -> Literal["convert", "error"]:
    if state["success"] and state.get("selected_files"):
        return "convert"  # 성공 → 변환 단계로
    return "error"        # 실패 → 에러 처리
```

## Agent Session 관리

PM Agent 실행 전에 각 Agent 세션이 tmux에서 실행되어 있어야 합니다:

```bash
# Agent 세션 생성 예시
tmux new-session -d -s obsidian-agent
tmux new-session -d -s converter-agent
tmux new-session -d -s github-agent

# 세션 확인
tmux list-sessions

# 특정 세션에 attach
tmux attach -t obsidian-agent
```

## Extending the Workflow

새로운 노드 추가 예시 (workflow.py):

```python
def validate_posts(state: PublisherState) -> PublisherState:
    """포스트 검증 노드"""
    response = execute_agent_task(
        "Validate converted posts",
        session_name="validator-agent"
    )
    # ... 처리 로직
    return state

# 워크플로우에 추가
workflow.add_node("validate", validate_posts)
workflow.add_edge("convert", "validate")
workflow.add_edge("validate", "upload")
```

## Integration with Flutter App

현재는 독립적으로 실행되지만, Flutter 앱과 통합하려면:

1. **Option 1**: Flutter에서 Python 스크립트를 subprocess로 실행
2. **Option 2**: REST API 서버로 PM Agent를 감싸서 Flutter가 HTTP로 호출
3. **Option 3**: CLI 인터페이스를 통한 통합

## 참고 자료

- LangGraph 공식 문서: https://langchain-ai.github.io/langgraph/
- tmux 사용법: https://github.com/tmux/tmux/wiki
