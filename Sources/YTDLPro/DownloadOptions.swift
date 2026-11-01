import Foundation

enum MediaType: String, CaseIterable, Identifiable, Codable {
    case videoAndAudio = "Video + Audio"
    case videoOnly = "Video only"
    case audioOnly = "Audio only"

    var id: String { rawValue }
}

enum VideoContainer: String, CaseIterable, Identifiable, Codable {
    case mp4, mkv, webm, mov
    var id: String { rawValue }
}

enum AudioFormat: String, CaseIterable, Identifiable, Codable {
    case mp3, m4a, aac, opus, flac, wav, ogg
    var id: String { rawValue }
    var ytDlpValue: String { self == .ogg ? "vorbis" : rawValue }
}

enum VideoResolution: String, CaseIterable, Identifiable, Codable {
    case best = "Best"
    case p4320 = "4320p"
    case p2160 = "2160p"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case p360 = "360p"
    case p240 = "240p"
    case p144 = "144p"
    case worst = "Worst"

    var id: String { rawValue }
    var height: Int? { Int(rawValue.dropLast()) }
}

enum CodecPreference: String, CaseIterable, Identifiable, Codable {
    case any = "Any"
    case h264 = "H.264"
    case h265 = "H.265 / HEVC"
    case vp9 = "VP9"
    case av1 = "AV1"

    var id: String { rawValue }
    var ytDlpFilter: String? {
        switch self {
        case .any: nil
        case .h264: "avc1"
        case .h265: "hev1"
        case .vp9: "vp9"
        case .av1: "av01"
        }
    }
}

enum AudioQualityMode: String, CaseIterable, Identifiable, Codable {
    case best = "Best available"
    case bitrate = "Bitrate"
    case vbr = "VBR quality"
    var id: String { rawValue }
}

enum SponsorAction: String, CaseIterable, Identifiable, Codable {
    case off = "Off"
    case mark = "Mark"
    case remove = "Remove"
    var id: String { rawValue }
}

enum PlaylistMode: String, CaseIterable, Identifiable, Codable {
    case whole = "Whole playlist"
    case single = "Single video"
    var id: String { rawValue }
}

enum CookieBrowser: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case safari = "Safari"
    case chrome = "Chrome"
    case firefox = "Firefox"
    case brave = "Brave"
    var id: String { rawValue }
}

enum SubfolderMode: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case uploader = "Uploader"
    case playlist = "Playlist"
    var id: String { rawValue }
}

struct DownloadOptions: Codable, Equatable {
    var mediaType: MediaType = .videoAndAudio
    var videoContainer: VideoContainer = .mp4
    var audioFormat: AudioFormat = .mp3
    var resolution: VideoResolution = .best
    var codec: CodecPreference = .any
    var maxFPS = "Any"
    var selectedFormatID = ""
    var audioQuality: AudioQualityMode = .best
    var audioBitrate = "320"
    var audioVBR = "0"
    var sampleRate = "Best"
    var embedThumbnail = false
    var embedMetadata = false
    var embedChapters = false
    var subtitles = false
    var subtitleLanguages = "en"
    var autoSubtitles = false
    var embedSubtitles = false
    var subtitleFormat = "srt"
    var writeDescription = false
    var writeInfoJSON = false
    var sponsorAction: SponsorAction = .off
    var sponsorCategories = "sponsor,selfpromo,interaction,intro,outro,preview,music_offtopic"
    var keepVideo = false
    var clipStart = ""
    var clipEnd = ""
    var playlistMode: PlaylistMode = .whole
    var playlistStart = ""
    var playlistEnd = ""
    var reversePlaylist = false
    var numberPlaylistItems = false
    var cookieBrowser: CookieBrowser = .none
    var rateLimit = ""
    var retries = "10"
    var concurrentFragments = "4"
    var proxy = ""
    var outputFolder = ""
    var filenameTemplate = "%(title)s"
    var restrictFilenames = false
    var dateAfter = ""
    var subfolderMode: SubfolderMode = .none
    var downloadArchive = false
    var extraArguments = ""

