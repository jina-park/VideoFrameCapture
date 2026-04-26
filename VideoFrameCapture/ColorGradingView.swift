import SwiftUI
import Combine

struct ColorGradingView: View {
    let originalImage: CGImage
    let onSave: (CGImage) -> Void

    @StateObject private var model = ColorGradingModel()
    @State private var processedImage: CGImage?
    @State private var showOriginal = false
    @State private var isProcessing = false
    @State private var cancellable: AnyCancellable?

    @Environment(\.dismiss) private var dismiss

    private var currentImage: CGImage {
        showOriginal ? originalImage : (processedImage ?? originalImage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.08).ignoresSafeArea()

                VStack(spacing: 0) {
                    previewSection
                    Divider().background(Color.white.opacity(0.1))
                    controlPanel
                }
            }
            .navigationTitle("색보정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.12), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { toolbarItems }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            cancellable = model.objectWillChange
                .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
                .sink { [weak model] _ in
                    guard let snap = model?.snapshot else { return }
                    Task { await self.updatePreview(snap: snap) }
                }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        ZStack(alignment: .bottom) {
            Color.black

            Image(currentImage, scale: 1, label: Text(showOriginal ? "원본" : "보정본"))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.1), value: showOriginal)

            if isProcessing {
                Color.black.opacity(0.35)
                ProgressView().tint(.white)
            }

            // 원본 보기 레이블
            if showOriginal {
                HStack {
                    Text("원본")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(10)
                    Spacer()
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            // 비교 버튼 (누르는 동안 원본 표시)
            HStack {
                Spacer()
                compareButton.padding(10)
            }
        }
        .frame(height: 260)
        .clipped()
    }

    private var compareButton: some View {
        Label(showOriginal ? "원본" : "비교", systemImage: "rectangle.split.2x1")
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in showOriginal = true }
                    .onEnded   { _ in showOriginal = false }
            )
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                colorWheelsSection
                    .padding(16)

                Divider().background(Color.white.opacity(0.1))

                basicSlidersSection
                    .padding(16)
            }
        }
        .background(Color(white: 0.10))
    }

    // MARK: - Color Wheels

    private var colorWheelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("컬러 휠")
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top) {
                ColorWheelView(label: "그림자",
                               offset: $model.shadowWheel,
                               brightness: $model.shadowBrightness)
                Spacer()
                ColorWheelView(label: "미드톤",
                               offset: $model.midtoneWheel,
                               brightness: $model.midtoneBrightness)
                Spacer()
                ColorWheelView(label: "하이라이트",
                               offset: $model.highlightWheel,
                               brightness: $model.highlightBrightness)
            }
        }
    }

    // MARK: - Basic Sliders

    private var basicSlidersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("기본 조정")

            sliderRow("노출",   $model.exposure,   -0.3...0.3, default: 0)
            sliderRow("대비",   $model.contrast,   0.5...1.5, default: 1)
            sliderRow("채도",   $model.saturation, 0...2,     default: 1)
            sliderRow("선명도", $model.sharpness,  0...1,     default: 0)

            Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)

            sliderRow("하이라이트", $model.highlights, 0...2, default: 1)
            sliderRow("그림자",     $model.shadows,    0...1, default: 0)
        }
    }

    @ViewBuilder
    private func sliderRow(_ label: String,
                            _ binding: Binding<Float>,
                            _ range: ClosedRange<Float>,
                            default defaultValue: Float) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .frame(width: 72, alignment: .leading)

            Slider(value: binding, in: range)
                .tint(Color(white: 0.75))
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        withAnimation(.spring(response: 0.2)) {
                            binding.wrappedValue = defaultValue
                        }
                    }
                )

            // 값 표시 — 탭하면 기본값 초기화
            Text(sliderLabel(binding.wrappedValue, default: defaultValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .onTapGesture {
                    withAnimation(.spring(response: 0.2)) {
                        binding.wrappedValue = defaultValue
                    }
                }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("취소") { dismiss() }
                .foregroundStyle(.white)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 18) {
                Button("초기화") {
                    withAnimation(.spring(response: 0.25)) {
                        model.reset()
                        processedImage = nil
                    }
                }
                .disabled(!model.isModified)
                .foregroundStyle(model.isModified ? .white : Color(white: 0.45))

                Button {
                    onSave(processedImage ?? originalImage)
                    dismiss()
                } label: {
                    Text("저장")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1)
    }

    private func sliderLabel(_ v: Float, default d: Float) -> String {
        abs(v - d) < 0.005 ? String(format: "%.1f", v) : String(format: "%+.2f", v - d)
    }

    @MainActor
    private func updatePreview(snap: ColorGradingSnapshot) async {
        guard !snap.isIdentity else {
            processedImage = nil
            isProcessing = false
            return
        }
        isProcessing = true
        let src = originalImage
        let result = await Task.detached(priority: .userInitiated) {
            ColorGradingProcessor.apply(to: src, snapshot: snap)
        }.value
        processedImage = result
        isProcessing = false
    }
}
