import AppKit
import SwiftUI

struct ToolSettingsView: View {
    @ObservedObject var downloads: DownloadCoordinator

    var body: some View {
        Form {
            Section("Tool preference") {
                Picker("Discovery order", selection: $downloads.toolPreference) {
                    ForEach(ToolPreference.allCases) { preference in
                        Text(preference.rawValue).tag(preference)
                    }
                }
                Text("System tools are found through a login shell. Built-in copies are stored in your YT-DLPro Application Support folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Active tools") {
                toolRow("yt-dlp", tool: downloads.tools.ytDlp)
                toolRow("ffmpeg", tool: downloads.tools.ffmpeg)
            }

            if !downloads.tools.missingTools.isEmpty {
                Section("Missing tools") {
                    Text("Not found: \(downloads.tools.missingTools.joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                    Button("Download tools", systemImage: "arrow.down.to.line") {
                        downloads.downloadTools()
                    }
                    .disabled(downloads.isDownloadingTools)
                }
            }

            if downloads.isDownloadingTools {
                Section("Download progress") {
                    ProgressView(value: downloads.toolDownloadProgress) {
                        Text(downloads.toolDownloadStatus ?? "Downloading tools")
                    }
                }
            } else if let error = downloads.toolDownloadError {
                Section("Download error") {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            } else if let status = downloads.toolDownloadStatus {
                Section("Tool status") { Text(status).foregroundStyle(.secondary) }
            }

            Section("Updates") {
                Button("Update active yt-dlp", systemImage: "arrow.clockwise") {
                    downloads.updateYtDlp()
                }
                .disabled(downloads.tools.ytDlp == nil || downloads.isUpdatingYtDlp)
            }

            Section("Download folder") {
                LabeledContent("Default folder") {
                    Text(downloads.globalOutputFolder)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Picker("Folder behavior", selection: $downloads.folderPolicy) {
                    ForEach(FolderPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                HStack {
                    Button("Choose folder…", systemImage: "folder", action: chooseGlobalFolder)
                    Button("Reset", systemImage: "arrow.counterclockwise") { downloads.resetGlobalOutputFolder() }
                }
            }

            Section("Downloads") {
                Stepper("Maximum concurrent downloads: \(downloads.maxConcurrentDownloads)", value: $downloads.maxConcurrentDownloads, in: 1...8)
                Toggle("Notify when downloads finish", isOn: $downloads.notificationsOnFinish)
                Toggle("Notify when downloads fail", isOn: $downloads.notificationsOnFailure)
                Toggle("Prevent sleep while downloads are active", isOn: $downloads.preventSleepWhileDownloading)
            }

            Section("Clipboard") {
                Toggle("Offer copied video links", isOn: $downloads.clipboardWatcherEnabled)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 540, height: 540)
    }

    private func chooseGlobalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            downloads.globalOutputFolder = url.path
        }
    }

    @ViewBuilder
    private func toolRow(_ name: String, tool: InstalledTool?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).fontWeight(.semibold)
                Spacer()
                if let tool {
                    Text(tool.source.rawValue).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Missing").font(.caption).foregroundStyle(.red)
                }
            }
            if let tool {
                Text(tool.version).font(.caption).foregroundStyle(.secondary)
                Text(tool.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }
}