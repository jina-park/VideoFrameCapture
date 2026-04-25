import SwiftUI
import AVFoundation
import Photos

// MARK: - AVPlayerLayer UIView

private final class PlayerLayerView: UIView {
    let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - SwiftUI wrapper

private struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - ViewModel

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    // Loading state
    @Published var videoInfo: VideoInfo?
    @Published var isLoadingVideo = false
    @Published var loadError: String?

    // Playback
    @Published var currentFrame: Int64 = 0
    @Published var isPlaying = false

    // Capture
    @Published var capturedImage: CGImage?
    @Published var isCapturing = false
    @Published var captureError: String?
    @Published var showCapturePreview = false

    // Save
    @Published var isSaving = false
    @Published var saveResult: String?
    @Published var showPermissionAlert = false

    let player = AVPlayer()
    private let extractor = FrameExtractor()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    // MARK: Load

    func loadVideo(url: URL) async {
        isLoadingVideo = true
        loadError = nil
        do {
            print("[DEBUG] loadVideo 시작: \(url.lastPathComponent)")
            let info = try await extractor.load(url: url)
            print("[DEBUG] VideoInfo 로드 완료 - \(info.formattedResolution) \(info.formattedFrameRate)")
            videoInfo = info

            let item = AVPlayerItem(url: info.url)
            player.replaceCurrentItem(with: item)
            print("[DEBUG] AVPlayerItem 설정 완료. 상태: \(item.status.rawValue)")
            setupObservers(info: info)

            // 아이템이 재생 준비될 때까지 대기
            await waitForPlayerItemReady()
            print("[DEBUG] 아이템 준비 완료. 상태: \(player.currentItem?.status.rawValue ?? -1)")

            let seekDone = await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            print("[DEBUG] seek(to: .zero) 결과: \(seekDone)")
        } catch {
            print("[DEBUG] 오류: \(error)")
            loadError = error.localizedDescription
        }
        isLoadingVideo = false
    }

    private func waitForPlayerItemReady() async {
        guard let item = player.currentItem else { return }
        if item.status == .readyToPlay { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var observation: NSKeyValueObservation?
            var resumed = false
            observation = item.observe(\.status, options: [.new]) { _, _ in
                guard !resumed else { return }
                let s = item.status
                if s == .readyToPlay || s == .failed {
                    resumed = true
                    observation?.invalidate()
                    continuation.resume()
                }
            }
        }
    }

    private func setupObservers(info: VideoInfo) {
        // Time observer fires ~30 times/sec regardless of frame rate
        let interval = CMTimeMake(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentFrame = info.frameForTime(time)
                self.isPlaying = self.player.timeControlStatus == .playing
            }
        }

        // Loop when reaching end
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
        }
    }

    // MARK: Seek

    func seekToFrame(_ frame: Int64) {
        guard let info = videoInfo else { return }
        let clamped = max(0, min(frame, info.totalFrames - 1))
        let time = info.timeForFrame(clamped)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentFrame = clamped
    }

    func seekBySeconds(_ delta: Double) {
        guard let info = videoInfo else { return }
        let current = Double(currentFrame) / Double(info.frameRate)
        let target  = max(0, min(current + delta, info.durationSeconds))
        seekToFrame(Int64(target * Double(info.frameRate)))
    }

    func previousFrame() { seekToFrame(currentFrame - 1) }
    func nextFrame()     { seekToFrame(currentFrame + 1) }

    // MARK: Play / Pause

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.play() }
    }

    // MARK: Capture

    func captureCurrentFrame() async {
        guard let info = videoInfo else { return }
        isCapturing = true
        captureError = nil
        capturedImage = nil

        let time = info.timeForFrame(currentFrame)
        do {
            capturedImage = try await extractor.extractFrame(at: time)
            showCapturePreview = true
        } catch is CancellationError {
            // swallow
        } catch {
            captureError = error.localizedDescription
        }
        isCapturing = false
    }

    // MARK: Save

    func saveCapture() async {
        guard let info = videoInfo, let cgImage = capturedImage else { return }
        isSaving = true
        saveResult = nil

        let frameTimestamp = Double(currentFrame) / Double(info.frameRate)
        let fileName = info.captureFileName(for: currentFrame)

        do {
            let data = try MetadataWriter.createJPEGData(
                from: cgImage,
                videoModificationDate: info.fileModificationDate,
                frameTimestamp: frameTimestamp
            )
            try await PhotoSaver.save(imageData: data, fileName: fileName)
            saveResult = "저장됨: \(fileName).jpg\n시각: \(info.formatTime(seconds: frameTimestamp))"
            showCapturePreview = false
            capturedImage = nil
        } catch SaveError.permissionDenied {
            showPermissionAlert = true
        } catch {
            captureError = error.localizedDescription
        }
        isSaving = false
    }

    // MARK: Cleanup

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        if let obs = endObserver  { NotificationCenter.default.removeObserver(obs) }
        player.pause()
        extractor.cancelAll()
    }
}

// MARK: - Capture Preview Sheet

private struct CapturePreviewSheet: View {
    let cgImage: CGImage
    let fileName: String
    let timestamp: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(cgImage, scale: 1, label: Text("캡쳐 미리보기"))
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .padding(.horizontal)

