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
    /// JPEG data with EXIF date and GPS copied from the source video.
    static func createJPEGData(
        from cgImage: CGImage,
        videoModificationDate: Date,
        frameTimestamp: Double,
        gpsProperties: [String: Any]? = nil,
        timezoneOffset: String? = nil
    ) throws -> Data {
        let captureDate = videoModificationDate.addingTimeInterval(frameTimestamp)

        // EXIF date format: "yyyy:MM:dd HH:mm:ss" (colons in date part, not dashes)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        // 오프셋이 있으면 해당 시간대로, 없으면 기기 현지 시간대로 날짜 문자열 생성
        if let offset = timezoneOffset,
           let tz = TimeZone(identifier: ianaIdentifier(from: offset)) {
            fmt.timeZone = tz
        } else {
            fmt.timeZone = TimeZone.current
        }
        let dateString = fmt.string(from: captureDate)

        var exifDict: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String:  dateString,
            kCGImagePropertyExifDateTimeDigitized as String: dateString
        ]
        if let offset = timezoneOffset {
            exifDict[kCGImagePropertyExifOffsetTimeOriginal as String]  = offset
            exifDict[kCGImagePropertyExifOffsetTimeDigitized as String] = offset
        }

        var properties: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 1.0,
            kCGImagePropertyExifDictionary as String: exifDict,
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFDateTime as String: dateString
            ] as [String: Any]
        ]

        if let gps = gpsProperties {
            properties[kCGImagePropertyGPSDictionary as String] = gps
        }

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

    // "+09:00" → "GMT+9" 형식으로 변환하여 TimeZone 생성에 사용
    private static func ianaIdentifier(from offset: String) -> String {
        // TimeZone(identifier:)은 "GMT+9", "GMT-5:30" 등을 허용
        let stripped = offset.replacingOccurrences(of: ":00", with: "")
                             .replacingOccurrences(of: ":30", with: ":30")
        return "GMT\(stripped)"
    }
}
