import Darwin
import Foundation

enum ToolPreference: String, CaseIterable, Identifiable, Codable, Equatable {
    case systemFirst = "Prefer system tools"
    case builtInFirst = "Prefer built-in copies"

    var id: String { rawValue }
}

enum ToolSource: String, Equatable {
    case system = "System"
    case builtIn = "Built-in"
}

struct InstalledTool: Identifiable {
    let name: String
    let path: String
    let version: String
    let source: ToolSource

    var id: String { name }
}

struct ToolStatus {
    var ytDlp: InstalledTool?
    var ffmpeg: InstalledTool?

    var missingTools: [String] {
        [ytDlp == nil ? "yt-dlp" : nil, ffmpeg == nil ? "ffmpeg" : nil].compactMap { $0 }
    }
}

enum ToolArchitecture: String, Hashable {
    case arm64
    case x64

    static var current: ToolArchitecture {
#if arch(arm64)
        return .arm64
#else
        var armCapability: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &armCapability, &size, nil, 0) == 0, armCapability == 1 {
            return .arm64
        }
        return .x64
#endif
    }
}

struct FFmpegToolAssets {
    let ffmpegURL: URL
    let ffprobeURL: URL
    let ffmpegSHA256: String
    let ffprobeSHA256: String
    let licenseURL: URL
}

enum ToolDownloadConfiguration {
    static let ytDlpBinaryURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    static let ytDlpChecksumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS")!
    static let ffmpegRelease = "b6.1.1"
    static let ffmpegByArchitecture: [ToolArchitecture: FFmpegToolAssets] = [
        .arm64: FFmpegToolAssets(
            ffmpegURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-arm64")!,
            ffprobeURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffprobe-darwin-arm64")!,
            ffmpegSHA256: "a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584",
            ffprobeSHA256: "bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64",
            licenseURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/darwin-arm64.LICENSE")!
        ),
        .x64: FFmpegToolAssets(
            ffmpegURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-x64")!,
            ffprobeURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffprobe-darwin-x64")!,
            ffmpegSHA256: "ebdddc936f61e14049a2d4b549a412b8a40deeff6540e58a9f2a2da9e6b18894",
            ffprobeSHA256: "fa3add0ce901f7241abe0dfc0155d958fc834aca3f8ce61f87cc712ae669c1e0",
            licenseURL: URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/darwin-x64.LICENSE")!
        )
    ]
}

enum ToolDiscovery {
    static let fallbackDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/YT-DLPro/bin", isDirectory: true)

    static func sourceOrder(for preference: ToolPreference) -> [ToolSource] {
        preference == .systemFirst ? [.system, .builtIn] : [.builtIn, .system]
    }

    static func locate(preference: ToolPreference, fallbackDirectory: URL = fallbackDirectory) async -> ToolStatus {
        async let ytDlp = locate(name: "yt-dlp", versionArguments: ["--version"], preference: preference, fallbackDirectory: fallbackDirectory)
        async let ffmpeg = locate(name: "ffmpeg", versionArguments: ["-version"], preference: preference, fallbackDirectory: fallbackDirectory)
        return await ToolStatus(ytDlp: ytDlp, ffmpeg: ffmpeg)
    }

    static func verify(path: URL, name: String, versionArguments: [String]) async -> InstalledTool? {
        guard FileManager.default.isExecutableFile(atPath: path.path) else { return nil }
        let output = ToolOutputCollector()
        let status: Int32
        do {
            status = try await ShellProcess.run(command: ShellProcess.command([path.path] + versionArguments)) {
                output.append($0)
            }
        } catch {
            return nil
        }
        guard status == 0, let version = output.value.split(whereSeparator: \.isNewline).first else { return nil }
        return InstalledTool(name: name, path: path.path, version: String(version), source: .builtIn)
    }

    private static func locate(
        name: String,
        versionArguments: [String],
        preference: ToolPreference,
        fallbackDirectory: URL
    ) async -> InstalledTool? {
        let builtInPath = fallbackDirectory.appendingPathComponent(name)
        for source in sourceOrder(for: preference) {
            let candidate: URL?
            switch source {
            case .system:
                candidate = await resolveSystemPath(name).map(URL.init(fileURLWithPath:))
            case .builtIn: candidate = FileManager.default.isExecutableFile(atPath: builtInPath.path) ? builtInPath : nil
            }
            guard let candidate, let verified = await verify(path: candidate, name: name, versionArguments: versionArguments) else {
                continue
            }
            return InstalledTool(name: verified.name, path: verified.path, version: verified.version, source: source)
        }
        return nil
    }

    private static func resolveSystemPath(_ name: String) async -> String? {
        let output = ToolOutputCollector()
        let status = try? await ShellProcess.run(command: "command -v \(ShellProcess.quote(name))") {
            output.append($0)
        }
        guard status == 0 else { return nil }
        return output.value.split(whereSeparator: \.isNewline).first.map(String.init)
    }
}

private final class ToolOutputCollector: @unchecked Sendable {
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