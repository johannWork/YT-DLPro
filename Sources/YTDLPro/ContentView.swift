import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var downloads: DownloadCoordinator
    @State private var urlInput = ""
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolStatus
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Video URLs")
                        .font(.headline)
                    TextEditor(text: $urlInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 106)
                        .overlay(alignment: .topLeading) {
                            if urlInput.isEmpty {
                                Text("Paste one URL per line, or drop links here")
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 6)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onDrop(of: [UTType.url], isTargeted: $isDropTargeted, perform: acceptDrop)
                    HStack {
                        Button("Add to Queue") {
                            downloads.addURLs(from: urlInput)
                            urlInput = ""
                        }
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Button("Start Queue") { downloads.startQueued() }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(downloads.tools.ytDlp == nil || !downloads.jobs.contains { $0.status == .queued || $0.status == .failed || $0.status == .cancelled })
                    }
                }
                .frame(maxWidth: 310)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Download Queue")
                            .font(.headline)
                        Spacer()
                        Text("\(downloads.jobs.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if downloads.jobs.isEmpty {
                        ContentUnavailableView("Queue is empty", systemImage: "arrow.down.circle", description: Text("Add video or playlist URLs to begin."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(downloads.jobs) { job in
                            QueueRow(job: job, cancel: { downloads.cancel(job) }, remove: { downloads.remove(job) })
                        }
                        .listStyle(.inset)
                    }
                }
            }
            .padding(20)
        }
        .background {
            if isDropTargeted {
                Color.accentColor.opacity(0.08)
                    .ignoresSafeArea()
        }
        }
        .background(.background)
        .onDrop(of: [UTType.url], isTargeted: $isDropTargeted, perform: acceptDrop)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var toolStatus: some View {
        if downloads.tools.missingTools.isEmpty {
            HStack(spacing: 18) {
                toolLabel("yt-dlp", tool: downloads.tools.ytDlp)
                toolLabel("ffmpeg", tool: downloads.tools.ffmpeg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(.quaternary.opacity(0.45))
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required tools not found: \(downloads.tools.missingTools.joined(separator: ", "))")
                        .fontWeight(.semibold)
                    Text("Install yt-dlp and ffmpeg with Homebrew:")
                        .foregroundStyle(.secondary)
                    Text("brew install yt-dlp ffmpeg")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Check Again") { Task { await downloads.refreshTools() } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.orange.opacity(0.1))
        }
    }

    private func toolLabel(_ name: String, tool: InstalledTool?) -> some View {
        Label("\(name)  \(tool?.version ?? "Not found")", systemImage: "checkmark.circle.fill")
            .foregroundStyle(tool == nil ? .red : .secondary)
            .font(.callout)
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !matching.isEmpty else { return false }
        for provider in matching {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in downloads.addURLs(from: url.absoluteString) }
            }
        }
        return true
    }
}

private struct QueueRow: View {
    let job: DownloadJob
    let cancel: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 10)
                Text(job.status.rawValue)
                    .font(.callout)
                    .foregroundStyle(job.status == .failed ? .red : .secondary)
                Button(job.status == .downloading ? "Cancel" : "Remove", systemImage: job.status == .downloading ? "xmark" : "trash", action: job.status == .downloading ? cancel : remove)
                    .labelStyle(.iconOnly)
                    .help(job.status == .downloading ? "Cancel download" : "Remove from queue")
            }
            if job.status == .downloading || job.progress > 0 {
                ProgressView(value: job.progress)
                HStack {
                    Text("\(Int(job.progress * 100))%")
                    if !job.speed.isEmpty { Text(job.speed) }
                    if !job.eta.isEmpty { Text("ETA \(job.eta)") }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let errorMessage = job.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button("Remove from Queue", systemImage: "trash", action: remove)
        }
    }
}