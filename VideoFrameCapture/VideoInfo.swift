import Foundation
import AVFoundation
import CoreGraphics

struct VideoInfo {
    let url: URL
    let fileName: String
    let fileNameWithoutExtension: String
    let resolution: CGSize
    let frameRate: Float
    let duration: CMTime
    let fileModificationDate: Date

    var durationSeconds: Double {
        CMTimeGetSeconds(duration)
    }

    var totalFrames: Int64 {
        max(1, Int64(durationSeconds * Double(frameRate)))
    }

    var formattedDuration: String {
        formatTime(seconds: durationSeconds)
    }

    var formattedResolution: String {
        "\(Int(resolution.width)) × \(Int(resolution.height))"
    }

    var formattedFrameRate: String {
        let rounded = Float(Int(frameRate))
        return rounded == frameRate ? "\(Int(frameRate))fps" : String(format: "%.3gfps", frameRate)
    }

    var formattedModificationDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt.string(from: fileModificationDate)
    }

    func timeForFrame(_ frameNumber: Int64) -> CMTime {
        let seconds = Double(frameNumber) / Double(frameRate)
        return CMTimeMakeWithSeconds(seconds, preferredTimescale: 600)
    }

    func frameForTime(_ time: CMTime) -> Int64 {
        let seconds = max(0, CMTimeGetSeconds(time))
        return min(Int64(seconds * Double(frameRate)), totalFrames - 1)
    }

    func formatTime(seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00:00.000" }
        let totalMs = Int(seconds * 1000)
        let ms = totalMs % 1000
        let totalSec = totalMs / 1000
        let sec = totalSec % 60
        let min = (totalSec / 60) % 60
        let hour = totalSec / 3600
        return String(format: "%02d:%02d:%02d.%03d", hour, min, sec, ms)
    }

    func captureFileName(for frameNumber: Int64) -> String {
        "\(fileNameWithoutExtension)_\(String(format: "%06d", frameNumber))"
    }
}
