import Photos
import Foundation
import UniformTypeIdentifiers

enum SaveError: LocalizedError {
    case permissionDenied
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "사진 라이브러리 접근 권한이 거부되었습니다."
        case .saveFailed(let msg):
            return "저장 실패: \(msg)"
        }
    }
}

struct PhotoSaver {
    static func currentStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    static func save(imageData: Data, fileName: String) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = fileName + ".jpg"
                options.uniformTypeIdentifier = UTType.jpeg.identifier
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: options)
            }
        } catch {
            throw SaveError.saveFailed(error.localizedDescription)
        }
    }
}
