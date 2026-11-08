import Foundation
import AppKit
import CryptoKit

/// 자체 업데이트 (2026-11-08) — Timeline 맥 앱의 Updater 를 가져왔다.
/// 방식: 받아 두고 사람이 설치 버튼을 누른다. 켤 때와 Check for Updates 때 version.json 을 읽고,
/// 설치된 CFBundleVersion 보다 크면 알린다. 설치는 버튼을 누른 뒤에만, 받은 zip 의 sha256 이 맞을 때만 한다.
/// 서버는 Startpage 의 /apps/<앱>/ (R2 mac-apps) — 프로가 자도 받는다.
/// 이 파일은 note-reader/mac/Sources/Updater.swift 를 가져왔다. 다른 것은 아래 `UpdateCfg` 뿐이다.
/// 올리기는 tools/publish-mac.sh, 시험은 tools/update-test-mac.sh.
enum UpdateCfg {
    static let app = "routine"
    static let displayName = "Routine"
    static func t(_ ko: String, _ en: String) -> String { ko }
}

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    struct Info: Equatable { let code: Int, name: String, size: Int, sha256: String, url: String }

    @Published var available: Info?
    @Published var busy: String?
    @Published var note: String?

    /// 시험할 때 UPDATE_BASE 로 다른 서버를 가리킬 수 있다 (실제 서버의 판을 건드리지 않는다)
    static var base: String {
        ProcessInfo.processInfo.environment["UPDATE_BASE"] ?? "https://start.comms.ms/apps/\(UpdateCfg.app)"
    }
    static var origin: String {
        guard let u = URL(string: base), let s = u.scheme, let h = u.host else { return base }
        return "\(s)://\(h)" + (u.port.map { ":\($0)" } ?? "")
    }

    static func info(_ key: String) -> String {
        let p = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        return (NSDictionary(contentsOf: p)?[key] as? String) ?? (Bundle.main.infoDictionary?[key] as? String) ?? "?"
    }
    static var installedCode: Int { Int(info("CFBundleVersion")) ?? 0 }
    static var installedName: String { info("CFBundleShortVersionString") }

    /// 켤 때 — 새 판이 있으면 그 판에 한 번만 묻는다
    func checkOnLaunch() async {
        await check()
        guard let i = available, UserDefaults.standard.integer(forKey: "updateAnnounced") != i.code else { return }
        UserDefaults.standard.set(i.code, forKey: "updateAnnounced")
        askInstall(i)
    }

    /// 앱 메뉴의 Check for Updates…
    func checkFromMenu() async {
        await check(manual: true)
        if let i = available { askInstall(i); return }
        let a = NSAlert()
        a.messageText = note == upToDate ? UpdateCfg.t("최신 버전입니다", "You're up to date.") : UpdateCfg.t("확인하지 못했습니다", "Couldn't check for updates.")
        a.informativeText = note == upToDate ? "\(UpdateCfg.displayName) v\(Updater.installedName)" : UpdateCfg.t("인터넷 연결을 확인하세요.", "Check your internet connection.")
        a.runModal()
    }

    private var upToDate: String { UpdateCfg.t("최신 버전입니다", "Up to date") }

    func check(manual: Bool = false) async {
        if manual { note = UpdateCfg.t("확인 중…", "Checking…") }
        var req = URLRequest(url: URL(string: "\(Updater.base)/version.json")!)
        req.timeoutInterval = 10; req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let m = j["mac"] as? [String: Any],
              let code = m["versionCode"] as? Int, let name = m["versionName"] as? String,
              let sha = m["sha256"] as? String, let url = m["url"] as? String else {
            if manual { note = UpdateCfg.t("확인하지 못했습니다", "Couldn't check") }
            return
        }
        available = code > Updater.installedCode ? Info(code: code, name: name, size: m["size"] as? Int ?? 0, sha256: sha, url: url) : nil
        if manual { note = available == nil ? upToDate : nil }
    }

    private func askInstall(_ i: Info) {
        let a = NSAlert()
        a.messageText = UpdateCfg.t("새 버전이 있습니다", "A new version of \(UpdateCfg.displayName) is available.")
        a.informativeText = UpdateCfg.t("v\(i.name) — 지금 v\(Updater.installedName)", "v\(i.name) — you have v\(Updater.installedName).")
        a.addButton(withTitle: UpdateCfg.t("설치 후 다시 열기", "Install and Relaunch"))
        a.addButton(withTitle: UpdateCfg.t("나중에", "Later"))
        if a.runModal() == .alertFirstButtonReturn { Task { await install() } }
    }

    /// 받기 → sha256 확인 → 풀기 → 바꿔 끼우기 → (relaunch 면) 새 판을 띄우고 이 판을 끈다
    func install(relaunch: Bool = true) async {
        guard let i = available, busy == nil || busy?.hasSuffix("…") == false else { return }
        busy = UpdateCfg.t("받는 중…", "Downloading…")
        let full = i.url.hasPrefix("http") ? i.url : Updater.origin + i.url
        guard let u = URL(string: full), let (data, resp) = try? await URLSession.shared.data(from: u),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { busy = UpdateCfg.t("받지 못했습니다", "Download failed"); return }
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hex.caseInsensitiveCompare(i.sha256) == .orderedSame else { busy = UpdateCfg.t("받은 파일이 맞지 않습니다", "Download didn't verify"); return }
        busy = UpdateCfg.t("설치 중…", "Installing…")
        let current = Bundle.main.bundleURL
        let err: String? = await Task.detached { Updater.swap(zip: data, into: current) }.value
        if let err { busy = err; return }
        busy = nil
        guard relaunch else { return }
        let cfg = NSWorkspace.OpenConfiguration(); cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: current, configuration: cfg) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }
    }

    /// 실패하면 화면에 낼 한 줄, 성공하면 nil. 실패하면 옛 앱을 제자리에 되돌린다
    nonisolated private static func swap(zip data: Data, into current: URL) -> String? {
        let fail = UpdateCfg.t("설치하지 못했습니다", "Couldn't install")
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("\(UpdateCfg.app)-update", isDirectory: true)
        try? fm.removeItem(at: dir); try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("app.zip")
        guard (try? data.write(to: zip)) != nil else { return fail }
        let x = dir.appendingPathComponent("x")
        let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, x.path]
        guard (try? unzip.run()) != nil else { return fail }
        unzip.waitUntilExit()
        guard let name = (try? fm.contentsOfDirectory(atPath: x.path))?.first(where: { $0.hasSuffix(".app") }) else { return fail }
        let newApp = x.appendingPathComponent(name)
        let backup = current.deletingLastPathComponent().appendingPathComponent(".\(current.lastPathComponent).old")
        try? fm.removeItem(at: backup)
        do { try fm.moveItem(at: current, to: backup) } catch { return fail }
        do { try fm.moveItem(at: newApp, to: current) } catch { try? fm.moveItem(at: backup, to: current); return fail }
        try? fm.removeItem(at: backup); try? fm.removeItem(at: dir)
        // 독·Finder 가 옛 아이콘을 붙들지 않게 — 시각을 바꾸고 LaunchServices 에 다시 알린다
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: current.path)
        let ls = Process()
        ls.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        ls.arguments = ["-f", current.path]; try? ls.run(); ls.waitUntilExit()
        return nil
    }

    /// `<실행파일> --updatetest` — 창 없이 확인·설치만 하고 끝낸다 (업데이트 시험 스크립트가 쓴다)
    static func runTestIfAsked() {
        guard CommandLine.arguments.contains("--updatetest") else { return }
        Task { @MainActor in
            let u = Updater.shared; await u.check()
            guard u.available != nil else { print("새 판 없음 (지금 \(installedCode))"); exit(1) }
            print("새 판 v\(u.available!.name) (\(u.available!.code)) 받는 중")
            await u.install(relaunch: false)
            print(u.busy.map { "✗ \($0)" } ?? "교체함"); exit(u.busy == nil ? 0 : 1)
        }
        RunLoop.main.run()
    }
}

import SwiftUI

/// 설정 창의 판 한 줄 — 설치된 판 · Check for Updates · 새 판이 있으면 Install
struct UpdateRow: View {
    @ObservedObject var u = Updater.shared
    var body: some View {
        LabeledContent(UpdateCfg.t("버전", "Version")) {
            HStack(spacing: 8) {
                Text("v\(Updater.installedName)").foregroundStyle(.secondary).textSelection(.enabled)
                if let n = u.busy ?? u.note { Text(n).foregroundStyle(.secondary) }
                if let i = u.available {
                    Button(UpdateCfg.t("v\(i.name) 설치", "Install v\(i.name)")) { Task { await u.install() } }
                        .disabled(u.busy?.hasSuffix("…") == true)
                } else {
                    Button(UpdateCfg.t("업데이트 확인", "Check for Updates")) { Task { await u.check(manual: true) } }
                }
            }
        }
    }
}
