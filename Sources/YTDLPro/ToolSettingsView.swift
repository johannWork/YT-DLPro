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
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 540, height: 540)
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