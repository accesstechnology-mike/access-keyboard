// CI only (see scripts/review_shots/add_target.rb). Shows the real app screens,
// one at a time, inside the app process, then waits while the workflow takes a
// Simulator screenshot. StoreKit uses the repo's AccessKeyboard.storekit file,
// selected on the ReviewShots scheme TestAction (and LaunchAction).
import StoreKit
import StoreKitTest
import SwiftUI
import UIKit
import XCTest
import AccessKeyboardCore
@testable import AccessKeyboard

@MainActor
final class ReviewShotsTests: XCTestCase {
    /// Kept alive for the whole test so StoreKit Testing stays attached.
    private var storeKitSession: SKTestSession?

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

    /// Product.products with a hard timeout. Without the scheme StoreKit config
    /// it can hang forever on Sandbox; never let that stall CI.
    private func productsWithin(_ seconds: Double) async throws -> [Product] {
        try await withThrowingTaskGroup(of: [Product].self) { group in
            group.addTask {
                try await Product.products(for: SubscriptionConfig.productIDs)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// Loads products until all three catalogue IDs are present, or gives up.
    /// Re-queries Product.products each pass so a partial Sandbox reply can recover.
    private func waitForThreeProducts(manager: SubscriptionManager) async -> [Product] {
        for attempt in 0..<24 {
            do {
                let lastDirect = try await productsWithin(12)
                print(
                    "REVIEWSHOTS direct products attempt \(attempt):",
                    lastDirect.map { "\($0.id) \($0.displayPrice) \($0.type.rawValue)" }
                )
            } catch {
                print("REVIEWSHOTS direct products attempt \(attempt) error:", error)
            }
            // refresh() also calls Product.products; bound it the same way.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await manager.refresh() }
                group.addTask { await self.pause(15) }
                _ = await group.next()
                group.cancelAll()
            }
            let ids = Set(manager.products.map(\.id))
            if SubscriptionConfig.productIDs.isSubset(of: ids) {
                return manager.products
            }
            await pause(0.75)
        }
        return manager.products
    }

    func testCaptureScreens() async throws {
        try FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let storekitPath = ProcessInfo.processInfo.environment["STOREKIT_PATH"] ?? ""
        let storekit = try XCTUnwrap(
            Bundle.main.url(forResource: "AccessKeyboard", withExtension: "storekit")
                ?? (storekitPath.isEmpty ? nil : URL(fileURLWithPath: storekitPath))
        )
        print("REVIEWSHOTS storekit", storekit.path)

        // Scheme TestAction already selects AccessKeyboard.storekit. SKTestSession
        // on iOS 26.3–26.5 often fails to save that config (SKInternalErrorDomain
        // Code=3); calling reset/clear/storefront then is a no-op that logs noise.
        // Still open a session with disableDialogs when we can, and keep it alive.
        do {
            let session = try SKTestSession(contentsOf: storekit)
            session.disableDialogs = true
            storeKitSession = session
            print("REVIEWSHOTS SKTestSession opened")
        } catch {
            print("REVIEWSHOTS SKTestSession open failed (scheme StoreKit still applies):", error)
        }

        let manager = SubscriptionManager()

        // Pro screen, as reached from the app's sidebar.
        var window = try show(NavigationStack { PaywallView().navigationTitle("Pro") }, manager: manager)
        let loaded = await waitForThreeProducts(manager: manager)
        let loadedIDs = Set(loaded.map(\.id))
        XCTAssertTrue(
            loadedIDs.contains(SubscriptionConfig.monthlyProductID),
            "Monthly missing. Got: \(loaded.map(\.id))"
        )
        XCTAssertTrue(
            loadedIDs.contains(SubscriptionConfig.yearlyProductID),
            "Yearly missing. Got: \(loaded.map(\.id))"
        )
        XCTAssertTrue(
            loadedIDs.contains(SubscriptionConfig.lifetimeProductID),
            "Lifetime missing. Got: \(loaded.map(\.id))"
        )
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
