import Foundation

enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    case paused = "Paused"
}

struct DownloadJob: Identifiable {
    let id: UUID
    let url: URL
    var title: String
    var options: DownloadOptions
    var profileID: UUID?
    var profileName: String?
    var profileOutputFolder: String?
    var outputPath: String?
    var status: DownloadStatus
    var progress: Double
    var speed: String
    var eta: String
    var errorMessage: String?

    init(url: URL, options: DownloadOptions = DownloadOptions(), profile: DownloadProfile? = nil) {
        id = UUID()
        self.url = url
        title = url.host ?? url.absoluteString
        self.options = options
        profileID = profile?.id
        profileName = profile?.name
        profileOutputFolder = profile?.outputFolder
        outputPath = nil
        status = .queued
        progress = 0
        speed = ""
        eta = ""
    }
}

enum FolderPolicy: String, CaseIterable, Identifiable {
    case alwaysUseDefault = "Always use this folder"
    case rememberLastFolder = "Remember the last folder used"

    var id: String { rawValue }
}

struct DownloadHistoryItem: Identifiable, Codable {
    let id: UUID
    let url: URL
    let title: String
    let downloadedAt: Date
    let outputPath: String?
    let profileName: String?
    let options: DownloadOptions
    let profileID: UUID?
    let profileOutputFolder: String?

    init(url: URL, title: String, downloadedAt: Date = Date(), outputPath: String?, profileName: String?, options: DownloadOptions, profileID: UUID?, profileOutputFolder: String?) {
        id = UUID()
        self.url = url
        self.title = title
        self.downloadedAt = downloadedAt
        self.outputPath = outputPath
        self.profileName = profileName
        self.options = options
        self.profileID = profileID
        self.profileOutputFolder = profileOutputFolder
    }
}