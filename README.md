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

**Prerequisites on the user's Mac**: `ytdl` (this project's CLI) plus `deno` and
`ffmpeg`. The extension only forwards the URL; the actual download is performed
by the local `ytdl` binary. Apple Silicon (arm64) only.

The app locates `ytdl` automatically, checking in order:

1. the path baked in at build time (`YTDL_BIN_PATH`, normally empty)
2. a path you saved in the app's own window
3. `~/.local/bin/ytdl`, `/opt/homebrew/bin/ytdl`, `/usr/local/bin/ytdl`
4. `ytdl` on your login shell's `PATH` — this is what finds a venv install

If autodetection picks the wrong binary or finds none, open **YTDLBridge.app**
and set the path there. The window shows the detected path as the default; the
**Choose…** button opens a file picker, and **Use detected path** clears the
override.

### For developers

See [`SafariExtension/SETUP.md`](SafariExtension/SETUP.md). In short: copy
`Local.xcconfig.sample` to `Local.xcconfig`, fill in your Apple Team ID, then hit
⌘R in Xcode. `YTDL_BIN_PATH` can stay empty — leave it unset unless you want a
specific binary preferred over autodetection.

Building a notarized `.dmg`:

```bash
cd SafariExtension
export TEAM_ID=XXXXXXXXXX          # your 10-char Apple Team ID
export NOTARY_PROFILE=AC_NOTARY    # profile created via `xcrun notarytool store-credentials`
./scripts/build_release.sh
# → build/YTDLBridge.dmg (signed with Developer ID, notarized, stapled)
```

Cutting a full GitHub Release (tag + build + upload) locally, in one shot:

```bash
cd SafariExtension
export TEAM_ID=XXXXXXXXXX
export NOTARY_PROFILE=AC_NOTARY
./scripts/release.sh 0.1.1
# → tags v0.1.1, builds the DMG, and publishes a GitHub Release with the asset.
```

The script refuses to run if the working tree is dirty, the tag already exists,
or `gh` / `notarytool` credentials are missing.

### Releasing via GitHub Actions

[`.github/workflows/release.yml`](.github/workflows/release.yml) does the same
thing on a **self-hosted macOS runner** (labels: `self-hosted`, `macOS`,
`ARM64`). Trigger it either way:

- push a tag — `git tag v0.1.1 && git push origin v0.1.1`
- or run **Actions → Release → Run workflow** and enter the version; the
  workflow creates and pushes the tag itself.

The asset is published as `YTDLBridge-<version>.dmg`.

**One-time runner setup**, since the workflow uses the runner's login keychain
rather than secrets:

1. Install the **Developer ID Application** certificate into the login keychain.
2. Register notary credentials once:
   ```bash
   xcrun notarytool store-credentials AC_NOTARY \
     --apple-id "you@example.com" --team-id XXXXXXXXXX \
     --password "app-specific-password"
   ```
3. Add repository variable **`TEAM_ID`** (Settings → Actions → Variables) with
   your 10-character team ID. Optionally set `NOTARY_PROFILE` if your profile
   isn't named `AC_NOTARY`.
4. Make sure the runner service can read the keychain — run it as your user in a
   GUI session, not as a LaunchDaemon, or `codesign` will fail to find the
   identity.

The workflow pre-flights the certificate, the notary profile and `TEAM_ID`
before building, generates the gitignored `Local.xcconfig` itself, and deletes
it afterward.

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
