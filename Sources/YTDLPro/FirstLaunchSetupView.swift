import AppKit
import SwiftUI

struct FirstLaunchSetupView: View {
    @ObservedObject var downloads: DownloadCoordinator

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)

            VStack(spacing: 7) {
                Text("Set up YT-DLPro")
                    .font(.largeTitle.weight(.semibold))
                Text("Install the tools needed to download and convert video. They’ll be stored in your user Library, not inside the app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }

            VStack(alignment: .leading, spacing: 9) {
                requirement("yt-dlp", tool: downloads.tools.ytDlp)
                requirement("ffmpeg", tool: downloads.tools.ffmpeg)
                requirement("Deno JavaScript runtime", tool: downloads.tools.jsRuntime)
            }
            .frame(maxWidth: 430, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            if downloads.isDownloadingTools {
                ProgressView(value: downloads.toolDownloadProgress) {
                    Text(downloads.toolDownloadStatus ?? "Preparing tools…")
                }
                .frame(maxWidth: 430)
            } else {
                Button("Set up now", systemImage: "arrow.down.to.line.circle.fill") {
                    downloads.downloadTools()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(downloads.tools.missingTools.isEmpty)
            }

            if let error = downloads.toolDownloadError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If the download host is unreachable, choose the executable file from an official release download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach(downloads.tools.missingTools, id: \.self) { name in
                            Button("Choose \(name)…") { chooseManualTool(name) }
                        }
                    }
                }
                .frame(maxWidth: 450, alignment: .leading)
            }

        }
        .padding(32)
    }

    private func requirement(_ title: String, tool: InstalledTool?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: tool == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(tool == nil ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let tool {
                    Text(tool.version).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Will be installed and verified").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func chooseManualTool(_ name: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Install Tool"
        panel.message = "Select the downloaded \(name) executable. It will be copied to YT-DLPro’s Application Support folder and verified."
        if panel.runModal() == .OK, let url = panel.url {
            downloads.installManualTool(from: url, name: name)
        }
    }
}
