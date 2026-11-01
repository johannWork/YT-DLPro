import SwiftUI

struct DownloadOptionsPanel: View {
    @Binding var options: DownloadOptions
    @Binding var globalOutputFolder: String
    let profileOutputFolder: String
    let chooseFolder: () -> Void

    var body: some View {
        Form {
            Section("Download") {
                Picker("Type", selection: $options.mediaType) {
                    ForEach(MediaType.allCases) { Text($0.rawValue).tag($0) }
                }
                if options.mediaType != .audioOnly {
                    Picker("Container", selection: $options.videoContainer) {
                        ForEach(VideoContainer.allCases) { Text($0.rawValue.uppercased()).tag($0) }
                    }
                    Picker("Resolution", selection: $options.resolution) {
                        ForEach(VideoResolution.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Codec", selection: $options.codec) {
                        ForEach(CodecPreference.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Max FPS", selection: $options.maxFPS) {
                        ForEach(["Any", "24", "30", "60", "120"], id: \.self) { Text($0 == "Any" ? $0 : "\($0) fps").tag($0) }
                    }
                }
                if options.mediaType == .audioOnly { audioControls }
                Toggle("Keep original after conversion", isOn: $options.keepVideo)
                    .disabled(options.mediaType != .audioOnly)
            }

            Section("Extras") {
                Toggle("Embed thumbnail", isOn: $options.embedThumbnail)
                Toggle("Embed metadata", isOn: $options.embedMetadata)
                Toggle("Embed chapters", isOn: $options.embedChapters)
                Toggle("Write description", isOn: $options.writeDescription)
                Toggle("Write info JSON", isOn: $options.writeInfoJSON)
                Toggle("Download subtitles", isOn: $options.subtitles)
                if options.subtitles {
                    TextField("Languages (comma-separated)", text: $options.subtitleLanguages)
                    Toggle("Include auto-generated subtitles", isOn: $options.autoSubtitles)
                    Toggle("Embed subtitles", isOn: $options.embedSubtitles)
                    Picker("Subtitle format", selection: $options.subtitleFormat) {
                        ForEach(["srt", "vtt", "ass"], id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                }
                Picker("SponsorBlock", selection: $options.sponsorAction) {
                    ForEach(SponsorAction.allCases) { Text($0.rawValue).tag($0) }
                }
                if options.sponsorAction != .off {
                    Menu {
                        ForEach(sponsorCategoryOptions, id: \.self) { category in
                            Toggle(category.capitalized, isOn: categoryBinding(category))
                        }
                    } label: {
                        Label("Categories (\(selectedSponsorCategories.count))", systemImage: "tag")
                    }
                }
            }

            Section("Clip & Playlist") {
                LabeledContent("Start / End") {
                    HStack {
                        TextField("00:00:00", text: $options.clipStart)
                        TextField("End", text: $options.clipEnd)
                    }
                    .textFieldStyle(.roundedBorder)
                }
                Picker("Playlist", selection: $options.playlistMode) {
                    ForEach(PlaylistMode.allCases) { Text($0.rawValue).tag($0) }
                }
                if options.playlistMode == .whole {
                    LabeledContent("Item range") {
                        HStack {
                            TextField("From", text: $options.playlistStart)
                            TextField("To", text: $options.playlistEnd)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    Toggle("Reverse playlist order", isOn: $options.reversePlaylist)
                    Toggle("Number playlist items", isOn: $options.numberPlaylistItems)
                }
            }

            Section("Network & Authentication") {
                Picker("Cookies from", selection: $options.cookieBrowser) {
                    ForEach(CookieBrowser.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Rate limit (e.g. 2M)", text: $options.rateLimit)
                TextField("Retries", text: $options.retries)
                TextField("Concurrent fragments", text: $options.concurrentFragments)
                TextField("Proxy URL", text: $options.proxy)
            }

            Section("Output") {
                LabeledContent("Folder") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Output folder", text: outputFolderBinding)
                        Button("Choose folder…", systemImage: "folder") { chooseFolder() }
                    }
                }
                Picker("Filename template", selection: $options.filenameTemplate) {
                    Text("Title").tag("%(title)s")
                    Text("Uploader - Title").tag("%(uploader)s - %(title)s")
                    Text("Playlist number - Title").tag("%(playlist_index)s - %(title)s")
                }
                Toggle("Restrict filenames", isOn: $options.restrictFilenames)
                TextField("Date after (YYYYMMDD)", text: $options.dateAfter)
                Picker("Subfolder by", selection: $options.subfolderMode) {
                    ForEach(SubfolderMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Skip items in download archive", isOn: $options.downloadArchive)
            }

            Section("Advanced") {
                TextField("Extra arguments", text: $options.extraArguments, axis: .vertical)
                    .lineLimit(2...5)
                Text("Arguments are passed as separate, safely quoted command-line values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var audioControls: some View {
        Group {
            Picker("Audio format", selection: $options.audioFormat) {
                ForEach(AudioFormat.allCases) { Text($0.rawValue.uppercased()).tag($0) }
            }
            Picker("Quality", selection: $options.audioQuality) {
                ForEach(AudioQualityMode.allCases) { Text($0.rawValue).tag($0) }
            }
            if options.audioQuality == .bitrate {
                Picker("Bitrate", selection: $options.audioBitrate) {
                    ForEach(["320", "256", "192", "128", "96", "64"], id: \.self) { Text("\($0) kbps").tag($0) }
                }
            } else if options.audioQuality == .vbr {
                Picker("VBR quality", selection: $options.audioVBR) {
                    ForEach((0...10).map(String.init), id: \.self) { Text($0).tag($0) }
                }
            }
            Picker("Sample rate", selection: $options.sampleRate) {
                ForEach(["Best", "22050", "32000", "44100", "48000", "96000"], id: \.self) { rate in
                    Text(rate == "Best" ? rate : "\(rate) Hz").tag(rate)
                }
            }
        }
    }

    private var outputFolderBinding: Binding<String> {
        Binding(
            get: { ProfileStore.resolvedFolder(perDownload: options.outputFolder, profile: profileOutputFolder, global: globalOutputFolder) },
            set: { options.outputFolder = ($0 == profileOutputFolder || $0 == globalOutputFolder) ? "" : $0 }
        )
    }

    private let sponsorCategoryOptions = ["sponsor", "selfpromo", "interaction", "intro", "outro", "preview", "music_offtopic", "filler", "poi_highlight"]

    private var selectedSponsorCategories: Set<String> {
        Set(options.sponsorCategories.split(separator: ",").map(String.init))
    }

    private func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { selectedSponsorCategories.contains(category) },
            set: { isSelected in
                var categories = selectedSponsorCategories
                if isSelected { categories.insert(category) } else { categories.remove(category) }
                options.sponsorCategories = sponsorCategoryOptions.filter(categories.contains).joined(separator: ",")
            }
        )
    }
}

struct VideoInfoHeader: View {
    let info: VideoInfo?
    let isLoading: Bool
    let error: String?

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Fetching video information…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let info {
                HStack(spacing: 10) {
                    AsyncImage(url: info.thumbnail) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                    }
                    .frame(width: 92, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(info.durationText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label("Inspect a URL to view title, thumbnail, and available formats.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct FormatsPanel: View {
    let formats: [FormatInfo]
    @Binding var selectedFormatID: String

    var body: some View {
        if formats.isEmpty {
            ContentUnavailableView("No format data", systemImage: "rectangle.stack", description: Text("Inspect a single video URL to load the formats yt-dlp can download."))
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("ID").frame(width: 54, alignment: .leading)
                    Text("Resolution").frame(width: 100, alignment: .leading)
                    Text("FPS").frame(width: 44, alignment: .trailing)
                    Text("Codec").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Size").frame(width: 70, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                List(formats) { format in
                    Button {
                        selectedFormatID = selectedFormatID == format.formatID ? "" : format.formatID
                    } label: {
                        HStack {
                            Text(format.formatID).frame(width: 54, alignment: .leading)
                            Text(format.resolution).frame(width: 100, alignment: .leading)
                            Text(format.fps.map { String(format: "%.0f", $0) } ?? "—")
                                .frame(width: 44, alignment: .trailing)
                            Text(format.codecs).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(format.size).frame(width: 70, alignment: .trailing)
                        }
                        .font(.system(.callout, design: .monospaced))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedFormatID == format.formatID ? Color.accentColor.opacity(0.16) : Color.clear)
                }
                .listStyle(.inset)
                HStack {
                    Text(selectedFormatID.isEmpty ? "Automatic format selection" : "Manual format ID: \(selectedFormatID)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selectedFormatID.isEmpty {
                        Button("Clear selection") { selectedFormatID = "" }
                    }
                }
                .font(.caption)
                .padding(10)
            }
        }
    }
}