import Foundation

@MainActor
final class DownloadCoordinator: ObservableObject {
    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var tools = ToolStatus()
    @Published var options = DownloadOptions()
    @Published var globalOutputFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true).path
    @Published private(set) var videoInfo: VideoInfo?
    @Published private(set) var inspectedURL: URL?
    @Published private(set) var isInspecting = false
    @Published private(set) var infoError: String?
    @Published private(set) var isUpdatingYtDlp = false

    private var tasks: [UUID: Task<Void, Never>] = [:]

    init() {
        Task { await refreshTools() }
    }

    func refreshTools() async {
        tools = await ToolDiscovery.locate()
    }

    func updateYtDlp() {
        guard !isUpdatingYtDlp else { return }
        isUpdatingYtDlp = true
        Task {
            _ = try? await ShellProcess.run(command: "brew upgrade yt-dlp")
            await refreshTools()
            isUpdatingYtDlp = false
        }
    }

    func addURLs(from text: String) {
        let urls = parseURLs(text)
        jobs.append(contentsOf: urls.map(DownloadJob.init(url:)))
        if let firstURL = urls.first {
            Task { await inspect(url: firstURL) }
        }
    }

    func inspect(from text: String) {
        guard let url = parseURLs(text).first else {
            infoError = "Enter a valid http or https video URL."
            return
        }
        Task { await inspect(url: url) }
    }

    func commandPreview(for urlText: String) -> String {
        let url = parseURLs(urlText).first ?? inspectedURL
        var arguments = options.arguments(globalOutputFolder: globalOutputFolder)
        if let url { arguments += ["--", url.absoluteString] }
        return ShellProcess.command([tools.ytDlp?.path ?? "yt-dlp"] + arguments)
    }

    private func inspect(url: URL) async {
        guard let tool = tools.ytDlp else {
            infoError = "yt-dlp is not installed. Install it with: brew install yt-dlp ffmpeg"
            return
        }
        isInspecting = true
        infoError = nil
        inspectedURL = url
        do {
            videoInfo = try await VideoInfoService.fetch(url: url, tool: tool)
        } catch {
            infoError = error.localizedDescription
            videoInfo = nil
        }
        isInspecting = false
    }

    private func parseURLs(_ text: String) -> [URL] {
        text.split(whereSeparator: \.isNewline)
            .compactMap { URL(string: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.scheme == "https" || $0.scheme == "http" }
    }

    func startQueued() {
        guard let tool = tools.ytDlp else { return }
        for job in jobs where job.status == .queued || job.status == .failed || job.status == .cancelled {
            guard tasks[job.id] == nil else { continue }
            let jobID = job.id
            tasks[jobID] = Task { await download(jobID, using: tool) }
        }
    }

    func cancel(_ job: DownloadJob) {
        tasks[job.id]?.cancel()
    }

    func remove(_ job: DownloadJob) {
        tasks[job.id]?.cancel()
        jobs.removeAll { $0.id == job.id }
    }

    private func download(_ jobID: UUID, using tool: InstalledTool) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .downloading
        jobs[index].errorMessage = nil

        let url = jobs[index].url.absoluteString
        let command = ShellProcess.command([tool.path] + options.arguments(globalOutputFolder: globalOutputFolder) + ["--", url])

        do {
            let status = try await ShellProcess.run(command: command) { [weak self] line in
                guard line.hasPrefix("download:") else { return }
                let fields = line.dropFirst("download:".count).split(separator: "|", omittingEmptySubsequences: false)
                guard let percentField = fields.first else { return }
                let percent = Double(percentField.filter { $0.isNumber || $0 == "." }) ?? 0
                let speed = fields.count > 1 ? String(fields[1]).trimmingCharacters(in: .whitespaces) : ""
                let eta = fields.count > 2 ? String(fields[2]).trimmingCharacters(in: .whitespaces) : ""
                Task { @MainActor in
                    guard let self, let currentIndex = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    self.jobs[currentIndex].progress = min(max(percent / 100, 0), 1)
                    self.jobs[currentIndex].speed = speed
                    self.jobs[currentIndex].eta = eta
                }
            }

            guard let currentIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            if Task.isCancelled {
                jobs[currentIndex].status = .cancelled
            } else if status == 0 {
                jobs[currentIndex].status = .completed
                jobs[currentIndex].progress = 1
            } else {
                jobs[currentIndex].status = .failed
                jobs[currentIndex].errorMessage = "yt-dlp exited with status \(status)."
            }
        } catch {
            if let currentIndex = jobs.firstIndex(where: { $0.id == jobID }) {
                jobs[currentIndex].status = Task.isCancelled ? .cancelled : .failed
                jobs[currentIndex].errorMessage = Task.isCancelled ? nil : error.localizedDescription
            }
        }
        tasks[jobID] = nil
    }
}