import Foundation

enum ShellProcess {
    static func quote(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func command(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }

    static func run(
        command: String,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Int32 {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let reader = Task {
            do {
                for try await line in outputPipe.fileHandleForReading.bytes.lines {
                    onLine(line)
                }
            } catch {
                onLine("Process output error: \(error.localizedDescription)")
            }
        }

        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { terminatedProcess in
                    continuation.resume(returning: terminatedProcess.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        await reader.value
        return status
    }
}