import Foundation
import AVFoundation
import CoreGraphics

class FrameExtractor: ObservableObject {
    private(set) var imageGenerator: AVAssetImageGenerator?

    enum ExtractorError: LocalizedError {
        case noVideoTrack
        case notLoaded
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:        return "비디오 트랙을 찾을 수 없습니다."
            case .notLoaded:           return "영상이 로드되지 않았습니다."
            case .extractionFailed(let msg): return "프레임 추출 실패: \(msg)"
            }
        }
    }

    func load(url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        let tracks   = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)

        guard let track = tracks.first else { throw ExtractorError.noVideoTrack }

        let naturalSize = try await track.load(.naturalSize)
        let transform   = try await track.load(.preferredTransform)
        let frameRate   = try await track.load(.nominalFrameRate)

        let transformed = naturalSize.applying(transform)
        let resolution  = CGSize(width: abs(transformed.width), height: abs(transformed.height))

        var modDate = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let d = attrs[.modificationDate] as? Date {
            modDate = d
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter  = .zero
        // maximumSize = .zero → no downscaling, returns full native resolution
        generator.maximumSize = .zero
        self.imageGenerator = generator

        return VideoInfo(
            url: url,
            fileName: url.lastPathComponent,
            fileNameWithoutExtension: url.deletingPathExtension().lastPathComponent,
            resolution: resolution,
            frameRate: frameRate,
            duration: duration,
            fileModificationDate: modDate
        )
    }

    func extractFrame(at time: CMTime) async throws -> CGImage {
        guard let generator = imageGenerator else { throw ExtractorError.notLoaded }

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(
                forTimes: [NSValue(time: time)]
            ) { _, cgImage, _, result, error in
                switch result {
                case .succeeded:
                    if let img = cgImage {
                        continuation.resume(returning: img)
                    } else {
                        continuation.resume(throwing: ExtractorError.extractionFailed("이미지 없음"))
                    }
                case .failed:
                    continuation.resume(throwing: ExtractorError.extractionFailed(
                        error?.localizedDescription ?? "알 수 없는 오류"
                    ))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                @unknown default:
                    continuation.resume(throwing: ExtractorError.extractionFailed("알 수 없는 오류"))
                }
            }
        }
    }

    func cancelAll() {
        imageGenerator?.cancelAllCGImageGeneration()
    }
}
