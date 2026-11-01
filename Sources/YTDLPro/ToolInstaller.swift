import CryptoKit
import Foundation

enum ToolInstaller {
    static let binaryDirectory = ToolDiscovery.fallbackDirectory
    private static let ffmpegRelease = "b6.1.1"

    static func installMissing(
        _ missingNames: [String],
        onProgress: @escaping @Sendable (String, Double, String) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        var names = missingNames
        if missingNames.contains("ffmpeg"), !names.contains("ffprobe") { names.append("ffprobe") }

        for name in names {
            let asset = try asset(named: name)
            let expectedChecksum = try await expectedChecksum(for: asset, name: name)
            onProgress(name, 0, "Downloading")
            let temporaryURL = binaryDirectory.appendingPathComponent(".\(name)-\(UUID().uuidString).download")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try await URLSessionFileDownload.download(from: asset.url, to: temporaryURL) { fraction in
                onProgress(name, fraction, "Downloading")
            }

            if let expectedChecksum {
                onProgress(name, 1, "Verifying checksum")
                let actualChecksum = try await checksum(of: temporaryURL)
                guard actualChecksum == expectedChecksum else {
                    throw ToolInstallError.checksumMismatch(name)
                }
            }

            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryURL.path)
            removeQuarantine(from: temporaryURL)
            onProgress(name, 1, "Verifying version")
            guard await ToolDiscovery.verify(path: temporaryURL, name: name, versionArguments: asset.versionArguments) != nil else {
                throw ToolInstallError.versionCheckFailed(name)
            }

            let installedURL = binaryDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: installedURL.path) {
                _ = try fileManager.replaceItemAt(installedURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: installedURL)
            }

            if let licenseURL = asset.licenseURL, name == "ffmpeg" {
                let (licenseData, _) = try await URLSession.shared.data(from: licenseURL)
                try licenseData.write(to: binaryDirectory.appendingPathComponent("ffmpeg.LICENSE"), options: .atomic)
            }
        }
    }

    private static func asset(named name: String) throws -> ToolAsset {
        switch name {
        case "yt-dlp":
            let baseURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/")!
            let sumsURL = baseURL.appendingPathComponent("SHA2-256SUMS")
            let binaryURL = baseURL.appendingPathComponent("yt-dlp_macos")
            return ToolAsset(url: binaryURL, versionArguments: ["--version"], checksumURL: sumsURL)
        case "ffmpeg", "ffprobe":
            let architecture = ToolArchitecture.current.rawValue
            let baseURL = URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/\(ffmpegRelease)/")!
            let filename = "\(name)-darwin-\(architecture)"
            let checksum: String
            let licenseURL: URL?
            if name == "ffmpeg", architecture == "arm64" {
                checksum = "a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584"
                licenseURL = baseURL.appendingPathComponent("darwin-arm64.LICENSE")
            } else if name == "ffmpeg" {
                checksum = "ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894"
                licenseURL = baseURL.appendingPathComponent("darwin-x64.LICENSE")
            } else if architecture == "arm64" {
                checksum = "bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64"
                licenseURL = nil
            } else {
                checksum = "fa3add0ce901f7241abe0dfc0155d958fc834aca3f8ce61f87cc712ae669c1e0"
                licenseURL = nil
            }
            return ToolAsset(
                url: baseURL.appendingPathComponent(filename),
                versionArguments: ["-version"],
                sha256: checksum,
                licenseURL: licenseURL
            )
        default:
            throw ToolInstallError.unsupportedTool(name)
        }
    }

    private static func checksum(of fileURL: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            let file = try FileHandle(forReadingFrom: fileURL)
            defer { try? file.close() }
            var hasher = SHA256()
            while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private static func expectedChecksum(for asset: ToolAsset, name: String) async throws -> String? {
        if let sha256 = asset.sha256 { return sha256 }
        guard let checksumURL = asset.checksumURL else { return nil }
        let (data, _) = try await URLSession.shared.data(from: checksumURL)
        guard let checksum = checksum(in: String(decoding: data, as: UTF8.self), for: name) else {
            throw ToolInstallError.checksumUnavailable(name)
        }
        return checksum
    }

    static func checksum(in manifest: String, for name: String) -> String? {
        for line in manifest.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let filename = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if filename == name { return String(fields[0]).lowercased() }
        }
        return nil
    }

    private static func removeQuarantine(from fileURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", fileURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // The quarantine attribute is absent on some downloads.
        }
    }
}

private struct ToolAsset {
    let url: URL
    let versionArguments: [String]
    var sha256: String?
    var checksumURL: URL?
    var licenseURL: URL?

    init(url: URL, versionArguments: [String], sha256: String? = nil, checksumURL: URL? = nil, licenseURL: URL? = nil) {
        self.url = url
        self.versionArguments = versionArguments
        self.sha256 = sha256
        self.checksumURL = checksumURL
        self.licenseURL = licenseURL
    }
}

private enum ToolInstallError: LocalizedError {
    case unsupportedTool(String)
    case checksumUnavailable(String)
    case checksumMismatch(String)
    case versionCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let name): "No download source is configured for \(name)."
        case .checksumUnavailable(let name): "Could not find the official SHA-256 checksum for \(name)."
        case .checksumMismatch(let name): "The downloaded \(name) binary failed its SHA-256 check. It was not installed."
        case .versionCheckFailed(let name): "The downloaded \(name) binary did not pass its version check. It was not installed."
        }
    }
}

private enum URLSessionFileDownload {
    static func download(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = FileDownloadDelegate(destination: destination, onProgress: onProgress)
        try await delegate.start(url: url)
    }
}

private final class FileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func start(url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success: continuation.resume()
        case .failure(let error): continuation.resume(throwing: error)
        }
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
    }
}