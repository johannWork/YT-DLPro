import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWorkspaceView: View {
    @ObservedObject var downloads: DownloadCoordinator
    @State private var urlInput = ""
    @State private var isDropTargeted = false
    @State private var selectedTab = WorkspaceTab.queue
    @State private var isProfileManagerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            toolStatus
            HSplitView {
                sidebar
                    .frame(minWidth: 350, idealWidth: 390, maxWidth: 480)
                workspace
                    .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            downloadStatusBar
            commandPreview
        }
        .background(.background)
        .onDrop(of: [UTType.url], isTargeted: $isDropTargeted, perform: acceptDrop)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: downloads.infoError) { _, error in
            if error != nil { selectedTab = .formats }
        }
        .sheet(isPresented: $isProfileManagerPresented) {
            ProfileManagerView(downloads: downloads)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Profile", selection: Binding(
                        get: { downloads.selectedProfileID },
                        set: { downloads.selectProfile($0) }
                    )) {
                        ForEach(downloads.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    .labelsHidden()
                    Button("Manage Profiles", systemImage: "slider.horizontal.3") {
                        isProfileManagerPresented = true
                    }
                    .labelStyle(.iconOnly)
                    .help("Manage download profiles")
                }
                HStack {
                    Text("Video URLs").font(.headline)
                    Spacer()
                    Button("Paste & Add", systemImage: "doc.on.clipboard") {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            urlInput = text
                            downloads.addURLs(from: text)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .help("Paste URLs and add them to the queue")
                    .keyboardShortcut("v", modifiers: .command)
                }
                TextEditor(text: $urlInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 76)
                    .overlay(alignment: .topLeading) {
                        if urlInput.isEmpty {
                            Text("One URL per line. Playlist URLs are supported.")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 6)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: [UTType.url], isTargeted: $isDropTargeted, perform: acceptDrop)
                HStack {
                    Button("Inspect", systemImage: "info.circle") { downloads.inspect(from: urlInput) }
                        .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || downloads.isInspecting)
                    Button("Add to Queue", systemImage: "plus") {
                        downloads.addURLs(from: urlInput)
                    }
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Start", systemImage: "arrow.down.circle.fill") { downloads.startQueued() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(downloads.tools.ytDlp == nil || !downloads.jobs.contains { $0.status == .queued || $0.status == .failed || $0.status == .cancelled })
                }
                VideoInfoHeader(info: downloads.videoInfo, isLoading: downloads.isInspecting, error: downloads.infoError)
            }
            .padding(14)

            Divider()

            DownloadOptionsPanel(
                options: $downloads.options,
                globalOutputFolder: $downloads.globalOutputFolder,
                profileOutputFolder: downloads.selectedProfile?.outputFolder ?? "",
                chooseFolder: chooseOutputFolder
            )
        }
        .background(.background)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Workspace", selection: $selectedTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Spacer()
                Text("\(downloads.jobs.count) queued")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
            switch selectedTab {
            case .queue:
                queueList
            case .formats:
                FormatsPanel(
                    formats: downloads.videoInfo?.formats ?? [],
                    selectedFormatID: $downloads.options.selectedFormatID
                )
            case .history:
                HistoryPanel(
                    history: downloads.history,
                    redownload: downloads.addHistoryItemAgain,
                    reveal: downloads.revealInFinder,
                    remove: downloads.removeHistory
                )
            }
        }
    }

    private var queueList: some View {
        Group {
            if downloads.jobs.isEmpty {
                ContentUnavailableView("Queue is empty", systemImage: "arrow.down.circle", description: Text("Add video or playlist URLs to begin."))
            } else {
                List {
                    ForEach(downloads.jobs) { job in
                        let index = downloads.jobs.firstIndex(where: { $0.id == job.id }) ?? 0
                        QueueRow(
                            job: job,
                            profiles: downloads.profiles,
                            canMoveUp: index > 0 && downloads.jobs[index - 1].status != .downloading,
                            canMoveDown: index < downloads.jobs.count - 1 && downloads.jobs[index + 1].status != .downloading,
                            moveUp: { downloads.moveJob(job.id, by: -1) },
                            moveDown: { downloads.moveJob(job.id, by: 1) },
                            pause: { downloads.pause(job) },
                            resume: { downloads.resume(job) },
                            retry: { downloads.retry(job) },
                            cancel: { downloads.cancel(job) },
                            remove: { downloads.remove(job) },
                            reveal: { downloads.revealInFinder(job.outputPath) },
                            applyProfile: { downloads.applyProfile($0, to: job.id) },
                            chooseFolder: { chooseJobFolder(job.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var downloadStatusBar: some View {
        VStack(spacing: 7) {
            ProgressView(value: downloads.overallProgress)
            HStack(spacing: 14) {
                Label("\(downloads.jobs.filter { $0.status == .completed }.count) / \(downloads.jobs.count) done", systemImage: "checkmark.circle")
                if !downloads.combinedSpeed.isEmpty {
                    Label(downloads.combinedSpeed, systemImage: "speedometer")
                }
                if !downloads.overallETA.isEmpty {
                    Label("ETA \(downloads.overallETA)", systemImage: "clock")
                }
                Spacer()
                Text("\(Int(downloads.overallProgress * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.28))
    }

    private var commandPreview: some View {
        let command = downloads.commandPreview(for: urlInput)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Command Preview", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                .labelStyle(.iconOnly)
                .help("Copy command")
            }
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.35))
    }

    @ViewBuilder
    private var toolStatus: some View {
        if downloads.tools.missingTools.isEmpty {
            HStack(spacing: 18) {
                toolLabel("yt-dlp", tool: downloads.tools.ytDlp)
                toolLabel("ffmpeg", tool: downloads.tools.ffmpeg)
                Spacer()
                Button("Update yt-dlp", systemImage: "arrow.clockwise") { downloads.updateYtDlp() }
                    .disabled(downloads.isUpdatingYtDlp)
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Tool Settings")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.45))
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required tools not found: \(downloads.tools.missingTools.joined(separator: ", "))")
                        .fontWeight(.semibold)
                    Text("Install yt-dlp and ffmpeg with Homebrew:").foregroundStyle(.secondary)
                    Text("brew install yt-dlp ffmpeg")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    if downloads.isDownloadingTools {
                        ProgressView(value: downloads.toolDownloadProgress) {
                            Text(downloads.toolDownloadStatus ?? "Downloading tools")
                        }
                        .frame(maxWidth: 360)
                    } else if let downloadError = downloads.toolDownloadError {
                        Text(downloadError).font(.caption).foregroundStyle(.red)
                    }
                }
                Spacer()
                Button("Download Tools", systemImage: "arrow.down.to.line") { downloads.downloadTools() }
                    .disabled(downloads.isDownloadingTools)
                Button("Check Again") { Task { await downloads.refreshTools() } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.1))
        }
    }

    private func toolLabel(_ name: String, tool: InstalledTool?) -> some View {
        Label("\(name)  \(tool.map { "\($0.source.rawValue) · \($0.version)" } ?? "Not found")", systemImage: "checkmark.circle.fill")
            .foregroundStyle(tool == nil ? .red : .secondary)
            .font(.callout)
            .help(tool?.path ?? "Not found")
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            downloads.options.outputFolder = url.path
        }
    }

    private func chooseJobFolder(_ jobID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            downloads.setDownloadFolder(url.path, for: jobID)
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !matching.isEmpty else { return false }
        for provider in matching {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    urlInput = url.absoluteString
                    downloads.addURLs(from: url.absoluteString)
                }
            }
        }
        return true
    }
}

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case formats = "Formats"
    case history = "History"
    var id: String { rawValue }
}

private struct QueueRow: View {
    let job: DownloadJob
    let profiles: [DownloadProfile]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let remove: () -> Void
    let reveal: () -> Void
    let applyProfile: (UUID?) -> Void
    let chooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.url.absoluteString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 10)
                if job.status != .downloading {
                    Button("Move up", systemImage: "arrow.up") { moveUp() }
                        .labelStyle(.iconOnly)
                        .disabled(!canMoveUp)
                        .help("Move up")
                    Button("Move down", systemImage: "arrow.down") { moveDown() }
                        .labelStyle(.iconOnly)
                        .disabled(!canMoveDown)
                        .help("Move down")
                }
                Text(job.status.rawValue)
                    .font(.callout)
                    .foregroundStyle(job.status == .failed ? .red : .secondary)
                if job.status == .downloading {
                    Button("Pause", systemImage: "pause.fill", action: pause).labelStyle(.iconOnly).help("Pause download")
                    Button("Cancel", systemImage: "xmark", action: cancel).labelStyle(.iconOnly).help("Cancel download")
                } else if job.status == .paused {
                    Button("Resume", systemImage: "play.fill", action: resume).labelStyle(.iconOnly).help("Resume download")
                    Button("Cancel", systemImage: "xmark", action: cancel).labelStyle(.iconOnly).help("Cancel download")
                } else if job.status == .failed || job.status == .cancelled {
                    Button("Retry", systemImage: "arrow.clockwise", action: retry).labelStyle(.iconOnly).help("Retry download")
                    Button("Remove", systemImage: "trash", action: remove).labelStyle(.iconOnly).help("Remove from queue")
                } else if job.status == .completed {
                    Button("Reveal in Finder", systemImage: "folder", action: reveal).labelStyle(.iconOnly).help("Reveal in Finder")
                } else {
                    Button("Remove", systemImage: "trash", action: remove).labelStyle(.iconOnly).help("Remove from queue")
                }
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
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 5)
        .contextMenu {
            if job.status == .downloading { Button("Pause", systemImage: "pause.fill", action: pause) }
            if job.status == .paused { Button("Resume", systemImage: "play.fill", action: resume) }
            if job.status == .failed || job.status == .cancelled { Button("Retry", systemImage: "arrow.clockwise", action: retry) }
            if job.outputPath != nil { Button("Reveal in Finder", systemImage: "folder", action: reveal) }
            Menu("Use profile") {
                ForEach(profiles) { profile in
                    Button(profile.name) { applyProfile(profile.id) }
                }
            }
            Button("Set output folder…", systemImage: "folder.badge.gearshape", action: chooseFolder)
            Button("Remove from Queue", systemImage: "trash", action: remove)
        }
    }
}

private struct HistoryPanel: View {
    let history: [DownloadHistoryItem]
    let redownload: (DownloadHistoryItem) -> Void
    let reveal: (String?) -> Void
    let remove: (DownloadHistoryItem) -> Void

    var body: some View {
        if history.isEmpty {
            ContentUnavailableView("No download history", systemImage: "clock.arrow.circlepath", description: Text("Completed downloads will appear here."))
        } else {
            List(history) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).fontWeight(.medium).lineLimit(1)
                        Text(item.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(item.downloadedAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 4)
                    Button("Re-download", systemImage: "arrow.down.circle") { redownload(item) }
                        .labelStyle(.iconOnly)
                        .help("Re-download")
                    Button("Reveal", systemImage: "folder") { reveal(item.outputPath) }
                        .labelStyle(.iconOnly)
                        .disabled(item.outputPath == nil)
                        .help("Reveal in Finder")
                    Button("Remove", systemImage: "trash") { remove(item) }
                        .labelStyle(.iconOnly)
                        .help("Remove from history")
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }
}