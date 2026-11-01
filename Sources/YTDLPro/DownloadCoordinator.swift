import Foundation
import AppKit
@preconcurrency import UserNotifications

@MainActor
final class DownloadCoordinator: ObservableObject {
    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var history: [DownloadHistoryItem] = []
    @Published private(set) var profiles: [DownloadProfile] = []
    @Published var selectedProfileID: UUID? {
        didSet {
            guard oldValue != selectedProfileID else { return }
            loadSelectedProfile()
        }
    }
    @Published private(set) var tools = ToolStatus()
    @Published var toolPreference: ToolPreference {
        didSet {
            UserDefaults.standard.set(toolPreference.rawValue, forKey: "toolPreference")
            Task { await refreshTools() }
        }
    }
    @Published var options = DownloadOptions()
    @Published var globalOutputFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true).path {
        didSet { UserDefaults.standard.set(globalOutputFolder, forKey: "globalOutputFolder") }
    }
    @Published var folderPolicy: FolderPolicy = .alwaysUseDefault {
        didSet { UserDefaults.standard.set(folderPolicy.rawValue, forKey: "folderPolicy") }
    }
    @Published var maxConcurrentDownloads = 2 {
        didSet {
            UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads")
            scheduleQueuedDownloads()
        }
    }
    @Published var notificationsOnFinish = true {
        didSet { UserDefaults.standard.set(notificationsOnFinish, forKey: "notificationsOnFinish") }
    }
    @Published var notificationsOnFailure = true {
        didSet { UserDefaults.standard.set(notificationsOnFailure, forKey: "notificationsOnFailure") }
    }
    @Published var preventSleepWhileDownloading = true {
        didSet {
            UserDefaults.standard.set(preventSleepWhileDownloading, forKey: "preventSleepWhileDownloading")
            updateSleepActivity()
        }
    }
    @Published private(set) var videoInfo: VideoInfo?
    @Published private(set) var inspectedURL: URL?
    @Published private(set) var isInspecting = false
    @Published private(set) var infoError: String?
    @Published private(set) var isUpdatingYtDlp = false
    @Published private(set) var isDownloadingTools = false
    @Published private(set) var toolDownloadProgress = 0.0
    @Published private(set) var toolDownloadStatus: String?
    @Published private(set) var toolDownloadError: String?
    @Published private(set) var overallProgress = 0.0
    @Published private(set) var combinedSpeed = ""
    @Published private(set) var overallETA = ""

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var pausedJobs: Set<UUID> = []
    private var lastProgressUpdate = Date.distantPast
    private var sleepActivity: NSObjectProtocol?
    private let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true).path

    init() {
        let savedPreference = UserDefaults.standard.string(forKey: "toolPreference")
        _toolPreference = Published(initialValue: ToolPreference(rawValue: savedPreference ?? "") ?? .systemFirst)
        globalOutputFolder = UserDefaults.standard.string(forKey: "globalOutputFolder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true).path
        folderPolicy = FolderPolicy(rawValue: UserDefaults.standard.string(forKey: "folderPolicy") ?? "") ?? .alwaysUseDefault
        maxConcurrentDownloads = max(1, UserDefaults.standard.object(forKey: "maxConcurrentDownloads") as? Int ?? 2)
        notificationsOnFinish = UserDefaults.standard.object(forKey: "notificationsOnFinish") as? Bool ?? true
        notificationsOnFailure = UserDefaults.standard.object(forKey: "notificationsOnFailure") as? Bool ?? true
        preventSleepWhileDownloading = UserDefaults.standard.object(forKey: "preventSleepWhileDownloading") as? Bool ?? true
        history = HistoryStore.load()
        if let document = try? ProfileStore.load() {
            profiles = document.profiles
            selectedProfileID = profiles.contains(where: { $0.id == document.lastUsedProfileID }) ? document.lastUsedProfileID : profiles.first?.id
        } else {
            profiles = ProfileStore.builtIns()
            selectedProfileID = profiles.first?.id
            persistProfiles()
        }
        if let selectedProfileID, let profile = profiles.first(where: { $0.id == selectedProfileID }) {
            options = profile.options
            persistProfiles(lastUsedProfileID: selectedProfileID)
        }
        installDockProgressView()
        Task { await refreshTools() }
    }

    var selectedProfile: DownloadProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    func refreshTools() async {
        let preference = toolPreference
        let discoveredTools = await ToolDiscovery.locate(preference: preference)
        guard preference == toolPreference else { return }
        tools = discoveredTools
    }

    func updateYtDlp() {
        guard !isUpdatingYtDlp else { return }
        guard let activeTool = tools.ytDlp else { return }
        isUpdatingYtDlp = true
        Task {
            let command = activeTool.source == .builtIn
                ? ShellProcess.command([activeTool.path, "-U"])
                : "brew upgrade yt-dlp"
            _ = try? await ShellProcess.run(command: command)
            await refreshTools()
            isUpdatingYtDlp = false
        }
    }

    func downloadTools() {
        guard !isDownloadingTools, !tools.missingTools.isEmpty else { return }
        let missingNames = tools.missingTools
        isDownloadingTools = true
        toolDownloadProgress = 0
        toolDownloadError = nil
        toolDownloadStatus = "Preparing downloads"
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ToolInstaller.installMissing(missingNames) { [weak self] name, fraction, stage in
                    Task { @MainActor [weak self] in
                        self?.toolDownloadProgress = fraction
                        self?.toolDownloadStatus = "\(stage): \(name)"
                    }
                }
                await refreshTools()
                toolDownloadProgress = 1
                toolDownloadStatus = "Tools installed and verified"
            } catch {
                await refreshTools()
                toolDownloadError = error.localizedDescription
                toolDownloadStatus = nil
            }
            isDownloadingTools = false
        }
    }

    func selectProfile(_ profileID: UUID?) {
        selectedProfileID = profileID
        if let profileID { persistProfiles(lastUsedProfileID: profileID) }
    }

    func saveCurrentProfile(named name: String, outputFolder: String = "") {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var savedOptions = options
        let profileFolder = outputFolder.isEmpty ? savedOptions.outputFolder : outputFolder
        savedOptions.outputFolder = ""
        let profile = DownloadProfile(name: name, options: savedOptions, outputFolder: profileFolder)
        profiles.append(profile)
        selectProfile(profile.id)
        persistProfiles()
    }

    func renameProfile(_ profileID: UUID, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = profiles.firstIndex(where: { $0.id == profileID }), !profiles[index].isBuiltIn else { return }
        profiles[index].name = name
        persistProfiles()
    }

    func setProfileFolder(_ profileID: UUID, to folder: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }), !profiles[index].isBuiltIn else { return }
        profiles[index].outputFolder = folder
        persistProfiles()
    }

    func duplicateProfile(_ profileID: UUID) {
        guard let source = profiles.first(where: { $0.id == profileID }) else { return }
        let copy = DownloadProfile(name: "\(source.name) Copy", options: source.options, outputFolder: source.outputFolder)
        profiles.append(copy)
        selectProfile(copy.id)
        persistProfiles()
    }

    func deleteProfile(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }), !profile.isBuiltIn else { return }
        profiles.removeAll { $0.id == profileID }
        if selectedProfileID == profileID { selectProfile(profiles.first?.id) }
        persistProfiles()
    }

    func importProfiles(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported: [DownloadProfile]
        if let profileList = try? JSONDecoder().decode([DownloadProfile].self, from: data) {
            imported = profileList
        } else {
            imported = try JSONDecoder().decode(ProfileDocument.self, from: data).profiles
        }
        profiles.append(contentsOf: imported.map { profile in
            var profile = profile
            profile.id = UUID()
            profile.isBuiltIn = false
            return profile
        })
        persistProfiles()
    }

    func exportProfiles(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let exportable = profiles.filter { !$0.isBuiltIn }
        try encoder.encode(exportable).write(to: url, options: .atomic)
    }

    func saveProfileDocument() { persistProfiles() }

    func resetGlobalOutputFolder() { globalOutputFolder = defaultFolder }

    func updateGlobalFolderFromLastUse(_ folder: String) {
        guard folderPolicy == .rememberLastFolder, !folder.isEmpty else { return }
        globalOutputFolder = folder
    }

    func revealInFinder(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func addHistoryItemAgain(_ item: DownloadHistoryItem) {
        var job = DownloadJob(url: item.url, options: item.options)
        job.profileID = item.profileID
        job.profileName = item.profileName
        job.profileOutputFolder = item.profileOutputFolder
        jobs.append(job)
        startQueued()
    }

    func removeHistory(_ item: DownloadHistoryItem) {
        history.removeAll { $0.id == item.id }
        persistHistory()
    }

    func applyProfile(_ profileID: UUID?, to jobID: UUID) {
        guard let profileID, let profile = profiles.first(where: { $0.id == profileID }),
              let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status != .downloading else { return }
        jobs[index].options = profile.options
        jobs[index].profileID = profile.id
        jobs[index].profileName = profile.name
        jobs[index].profileOutputFolder = profile.outputFolder
    }

    func setDownloadFolder(_ folder: String, for jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].status != .downloading else { return }
        jobs[index].options.outputFolder = folder
    }

    func addURLs(from text: String) {
        let urls = parseURLs(text)
        let profile = selectedProfile
        jobs.append(contentsOf: urls.map { DownloadJob(url: $0, options: options, profile: profile) })
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
        var previewOptions = options
        previewOptions.outputFolder = ProfileStore.resolvedFolder(
            perDownload: options.outputFolder,
            profile: selectedProfile?.outputFolder ?? "",
            global: globalOutputFolder
        )
        var arguments = previewOptions.arguments(globalOutputFolder: globalOutputFolder)
        if let ffmpeg = tools.ffmpeg { arguments += ["--ffmpeg-location", ffmpeg.path] }
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
            if let title = videoInfo?.title {
                for index in jobs.indices where jobs[index].url == url { jobs[index].title = title }
            }
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
        scheduleQueuedDownloads()
    }

    func cancel(_ job: DownloadJob) {
        pausedJobs.remove(job.id)
        tasks[job.id]?.cancel()
        if let index = jobs.firstIndex(where: { $0.id == job.id }), tasks[job.id] == nil {
            jobs[index].status = .cancelled
        }
    }

    func pause(_ job: DownloadJob) {
        guard job.status == .downloading else { return }
        pausedJobs.insert(job.id)
        tasks[job.id]?.cancel()
    }

    func resume(_ job: DownloadJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }), jobs[index].status == .paused else { return }
        pausedJobs.remove(job.id)
        jobs[index].status = .queued
        scheduleQueuedDownloads()
    }

    func retry(_ job: DownloadJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }), jobs[index].status == .failed || jobs[index].status == .cancelled else { return }
        jobs[index].progress = 0
        jobs[index].errorMessage = nil
        jobs[index].status = .queued
        scheduleQueuedDownloads()
    }

    func moveJobs(from source: IndexSet, to destination: Int) {
        jobs.move(fromOffsets: source, toOffset: destination)
    }

    func moveJob(_ jobID: UUID, by offset: Int) {
        guard let current = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let destination = current + offset
        guard jobs.indices.contains(destination), jobs[current].status != .downloading,
              jobs[destination].status != .downloading else { return }
        jobs.swapAt(current, destination)
    }

    func remove(_ job: DownloadJob) {
        if tasks[job.id] != nil {
            cancel(job)
            return
        }
        tasks[job.id]?.cancel()
        jobs.removeAll { $0.id == job.id }
        updateAggregateProgress(force: true)
    }

    private func scheduleQueuedDownloads() {
        guard let tool = tools.ytDlp else { return }
        let activeCount = tasks.count
        let availableSlots = max(0, maxConcurrentDownloads - activeCount)
        guard availableSlots > 0 else { return }
        let queued = jobs.filter { $0.status == .queued && tasks[$0.id] == nil }.prefix(availableSlots)
        for job in queued {
            let jobID = job.id
            tasks[jobID] = Task { await download(jobID, using: tool) }
        }
    }

    private func download(_ jobID: UUID, using tool: InstalledTool) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].status = .downloading
        jobs[index].errorMessage = nil
        updateSleepActivity()
        updateAggregateProgress(force: true)

        let job = jobs[index]
        let url = job.url.absoluteString
        var effectiveOptions = job.options
        effectiveOptions.outputFolder = ProfileStore.resolvedFolder(
            perDownload: job.options.outputFolder,
            profile: job.profileOutputFolder ?? "",
            global: globalOutputFolder
        )
        var arguments = effectiveOptions.arguments(globalOutputFolder: globalOutputFolder)
        if let ffmpeg = tools.ffmpeg { arguments += ["--ffmpeg-location", ffmpeg.path] }
        arguments += ["--print", "after_move:YT-DLPRO_PATH:%(filepath)s", "--", url]
        let command = ShellProcess.command([tool.path] + arguments)
        let outputCollector = JobOutputPathCollector()

        do {
            let status = try await ShellProcess.run(command: command) { [weak self] line in
                if !line.hasPrefix("download:") {
                    let outputPrefix = "YT-DLPRO_PATH:"
                    if line.hasPrefix(outputPrefix) {
                        outputCollector.append(String(line.dropFirst(outputPrefix.count)))
                    }
                    return
                }
                guard line.hasPrefix("download:") else { return }
                let fields = line.dropFirst("download:".count).split(separator: "|", omittingEmptySubsequences: false)
                guard let percentField = fields.first else { return }
                let percent = Double(percentField.filter { $0.isNumber || $0 == "." }) ?? 0
                let speed = fields.count > 1 ? String(fields[1]).trimmingCharacters(in: .whitespaces) : ""
                let eta = fields.count > 2 ? String(fields[2]).trimmingCharacters(in: .whitespaces) : ""
                Task { @MainActor in
                    guard let self, let currentIndex = self.jobs.firstIndex(where: { $0.id == jobID }) else { return }
                    guard Date().timeIntervalSince(self.lastProgressUpdate) >= 0.25 else { return }
                    self.jobs[currentIndex].progress = min(max(percent / 100, 0), 1)
                    self.jobs[currentIndex].speed = speed
                    self.jobs[currentIndex].eta = eta
                    self.updateAggregateProgress()
                }
            }

            guard let currentIndex = jobs.firstIndex(where: { $0.id == jobID }) else { return }
            let outputPath = outputCollector.value
            if Task.isCancelled {
                jobs[currentIndex].status = pausedJobs.contains(jobID) ? .paused : .cancelled
            } else if status == 0 {
                jobs[currentIndex].status = .completed
                jobs[currentIndex].progress = 1
                jobs[currentIndex].outputPath = outputPath
                history.insert(DownloadHistoryItem(
                    url: job.url,
                    title: job.title,
                    outputPath: outputPath,
                    profileName: job.profileName,
                    options: job.options,
                    profileID: job.profileID,
                    profileOutputFolder: job.profileOutputFolder
                ), at: 0)
                persistHistory()
                updateGlobalFolderFromLastUse(effectiveOptions.outputFolder)
                if notificationsOnFinish { sendNotification(title: "Download complete", body: job.title) }
            } else {
                jobs[currentIndex].status = .failed
                jobs[currentIndex].errorMessage = "yt-dlp exited with status \(status)."
                if notificationsOnFailure { sendNotification(title: "Download failed", body: job.title) }
            }
        } catch {
            if let currentIndex = jobs.firstIndex(where: { $0.id == jobID }) {
                jobs[currentIndex].status = Task.isCancelled ? (pausedJobs.contains(jobID) ? .paused : .cancelled) : .failed
                jobs[currentIndex].errorMessage = Task.isCancelled ? nil : error.localizedDescription
            }
        }
        tasks[jobID] = nil
        updateSleepActivity()
        updateAggregateProgress(force: true)
        scheduleQueuedDownloads()
    }

    private func loadSelectedProfile() {
        guard let profile = selectedProfile else { return }
        options = profile.options
        persistProfiles(lastUsedProfileID: profile.id)
    }

    private func persistProfiles(lastUsedProfileID: UUID? = nil) {
        let currentID = lastUsedProfileID ?? selectedProfileID
        try? ProfileStore.save(ProfileDocument(profiles: profiles, lastUsedProfileID: currentID))
    }

    private func persistHistory() { try? HistoryStore.save(history) }

    private func updateAggregateProgress(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressUpdate) >= 0.25 else { return }
        lastProgressUpdate = now
        let total = jobs.count
        guard total > 0 else {
            overallProgress = 0
            combinedSpeed = ""
            overallETA = ""
            DockProgressView.shared.update(progress: 0)
            return
        }
        overallProgress = jobs.reduce(0.0) { partial, job in
            partial + (job.status == .completed ? 1 : job.progress)
        } / Double(total)
        let speeds = jobs.filter { $0.status == .downloading }.compactMap { Self.bytesPerSecond($0.speed) }
        let bytesPerSecond = speeds.reduce(0, +)
        combinedSpeed = bytesPerSecond > 0 ? ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s" : ""
        let activeETAs = jobs.filter { $0.status == .downloading }.compactMap { Self.seconds(fromETA: $0.eta) }
        let pendingCount = jobs.filter { $0.status == .queued || $0.status == .paused }.count
        let activeSpan = activeETAs.max() ?? 0
        let averageSpan = activeETAs.isEmpty ? 0 : activeETAs.reduce(0, +) / activeETAs.count
        let queuedSpan = averageSpan * Int(ceil(Double(pendingCount) / Double(maxConcurrentDownloads)))
        let remainingSeconds = activeSpan + queuedSpan
        overallETA = remainingSeconds > 0 ? Self.formatDuration(remainingSeconds) : ""
        DockProgressView.shared.update(progress: overallProgress)
    }

    private static func bytesPerSecond(_ speed: String) -> Double? {
        let value = speed.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = Double(value.prefix { $0.isNumber || $0 == "." })
        guard let number else { return nil }
        let suffix = value.drop(while: { $0.isNumber || $0 == "." }).lowercased()
        if suffix.contains("gib") || suffix.contains("gb") { return number * 1_000_000_000 }
        if suffix.contains("mib") || suffix.contains("mb") { return number * 1_000_000 }
        if suffix.contains("kib") || suffix.contains("kb") { return number * 1_000 }
        return number
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(seconds % 60)s"
    }

    private static func seconds(fromETA eta: String) -> Int? {
        let parts = eta.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reversed().enumerated().reduce(0) { total, value in
            total + value.element * Int(pow(60.0, Double(value.offset)))
        }
    }

    private func sendNotification(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private func installDockProgressView() {
        NSApp.dockTile.contentView = DockProgressView.shared
        NSApp.dockTile.display()
    }

    private func updateSleepActivity() {
        let hasActiveDownloads = jobs.contains { $0.status == .downloading }
        if preventSleepWhileDownloading, hasActiveDownloads, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "YT-DLPro downloads are active")
        } else if (!preventSleepWhileDownloading || !hasActiveDownloads), let sleepActivity {
            ProcessInfo.processInfo.endActivity(sleepActivity)
            self.sleepActivity = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private final class JobOutputPathCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    func append(_ path: String) {
        lock.lock()
        self.path = path
        lock.unlock()
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }
}