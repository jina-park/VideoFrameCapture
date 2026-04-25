import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum MetadataWriterError: LocalizedError {
    case destinationCreationFailed
    case finalizationFailed

    var errorDescription: String? {
        switch self {
        case .destinationCreationFailed: return "이미지 대상 생성 실패"
        case .finalizationFailed:        return "이미지 파일 완성 실패"
        }
    }
}

struct MetadataWriter {
    /// JPEG data with EXIF date set to (videoModificationDate + frameTimestamp seconds).
    static func createJPEGData(
        from cgImage: CGImage,
        videoModificationDate: Date,
        frameTimestamp: Double
    ) throws -> Data {
        let captureDate = videoModificationDate.addingTimeInterval(frameTimestamp)

        // EXIF date format: "yyyy:MM:dd HH:mm:ss" (colons in date part, not dashes)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.timeZone = TimeZone.current
        let dateString = fmt.string(from: captureDate)

        let properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 1.0,
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifDateTimeOriginal as String: dateString,
                kCGImagePropertyExifDateTimeDigitized as String: dateString
            ] as [String: Any],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFDateTime as String: dateString
            ] as [String: Any]
        ]

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw MetadataWriterError.destinationCreationFailed
        }

        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw MetadataWriterError.finalizationFailed
        }

        return data as Data
    }
}
