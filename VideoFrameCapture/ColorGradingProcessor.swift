import CoreImage
import CoreGraphics
import Foundation
import Metal

struct ColorGradingProcessor {

    // Metal 가속 CIContext (프로세스 전체 공유)
    static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device,
                            options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()

    static func apply(to cgImage: CGImage, snapshot: ColorGradingSnapshot) -> CGImage? {
        guard !snapshot.isIdentity else { return cgImage }
        var ci = CIImage(cgImage: cgImage)

        // 1. 노출 (CIExposureAdjust)
        if snapshot.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(snapshot.exposure, forKey: kCIInputEVKey)
            ci = f.outputImage ?? ci
        }

        // 2. 대비 / 채도 (CIColorControls)
        if (snapshot.contrast != 1 || snapshot.saturation != 1),
           let f = CIFilter(name: "CIColorControls") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(snapshot.contrast,    forKey: kCIInputContrastKey)
            f.setValue(snapshot.saturation,  forKey: kCIInputSaturationKey)
            f.setValue(Float(0),             forKey: kCIInputBrightnessKey)
            ci = f.outputImage ?? ci
        }

        // 3. 하이라이트 / 그림자 (CIHighlightShadowAdjust)
        if (snapshot.highlights != 1 || snapshot.shadows != 0),
           let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(snapshot.highlights, forKey: "inputHighlightAmount")
            f.setValue(snapshot.shadows,    forKey: "inputShadowAmount")
            ci = f.outputImage ?? ci
        }

        // 4. 색상 휠 — 루미넌스 마스킹 기반 32³ CIColorCube
        let wheelsActive =
            snapshot.highlightWheel != .zero || snapshot.midtoneWheel != .zero || snapshot.shadowWheel != .zero
            || snapshot.highlightBrightness != 0 || snapshot.midtoneBrightness != 0 || snapshot.shadowBrightness != 0
        if wheelsActive, let wheeled = applyColorWheels(to: ci, snapshot: snapshot) {
            ci = wheeled
        }

        // 5. 선명도 (CIUnsharpMask)
        if snapshot.sharpness > 0, let f = CIFilter(name: "CIUnsharpMask") {
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(Float(2.5),          forKey: kCIInputRadiusKey)
            f.setValue(snapshot.sharpness,  forKey: kCIInputIntensityKey)
            ci = f.outputImage ?? ci
        }

        return ciContext.createCGImage(ci, from: ci.extent)
    }

    // MARK: - Color Cube

    private static func applyColorWheels(to image: CIImage,
                                          snapshot: ColorGradingSnapshot) -> CIImage? {
        let size = 32
        var cube = [Float](repeating: 0, count: size * size * size * 4)

        let hRGB = snapshot.highlightWheel.rgbOffset
        let mRGB = snapshot.midtoneWheel.rgbOffset
        let sRGB = snapshot.shadowWheel.rgbOffset

        for bIdx in 0..<size {
            for gIdx in 0..<size {
                for rIdx in 0..<size {
                    let r0 = Float(rIdx) / Float(size - 1)
                    let g0 = Float(gIdx) / Float(size - 1)
                    let b0 = Float(bIdx) / Float(size - 1)

                    // BT.709 루미넌스
                    let lum = 0.2126 * r0 + 0.7152 * g0 + 0.0722 * b0

                    // 영역별 부드러운 가중치
                    let hw = smoothstep(0.55, 0.90, lum)           // 밝은 영역
                    let sw = 1.0 - smoothstep(0.10, 0.45, lum)     // 어두운 영역
                    let mw = max(0, 1.0 - hw - sw)                  // 중간 영역

                    let rOff = hw * hRGB.r + mw * mRGB.r + sw * sRGB.r
                    let gOff = hw * hRGB.g + mw * mRGB.g + sw * sRGB.g
                    let bOff = hw * hRGB.b + mw * mRGB.b + sw * sRGB.b
                    let lumOff = hw * snapshot.highlightBrightness
                               + mw * snapshot.midtoneBrightness
                               + sw * snapshot.shadowBrightness

                    let i = (bIdx * size * size + gIdx * size + rIdx) * 4
                    cube[i + 0] = max(0, min(1, r0 + rOff + lumOff))
                    cube[i + 1] = max(0, min(1, g0 + gOff + lumOff))
                    cube[i + 2] = max(0, min(1, b0 + bOff + lumOff))
                    cube[i + 3] = 1.0
                }
            }
        }

        let data = cube.withUnsafeBytes { Data($0) }
        guard let filter = CIFilter(name: "CIColorCube") else { return nil }
        filter.setValue(size,           forKey: "inputCubeDimension")
        filter.setValue(data as NSData, forKey: "inputCubeData")
        filter.setValue(image,          forKey: kCIInputImageKey)
        return filter.outputImage
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
