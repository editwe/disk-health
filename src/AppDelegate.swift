import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    private var window: NSWindow!
    private var webView: WKWebView!

    /// UI language: follows the system, can be forced with DH_LANG=zh|en.
    private let isChinese: Bool = {
        if let override = ProcessInfo.processInfo.environment["DH_LANG"] {
            return override.lowercased().hasPrefix("zh")
        }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    }()

    private func t(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "refresh")
        config.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .windowBackgroundColor
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 652),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = t("硬盘健康", "Disk Health")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 540, height: 600)
        window.contentView = webView
        if ProcessInfo.processInfo.environment["DH_DARK"] != nil {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<h1 style='font-family:-apple-system;padding:40px'>index.html missing</h1>", baseURL: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: t("关于「硬盘健康」", "About Disk Health"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("隐藏「硬盘健康」", "Hide Disk Health"),
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t("退出「硬盘健康」", "Quit Disk Health"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: t("显示", "View"))
        let refresh = NSMenuItem(title: t("刷新", "Refresh"), action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        viewMenu.addItem(refresh)
        viewItem.submenu = viewMenu

        NSApp.mainMenu = main
    }

    @objc private func refreshAction() {
        inject()
    }

    // MARK: - Data

    private func inject() {
        let json = String(cString: dh_read_health_json())
        let meta = "{\"total\":\(volumeCapacity().total),\"free\":\(volumeCapacity().free),"
                 + "\"lang\":\"\(isChinese ? "zh" : "en")\","
                 + "\"redact\":\(ProcessInfo.processInfo.environment["DH_REDACT"] != nil)}"
        webView.evaluateJavaScript("window.render(\(json), \(meta));") { _, error in
            if let error {
                NSLog("render failed: %@", error.localizedDescription)
            }
        }
        captureIfRequested()
    }

    private func volumeCapacity() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) else {
            return (0, 0)
        }
        return (Int64(values.volumeTotalCapacity ?? 0), Int64(values.volumeAvailableCapacity ?? 0))
    }

    /// Debug hook: DH_SNAPSHOT=/path/out.png renders once, saves a snapshot and quits.
    private func captureIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["DH_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let config = WKSnapshotConfiguration()
            config.rect = self.webView.bounds
            self.webView.takeSnapshot(with: config) { image, error in
                defer { NSApp.terminate(nil) }
                guard let image,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    NSLog("snapshot failed: %@", error?.localizedDescription ?? "unknown")
                    return
                }
                try? png.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    // MARK: - WKNavigationDelegate / WKScriptMessageHandler

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inject()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "refresh" { inject() }
    }
}
