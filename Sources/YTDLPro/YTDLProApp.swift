import SwiftUI

@main
struct YTDLProApp: App {
    @StateObject private var downloads = DownloadCoordinator()

    var body: some Scene {
        WindowGroup("YT-DLPro") {
            ContentView(downloads: downloads)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}