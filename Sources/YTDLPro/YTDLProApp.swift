import SwiftUI

@main
struct YTDLProApp: App {
    @NSApplicationDelegateAdaptor(AppURLDelegate.self) private var appDelegate
    @StateObject private var downloads = DownloadCoordinator()

    var body: some Scene {
        WindowGroup("YT-DLPro") {
            Group {
                if downloads.isCheckingInitialSetup {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Checking YT-DLPro setup…").foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 520, minHeight: 320)
                } else if !downloads.tools.missingTools.isEmpty {
                    FirstLaunchSetupView(downloads: downloads)
                        .frame(minWidth: 620, minHeight: 440)
                } else {
                    MainWorkspaceView(downloads: downloads)
                        .frame(minWidth: 1020, minHeight: 700)
                }
            }
        }

        Settings {
            ToolSettingsView(downloads: downloads)
        }
    }
}