                VStack(spacing: 4) {
                    Text(fileName + ".jpg")
                        .font(.headline)
                    Text(timestamp)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 20) {
                    Button("취소", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                        .disabled(isSaving)

                    Button(action: onSave) {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("사진 앱에 저장", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                }
                .padding(.bottom)
            }
            .navigationTitle("캡쳐 미리보기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Main View

struct VideoPlayerView: View {
    let url: URL

    @StateObject private var vm = VideoPlayerViewModel()
    @State private var isDragging = false
    @State private var dragFrame: Double = 0

    var body: some View {
        Group {
            if vm.isLoadingVideo {
                ProgressView("영상 불러오는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.loadError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("불러오기 실패")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let info = vm.videoInfo {
                playerContent(info: info)
            }
        }
        .onAppear {
            print("[DEBUG] VideoPlayerView onAppear 호출됨")
            Task { await vm.loadVideo(url: url) }
        }
        .navigationTitle(vm.videoInfo?.fileNameWithoutExtension ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // Capture preview sheet
        .sheet(isPresented: $vm.showCapturePreview) {
            if let img = vm.capturedImage, let info = vm.videoInfo {
                let ts = Double(vm.currentFrame) / Double(info.frameRate)
                CapturePreviewSheet(
                    cgImage: img,
                    fileName: info.captureFileName(for: vm.currentFrame),
                    timestamp: info.formatTime(seconds: ts),
                    isSaving: vm.isSaving,
                    onSave: { Task { await vm.saveCapture() } },
                    onCancel: {
                        vm.showCapturePreview = false
                        vm.capturedImage = nil
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        // Save success toast
        .overlay(alignment: .bottom) {
            if let msg = vm.saveResult {
                Text(msg)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        vm.saveResult = nil
                    }
            }
        }
        .animation(.easeInOut, value: vm.saveResult)
        // Permission alert
        .alert("사진 접근 권한 필요", isPresented: $vm.showPermissionAlert) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("설정 앱 > VideoFrameCapture > 사진에서 권한을 허용해주세요.")
        }
    }

    // MARK: Player content

    @ViewBuilder
    private func playerContent(info: VideoInfo) -> some View {
        VStack(spacing: 0) {
            // Video preview
            PlayerView(player: vm.player)
                .aspectRatio(
                    info.resolution.width / max(1, info.resolution.height),
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .background(Color.black)

            ScrollView {
                VStack(spacing: 12) {
                    metadataBar(info: info)
                    frameInfoRow(info: info)
                    scrubber(info: info)
                    playbackControls(info: info)
                    jumpButtons
                    captureSection(info: info)
                }
                .padding()
            }
        }
    }

    // MARK: Metadata

    private func metadataBar(info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(info.fileName, systemImage: "film")
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 12) {
                metaChip(info.formattedResolution, icon: "aspectratio")
                metaChip(info.formattedFrameRate, icon: "timer")
                metaChip(info.formattedDuration, icon: "clock")
            }
            Text("수정일: \(info.formattedModificationDate)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metaChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: Frame info

    private func frameInfoRow(info: VideoInfo) -> some View {
        let frameTimestamp = Double(vm.currentFrame) / Double(info.frameRate)
        return Text("프레임  \(String(format: "%06d", vm.currentFrame))  /  \(info.formatTime(seconds: frameTimestamp))")
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Scrubber

    private func scrubber(info: VideoInfo) -> some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isDragging ? dragFrame : Double(vm.currentFrame) },
                    set: { val in
                        dragFrame = val
                        if isDragging { vm.seekToFrame(Int64(val)) }
                    }
                ),
                in: 0...Double(max(1, info.totalFrames - 1)),
                onEditingChanged: { editing in
                    if editing { dragFrame = Double(vm.currentFrame) }
                    isDragging = editing
                    if !editing { vm.seekToFrame(Int64(dragFrame)) }
                }
            )
            HStack {
                Text("0:00")
                Spacer()
                Text(info.formattedDuration)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Playback controls

    private func playbackControls(info: VideoInfo) -> some View {
        HStack(spacing: 4) {
            controlButton(icon: vm.isPlaying ? "pause.fill" : "play.fill",
                          label: vm.isPlaying ? "일시정지" : "재생") {
                vm.togglePlayPause()
            }
            .font(.title2)

            Divider().frame(height: 28).padding(.horizontal, 4)

            controlButton(icon: "backward.frame", label: "이전 프레임") { vm.previousFrame() }
            controlButton(icon: "forward.frame",  label: "다음 프레임") { vm.nextFrame() }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Jump buttons

    private var jumpButtons: some View {
        HStack(spacing: 6) {
            ForEach([(-10, "-10초"), (-5, "-5초"), (-1, "-1초"), (1, "+1초"), (5, "+5초"), (10, "+10초")],
                    id: \.0) { (delta, label) in
                Button(label) { vm.seekBySeconds(Double(delta)) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: Capture

    private func captureSection(info: VideoInfo) -> some View {
        VStack(spacing: 8) {
            if let err = vm.captureError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await vm.captureCurrentFrame() }
            } label: {
                if vm.isCapturing {
                    ProgressView().tint(.white)
                } else {
                    Label("현재 프레임 캡쳐", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isCapturing)
        }
    }

    // MARK: Helper

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(label)
    }
}
