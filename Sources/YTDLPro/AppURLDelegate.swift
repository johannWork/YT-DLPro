import AppKit

final class AppURLDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .ytDlpOpenURLs, object: urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.compactMap { filename -> URL? in
            if let url = URL(string: filename), let scheme = url.scheme, ["http", "https"].contains(scheme) {
                return url
            }
            if filename.hasSuffix(".webloc"), let data = try? Data(contentsOf: URL(fileURLWithPath: filename)),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
               let address = plist["URL"] {
                return URL(string: address)
            }
            return nil
        }
        if !urls.isEmpty { NotificationCenter.default.post(name: .ytDlpOpenURLs, object: urls) }
        sender.reply(toOpenOrPrint: .success)
    }
}