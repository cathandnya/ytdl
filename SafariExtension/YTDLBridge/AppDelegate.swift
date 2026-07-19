import Cocoa
import UserNotifications
import os.log

private let log = OSLog(subsystem: "org.cathand.YTDLBridge", category: "app")
private let safariCookiesPath =
    ("~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies" as NSString).expandingTildeInPath

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Trigger the TCC prompt for Full Disk Access by reading Safari's cookies.
        // If access is denied, guide the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            checkSafariCookieAccess()
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        urls.forEach(dispatch(url:))
    }

    @objc private func handleGetURL(event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s)
        else { return }
        dispatch(url: url)
    }

    private func dispatch(url: URL) {
        guard url.scheme == "ytdlbridge", url.host == "download" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let target = items.first(where: { $0.name == "url" })?.value,
              let targetURL = URL(string: target),
              targetURL.scheme?.hasPrefix("http") == true
        else {
            notify(title: "YTDL Bridge error", body: "invalid url")
            return
        }
        let audioOnly = (items.first(where: { $0.name == "audioOnly" })?.value == "1")

        do {
            try runYtdl(targetURL: targetURL, audioOnly: audioOnly)
            notify(title: "ytdl started", body: targetURL.absoluteString)
        } catch {
            os_log("runYtdl error: %{public}@", log: log, type: .error, String(describing: error))
            notify(title: "ytdl failed to start", body: String(describing: error))
        }
    }

    private func runYtdl(targetURL: URL, audioOnly: Bool) throws {
        let ytdlPath = configuredYtdlPath()
        let downloads = ("~/Downloads" as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: ytdlPath) else {
            throw NSError(domain: "YTDLBridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                              "ytdl not found at \(ytdlPath).\n" +
                              "Set YTDL_BIN_PATH in SafariExtension/Local.xcconfig and rebuild."])
        }

        var args = ["-d", downloads]
        if audioOnly { args.append("--audio-only") }
        args.append(targetURL.absoluteString)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: ytdlPath)
        p.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        var stdoutData = Data()
        var stderrData = Data()
        let ioQueue = DispatchQueue(label: "org.cathand.YTDLBridge.ytdl.io")

        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            if !d.isEmpty { ioQueue.sync { stdoutData.append(d) } }
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let d = fh.availableData
            if !d.isEmpty { ioQueue.sync { stderrData.append(d) } }
        }

        p.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            let (stdout, stderr) = ioQueue.sync { (stdoutData, stderrData) }
            let stdoutStr = String(data: stdout, encoding: .utf8) ?? ""
            let stderrStr = String(data: stderr, encoding: .utf8) ?? ""
            if status == 0 {
                notify(title: "ytdl finished", body: targetURL.absoluteString)
            } else {
                os_log("ytdl failed status=%d stderr=%{public}@ stdout=%{public}@",
                       log: log, type: .error, status, stderrStr, stdoutStr)
                if stderrStr.contains("Operation not permitted")
                    && stderrStr.contains("Cookies.binarycookies") {
                    DispatchQueue.main.async { promptForFullDiskAccess() }
                }
                let detail = friendlyError(stderr: stderrStr, stdout: stdoutStr)
                notify(title: "ytdl failed (exit \(status))",
                       body: detail.isEmpty ? targetURL.absoluteString : detail)
            }
        }

        try p.run()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { false }
}

private func configuredYtdlPath() -> String {
    let raw = (Bundle.main.object(forInfoDictionaryKey: "YTDLBinPath") as? String) ?? ""
    return (raw as NSString).expandingTildeInPath
}

private func checkSafariCookieAccess() {
    // Reading this file triggers macOS's Full Disk Access TCC check.
    // If the app has been granted access, this succeeds silently.
    // If not, macOS shows the standard "allow access" prompt (once per install).
    let fd = open(safariCookiesPath, O_RDONLY)
    if fd >= 0 {
        close(fd)
        return
    }
    if errno == EPERM || errno == EACCES {
        promptForFullDiskAccess()
    }
}

private var didShowFullDiskPrompt = false

private func promptForFullDiskAccess() {
    if didShowFullDiskPrompt { return }
    didShowFullDiskPrompt = true

    let alert = NSAlert()
    alert.messageText = "Full Disk Access is required"
    alert.informativeText = """
    YTDL Bridge reads Safari's login cookies to access YouTube.
    macOS requires Full Disk Access to allow this.

    Click "Open System Settings", add YTDLBridge to the list, and toggle it on.
    """
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")
    NSApp.activate(ignoringOtherApps: true)
    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}

private func friendlyError(stderr: String, stdout: String) -> String {
    let combined = (stderr + "\n" + stdout)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    if let last = combined.last(where: { $0.uppercased().contains("ERROR") }) {
        let trimmed = last
            .replacingOccurrences(of: "\u{1B}[0;31m", with: "")
            .replacingOccurrences(of: "\u{1B}[0m", with: "")
        return String(trimmed.prefix(300))
    }
    return String((combined.last ?? "").prefix(300))
}

private func notify(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
}
