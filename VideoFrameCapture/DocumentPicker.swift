import SwiftUI
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.movie, .video, .audiovisualContent]
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            // Copy to a temp location so we have persistent access without
            // holding the security scope open for the entire session.
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)

            do {
                try FileManager.default.copyItem(at: url, to: dest)
                onPick(dest)
            } catch {
                // Copy failed (e.g. insufficient space) – fall back to original.
                // Re-start scope; caller must not hold it past the session.
                _ = url.startAccessingSecurityScopedResource()
                onPick(url)
            }
        }
    }
}
