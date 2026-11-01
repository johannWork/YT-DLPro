# YT-DLPro

Native SwiftUI GUI for `yt-dlp`, `ffmpeg`, and Deno. YT-DLPro does not bundle these tools in the app. On first launch, **Set up now** can install standalone copies in `~/Library/Application Support/YT-DLPro/bin` when system copies are not found.

## Requirements

- macOS 14 or newer
- Xcode with the macOS SDK
- Network access for video metadata and downloads

The app and release ZIP are universal `arm64` + `x86_64`. Build products and test downloads stay inside the ignored `build/` directory.
The app icon is generated from the transparent `YT-DLPro.png` logo in the project root and embedded as a native macOS ICNS resource.
The install script checks the OS version and prints a macOS 14 requirement message before building when run on an older Mac. The app itself cannot display an in-app warning on unsupported systems because macOS blocks launch below its deployment target.

## Build

Open `Package.swift` in Xcode and build the `YTDLPro` scheme. Or use:

```zsh
cd "/Volumes/PSSD GP30/VSCode Projects/YT-DLPro"
xcodebuild -scheme YTDLPro -configuration Debug -destination 'platform=macOS' -derivedDataPath "build/Xcode" build
```

The executable is written to `build/Xcode/Build/Products/Debug/YT-DLPro`.

## Run

Run the Xcode scheme, or launch the debug executable:

```zsh
cd "/Volumes/PSSD GP30/VSCode Projects/YT-DLPro"
"build/Xcode/Build/Products/Debug/YT-DLPro"
```

System tools are discovered through a login shell so Homebrew paths are available. The tool settings show the selected paths/versions and allow choosing system-first or built-in-first resolution. YouTube downloads use Deno and yt-dlp's official EJS scripts. The app can update the active yt-dlp, inspect video formats, manage profiles/history, and download media.

## Install And Package

Run the installer from Terminal:

```zsh
cd "/Volumes/PSSD GP30/VSCode Projects/YT-DLPro"
./scripts/install.sh
```

The script builds a universal Release app with an ad-hoc signature, installs `YT-DLPro.app` in `/Applications`, and creates `build/YT-DLPro-universal.zip`. It may ask for your Mac administrator password when copying into `/Applications`.

The ZIP contains only the app. Download tools are fetched during first-launch setup and stay outside the app bundle.

## First Launch On A New Mac

The app is ad-hoc signed, not notarized. If Gatekeeper blocks it, in Finder right-click `YT-DLPro.app`, choose **Open**, then confirm **Open** in the dialog. Alternatively, remove the quarantine attribute in Terminal:

```zsh
xattr -cr "/Applications/YT-DLPro.app"
```

On first use, select **Set up now** to install yt-dlp, ffmpeg/ffprobe, and Deno without using Terminal. The standalone yt-dlp binary is downloaded from the official yt-dlp GitHub release. Static FFmpeg and ffprobe binaries come from the `ffmpeg-static` release assets: arm64 uses `ffmpeg-darwin-arm64`; Intel uses `ffmpeg-darwin-x64`. Deno comes from official `denoland/deno` release ZIPs. The installer verifies SHA-256 checksums, sets executable permissions, removes quarantine, and checks tool versions before use. FFmpeg licensing information is saved alongside the fallback tools. If a download host is unreachable, setup offers a file picker for a manually downloaded executable; Deno ZIPs must be extracted first.

Current yt-dlp YouTube guidance recommends Deno (minimum supported 2.3.0) as the JavaScript runtime. YT-DLPro discovers system Deno or installs a fallback copy, passes its path explicitly, and enables yt-dlp's official EJS scripts from GitHub.

## Tests

```zsh
cd "/Volumes/PSSD GP30/VSCode Projects/YT-DLPro"
xcodebuild -scheme YTDLPro -destination 'platform=macOS,arch=arm64' -derivedDataPath "build/Xcode" test
```

Real test media, when generated, is kept under `build/DownloadTests` and is not included in Git or the app ZIP.