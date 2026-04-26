import SwiftUI
import Photos
import AVFoundation

@MainActor
final class AppState: ObservableObject {
    @Published var pendingVideoURL: URL?

    private let groupID = "group.com.videoframecapture.VideoFrameCapture"

    // MARK: - 외부 URL (onOpenURL / DocumentPicker)

    func open(url: URL) async {
        if url.scheme == "ph" {
            let id = url.host ?? String(url.path.dropFirst())
            pendingVideoURL = try? await exportPHAsset(localIdentifier: id)
        } else {
            pendingVideoURL = await copyToTemp(url: url)
        }
    }

    // MARK: - Share Extension → App Group 확인

    func checkAppGroup() async {
        guard let defaults = UserDefaults(suiteName: groupID),
              let filename = defaults.string(forKey: "pendingVideoFilename"),
              let container = FileManager.default
                  .containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return }

        let src = container.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: src.path) else {
            defaults.removeObject(forKey: "pendingVideoFilename")
            return
        }

        defaults.removeObject(forKey: "pendingVideoFilename")

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "/" + filename)
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
            try? FileManager.default.removeItem(at: src)
            pendingVideoURL = dest
        } catch {
            pendingVideoURL = src
        }
    }

    // MARK: - Private

    private func copyToTemp(url: URL) async -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "/" + url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }

    private func exportPHAsset(localIdentifier: String) async throws -> URL {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaType == .video else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try await withCheckedThrowingContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.version = .original
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    cont.resume(throwing: CocoaError(.fileNoSuchFile))
                    return
                }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "/" + urlAsset.url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: urlAsset.url, to: dest)
                    cont.resume(returning: dest)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
