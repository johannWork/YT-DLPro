import Foundation

enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

struct DownloadJob: Identifiable {
    let id: UUID
    let url: URL
    var status: DownloadStatus
    var progress: Double
    var speed: String
    var eta: String
    var errorMessage: String?

    init(url: URL) {
        id = UUID()
        self.url = url
        status = .queued
        progress = 0
        speed = ""
        eta = ""
    }
}