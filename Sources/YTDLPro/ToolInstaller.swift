import CryptoKit
import Foundation

enum ToolInstaller {
    static let binaryDirectory = ToolDiscovery.fallbackDirectory

    static func installMissing(
        _ missingNames: [String],
        in binaryDirectory: URL = binaryDirectory,
        onProgress: @escaping @Sendable (String, Double, String) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        var names = missingNames
        if missingNames.contains("ffmpeg"), !names.contains("ffprobe") { names.append("ffprobe") }

        for name in names {
            let asset = try asset(named: name)
            let checksumValue: String?
            do {
                checksumValue = try await expectedChecksum(for: asset, name: name)
            } catch {
                throw ToolInstallError.downloadHostUnavailable(name, asset.url, error.localizedDescription)
            }
            onProgress(name, 0, "Downloading")
            let temporaryURL = binaryDirectory.appendingPathComponent(".\(name)-\(UUID().uuidString).download")
            defer { try? fileManager.removeItem(at: temporaryURL) }
            let extractionDirectory = binaryDirectory.appendingPathComponent(".\(name)-\(UUID().uuidString).extract", isDirectory: true)
            defer { try? fileManager.removeItem(at: extractionDirectory) }
            do {
                try await URLSessionFileDownload.download(from: asset.url, to: temporaryURL) { fraction in
                    onProgress(name, fraction, "Downloading")
                }
            } catch {
                throw ToolInstallError.downloadHostUnavailable(name, asset.url, error.localizedDescription)
            }

            if let checksumValue {
                onProgress(name, 1, "Verifying checksum")
                let actualChecksum = try await checksum(of: temporaryURL)
                guard actualChecksum == checksumValue else {
                    throw ToolInstallError.checksumMismatch(name)
                }
            }

            let executableURL: URL
            if let archiveExecutableName = asset.archiveExecutableName {
                try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
                let extractionCommand = ShellProcess.command(["/usr/bin/ditto", "-x", "-k", temporaryURL.path, extractionDirectory.path])
                let extractionStatus = try await ShellProcess.run(command: extractionCommand)
                guard extractionStatus == 0 else { throw ToolInstallError.archiveExtractionFailed(name) }
                executableURL = extractionDirectory.appendingPathComponent(archiveExecutableName)
            } else {
                executableURL = temporaryURL
            }
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
            removeQuarantine(from: executableURL)
            onProgress(name, 1, "Verifying version")
            guard await ToolDiscovery.verify(path: executableURL, name: name, versionArguments: asset.versionArguments) != nil else {
                throw ToolInstallError.versionCheckFailed(name)
            }

            let installedURL = binaryDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: installedURL.path) {
                _ = try fileManager.replaceItemAt(installedURL, withItemAt: executableURL)
            } else {
                try fileManager.copyItem(at: executableURL, to: installedURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)

            if let licenseURL = asset.licenseURL, name == "ffmpeg" {
                let (licenseData, _) = try await URLSession.shared.data(from: licenseURL)
                try licenseData.write(to: binaryDirectory.appendingPathComponent("ffmpeg.LICENSE"), options: .atomic)
            }
        }
    }

    static func installManualTool(from sourceURL: URL, name: String, in binaryDirectory: URL = binaryDirectory) async throws {
        guard ["yt-dlp", "ffmpeg", "ffprobe", "deno"].contains(name) else {
            throw ToolInstallError.unsupportedTool(name)
        }
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        let destination = binaryDirectory.appendingPathComponent(name)
        let temporary = binaryDirectory.appendingPathComponent(".\(name)-\(UUID().uuidString).manual")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: sourceURL, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        removeQuarantine(from: temporary)
        let versionArgs = name == "yt-dlp" ? ["--version"] : ["-version"]
        guard await ToolDiscovery.verify(path: temporary, name: name, versionArguments: versionArgs) != nil else {
            throw ToolInstallError.versionCheckFailed(name)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.copyItem(at: temporary, to: destination)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private static func asset(named name: String) throws -> ToolAsset {
        switch name {
        case "yt-dlp":
            return ToolAsset(
                url: ToolDownloadConfiguration.ytDlpBinaryURL,
                versionArguments: ["--version"],
                checksumURL: ToolDownloadConfiguration.ytDlpChecksumsURL,
                checksumFileName: "yt-dlp_macos"
            )
        case "deno":
            guard let deno = ToolDownloadConfiguration.denoByArchitecture[.current] else {
                throw ToolInstallError.unsupportedTool("deno for \(ToolArchitecture.current.rawValue)")
            }
            return ToolAsset(
                url: deno.archiveURL,
                versionArguments: ["--version"],
                checksumURL: deno.checksumURL,
                checksumFileName: deno.checksumFileName,
                archiveExecutableName: "deno"
            )
        case "ffmpeg", "ffprobe":
            guard let assets = ToolDownloadConfiguration.ffmpegByArchitecture[.current] else {
                throw ToolInstallError.unsupportedTool("\(name) for \(ToolArchitecture.current.rawValue)")
            }
            let isFFmpeg = name == "ffmpeg"
            return ToolAsset(
                url: isFFmpeg ? assets.ffmpegURL : assets.ffprobeURL,
                versionArguments: ["-version"],
                sha256: isFFmpeg ? assets.ffmpegSHA256 : assets.ffprobeSHA256,
                licenseURL: isFFmpeg ? assets.licenseURL : nil
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
        guard let checksum = checksum(in: String(decoding: data, as: UTF8.self), for: asset.checksumFileName ?? name) else {
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
    var checksumFileName: String?
    var archiveExecutableName: String?
    var licenseURL: URL?

    init(url: URL, versionArguments: [String], sha256: String? = nil, checksumURL: URL? = nil, checksumFileName: String? = nil, archiveExecutableName: String? = nil, licenseURL: URL? = nil) {
        self.url = url
        self.versionArguments = versionArguments
        self.sha256 = sha256
        self.checksumURL = checksumURL
        self.checksumFileName = checksumFileName
        self.archiveExecutableName = archiveExecutableName
        self.licenseURL = licenseURL
    }
}

private enum ToolInstallError: LocalizedError {
    case unsupportedTool(String)
    case checksumUnavailable(String)
    case checksumMismatch(String)
    case versionCheckFailed(String)
    case archiveExtractionFailed(String)
    case downloadHostUnavailable(String, URL, String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let name): "No download source is configured for \(name)."
        case .checksumUnavailable(let name): "Could not find the official SHA-256 checksum for \(name)."
        case .checksumMismatch(let name): "The downloaded \(name) binary failed its SHA-256 check. It was not installed."
        case .versionCheckFailed(let name): "The downloaded \(name) binary did not pass its version check. It was not installed."
        case .archiveExtractionFailed(let name): "The downloaded \(name) archive could not be extracted."
        case .downloadHostUnavailable(let name, let url, let detail): "Could not reach the download host for \(name): \(detail)\n\nYou can download it manually from:\n\(url.absoluteString)\nThen use Choose File to install the executable. Deno archives must be unzipped first."
        case .httpStatus(let status): "The download host returned HTTP \(status). Check your connection or choose the downloaded file manually."
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
        if let response = downloadTask.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            finish(.failure(ToolInstallError.httpStatus(response.statusCode)))
            return
        }
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