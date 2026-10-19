// CI only (see scripts/review_shots/add_target.rb). Shows the real app screens,
// one at a time, inside the app process, then waits while the workflow takes a
// Simulator screenshot. StoreKit uses the repo's AccessKeyboard.storekit file.
import StoreKit
import StoreKitTest
import SwiftUI
import UIKit
import XCTest
@testable import AccessKeyboard

@MainActor
final class ReviewShotsTests: XCTestCase {
    private var shotDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOT_DIR"] ?? NSTemporaryDirectory())
    }

    private var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    private func window() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first ?? UIWindow(windowScene: scene)
        window.makeKeyAndVisible()
        return window
    }

    private func show<V: View>(_ view: V, manager: SubscriptionManager) throws -> UIWindow {
        let window = try window()
        window.rootViewController = UIHostingController(rootView: view.environmentObject(manager))
        return window
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Writes ready-<name>, waits for the workflow to write done-<name>.
    private func capture(_ name: String, window: UIWindow) async {
        await pause(2.5)
        let full = "\(device)-\(name)"
        // Fallback in-process render (no keyboard window, no status bar).
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: shotDir.appendingPathComponent("render-\(full).png"))
        FileManager.default.createFile(atPath: shotDir.appendingPathComponent("ready-\(full)").path, contents: Data())
        let done = shotDir.appendingPathComponent("done-\(full)").path
        for _ in 0..<60 where !FileManager.default.fileExists(atPath: done) {
            await pause(0.5)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = full
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func typeSample(in window: UIWindow, _ text: String) {
        func find(_ view: UIView) -> UITextView? {
            if let tv = view as? UITextView { return tv }
            for sub in view.subviews { if let hit = find(sub) { return hit } }
            return nil
        }
        if let textView = find(window) {
            textView.becomeFirstResponder()
            textView.insertText(text)
        }
    }

    func testCaptureScreens() async throws {
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let storekitPath = ProcessInfo.processInfo.environment["STOREKIT_PATH"] ?? ""
        let storekit = try XCTUnwrap(
            Bundle.main.url(forResource: "AccessKeyboard", withExtension: "storekit")
                ?? (storekitPath.isEmpty ? nil : URL(fileURLWithPath: storekitPath))
        )
        let session = try SKTestSession(contentsOf: storekit)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()

        let manager = SubscriptionManager()

        // Pro screen, as reached from the app's sidebar.
        var window = try show(NavigationStack { PaywallView().navigationTitle("Pro") }, manager: manager)
        await manager.refresh()
        for _ in 0..<60 where manager.products.count < 3 {
            await pause(0.5)
        }
        XCTAssertEqual(manager.products.count, 3, "StoreKit test products did not load")
        await capture("paywall", window: window)

        // The app as it opens, with the keyboard on the Type screen.
        window = try show(RootView(), manager: manager)
        await pause(1.5)
        typeSample(in: window, "Thank you for the lovely afternoon. See you on Friday at the library")
        await capture("type", window: window)

        window = try show(NavigationStack { TypingScreen().navigationTitle("Type") }, manager: manager)
        await pause(1.5)
        typeSample(in: window, "I would like to book a meeting for next week")
        await capture("type-only", window: window)

        window = try show(NavigationStack { SettingsView().navigationTitle("Settings") }, manager: manager)
        await capture("settings", window: window)

        window = try show(NavigationStack { SetupView().navigationTitle("Enable system-wide") }, manager: manager)
        await capture("setup", window: window)
    }
}
