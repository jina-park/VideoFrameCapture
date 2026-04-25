# VideoFrameCapture

영상의 특정 프레임을 원본 해상도 JPEG로 캡쳐하고, 정확한 타임스탬프 EXIF와 함께 사진 앱에 저장하는 iOS/iPadOS 앱.

## 주요 기능

- 사진 앱 또는 파일 앱에서 영상 불러오기
- 프레임 단위 탐색 (슬라이더, 이전/다음 프레임, ±1/5/10초 점프)
- 원본 해상도 프레임 캡쳐 (다운스케일 없음)
- 파일명: `{영상명}_{000000}` (6자리 제로패딩)
- EXIF 날짜: 영상 파일 수정일 + 프레임 타임스탬프
- 사진 앱에 저장 (`.addOnly` 권한, 기존 라이브러리 접근 불가)
- iPhone / iPad / Mac Catalyst 지원
- 4K · 60fps · 120fps · 240fps 슬로우모션 지원

## 요구 사항

| 항목 | 버전 |
|------|------|
| iOS 배포 대상 | 16.0 이상 |
| Swift | 5.9 |
| Xcode | 15 이상 |
| xcodegen | 2.x (프로젝트 생성용) |

## 빌드 방법

```bash
# xcodegen 없으면 자동 설치 후 .xcodeproj 생성
./setup.sh
```

또는 xcodegen이 이미 설치된 경우:

```bash
xcodegen generate
open VideoFrameCapture.xcodeproj
```

Xcode에서 Signing & Capabilities → Team 설정 후 ⌘+R.

## 프로젝트 구조

```
VideoFrameCapture/
├── VideoFrameCaptureApp.swift   # @main 진입점
├── ContentView.swift            # 홈 화면, 영상 선택
├── VideoPlayerView.swift        # 플레이어 + 캡쳐 UI 전체
├── VideoInfo.swift              # 영상 메타데이터 모델
├── FrameExtractor.swift         # AVAssetImageGenerator 래퍼
├── MetadataWriter.swift         # JPEG EXIF 임베딩
├── PhotoSaver.swift             # PHPhotoLibrary 저장
├── DocumentPicker.swift         # 파일 앱 피커 UIViewControllerRepresentable
├── Assets.xcassets/
└── Info.plist
project.yml                      # xcodegen 설정
setup.sh                         # 빌드 환경 초기화 스크립트
```

## 파일별 역할

### `VideoInfo.swift`
영상 메타데이터를 담는 값 타입(`struct`).

| 프로퍼티/메서드 | 설명 |
|---|---|
| `resolution`, `frameRate`, `duration` | 해상도, 프레임레이트, 길이 |
| `totalFrames` | 전체 프레임 수 |
| `timeForFrame(_:)` | 프레임 번호 → `CMTime` |
| `frameForTime(_:)` | `CMTime` → 프레임 번호 |
| `captureFileName(for:)` | `영상명_000123` 형태 파일명 생성 |
| `formatTime(seconds:)` | `HH:mm:ss.mmm` 형식 시각 문자열 |

### `FrameExtractor.swift`
- `load(url:)` — AVURLAsset에서 해상도·프레임레이트·수정일을 비동기 로드, `AVAssetImageGenerator` 초기화
- `extractFrame(at:)` — `generateCGImagesAsynchronously`를 `withCheckedThrowingContinuation`으로 래핑, tolerance = `.zero`로 정확한 프레임 추출
- `maximumSize = .zero` → 다운스케일 없이 원본 해상도 반환

### `MetadataWriter.swift`
- `createJPEGData(from:videoModificationDate:frameTimestamp:)`
- `CGImageDestination` + `kCGImagePropertyExifDictionary`로 EXIF 날짜 임베딩
- EXIF 날짜 = 영상 수정일 + 프레임 오프셋(초)
- 날짜 형식: `yyyy:MM:dd HH:mm:ss` (EXIF 표준, 날짜 구분자도 콜론)

### `PhotoSaver.swift`
- `PHPhotoLibrary.requestAuthorization(for: .addOnly)` — 기존 사진 접근 불가, 추가 전용
- `PHAssetCreationRequest` + `originalFilename`으로 지정 파일명으로 저장

### `DocumentPicker.swift`
- `UIDocumentPickerViewController` 래퍼
- 보안 스코프 접근 후 임시 디렉터리로 복사 → 세션 종료 후에도 파일 접근 유지

### `ContentView.swift`
- `PhotosPicker`(`.movies`)와 `DocumentPicker` 두 가지 진입점 제공
- `VideoFile: Transferable` — `.movie`, `.video`, `.audiovisualContent` 세 타입 처리
- 영상 선택 시 NavigationStack 루트를 `VideoPlayerView`로 교체

### `VideoPlayerView.swift`
- `PlayerLayerView` (`UIView` 서브클래스) — `AVPlayerLayer`를 sublayer로 추가, `layoutSubviews`에서 `CATransaction.setDisableActions(true)`로 즉시 레이아웃 반영
- `VideoPlayerViewModel` (`@MainActor ObservableObject`)
  - `loadVideo(url:)` — `waitForPlayerItemReady()` KVO 대기 후 seek
  - `seekToFrame(_:)` / `seekBySeconds(_:)` — tolerance `.zero` 정밀 탐색
  - `captureCurrentFrame()` — `FrameExtractor.extractFrame` 호출
  - `saveCapture()` — `MetadataWriter` + `PhotoSaver` 연계 저장
- `CapturePreviewSheet` — 캡쳐 미리보기 시트 (파일명, 타임스탬프 표시)

## 권한

| 키 | 용도 |
|---|---|
| `NSPhotoLibraryUsageDescription` | 사진 앱에서 영상 불러오기 |
| `NSPhotoLibraryAddUsageDescription` | 캡쳐 이미지 사진 앱에 저장 |

## 개발 중 주요 해결 사항

| 문제 | 원인 | 해결 |
|---|---|---|
| `.onChange` 빌드 오류 | iOS 17 전용 두 파라미터 시그니처 사용 | 단일 파라미터 `{ newItem in }` 로 교체 |
| `ContentUnavailableView` 빌드 오류 | iOS 17 전용 API | 커스텀 VStack으로 교체 |
| Sendable 경고 | `addPeriodicTimeObserver` 클로저 actor 격리 | `MainActor.assumeIsolated { }` 로 래핑 |
| `seek` 누락 `await` | `player.seek(to:toleranceBefore:toleranceAfter:)` 비동기 | `await` 추가 |
| 영상 까만 화면 | AVPlayerLayer 레이아웃 미반영 | `CATransaction.setDisableActions(true)` 추가 |
| `fullScreenCover` 무반응 | PhotosPicker 해제와 시트 표시 충돌 | NavigationStack 루트 교체 방식으로 변경 |
| `.task` 미실행 | NavigationStack 루트 교체 시 `.task` 미발동 | `.onAppear { Task { ... } }` 로 교체 |
