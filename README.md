# ytdl

A thin CLI wrapper around [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) with
[`rich`](https://github.com/Textualize/rich) progress display, plus a Safari Web
Extension that lets you download the current tab with a single click.

## Requirements

- Python 3.10+
- **[deno](https://deno.land)** — required to solve YouTube's JS challenges
  (n-signature). Many videos won't work with `node` alone.
- **ffmpeg** — needed for audio extraction (`--audio-only`) and for muxing
  video+audio streams.

```bash
brew install deno ffmpeg
```

## Install

Run from the project root (where [pyproject.toml](pyproject.toml) lives):

```bash
pip install -e .
```

This installs the `ytdl` command.

## Usage

```bash
# Basic (best-quality mp4)
ytdl "https://www.youtube.com/watch?v=XXXXXXXXXXX"

# Audio only (mp3)
ytdl --audio-only "URL"

# Custom output directory
ytdl -d ~/Downloads "URL"

# Output filename template
ytdl -o "%(uploader)s - %(title)s.%(ext)s" "URL"

# List available formats
ytdl --list-formats "URL"

# Explicit format (e.g. 720p, bestaudio)
ytdl -f "bestvideo[height<=720]+bestaudio" "URL"

# Subtitles (ja / en)
ytdl --subtitles "URL"

# Entire playlist
ytdl --playlist "PLAYLIST_URL"
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `-o, --output` | `%(title)s.%(ext)s` | Output filename template |
| `-d, --output-dir` | `.` | Destination directory |
| `-f, --format` | *(see below)* | yt-dlp format selector |
| `--audio-only` | off | Save audio as mp3 |
| `--list-formats` | off | Show available formats |
| `--subtitles` | off | Download subtitles (ja, en) |
| `--playlist` | off | Download entire playlist |
| `--cookies-from-browser` | `safari` | Read cookies from a browser (`chrome`, `firefox`, `edge`, `brave`, …). Pass `""` to disable. |
| `--cookies` | *(none)* | Path to a `cookies.txt` file |
| `--player-client` | `default,web,mweb,ios,android` | YouTube player clients to try (comma-separated) |

Default format expression:

```
bestvideo[ext=mp4]+bestaudio[ext=m4a] / bestvideo+bestaudio / best[ext=mp4] / best
```

## About cookies

- By default the tool reads cookies from **Safari**. Being signed in there lets
  you download age-gated, unlisted, and Premium-quality videos.
- If you use Chrome, quit Chrome first — otherwise the Cookie DB is locked and
  cannot be read. Safari's DB can be read while Safari is running.
- Use `--cookies-from-browser ""` to disable cookies entirely.

## Troubleshooting

### `Please sign in. Use --cookies-from-browser`

The target video requires authentication. Make sure you're signed into YouTube
in Safari, or pass a different browser explicitly:

```bash
ytdl --cookies-from-browser chrome "URL"
```

### `Requested format is not available` (only storyboards listed)

The n-parameter challenge failed to resolve. Check:

1. `deno` is installed (`which deno`)
2. yt-dlp is up to date (`pip install -U yt-dlp`)

### Using a specific browser profile

`--cookies-from-browser` accepts profile syntax like `chrome:Profile 1` (see
`yt-dlp --help` for details).

## Safari extension (YTDL Bridge)

A **Safari Web Extension** under [`SafariExtension/`](SafariExtension/) exposes
a toolbar button that downloads the current tab into `~/Downloads/`. The
directory contains the full Xcode project and a build script that signs and
notarizes a `.dmg`.

### For end users (installing a distributed `.dmg`)

1. Download `YTDLBridge.dmg` from GitHub Releases.
2. Open the `.dmg` and drag `YTDLBridge.app` into `/Applications`.
3. Launch `YTDLBridge.app` once so Safari registers the extension. You can quit
   the app afterward.
4. Open **Safari > Settings > Extensions**, enable **YTDL Bridge**, and allow
   it on all websites.
5. On first use, macOS prompts for notification and Downloads-folder access —
   allow both.
6. Click the YTDL Bridge toolbar icon on any tab and pick **Download video** or
   **Download audio only**. The file appears in `~/Downloads/` and a
   notification fires when done.

**Prerequisites on the user's Mac**: `ytdl` (this project's CLI, installed in a
venv) plus `deno` and `ffmpeg`. The extension only forwards the URL; the actual
download is performed by the local `ytdl` binary.

### For developers

See [`SafariExtension/SETUP.md`](SafariExtension/SETUP.md). In short: copy
`Local.xcconfig.sample` to `Local.xcconfig`, fill in your Apple Team ID and the
path to your `ytdl` binary, then hit ⌘R in Xcode.

Building a notarized `.dmg`:

```bash
cd SafariExtension
export TEAM_ID=XXXXXXXXXX          # your 10-char Apple Team ID
export NOTARY_PROFILE=AC_NOTARY    # profile created via `xcrun notarytool store-credentials`
./scripts/build_release.sh
# → build/YTDLBridge.dmg (signed with Developer ID, notarized, stapled)
```

Cutting a full GitHub Release (tag + build + upload) in one shot:

```bash
cd SafariExtension
export TEAM_ID=XXXXXXXXXX
export NOTARY_PROFILE=AC_NOTARY
./scripts/release.sh 0.1.1
# → tags v0.1.1, builds the DMG, and publishes a GitHub Release with the asset.
```

The script refuses to run if the working tree is dirty, the tag already exists,
or `gh` / `notarytool` credentials are missing.

### Limitations

- Output is fixed to `~/Downloads/`.
- No quality picker (only video / audio-only).
- The `ytdl` binary path is set in `SafariExtension/Local.xcconfig`
  (`YTDL_BIN_PATH`) and baked into `Info.plist` at build time. Rebuild after
  recreating the venv.

## License

Source code is released under the **MIT License**. See [LICENSE](LICENSE).

Runtime dependencies (yt-dlp, Click, Rich, ffmpeg, deno) are distributed under
their own licenses — see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Disclaimer

- This tool is developed for personal learning and archival use. Any use of
  downloaded content must comply with the copyright of the source material and
  the [YouTube Terms of Service](https://www.youtube.com/t/terms). Use at your
  own risk.
- YouTube's internals change frequently. When something breaks, updating the
  underlying `yt-dlp` (`pip install -U yt-dlp`) usually fixes it.
- No warranty or support is provided.
