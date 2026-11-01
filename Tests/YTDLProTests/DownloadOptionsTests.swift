import XCTest
@testable import YTDLPro

final class DownloadOptionsTests: XCTestCase {
    func testCombinedVideoSelectorHonorsHeightLimit() {
        var options = DownloadOptions()
        options.resolution = .p1080

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let formatIndex = arguments.firstIndex(of: "-f")!

        XCTAssertEqual(
            arguments[formatIndex + 1],
            "bestvideo[height<=1080][vcodec^=avc1]+bestaudio[acodec^=mp4a]/best[ext=mp4][height<=1080][vcodec^=avc1][acodec^=mp4a]"
        )
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

    func testQueuedMP3ProfileUsesCurrentMP4AndResolutionWhenStarted() {
        let mp3Profile = ProfileStore.builtIns().first { $0.name == "MP3 320" }!
        var currentOptions = mp3Profile.options
        currentOptions.mediaType = .videoAndAudio
        currentOptions.videoContainer = .mp4
        currentOptions.resolution = .p720

        var job = DownloadJob(url: URL(string: "https://example.com/video")!, options: mp3Profile.options, profile: mp3Profile)
        job.prepareToStart(options: currentOptions, profile: mp3Profile)
        let arguments = job.options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let formatIndex = arguments.firstIndex(of: "-f")!
        let formatSelector = arguments[formatIndex + 1]

        XCTAssertFalse(arguments.contains("-x"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--merge-output-format")! + 1], "mp4")
        XCTAssertTrue(formatSelector.contains("[height<=720]"))
        XCTAssertTrue(formatSelector.contains("[vcodec^=avc1]"))
    }

    func testQueuedMP3ProfileUsesCurrentAudioBitrateWhenStarted() {
        let mp3Profile = ProfileStore.builtIns().first { $0.name == "MP3 320" }!
        var currentOptions = mp3Profile.options
        currentOptions.audioBitrate = "192"

        var job = DownloadJob(url: URL(string: "https://example.com/video")!, options: mp3Profile.options, profile: mp3Profile)
        job.prepareToStart(options: currentOptions, profile: mp3Profile)
        let arguments = job.options.arguments(globalOutputFolder: "/tmp/YT-DLPro")

        XCTAssertEqual(arguments[arguments.firstIndex(of: "--audio-quality")! + 1], "192K")
    }

    func testStartSnapshotUsesCurrentFolderClipAndExtraArgumentsButKeepsQueueFolderOverride() {
        let profile = ProfileStore.builtIns().first { $0.name == "MP4 1080p" }!
        var currentOptions = profile.options
        currentOptions.outputFolder = "/tmp/panel-folder"
        currentOptions.clipStart = "00:01"
        currentOptions.clipEnd = "00:05"
        currentOptions.extraArguments = "--no-warnings --socket-timeout 30"

        var job = DownloadJob(url: URL(string: "https://example.com/video")!, options: profile.options, profile: profile)
        job.perDownloadFolderOverride = "/tmp/queue-folder"
        job.prepareToStart(options: currentOptions, profile: profile)
        let arguments = job.options.arguments(globalOutputFolder: "/tmp/global")

        XCTAssertEqual(arguments[arguments.firstIndex(of: "-o")! + 1], "/tmp/queue-folder/%(title)s.%(ext)s")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--download-sections")! + 1], "*00:01-00:05")
        XCTAssertTrue(arguments.contains("--no-warnings"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--socket-timeout")! + 1], "30")
    }

    func testStartSnapshotUsesPanelFolderInsteadOfSelectedProfileFolder() {
        let profile = DownloadProfile(name: "Custom folder", options: DownloadOptions(), outputFolder: "/tmp/profile-folder")
        var currentOptions = profile.options
        currentOptions.outputFolder = "/tmp/global-folder"

        var job = DownloadJob(url: URL(string: "https://example.com/video")!, options: profile.options, profile: profile)
        job.prepareToStart(options: currentOptions, profile: profile)
        let effectiveFolder = ProfileStore.resolvedFolder(
            perDownload: job.options.outputFolder,
            profile: job.profileOutputFolder ?? "",
            global: "/tmp/fallback-folder"
        )

        XCTAssertEqual(effectiveFolder, "/tmp/global-folder")
    }

    func testSwitchingProfileReloadsQueuedJobAndStartedSnapshotStaysFixed() {
        let profiles = ProfileStore.builtIns()
        let mp3Profile = profiles.first { $0.name == "MP3 320" }!
        let mp4Profile = profiles.first { $0.name == "MP4 1080p" }!
        var job = DownloadJob(url: URL(string: "https://example.com/video")!, options: mp3Profile.options, profile: mp3Profile)

        job.apply(profile: mp4Profile)
        XCTAssertEqual(job.options, mp4Profile.options)
        XCTAssertEqual(job.profileID, mp4Profile.id)
        XCTAssertEqual(job.profileName, mp4Profile.name)

        job.prepareToStart(options: mp4Profile.options, profile: mp4Profile)
        var changedOptions = mp3Profile.options
        changedOptions.audioBitrate = "128"
        job.prepareToStart(options: changedOptions, profile: mp3Profile)

        XCTAssertEqual(job.options, mp4Profile.options)
        XCTAssertEqual(job.profileID, mp4Profile.id)
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

    func testMP4DefaultsRequireH264AndAACStreams() {
        var options = DownloadOptions()
        options.videoContainer = .mp4
        options.resolution = .p1080

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let selectorIndex = arguments.firstIndex(of: "-f")!

        XCTAssertEqual(
            arguments[selectorIndex + 1],
            "bestvideo[height<=1080][vcodec^=avc1]+bestaudio[acodec^=mp4a]/best[ext=mp4][height<=1080][vcodec^=avc1][acodec^=mp4a]"
        )
        XCTAssertFalse(arguments[selectorIndex + 1].contains("av01"))
        XCTAssertFalse(arguments[selectorIndex + 1].contains("vp9"))
    }

    func testMP4KeepsExplicitAV1CodecChoice() {
        var options = DownloadOptions()
        options.videoContainer = .mp4
        options.codec = .av1

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let selectorIndex = arguments.firstIndex(of: "-f")!

        XCTAssertTrue(arguments[selectorIndex + 1].contains("[vcodec*=av01]"))
        XCTAssertTrue(arguments[selectorIndex + 1].contains("[acodec^=mp4a]"))
    }

    func testMP4FallbackForcesH264AACEncodingThroughMKVIntermediate() {
        var options = DownloadOptions()
        options.videoContainer = .mp4

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro", forceMP4Reencode: true)

        XCTAssertTrue(arguments.contains("mkv"))
        XCTAssertTrue(arguments.contains("--recode-video"))
        XCTAssertTrue(arguments.contains("mp4"))
        XCTAssertTrue(arguments.contains("VideoConvertor+ffmpeg_o:-c:v libx264 -c:a aac"))
    }

    func testResolveProfilesForceExpectedCodecs() {
        let profiles = ProfileStore.builtIns()
        let video = profiles.first { $0.name == "Resolve H.264 MP4 (AAC)" }!
        let audio = profiles.first { $0.name == "Resolve WAV audio" }!
        let videoArguments = video.options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let videoArgumentsText = videoArguments.joined(separator: " ")

        XCTAssertTrue(videoArgumentsText.contains("[vcodec*=avc1]"))
        XCTAssertTrue(videoArgumentsText.contains("[acodec^=mp4a]"))
        XCTAssertTrue(video.options.extraArguments.isEmpty)
        XCTAssertEqual(audio.options.audioFormat, .wav)
    }

    func testClipRangeUsesDownloadSectionsArgument() {
        var options = DownloadOptions()
        options.clipStart = "00:01"
        options.clipEnd = "00:05"

        let arguments = options.arguments(globalOutputFolder: "/tmp/YT-DLPro")
        let sectionIndex = arguments.firstIndex(of: "--download-sections")!

        XCTAssertEqual(arguments[sectionIndex + 1], "*00:01-00:05")
        XCTAssertTrue(arguments.contains("--force-keyframes-at-cuts"))
    }

    func testSafariPermissionErrorNamesFullDiskAccessPath() {
        let message = DownloadCoordinator.userFacingDownloadError("Operation not permitted while reading Safari cookies", cookieBrowser: .safari)

        XCTAssertTrue(message?.contains("System Settings > Privacy & Security > Full Disk Access") == true)
    }

    func testCommonExtractorErrorsAreActionable() {
        XCTAssertTrue(DownloadCoordinator.userFacingDownloadError("Sign in to confirm your age", cookieBrowser: .none)?.contains("age-restricted") == true)
        XCTAssertTrue(DownloadCoordinator.userFacingDownloadError("This video is private", cookieBrowser: .none)?.contains("private") == true)
        XCTAssertTrue(DownloadCoordinator.userFacingDownloadError("Not available in your country", cookieBrowser: .none)?.contains("geo-blocked") == true)
        XCTAssertTrue(DownloadCoordinator.userFacingDownloadError("ffmpeg is not installed", cookieBrowser: .none)?.contains("brew install ffmpeg") == true)
    }
}