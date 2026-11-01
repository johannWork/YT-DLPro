import Foundation
import AppKit
@preconcurrency import UserNotifications

@MainActor
final class DownloadCoordinator: ObservableObject {
    @Published private(set) var jobs: [DownloadJob] = []
    @Published private(set) var history: [DownloadHistoryItem] = []
    @Published private(set) var profiles: [DownloadProfile] = []
    @Published private(set) var isCheckingInitialSetup = true
    @Published private(set) var outputFolderAccessible = false
    @Published private(set) var notificationsAuthorized = false
    @Published private(set) var isCheckingRequirements = false
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
    @Published var clipboardWatcherEnabled = false {
        didSet {
            UserDefaults.standard.set(clipboardWatcherEnabled, forKey: "clipboardWatcherEnabled")
            updateClipboardWatcher()
        }
    }
    @Published var clipboardURLToAdd: URL?
    @Published private(set) var terminalError: String?
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
    private var clipboardWatcherTask: Task<Void, Never>?
    private var clipboardWatcherID: UUID?
    private var clipboardChangeCount = NSPasteboard.general.changeCount
    private var notificationTokens: [NSObjectProtocol] = []
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
        clipboardWatcherEnabled = UserDefaults.standard.bool(forKey: "clipboardWatcherEnabled")
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
        notificationTokens.append(NotificationCenter.default.addObserver(forName: .ytDlpOpenURLs, object: nil, queue: .main) { [weak self] notification in
            guard let urls = notification.object as? [URL] else { return }
            Task { @MainActor in self?.addURLs(from: urls.map(\.absoluteString).joined(separator: "\n")) }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateClipboardWatcher() }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopClipboardWatcher() }
        })
        updateClipboardWatcher()
        Task { await refreshTools() }
    }

    var selectedProfile: DownloadProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    var selectedProfileHasChanges: Bool {
        guard let selectedProfile else { return false }
        return options != selectedProfile.options
    }

    func refreshTools() async {
        let preference = toolPreference
        let discoveredTools = await ToolDiscovery.locate(preference: preference)
        guard preference == toolPreference else { return }
        tools = discoveredTools
        isCheckingInitialSetup = false
        await refreshRequirements()
    }

    func refreshRequirements() async {
        isCheckingRequirements = true
        outputFolderAccessible = Self.canWriteToDirectory(globalOutputFolder)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        isCheckingRequirements = false
    }

    func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshRequirements()
        }
    }

    func chooseGlobalOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            globalOutputFolder = url.path
            Task { await refreshRequirements() }
        }
    }

    private static func canWriteToDirectory(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path), FileManager.default.isWritableFile(atPath: url.path) else { return false }
        let probeURL = url.appendingPathComponent(".ytdlpro-write-check-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .atomic)
            try FileManager.default.removeItem(at: probeURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            return false
        }
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

    func downloadTools(_ requestedNames: [String]? = nil) {
        let missingNames = requestedNames ?? tools.missingTools
        guard !isDownloadingTools, !missingNames.isEmpty else { return }
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

    func installManualTool(from url: URL, name: String) {
        isDownloadingTools = true
        toolDownloadError = nil
        toolDownloadStatus = "Verifying selected \(name) file"
        Task {
            do {
                try await ToolInstaller.installManualTool(from: url, name: name)
                await refreshTools()
                toolDownloadStatus = "\(name) installed and verified"
                toolDownloadProgress = 1
            } catch {
                toolDownloadStatus = nil
                toolDownloadError = error.localizedDescription
            }
            isDownloadingTools = false
        }
    }

    func selectProfile(_ profileID: UUID?) {
        selectedProfileID = profileID
        if let profileID { persistProfiles(lastUsedProfileID: profileID) }
    }

    func saveChangesToSelectedProfile() {
        guard let selectedProfile,
              let index = profiles.firstIndex(where: { $0.id == selectedProfile.id }) else { return }
        var savedOptions = options
        let updatedFolder = savedOptions.outputFolder
        savedOptions.outputFolder = ""
        profiles[index].options = savedOptions
        if !updatedFolder.isEmpty { profiles[index].outputFolder = updatedFolder }
        options = savedOptions
        reloadQueuedJobs(for: profiles[index])
        persistProfiles()
    }

    func revertChangesToSelectedProfile() {
        loadSelectedProfile()
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
              let index = jobs.firstIndex(where: { $0.id == jobID }), !jobs[index].hasStarted else { return }
        jobs[index].apply(profile: profile)
    }

    func setDownloadFolder(_ folder: String, for jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), !jobs[index].hasStarted else { return }
        jobs[index].perDownloadFolderOverride = folder
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
        var arguments = ytDlpArguments(for: options, profileFolder: selectedProfile?.outputFolder ?? "")
        if let url { arguments += ["--", url.absoluteString] }
        return ShellProcess.command([tools.ytDlp?.path ?? "yt-dlp"] + arguments)
    }

    func openCommandInTerminal(for urlText: String) {
        let command = commandPreview(for: urlText)
        terminalError = nil
        Task {
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = "tell application \"Terminal\" to do script \"\(escaped)\""
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus == 0 ? nil : "Terminal could not be opened. Check YT-DLPro permissions under System Settings > Privacy & Security > Automation."
                } catch {
                    return error.localizedDescription
                }
            }.value
            terminalError = failure
        }
    }

    func addClipboardURLToQueue() {
        guard let clipboardURLToAdd else { return }
        addURLs(from: clipboardURLToAdd.absoluteString)
        self.clipboardURLToAdd = nil
    }

    func dismissClipboardOffer() { clipboardURLToAdd = nil }

    private func inspect(url: URL) async {
        guard let tool = tools.ytDlp else {
            infoError = "yt-dlp is not installed. Install it with: brew install yt-dlp ffmpeg"
            return
        }
        isInspecting = true
        infoError = nil
        inspectedURL = url
        do {
            videoInfo = try await VideoInfoService.fetch(url: url, tool: tool, jsRuntime: tools.jsRuntime)
            if let title = videoInfo?.title {
                for index in jobs.indices where jobs[index].url == url { jobs[index].title = title }
            }
        } catch {
            infoError = Self.userFacingDownloadError(error.localizedDescription, cookieBrowser: options.cookieBrowser) ?? error.localizedDescription
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
            guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { continue }
            jobs[index].prepareToStart(options: options, profile: selectedProfile)
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
        let effectiveOptions = resolvedOptions(for: job.options, profileFolder: job.profileOutputFolder ?? "")
        var arguments = ytDlpArguments(for: job.options, profileFolder: job.profileOutputFolder ?? "")
        arguments += ["--", url]
        let command = ShellProcess.command([tool.path] + arguments)
        let outputCollector = JobOutputPathCollector()
        let logCollector = JobOutputLogCollector()

        do {
            var status = try await runDownload(command: command, jobID: jobID, outputCollector: outputCollector, logCollector: logCollector)
            let shouldReencodeMP4 = effectiveOptions.videoContainer == .mp4
                && effectiveOptions.mediaType != .audioOnly
                && effectiveOptions.selectedFormatID.isEmpty
                && !Task.isCancelled
                && Self.hasNoCompatibleFormatError(logCollector.value)

            if status != 0, shouldReencodeMP4 {
                outputCollector.clear()
                var fallbackArguments = ytDlpArguments(
                    for: job.options,
                    profileFolder: job.profileOutputFolder ?? "",
                    forceMP4Reencode: true
                )
                fallbackArguments += ["--", url]
                let fallbackCommand = ShellProcess.command([tool.path] + fallbackArguments)
                status = try await runDownload(command: fallbackCommand, jobID: jobID, outputCollector: outputCollector, logCollector: logCollector)
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
                jobs[currentIndex].errorMessage = Self.userFacingDownloadError(logCollector.value, cookieBrowser: job.options.cookieBrowser)
                    ?? "yt-dlp exited with status \(status)."
                if notificationsOnFailure { sendNotification(title: "Download failed", body: job.title) }
            }
        } catch {
            if let currentIndex = jobs.firstIndex(where: { $0.id == jobID }) {
                jobs[currentIndex].status = Task.isCancelled ? (pausedJobs.contains(jobID) ? .paused : .cancelled) : .failed
                jobs[currentIndex].errorMessage = Task.isCancelled ? nil : Self.userFacingDownloadError(error.localizedDescription, cookieBrowser: job.options.cookieBrowser) ?? error.localizedDescription
            }
        }
        tasks[jobID] = nil
        updateSleepActivity()
        updateAggregateProgress(force: true)
        scheduleQueuedDownloads()
    }

    private func runDownload(
        command: String,
        jobID: UUID,
        outputCollector: JobOutputPathCollector,
        logCollector: JobOutputLogCollector
    ) async throws -> Int32 {
        try await ShellProcess.run(command: command) { [weak self] line in
            if !line.hasPrefix("download:") {
                let outputPrefix = "YT-DLPRO_PATH:"
                if line.hasPrefix(outputPrefix) {
                    outputCollector.append(String(line.dropFirst(outputPrefix.count)))
                } else {
                    logCollector.append(line)
                }
                return
            }
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
    }

    private static func hasNoCompatibleFormatError(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("requested format is not available") || normalized.contains("no video formats found")
    }

    nonisolated static func userFacingDownloadError(_ output: String, cookieBrowser: CookieBrowser) -> String? {
        let normalized = output.lowercased()
        if cookieBrowser == .safari,
           normalized.contains("operation not permitted") || normalized.contains("permission denied") || normalized.contains("could not copy cookies") || normalized.contains("failed to decrypt") {
            return "Safari cookies could not be read. Enable YT-DLPro in System Settings > Privacy & Security > Full Disk Access, then quit and reopen the app."
        }
        if normalized.contains("age-restricted") || normalized.contains("sign in to confirm your age") || normalized.contains("confirm your age") {
            return "This video is age-restricted. Enable Safari cookies in YT-DLPro settings and grant Full Disk Access, or choose another browser with an authenticated session."
        }
        if normalized.contains("private video") || normalized.contains("video is private") || normalized.contains("private video") {
            return "This video is private or unavailable to the current account. Use cookies from an account with permission to view it."
        }
        if normalized.contains("not available in your country") || normalized.contains("geo-restricted") || normalized.contains("geographic restriction") || normalized.contains("blocked in your country") {
            return "This video is geo-blocked for your current network location. Try a permitted network location or a proxy you are authorized to use."
        }
        if normalized.contains("ffmpeg not found") || normalized.contains("ffmpeg is not installed") || normalized.contains("ffmpeg is required") || normalized.contains("ffmpeg/ffprobe not found") {
            return "This option requires ffmpeg. Install it with `brew install ffmpeg` or use Settings > Download tools."
        }
        return nil
    }

    private func loadSelectedProfile() {
        guard let profile = selectedProfile else { return }
        options = profile.options
        reloadQueuedJobs(for: profile)
        persistProfiles(lastUsedProfileID: profile.id)
    }

    private func reloadQueuedJobs(for profile: DownloadProfile) {
        for index in jobs.indices where jobs[index].status == .queued && !jobs[index].hasStarted {
            jobs[index].apply(profile: profile)
        }
    }

    private func resolvedOptions(for options: DownloadOptions, profileFolder: String) -> DownloadOptions {
        var resolved = options
        resolved.outputFolder = ProfileStore.resolvedFolder(
            perDownload: options.outputFolder,
            profile: profileFolder,
            global: globalOutputFolder
        )
        return resolved
    }

    private func ytDlpArguments(
        for options: DownloadOptions,
        profileFolder: String,
        forceMP4Reencode: Bool = false
    ) -> [String] {
        let effectiveOptions = resolvedOptions(for: options, profileFolder: profileFolder)
        var arguments = effectiveOptions.arguments(
            globalOutputFolder: globalOutputFolder,
            forceMP4Reencode: forceMP4Reencode
        )
        if let ffmpeg = tools.ffmpeg { arguments += ["--ffmpeg-location", ffmpeg.path] }
        if let jsRuntime = tools.jsRuntime {
            arguments += ["--js-runtimes", "deno:\(jsRuntime.path)", "--remote-components", "ejs:github"]
        }
        arguments += ["--print", "after_move:YT-DLPRO_PATH:%(filepath)s"]
        return arguments
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

    private func updateClipboardWatcher() {
        guard clipboardWatcherEnabled, NSApp.isActive else {
            stopClipboardWatcher()
            return
        }
        guard clipboardWatcherTask == nil else { return }
        clipboardChangeCount = NSPasteboard.general.changeCount
        let watcherID = UUID()
        clipboardWatcherID = watcherID
        clipboardWatcherTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.clipboardWatcherEnabled, NSApp.isActive, !Task.isCancelled else { break }
                let pasteboard = NSPasteboard.general
                guard pasteboard.changeCount != self.clipboardChangeCount else { continue }
                self.clipboardChangeCount = pasteboard.changeCount
                guard let text = pasteboard.string(forType: .string),
                      let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                      url.scheme == "http" || url.scheme == "https" else { continue }
                self.clipboardURLToAdd = url
            }
            guard self?.clipboardWatcherID == watcherID else { return }
            self?.clipboardWatcherID = nil
            self?.clipboardWatcherTask = nil
        }
    }

    private func stopClipboardWatcher() {
        clipboardWatcherID = nil
        clipboardWatcherTask?.cancel()
        clipboardWatcherTask = nil
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

extension Notification.Name {
    static let ytDlpOpenURLs = Notification.Name("YT-DLPro.OpenURLs")
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

    func clear() {
        lock.lock()
        path = nil
        lock.unlock()
    }

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }
}

private final class JobOutputLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}