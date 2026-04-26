import SwiftUI

struct ColorWheelView: View {
    let label: String
    @Binding var offset: ColorWheelOffset
    @Binding var brightness: Float
    var size: CGFloat = 108

    var body: some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            ZStack {
                wheelDisk
                    .frame(width: size, height: size)

                // 핀
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .offset(
                        x:  CGFloat(offset.x) * size * 0.46,
                        y: -CGFloat(offset.y) * size * 0.46
                    )
                    .animation(.interactiveSpring(response: 0.15), value: offset)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(dragGesture)
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    offset = .zero
                }
            }

            // 밝기 슬라이더
            VStack(spacing: 2) {
                Slider(value: $brightness, in: -0.3...0.3)
                    .frame(width: size)
                    .tint(.white)

                Text(brightnessText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Wheel Disk

    private var wheelDisk: some View {
        ZStack {
            // 색조 링 (AngularGradient)
            AngularGradient(
                colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                    Color(hue: $0, saturation: 1, brightness: 1)
                },
                center: .center
            )

            // 중앙→외곽 채도 그라디언트 (흰색 오버레이 → 투명)
            RadialGradient(
                colors: [.white, .white.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.5
            )

            // 외곽 테두리
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

            // 중앙 십자 가이드
            Path { p in
                p.move(to: CGPoint(x: size / 2 - 6, y: size / 2))
                p.addLine(to: CGPoint(x: size / 2 + 6, y: size / 2))
                p.move(to: CGPoint(x: size / 2, y: size / 2 - 6))
                p.addLine(to: CGPoint(x: size / 2, y: size / 2 + 6))
            }
            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        }
        .clipShape(Circle())
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let cx = size / 2, cy = size / 2
                let dx = Float((v.location.x - cx) / (size / 2))
                let dy = Float(-(v.location.y - cy) / (size / 2))
                let mag = (dx * dx + dy * dy).squareRoot()
                if mag > 1 {
                    offset = ColorWheelOffset(x: dx / mag, y: dy / mag)
                } else {
                    offset = ColorWheelOffset(x: dx, y: dy)
                }
            }
    }

    // MARK: - Helpers

    private var brightnessText: String {
        abs(brightness) < 0.005 ? "0" : String(format: "%+.2f", brightness)
    }
}
