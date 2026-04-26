import SwiftUI

@main
struct VideoFrameCaptureApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    if url.scheme == "videoframecapture" {
                        // Share Extension이 앱을 깨운 경우 → App Group 확인
                        Task { await appState.checkAppGroup() }
                    } else {
                        Task { await appState.open(url: url) }
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // 앱이 포그라운드로 올 때마다 공유 대기 영상 확인
                Task { await appState.checkAppGroup() }
            }
        }
    }
}
