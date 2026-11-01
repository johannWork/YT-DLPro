import Foundation

struct InstalledTool: Identifiable {
    let name: String
    let path: String
    let version: String

    var id: String { name }
}

struct ToolStatus {
    var ytDlp: InstalledTool?
    var ffmpeg: InstalledTool?

    var missingTools: [String] {
        [ytDlp == nil ? "yt-dlp" : nil, ffmpeg == nil ? "ffmpeg" : nil].compactMap { $0 }
    }
}

enum ToolDiscovery {
    static func locate() async -> ToolStatus {
        async let ytDlp = discover(name: "yt-dlp", versionArguments: ["--version"])
        async let ffmpeg = discover(name: "ffmpeg", versionArguments: ["-version"])
        return await ToolStatus(ytDlp: ytDlp, ffmpeg: ffmpeg)
    }

    private static func discover(name: String, versionArguments: [String]) async -> InstalledTool? {
        let lookup = await capture("command -v \(ShellProcess.quote(name))")
        guard lookup.status == 0, let path = lookup.output.split(whereSeparator: \.isNewline).first else {
            return nil
        }

        let versionCommand = ShellProcess.command([String(path)] + versionArguments)
        let result = await capture(versionCommand)
        let versionLine = result.output.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Unknown version"
        return InstalledTool(name: name, path: String(path), version: versionLine)
    }

    private static func capture(_ command: String) async -> (status: Int32, output: String) {
        let buffer = OutputBuffer()
        do {
            let status = try await ShellProcess.run(command: command) { line in
                buffer.append(line)
            }
            return (status, buffer.value)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ line: String) {
        lock.lock()
        storage += line + "\n"
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}