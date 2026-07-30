import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "org.cathand.YTDLBridge.Extension"

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self
        self.webView.configuration.userContentController.add(self, name: "controller")
        self.webView.loadFileURL(
            Bundle.main.url(forResource: "Main", withExtension: "html")!,
            allowingReadAccessTo: Bundle.main.resourceURL!
        )
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        webView.evaluateJavaScript("show()")

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { state, error in
            guard let state, error == nil else { return }
            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show(\(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show(\(state.isEnabled), false)")
                }
            }
        }

        refreshYtdlPath()
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.body as? String == "open-preferences" {
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                guard error == nil else { return }
                DispatchQueue.main.async { NSApp.terminate(self) }
            }
            return
        }

        guard let msg = message.body as? [String: Any],
              let name = msg["name"] as? String else { return }
        let value = (msg["value"] as? String) ?? ""

        switch name {
        case "save-ytdl-path":
            saveYtdlPath(value)
        case "reset-ytdl-path":
            UserDefaults.standard.removeObject(forKey: ytdlPathDefaultsKey)
            refreshYtdlPath()
        case "browse-ytdl-path":
            browseForYtdlPath()
        default:
            break
        }
    }

    // MARK: - ytdl path

    private func saveYtdlPath(_ raw: String) {
        let path = (raw as NSString).expandingTildeInPath
        if path.isEmpty {
            UserDefaults.standard.removeObject(forKey: ytdlPathDefaultsKey)
        } else {
            UserDefaults.standard.set(path, forKey: ytdlPathDefaultsKey)
        }
        refreshYtdlPath()
    }

    private func browseForYtdlPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose the ytdl executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.saveYtdlPath(url.path)
        }
    }

    /// Push the current detected + saved paths into the web view.
    private func refreshYtdlPath() {
        let saved = UserDefaults.standard.string(forKey: ytdlPathDefaultsKey) ?? ""
        let detected = detectedYtdlPath() ?? ""
        let effective = saved.isEmpty ? detected : saved
        let valid = !effective.isEmpty
            && FileManager.default.isExecutableFile(atPath: effective)

        let js = "showYtdlPath("
            + "\(jsString(detected)), \(jsString(saved)), \(valid))"
        webView.evaluateJavaScript(js)
    }

    /// JSON-encode so paths with quotes or backslashes can't break out of the literal.
    private func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s], options: []),
              let arr = String(data: data, encoding: .utf8),
              arr.count >= 2
        else { return "\"\"" }
        return String(arr.dropFirst().dropLast())
    }
}
