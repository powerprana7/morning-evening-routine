import AppKit
import SwiftUI

/// 판 창 (2026-11-08) — 설정 화면이 없는 웹 감싸개 앱이라, 앱 메뉴의 「정보」가 이 창을 연다.
/// 설치된 판(v26.11.08 (1247) 꼴)과 Check for Updates · Install 버튼이 있는 한 줄(UpdateRow)을 띄운다.
@MainActor
enum VersionWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let view = VStack(alignment: .leading, spacing: 14) {
                Text(UpdateCfg.displayName).font(.title2.bold())
                UpdateRow()
            }
            .padding(24)
            .frame(minWidth: 420, alignment: .leading)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = UpdateCfg.t("\(UpdateCfg.displayName) 정보", "About \(UpdateCfg.displayName)")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
