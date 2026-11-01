import Foundation
import XCTest
@testable import YTDLPro

final class ToolInstallerIntegrationTests: XCTestCase {
    func testArchitectureSpecificFFmpegURLsAreConfigured() {
        XCTAssertEqual(
            ToolDownloadConfiguration.ffmpegByArchitecture[.arm64]?.ffmpegURL.absoluteString,
            "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-arm64"
        )
        XCTAssertEqual(
            ToolDownloadConfiguration.ffmpegByArchitecture[.x64]?.ffmpegURL.absoluteString,
            "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/ffmpeg-darwin-x64"
        )
    }

    func testFallbackToolInstallInIsolatedDirectory() async throws {
        let isolatedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("YT-DLPro-tools-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: isolatedDirectory) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: isolatedDirectory.appendingPathComponent("yt-dlp").path))
        try await ToolInstaller.installMissing(["yt-dlp", "ffmpeg"], in: isolatedDirectory) { _, _, _ in }

        let status = await ToolDiscovery.locate(preference: .builtInFirst, fallbackDirectory: isolatedDirectory)
        XCTAssertEqual(status.ytDlp?.source, .builtIn)
        XCTAssertEqual(status.ffmpeg?.source, .builtIn)
        XCTAssertNotNil(status.ytDlp?.version)
        XCTAssertNotNil(status.ffmpeg?.version)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: isolatedDirectory.appendingPathComponent("ffprobe").path))

        let videoURL = URL(string: "https://www.youtube.com/watch?v=ScMzIvxBSi4")!
        let info = try await VideoInfoService.fetch(url: videoURL, tool: status.ytDlp!)
        XCTAssertEqual(info.title, "Placeholder Video")
        XCTAssertGreaterThan(info.formats.count, 0)

        let ffmpegCommand = ShellProcess.command([
            status.ffmpeg!.path,
            "-hide_banner",
            "-f", "lavfi",
            "-i", "color=c=black:s=32x32:d=0.2",
            "-c:v", "libx264",
            "-f", "null",
            "-"
        ])
        let ffmpegExit = try await ShellProcess.run(command: ffmpegCommand)
        XCTAssertEqual(ffmpegExit, 0)
    }
}
