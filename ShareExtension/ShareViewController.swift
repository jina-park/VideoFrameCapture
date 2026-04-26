import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private let groupID   = "group.com.videoframecapture.VideoFrameCapture"
    private let appScheme = "videoframecapture://open"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLoadingUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await processVideo() }
    }

    // MARK: - UI

    private func setupLoadingUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.layer.cornerRadius = 16
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blur)

        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(indicator)

        NSLayoutConstraint.activate([
            blur.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            blur.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            blur.widthAnchor.constraint(equalToConstant: 80),
            blur.heightAnchor.constraint(equalToConstant: 80),
            indicator.centerXAnchor.constraint(equalTo: blur.contentView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor),
        ])
    }

    // MARK: - Processing

    @MainActor
    private func processVideo() async {
        defer { extensionContext?.completeRequest(returningItems: nil) }

        guard let item  = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else { return }

        let types = [
            UTType.movie.identifier,
            UTType.mpeg4Movie.identifier,
            "com.apple.quicktime-movie",
            UTType.video.identifier,
            UTType.audiovisualContent.identifier,
        ]

        var tempURL: URL?
        for type in types {
            guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
            tempURL = try? await loadFileCopy(from: provider, typeID: type)
            if tempURL != nil { break }
        }

        guard let srcURL = tempURL else { return }
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return }

        let filename = srcURL.lastPathComponent
        let dest = container.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: srcURL, to: dest)) != nil else { return }
        try? FileManager.default.removeItem(at: srcURL)

        UserDefaults(suiteName: groupID)?.set(filename, forKey: "pendingVideoFilename")

        openApp()
    }

    // NSItemProvider 콜백에서 즉시 임시 복사본을 만들어 URL 소멸 방지
    private func loadFileCopy(from provider: NSItemProvider, typeID: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            provider.loadFileRepresentation(forTypeIdentifier: typeID) { url, error in
                guard let url else {
                    cont.resume(throwing: error ?? CocoaError(.fileNoSuchFile))
                    return
                }
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: temp)
                    cont.resume(returning: temp)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Open App

    private func openApp() {
        guard let url = URL(string: appScheme) else { return }
        // Share Extension은 openURL을 직접 호출할 수 없으므로 리스폰더 체인 이용
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }
}
