# YT-DLPro

Native macOS video downloader interface for `yt-dlp`, `ffmpeg`, and Deno.

# [Download Latest YT-DLPro](https://github.com/johannWork/YT-DLPro/releases/latest)

<p align="center">
  <img src="docs/logo.png" alt="YT-DLPro logo" width="128">
</p>

<h1 align="center">YT-DLPro</h1>

<p align="center">Native macOS video downloader interface for <code>yt-dlp</code>, <code>ffmpeg</code>, and Deno.</p>

<h2 align="center"><a href="https://github.com/johannWork/YT-DLPro/releases/latest">Download Latest YT-DLPro</a></h2>

1. Download and open the latest DMG.
2. Drag `YT-DLPro.app` to the Applications folder.
3. On first launch, right-click the app and choose **Open**. If Gatekeeper still blocks it, use **System Settings > Privacy & Security > Open Anyway**, or run `xattr -cr /Applications/YT-DLPro.app` in Terminal.

**Disclaimer:** You are responsible for following the laws and site terms where you live. YT-DLPro does not bundle `yt-dlp`, `ffmpeg`, or Deno.

<!-- Add a screenshot: ![YT-DLPro main window](docs/screenshot.png) -->

## Features

**Downloading**
- Video + audio, video only, or audio only
- Video containers: MP4, MKV, WebM, MOV
- Audio formats: MP3, M4A, AAC, Opus, FLAC, WAV, OGG
- Resolutions from 144p up to 4320p, plus Best and Worst
- Codec preference (H.264, H.265, VP9, AV1) and max FPS
- Audio bitrate, VBR quality, and sample rate
- MP4 defaults to H.264 + AAC so files import cleanly into editors like DaVinci Resolve, with an automatic ffmpeg re-encode if no compatible stream exists
- Clip downloads with start and end times
- Playlist support: whole playlist or single video, item range, reverse order, numbering
- Format table showing every available format, with manual format selection

**Queue and progress**
- Paste multiple links, or drag and drop links onto the window or Dock icon
- Per-item progress, speed, and ETA
- Pause, resume, retry, cancel, and reorder
- Overall download bar and Dock icon progress
- Adjustable number of simultaneous downloads

**Profiles**
- Save, load, rename, duplicate, delete, import, and export profiles
- Built-in profiles: MP3 320, MP4 1080p, Best Video 4K, Audio M4A Best, Podcast MP3 128, Resolve H.264 MP4 (AAC), and Resolve WAV audio
- Per-download profile override
- Remembers your last used profile

**Extras**
- Embed thumbnail, metadata, and chapters
- Subtitles: language choice, auto-generated captions, embed or save separately (SRT, VTT, ASS)
- SponsorBlock: mark or remove segments by category
- Cookies from Safari, Chrome, Firefox, or Brave
- Download archive to skip videos you already have
- Rate limit, retries, concurrent fragments, and proxy
- Filename templates, subfolders by uploader or playlist, and a date filter
- Free-form extra arguments field

**Convenience**
- Live command preview with copy and Open in Terminal
- Download history with re-download and reveal in Finder
- Global default download folder, with per-profile and per-download overrides
- Optional clipboard watcher that offers to add copied links
- Notifications and sleep prevention while downloads run
- Clear messages for age-restricted, private, geo-blocked, and missing-ffmpeg errors, and for Safari Full Disk Access
- First-launch setup that installs the required tools without Terminal
- Universal app (Apple Silicon and Intel)

## Requirements

- macOS 14 or newer
- Xcode with the macOS SDK (only needed to build from source)
- Network access for video metadata and downloads

YT-DLPro does not bundle these tools in the app. On first launch, **Set up now** can install standalone copies in `~/Library/Application Support/YT-DLPro/bin` when system copies are not found.

The app and release ZIP are universal `arm64` + `x86_64`. Build products and test downloads stay inside the ignored `build/` directory.
The app icon is generated from the transparent `YT-DLPro.png` logo in the project root and embedded as a native macOS ICNS resource.
The install script checks the OS version and prints a macOS 14 requirement message before building when run on an older Mac. The app itself cannot display an in-app warning on unsupported systems because macOS blocks launch below its deployment target.

