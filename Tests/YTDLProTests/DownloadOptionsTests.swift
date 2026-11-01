import XCTest
@testable import YTDLPro

final class DownloadOptionsTests: XCTestCase {
    func testCombinedVideoSelectorHonorsHeightLimit() {
        var options = DownloadOptions()
        options.resolution = .p1080

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let formatIndex = arguments.firstIndex(of: "-f")!

        XCTAssertEqual(arguments[formatIndex + 1], "bestvideo[height<=1080]+bestaudio/best[height<=1080]")
    }

    func testAudioConversionIncludesSelectedQualityAndSampleRate() {
        var options = DownloadOptions()
        options.mediaType = .audioOnly
        options.audioFormat = .mp3
        options.audioQuality = .bitrate
        options.audioBitrate = "192"
        options.sampleRate = "44100"

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")

        XCTAssertTrue(arguments.contains("-x"))
        XCTAssertTrue(arguments.contains("mp3"))
        XCTAssertTrue(arguments.contains("192K"))
        XCTAssertTrue(arguments.contains("ExtractAudio+ffmpeg_o:-ar 44100"))
    }

    func testMetadataDecodesFormatsWithOptionalFields() throws {
        let json = #"{"title":"Sample","thumbnail":"https://example.com/thumb.jpg","duration":65,"formats":[{"format_id":"137","height":1080,"vcodec":"avc1.640028","acodec":"none"},{"format_id":"140","vcodec":"none","acodec":"mp4a.40.2"}]}"#
        let info = try JSONDecoder().decode(VideoInfo.self, from: Data(json.utf8))

        XCTAssertEqual(info.title, "Sample")
        XCTAssertEqual(info.durationText, "0:01:05")
        XCTAssertEqual(info.formats.count, 2)
        XCTAssertEqual(info.formats[0].resolution, "1080p")
        XCTAssertEqual(info.formats[1].size, "—")
    }

    func testOggChoiceUsesSupportedVorbisEncoderName() {
        var options = DownloadOptions()
        options.mediaType = .audioOnly
        options.audioFormat = .ogg

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let formatIndex = arguments.firstIndex(of: "--audio-format")!

        XCTAssertEqual(arguments[formatIndex + 1], "vorbis")
    }

    func testToolPreferenceControlsDiscoveryOrder() {
        XCTAssertEqual(ToolDiscovery.sourceOrder(for: .systemFirst), [.system, .builtIn])
        XCTAssertEqual(ToolDiscovery.sourceOrder(for: .builtInFirst), [.builtIn, .system])
    }

    func testToolArchitectureHasMatchingReleaseAssetName() {
        XCTAssertTrue(["arm64", "x64"].contains(ToolArchitecture.current.rawValue))
    }

    func testYtDlpChecksumManifestFindsBinaryEntry() {
        let manifest = "abc123  yt-dlp\ndef456 *yt-dlp_macos\n"

        XCTAssertEqual(ToolInstaller.checksum(in: manifest, for: "yt-dlp_macos"), "def456")
        XCTAssertNil(ToolInstaller.checksum(in: manifest, for: "missing-binary"))
    }
}