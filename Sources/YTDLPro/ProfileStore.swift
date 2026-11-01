import Foundation

struct DownloadProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var options: DownloadOptions
    var outputFolder: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, options: DownloadOptions, outputFolder: String = "", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.options = options
        self.outputFolder = outputFolder
        self.isBuiltIn = isBuiltIn
    }
}

struct ProfileDocument: Codable {
    var profiles: [DownloadProfile]
    var lastUsedProfileID: UUID?
}

enum ProfileStore {
    static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/YT-DLPro", isDirectory: true)
    static let fileURL = directoryURL.appendingPathComponent("profiles.json")

    static func builtIns() -> [DownloadProfile] {
        var profiles: [DownloadProfile] = []

        var mp3 = DownloadOptions()
        mp3.mediaType = .audioOnly
        mp3.audioFormat = .mp3
        mp3.audioQuality = .bitrate
        mp3.audioBitrate = "320"
        profiles.append(DownloadProfile(name: "MP3 320", options: mp3, isBuiltIn: true))

        var mp4 = DownloadOptions()
        mp4.videoContainer = .mp4
        mp4.resolution = .p1080
        profiles.append(DownloadProfile(name: "MP4 1080p", options: mp4, isBuiltIn: true))

        var best4K = DownloadOptions()
        best4K.resolution = .p2160
        profiles.append(DownloadProfile(name: "Best Video 4K", options: best4K, isBuiltIn: true))

        var m4a = DownloadOptions()
        m4a.mediaType = .audioOnly
        m4a.audioFormat = .m4a
        profiles.append(DownloadProfile(name: "Audio M4A Best", options: m4a, isBuiltIn: true))

        var podcast = DownloadOptions()
        podcast.mediaType = .audioOnly
        podcast.audioFormat = .mp3
        podcast.audioQuality = .bitrate
        podcast.audioBitrate = "128"
        podcast.embedMetadata = true
        profiles.append(DownloadProfile(name: "Podcast MP3 128", options: podcast, isBuiltIn: true))

        var resolveVideo = DownloadOptions()
        resolveVideo.videoContainer = .mp4
        resolveVideo.codec = .h264
        profiles.append(DownloadProfile(name: "Resolve H.264 MP4 (AAC)", options: resolveVideo, isBuiltIn: true))

        var resolveAudio = DownloadOptions()
        resolveAudio.mediaType = .audioOnly
        resolveAudio.audioFormat = .wav
        profiles.append(DownloadProfile(name: "Resolve WAV audio", options: resolveAudio, isBuiltIn: true))

        return profiles
    }

    static func load(from url: URL = fileURL) throws -> ProfileDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProfileDocument(profiles: builtIns(), lastUsedProfileID: nil)
        }
        let decoder = JSONDecoder()
        let document = try decoder.decode(ProfileDocument.self, from: Data(contentsOf: url))
        let builtInNames = Set(builtIns().map(\.name))
        let storedBuiltIns = Set(document.profiles.filter(\.isBuiltIn).map(\.name))
        let missingBuiltIns = builtIns().filter { builtInNames.contains($0.name) && !storedBuiltIns.contains($0.name) }
        return ProfileDocument(profiles: document.profiles + missingBuiltIns, lastUsedProfileID: document.lastUsedProfileID)
    }

    static func save(_ document: ProfileDocument, to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    static func resolvedFolder(perDownload: String, profile: String, global: String) -> String {
        if !perDownload.isEmpty { return perDownload }
        if !profile.isEmpty { return profile }
        return global
    }
}

enum HistoryStore {
    static let fileURL = ProfileStore.directoryURL.appendingPathComponent("history.json")

    static func load(from url: URL = fileURL) -> [DownloadHistoryItem] {
        guard let data = try? Data(contentsOf: url),
              let history = try? historyDecoder().decode([DownloadHistoryItem].self, from: data) else { return [] }
        return history
    }

    static func save(_ history: [DownloadHistoryItem], to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: url, options: .atomic)
    }

    private static func historyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}