## Build

Open `Package.swift` in Xcode and build the `YTDLPro` scheme. Or use:

```zsh
cd path/to/YT-DLPro
xcodebuild -scheme YTDLPro -configuration Debug -destination 'platform=macOS' -derivedDataPath "build/Xcode" build
```

The executable is written to `build/Xcode/Build/Products/Debug/YT-DLPro`.

## Run

Run the Xcode scheme, or launch the debug executable:

```zsh
cd path/to/YT-DLPro
"build/Xcode/Build/Products/Debug/YT-DLPro"
```

System tools are discovered through a login shell so Homebrew paths are available. The tool settings show the selected paths/versions and allow choosing system-first or built-in-first resolution. YouTube downloads use Deno and yt-dlp's official EJS scripts. The app can update the active yt-dlp, inspect video formats, manage profiles/history, and download media.

## Install And Package

Run the installer from Terminal:

```zsh
cd path/to/YT-DLPro
./scripts/install.sh
```

The script builds a universal Release app with an ad-hoc signature, installs `YT-DLPro.app` in `/Applications`, and creates `build/YT-DLPro-universal.zip`. It may ask for your Mac administrator password when copying into `/Applications`.

The ZIP contains only the app. Download tools are fetched during first-launch setup and stay outside the app bundle.

To prepare and publish a versioned drag-to-install DMG from a local checkout, run `./scripts/release.sh 1.0.0`. Add `--draft` or `--prerelease` to create a test release instead of publishing it immediately. The script requires the GitHub CLI (`gh`) to be installed and authenticated.

## First Launch On A New Mac

The app is ad-hoc signed, not notarized. If Gatekeeper blocks it, in Finder right-click `YT-DLPro.app`, choose **Open**, then confirm **Open** in the dialog. You can also use **System Settings > Privacy & Security > Open Anyway** after the blocked launch, or remove the quarantine attribute in Terminal:

```zsh
xattr -cr "/Applications/YT-DLPro.app"
```

On first use, select **Set up now** to install yt-dlp, ffmpeg/ffprobe, and Deno without using Terminal. The standalone yt-dlp binary is downloaded from the official yt-dlp GitHub release. Static FFmpeg and ffprobe binaries come from the `ffmpeg-static` release assets: arm64 uses `ffmpeg-darwin-arm64`; Intel uses `ffmpeg-darwin-x64`. Deno comes from official `denoland/deno` release ZIPs. The installer verifies SHA-256 checksums, sets executable permissions, removes quarantine, and checks tool versions before use. FFmpeg licensing information is saved alongside the fallback tools. If a download host is unreachable, setup offers a file picker for a manually downloaded executable; Deno ZIPs must be extracted first.

Current yt-dlp YouTube guidance recommends Deno (minimum supported 2.3.0) as the JavaScript runtime. YT-DLPro discovers system Deno or installs a fallback copy, passes its path explicitly, and enables yt-dlp's official EJS scripts from GitHub. The setup screen appears when the required tools are not found.

## Terminal Features

- Tools are discovered through a login shell so Homebrew installations are visible; with **Prefer system tools** selected, they are used before built-in copies.
- **Prefer system tools / Prefer built-in copies** switches which installation source takes priority.
- System `yt-dlp` copies are updated through Homebrew; built-in copies use `yt-dlp -U`.
- **Open in Terminal** and **Copy as shell command** give you the exact yt-dlp command the app runs.
- The setup screen appears only when no required tools are found.

## Tests

```zsh
cd path/to/YT-DLPro
xcodebuild -scheme YTDLPro -destination 'platform=macOS,arch=arm64' -derivedDataPath "build/Xcode" test
```

Real test media, when generated, is kept under `build/DownloadTests` and is not included in Git or the app ZIP.

## Where files are stored

- Profiles, history, settings, and downloaded tools: `~/Library/Application Support/YT-DLPro/`
- Downloads: your chosen output folder (default `~/Downloads`)

## License

MIT. See [LICENSE](LICENSE).
