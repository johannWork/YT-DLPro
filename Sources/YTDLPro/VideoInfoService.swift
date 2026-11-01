import Foundation

enum VideoInfoService {
    static func fetch(url: URL, tool: InstalledTool, jsRuntime: InstalledTool? = nil) async throws -> VideoInfo {
        var arguments = ["--no-warnings", "--skip-download"]
        if let jsRuntime {
            arguments += ["--js-runtimes", "deno:\(jsRuntime.path)", "--remote-components", "ejs:github"]
        }
        arguments += ["-J", "--", url.absoluteString]
        let command = ShellProcess.command([tool.path] + arguments)
        let output = OutputCollector()
        let status = try await ShellProcess.run(command: command) { line in
            output.append(line)
        }
        guard status == 0 else {
            let message = output.value.trimmingCharacters(in: .whitespacesAndNewlines)
            throw VideoInfoError.commandFailed(message.isEmpty ? "yt-dlp exited with status \(status)." : message)
        }
        guard let jsonLine = output.value.split(whereSeparator: \.isNewline).first(where: { $0.first == "{" }) else {
            throw VideoInfoError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(VideoInfo.self, from: Data(jsonLine.utf8))
        } catch {
            throw VideoInfoError.invalidResponse
        }
    }
}

enum VideoInfoError: LocalizedError {
    case commandFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message
        case .invalidResponse: "yt-dlp returned video data that could not be read."
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
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