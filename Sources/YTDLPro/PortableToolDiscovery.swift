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

enum ToolArchitecture: String {
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