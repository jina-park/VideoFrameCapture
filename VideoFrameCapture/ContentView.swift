import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - VideoFile Transferable

struct VideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            print("[DEBUG] Transferable importing: \(received.file)")
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "/" + received.file.lastPathComponent)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: received.file, to: dest)
            print("[DEBUG] 복사 완료: \(dest)")
            return VideoFile(url: dest)
        }
        FileRepresentation(contentType: .video) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            print("[DEBUG] Transferable(video) importing: \(received.file)")
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "/" + received.file.lastPathComponent)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
        FileRepresentation(contentType: .audiovisualContent) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            print("[DEBUG] Transferable(audiovisual) importing: \(received.file)")
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "/" + received.file.lastPathComponent)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFile(url: dest)
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @State private var navigationPath: [URL] = []
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showDocumentPicker = false
    @State private var isLoadingFromPhotos = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            welcomeView
                .navigationDestination(for: URL.self) { url in
                    VideoPlayerView(url: url)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("닫기") {
                                    navigationPath.removeAll()
                                }
                            }
                        }
                }
        }
        // 외부 공유(공유 시트)로 받은 영상 자동 이동
        .onChange(of: appState.pendingVideoURL) { url in
            guard let url else { return }
            navigationPath = [url]
            appState.pendingVideoURL = nil
        }
        // PhotosPicker item handler
        .onChange(of: photosPickerItem) { newItem in
            guard let newItem else { return }
            print("[DEBUG] PhotosPicker 아이템 선택됨")
            isLoadingFromPhotos = true
            loadError = nil
            Task {
                do {
                    print("[DEBUG] loadTransferable 시작")
                    if let file = try await newItem.loadTransferable(type: VideoFile.self) {
                        print("[DEBUG] VideoFile 로드 성공: \(file.url)")
                        navigationPath = [file.url]
                    } else {
                        print("[DEBUG] VideoFile nil 반환됨")
                        loadError = "영상을 불러올 수 없습니다."
                    }
                } catch {
                    print("[DEBUG] loadTransferable 오류: \(error)")
                    loadError = error.localizedDescription
                }
                isLoadingFromPhotos = false
                photosPickerItem = nil
            }
        }
        // Document picker sheet
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                showDocumentPicker = false
                navigationPath = [url]
            }
        }
    }

    // MARK: Welcome

    private var welcomeView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                Text("VideoFrameCapture")
                    .font(.largeTitle.bold())
                Text("영상의 특정 프레임을 원본 해상도로 캡쳐하고\n정확한 타임스탬프와 함께 사진 앱에 저장합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                PhotosPicker(
                    selection: $photosPickerItem,
                    matching: .videos
                ) {
                    Label("사진 앱에서 가져오기", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: 300)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoadingFromPhotos)

                Button {
                    showDocumentPicker = true
                } label: {
                    Label("파일 앱에서 가져오기", systemImage: "folder")
                        .frame(maxWidth: 300)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if isLoadingFromPhotos {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("영상 불러오는 중…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let err = loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            Text("4K · 60fps · 120fps · 240fps 슬로우모션 지원")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .navigationTitle("VideoFrameCapture")
        .navigationBarTitleDisplayMode(.inline)
    }
}
