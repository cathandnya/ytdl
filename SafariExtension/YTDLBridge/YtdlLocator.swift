import Foundation

/// UserDefaults key holding a user-chosen absolute path to the `ytdl` executable.
/// Empty/absent means "use whatever autodetection finds".
let ytdlPathDefaultsKey = "YTDLBinPath"

/// Candidate locations for the `ytdl` executable, most likely first.
///
/// There is no single install location: `pip install -e .` puts it in a venv next
/// to wherever the repo was cloned, `pipx` uses ~/.local/bin, and a Homebrew-python
/// install lands in /opt/homebrew/bin. So we probe the common ones rather than
/// baking one absolute path into the app.
func ytdlSearchPaths() -> [String] {
    var paths: [String] = []

    // A build-time default, if this build was configured with one.
    if let raw = Bundle.main.object(forInfoDictionaryKey: "YTDLBinPath") as? String,
       !raw.isEmpty {
        paths.append((raw as NSString).expandingTildeInPath)
    }

    paths += [
        "~/.local/bin/ytdl",
        "/opt/homebrew/bin/ytdl",
        "/usr/local/bin/ytdl",
    ].map { ($0 as NSString).expandingTildeInPath }

    return paths
}

/// The path autodetection would pick, ignoring any user override.
func detectedYtdlPath() -> String? {
    let fm = FileManager.default
    for path in ytdlSearchPaths() where fm.isExecutableFile(atPath: path) {
        return path
    }
    // Fall back to a PATH lookup — catches venvs and layouts we don't know about.
    return which("ytdl")
}

/// The path the app should actually run: the user's override when set and usable,
/// otherwise autodetection.
func resolveYtdlPath() -> String? {
    if let saved = UserDefaults.standard.string(forKey: ytdlPathDefaultsKey), !saved.isEmpty {
        let expanded = (saved as NSString).expandingTildeInPath
        if FileManager.default.isExecutableFile(atPath: expanded) {
            return expanded
        }
        // A saved-but-broken path (venv rebuilt, repo moved) shouldn't wedge the app.
    }
    return detectedYtdlPath()
}

/// Resolve `name` against the login shell's PATH.
///
/// A GUI app inherits a minimal PATH, so asking the user's shell is the only way
/// to see a venv that's only on PATH because of their profile.
func which(_ name: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-lc", "command -v \(name)"]

    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice

    do {
        try p.run()
    } catch {
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()

    guard p.terminationStatus == 0,
          let out = String(data: data, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
          !out.isEmpty,
          FileManager.default.isExecutableFile(atPath: out)
    else { return nil }
    return out
}
