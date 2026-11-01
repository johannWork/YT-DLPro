import AppKit
import SwiftUI

struct SetupCheckView: View {
    @ObservedObject var downloads: DownloadCoordinator

    var body: some View {
        Form {
            Section("Download tools") {
                requirementRow(
                    title: "yt-dlp",
                    detail: toolDetail(downloads.tools.ytDlp),
                    isReady: downloads.tools.ytDlp != nil,
                    fixTitle: "Install",
                    fix: { downloads.downloadTools(["yt-dlp"]) },
                    manualFix: { chooseManualTool("yt-dlp") }
                )
                requirementRow(
                    title: "ffmpeg",
                    detail: toolDetail(downloads.tools.ffmpeg),
                    isReady: downloads.tools.ffmpeg != nil,
                    fixTitle: "Install",
                    fix: { downloads.downloadTools(["ffmpeg"]) },
                    manualFix: { chooseManualTool("ffmpeg") }
                )
                requirementRow(
                    title: "Deno (YouTube JavaScript runtime)",
                    detail: toolDetail(downloads.tools.jsRuntime),
                    isReady: downloads.tools.jsRuntime != nil,
                    fixTitle: "Install",
                    fix: { downloads.downloadTools(["deno"]) },
                    manualFix: { chooseManualTool("deno") }
                )
            }

            Section("App access") {
                requirementRow(
                    title: "Output folder access",
                    detail: downloads.outputFolderAccessible ? downloads.globalOutputFolder : "YT-DLPro cannot write to the selected output folder.",
                    isReady: downloads.outputFolderAccessible,
                    fixTitle: "Choose folder",
                    fix: downloads.chooseGlobalOutputFolder
                )
                requirementRow(
                    title: "Notifications",
                    detail: downloads.notificationsAuthorized ? "Permission granted" : "Permission not granted",
                    isReady: downloads.notificationsAuthorized,
                    fixTitle: "Allow",
                    fix: downloads.requestNotificationPermission
                )
            }

            if downloads.isDownloadingTools {
                Section("Setup progress") {
                    ProgressView(value: downloads.toolDownloadProgress) {
                        Text(downloads.toolDownloadStatus ?? "Preparing tools…")
                    }
                }
            }
            if let error = downloads.toolDownloadError {
                Section("Download problem") {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Text("If the host is unreachable, use Choose File to select the matching executable from an official release archive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await downloads.refreshRequirements() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Check again", systemImage: "arrow.clockwise") {
                    Task {
                        await downloads.refreshTools()
                        await downloads.refreshRequirements()
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 470)
    }

    private func requirementRow(
        title: String,
        detail: String,
        isReady: Bool,
        fixTitle: String,
        fix: @escaping () -> Void,
        manualFix: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isReady ? Color.green : Color.red)
                .accessibilityLabel(isReady ? "Ready" : "Needs attention")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            if !isReady {
                Button(fixTitle, action: fix)
                    .disabled(downloads.isDownloadingTools)
                if let manualFix {
                    Button("Choose File…", systemImage: "doc.badge.plus", action: manualFix)
                        .labelStyle(.iconOnly)
                        .help("Select an already downloaded executable")
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func toolDetail(_ tool: InstalledTool?) -> String {
        guard let tool else { return "Not found" }
        return "\(tool.version) · \(tool.path)"
    }

    private func chooseManualTool(_ name: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Install Tool"
        panel.message = "Select the downloaded \(name) executable. It will be copied into YT-DLPro’s Application Support folder and verified."
        if panel.runModal() == .OK, let url = panel.url {
            downloads.installManualTool(from: url, name: name)
        }
    }
}
