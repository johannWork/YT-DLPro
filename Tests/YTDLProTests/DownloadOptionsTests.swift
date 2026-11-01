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

    func testBuiltInProfilesIncludeRequestedNames() {
        let names = Set(ProfileStore.builtIns().map(\.name))

        XCTAssertEqual(names, [
            "MP3 320",
            "MP4 1080p",
            "Best Video 4K",
            "Audio M4A Best",
            "Podcast MP3 128",
            "Resolve H.264 MP4 (AAC)",
            "Resolve WAV audio"
        ])
    }

    func testProfileDocumentSaveLoadRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("profiles.json")
        var options = DownloadOptions()
        options.mediaType = .audioOnly
        options.audioFormat = .mp3
        options.audioQuality = .bitrate
        options.audioBitrate = "320"
        let profile = DownloadProfile(name: "Test MP3", options: options, outputFolder: "/tmp/audio")
        let document = ProfileDocument(profiles: ProfileStore.builtIns() + [profile], lastUsedProfileID: profile.id)

        try ProfileStore.save(document, to: file)
        let loaded = try ProfileStore.load(from: file)

        XCTAssertEqual(loaded.lastUsedProfileID, profile.id)
        XCTAssertEqual(loaded.profiles.first(where: { $0.id == profile.id }), profile)
        XCTAssertTrue(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("Test MP3"))
    }

    func testHistorySaveLoadRoundTripRetainsDateAndOptions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        var options = DownloadOptions()
        options.resolution = .p720
        let item = DownloadHistoryItem(
            url: URL(string: "https://example.com/video")!,
            title: "A public video",
            downloadedAt: Date(timeIntervalSince1970: 1_700_000_000),
            outputPath: "/tmp/video.mp4",
            profileName: "Test",
            options: options,
            profileID: UUID(),
            profileOutputFolder: "/tmp"
        )

        try HistoryStore.save([item], to: file)
        let loaded = HistoryStore.load(from: file)

        XCTAssertEqual(loaded.first?.title, item.title)
        XCTAssertEqual(loaded.first?.downloadedAt, item.downloadedAt)
        XCTAssertEqual(loaded.first?.options, item.options)
    }

    func testFolderPriorityUsesPerDownloadThenProfileThenGlobal() {
        XCTAssertEqual(ProfileStore.resolvedFolder(perDownload: "/download", profile: "/profile", global: "/global"), "/download")
        XCTAssertEqual(ProfileStore.resolvedFolder(perDownload: "", profile: "/profile", global: "/global"), "/profile")
        XCTAssertEqual(ProfileStore.resolvedFolder(perDownload: "", profile: "", global: "/global"), "/global")
    }
}