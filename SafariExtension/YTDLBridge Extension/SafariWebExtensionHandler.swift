import AppKit
import Foundation
import SafariServices

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let msg = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]

        guard let target = (msg["url"] as? String).flatMap(URL.init(string:)),
              target.scheme?.hasPrefix("http") == true
        else {
            respond(context, ok: false, message: "no url")
            return
        }
        let audioOnly = (msg["audioOnly"] as? Bool) ?? false

        var comps = URLComponents()
        comps.scheme = "ytdlbridge"
        comps.host = "download"
        comps.queryItems = [
            URLQueryItem(name: "url", value: target.absoluteString),
            URLQueryItem(name: "audioOnly", value: audioOnly ? "1" : "0"),
        ]
        guard let dispatchURL = comps.url else {
            respond(context, ok: false, message: "url encode failed")
            return
        }

        NSWorkspace.shared.open(dispatchURL)
        respond(context, ok: true, message: "dispatched")
    }

    private func respond(_ ctx: NSExtensionContext, ok: Bool, message: String) {
        let out = NSExtensionItem()
        out.userInfo = [SFExtensionMessageKey: ["ok": ok, "message": message]]
        ctx.completeRequest(returningItems: [out], completionHandler: nil)
    }
}
