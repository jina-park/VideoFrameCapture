import Foundation
import SwiftUI

// MARK: - ColorWheelOffset

struct ColorWheelOffset: Equatable, Sendable {
    var x: Float = 0  // -1 ~ +1 (좌우)
    var y: Float = 0  // -1 ~ +1 (상하)

    static let zero = ColorWheelOffset(x: 0, y: 0)

    var magnitude: Float { (x * x + y * y).squareRoot() }

    /// 색상 원의 (x,y) 위치를 RGB 채널 오프셋으로 변환
    /// 0° = Red, 120° = Green, 240° = Blue
    var rgbOffset: (r: Float, g: Float, b: Float) {
        let θ = atan2(y, x)
        let mag = min(magnitude, 1.0) * 0.12
        let r = mag * cos(θ)
        let g = mag * cos(θ - 2 * Float.pi / 3)
        let b = mag * cos(θ + 2 * Float.pi / 3)
        return (r, g, b)
    }
}

// MARK: - ColorGradingSnapshot  (Sendable — Task.detached에 전달)

struct ColorGradingSnapshot: Sendable {
    let exposure: Float
    let contrast: Float
    let saturation: Float
    let sharpness: Float
    let highlights: Float
    let shadows: Float
    let highlightWheel: ColorWheelOffset
    let midtoneWheel: ColorWheelOffset
    let shadowWheel: ColorWheelOffset
    let highlightBrightness: Float
    let midtoneBrightness: Float
    let shadowBrightness: Float

    var isIdentity: Bool {
        exposure == 0 && contrast == 1 && saturation == 1 && sharpness == 0
        && highlights == 1 && shadows == 0
        && highlightWheel == .zero && midtoneWheel == .zero && shadowWheel == .zero
        && highlightBrightness == 0 && midtoneBrightness == 0 && shadowBrightness == 0
    }
}

// MARK: - ColorGradingModel

@MainActor
final class ColorGradingModel: ObservableObject {
    // 기본 조정
    @Published var exposure: Float = 0        // -2 ~ +2
    @Published var contrast: Float = 1        // 0.5 ~ 1.5
    @Published var saturation: Float = 1      // 0 ~ 2
    @Published var sharpness: Float = 0       // 0 ~ 1
    @Published var highlights: Float = 1      // 0 ~ 2
    @Published var shadows: Float = 0         // 0 ~ 1

    // 색상 휠
    @Published var highlightWheel = ColorWheelOffset.zero
    @Published var midtoneWheel   = ColorWheelOffset.zero
    @Published var shadowWheel    = ColorWheelOffset.zero

    // 휠별 밝기 오프셋
    @Published var highlightBrightness: Float = 0  // -0.3 ~ +0.3
    @Published var midtoneBrightness: Float   = 0
    @Published var shadowBrightness: Float    = 0

    var isModified: Bool { !snapshot.isIdentity }

    var snapshot: ColorGradingSnapshot {
        ColorGradingSnapshot(
            exposure: exposure, contrast: contrast, saturation: saturation,
            sharpness: sharpness, highlights: highlights, shadows: shadows,
            highlightWheel: highlightWheel, midtoneWheel: midtoneWheel, shadowWheel: shadowWheel,
            highlightBrightness: highlightBrightness, midtoneBrightness: midtoneBrightness,
            shadowBrightness: shadowBrightness
        )
    }

    func reset() {
        exposure = 0; contrast = 1; saturation = 1; sharpness = 0
        highlights = 1; shadows = 0
        highlightWheel = .zero; midtoneWheel = .zero; shadowWheel = .zero
        highlightBrightness = 0; midtoneBrightness = 0; shadowBrightness = 0
    }
}
