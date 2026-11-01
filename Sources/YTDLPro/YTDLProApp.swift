import SwiftUI

@main
struct YTDLProApp: App {
    @NSApplicationDelegateAdaptor(AppURLDelegate.self) private var appDelegate
    @StateObject private var downloads = DownloadCoordinator()

    var body: some Scene {
        WindowGroup("YT-DLPro") {
            MainWorkspaceView(downloads: downloads)
                .frame(minWidth: 1020, minHeight: 700)
        }

        Settings {
            ToolSettingsView(downloads: downloads)
        }
    }
}