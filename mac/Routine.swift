// 루틴 — 맥 앱 (D-016)
//
// 배포된 URL 을 WKWebView 로 띄운다. 브라우저에 의존하지 않고, 독 아이콘으로 실행되며,
// 창 크기를 기억한다.
//
// 왜 로컬 사본이 아니라 URL 을 띄우나
//   앱 안에 HTML 을 넣어버리면 그 순간 맥만 다른 버전을 보게 된다. 앱을 다시 만들기
//   전까지 push 한 수정이 맥에 영영 안 온다 — D-014·D-015 로 없앤 문제가 되살아난다.
//   그래서 원본은 언제나 URL 이고, **네트워크가 안 될 때만** 동봉 사본으로 넘어간다.

import Cocoa
import WebKit

let remoteURL = URL(string: "https://powerprana7.github.io/morning-evening-routine/")!
let paper = NSColor(srgbRed: 0.992, green: 0.980, blue: 0.953, alpha: 1)   // #fdfaf3

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var usingFallback = false

    func applicationDidFinishLaunching(_ note: Notification) {
        let cfg = WKWebViewConfiguration()
        // 완료음이 사용자 조작 없이도 울릴 수 있게 (앱 안에서는 자동재생 제한이 불필요)
        cfg.mediaTypesRequiringUserActionForPlayback = []

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")   // 흰 깜빡임 방지

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "routine"
        window.backgroundColor = paper
        window.contentView = web
        window.setFrameAutosaveName("RoutineMainWindow")   // 창 위치·크기를 기억한다
        window.minSize = NSSize(width: 360, height: 520)
        if window.frame.origin == .zero { window.center() }
        window.makeKeyAndOrderFront(nil)

        buildMenu()
        load()
        NSApp.activate(ignoringOtherApps: true)
    }

    func load() {
        usingFallback = false
        // 항상 새것을 먼저 본다 — 캐시를 먼저 쓰면 push 한 수정이 늦게 온다
        var req = URLRequest(url: remoteURL)
        req.cachePolicy = .reloadRevalidatingCacheData
        req.timeoutInterval = 8
        web.load(req)
    }

    // 네트워크가 안 되면 앱에 동봉된 사본으로
    func fallback() {
        guard !usingFallback,
              let local = Bundle.main.url(forResource: "index", withExtension: "html")
        else { return }
        usingFallback = true
        web.loadFileURL(local, allowingReadAccessTo: local.deletingLastPathComponent())
    }

    func webView(_ w: WKWebView, didFail nav: WKNavigation!, withError e: Error) { fallback() }
    func webView(_ w: WKWebView, didFailProvisionalNavigation nav: WKNavigation!,
                 withError e: Error) { fallback() }

    // 창을 닫으면 앱도 끝난다 (독에 남아 있을 이유가 없다)
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    @objc func reload() { load() }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "routine 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "routine 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "보기")
        viewMenu.addItem(withTitle: "새로고침", action: #selector(reload), keyEquivalent: "r")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