    func arguments(globalOutputFolder: String, formatID: String? = nil) -> [String] {
        var result = ["--newline", "--progress-template", "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"]
        let chosenID = formatID ?? selectedFormatID
        if !chosenID.isEmpty {
            result += ["-f", chosenID]
        } else {
            result += ["-f", formatSelector]
        }

        if mediaType == .audioOnly {
            result += ["-x", "--audio-format", audioFormat.ytDlpValue]
            switch audioQuality {
            case .best: break
            case .bitrate: result += ["--audio-quality", "\(audioBitrate)K"]
            case .vbr: result += ["--audio-quality", audioVBR]
            }
            if sampleRate != "Best", !sampleRate.isEmpty {
                result += ["--postprocessor-args", "ExtractAudio+ffmpeg_o:-ar \(sampleRate)"]
            }
        } else {
            result += ["--merge-output-format", videoContainer.rawValue]
        }

        if embedThumbnail { result.append("--embed-thumbnail") }
        if embedMetadata { result.append("--embed-metadata") }
        if embedChapters { result.append("--embed-chapters") }
        if subtitles {
            result.append(autoSubtitles ? "--write-auto-subs" : "--write-subs")
            if !subtitleLanguages.isEmpty { result += ["--sub-langs", subtitleLanguages] }
            result += ["--sub-format", subtitleFormat]
            if embedSubtitles { result.append("--embed-subs") }
        }
        if writeDescription { result.append("--write-description") }
        if writeInfoJSON { result.append("--write-info-json") }
        if sponsorAction != .off, !sponsorCategories.isEmpty {
            result += [sponsorAction == .mark ? "--sponsorblock-mark" : "--sponsorblock-remove", sponsorCategories]
        }
        if keepVideo { result.append("--keep-video") }

        if !clipStart.isEmpty || !clipEnd.isEmpty {
            result += ["--download-sections", "*\(clipStart)-\(clipEnd)", "--force-keyframes-at-cuts"]
        }
        if playlistMode == .single {
            result.append("--no-playlist")
        } else if !playlistStart.isEmpty || !playlistEnd.isEmpty {
            let range: String
            if !playlistStart.isEmpty, !playlistEnd.isEmpty {
                range = "\(playlistStart):\(playlistEnd)"
            } else if !playlistStart.isEmpty {
                range = "\(playlistStart):"
            } else {
                range = "1:\(playlistEnd)"
            }
            result += ["--playlist-items", range]
        }
        if reversePlaylist { result.append("--playlist-reverse") }

        if cookieBrowser != .none { result += ["--cookies-from-browser", cookieBrowser.rawValue.lowercased()] }
        if !rateLimit.isEmpty { result += ["--limit-rate", rateLimit] }
        if !retries.isEmpty { result += ["--retries", retries] }
        if !concurrentFragments.isEmpty { result += ["--concurrent-fragments", concurrentFragments] }
        if !proxy.isEmpty { result += ["--proxy", proxy] }

        let folder = outputFolder.isEmpty ? globalOutputFolder : outputFolder
        let template = numberPlaylistItems ? "%(playlist_index)s - \(filenameTemplate)" : filenameTemplate
        let subfolder: String
        switch subfolderMode {
        case .none: subfolder = ""
        case .uploader: subfolder = "%(uploader)s/"
        case .playlist: subfolder = "%(playlist_title)s/"
        }
        result += ["-o", URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(subfolder + template + ".%(ext)s").path]
        if restrictFilenames { result.append("--restrict-filenames") }
        if !dateAfter.isEmpty { result += ["--dateafter", dateAfter] }
        if downloadArchive { result += ["--download-archive", URL(fileURLWithPath: folder).appendingPathComponent(".yt-dlp-archive.txt").path] }
        result += extraArgumentTokens
        return result
    }

    private var formatSelector: String {
        if mediaType == .audioOnly { return "bestaudio/best" }
        let heightFilter = resolution.height.map { "[height<=\($0)]" } ?? ""
        let fpsFilter = Int(maxFPS).map { "[fps<=\($0)]" } ?? ""
        let codecFilter = codec.ytDlpFilter.map { "[vcodec*=\($0)]" } ?? ""
        let quality = resolution == .worst ? "worst" : "best"
        let video = "\(quality)video\(heightFilter)\(fpsFilter)\(codecFilter)"
        let fallback = "\(quality)\(heightFilter)\(fpsFilter)\(codecFilter)"
        if mediaType == .videoOnly { return "\(video)/\(fallback)" }
        return "\(video)+bestaudio/\(fallback)"
    }

    private var extraArgumentTokens: [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in extraArguments {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

struct FormatInfo: Identifiable, Decodable {
    let formatID: String
    let width: Int?
    let height: Int?
    let fps: Double?
    let vcodec: String?
    let acodec: String?
    let filesize: Double?
    let filesizeApprox: Double?

    var id: String { formatID }
    var resolution: String {
        if let width, let height { return "\(width) x \(height)" }
        return height.map { "\($0)p" } ?? "Audio"
    }
    var codecs: String {
        [vcodec, acodec].compactMap { value in
            guard let value, value != "none" else { return nil }
            return value
        }.joined(separator: " / ")
    }
    var size: String {
        guard let bytes = filesize ?? filesizeApprox else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case width, height, fps, vcodec, acodec, filesize
        case filesizeApprox = "filesize_approx"
    }
}

struct VideoInfo: Decodable {
    let title: String
    let thumbnail: URL?
    let duration: Double?
    let formats: [FormatInfo]

    var durationText: String {
        guard let duration else { return "Duration unavailable" }
        let totalSeconds = Int(duration)
        return String(format: "%d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    enum CodingKeys: String, CodingKey {
        case title, thumbnail, duration, formats
    }
}