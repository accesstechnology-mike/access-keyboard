import UIKit
import os
import AccessKeyboardCore

final class KeyboardViewController: UIInputViewController, KeyboardHost {
    private let keyboard = KeyboardView()
    private var heightConstraint: NSLayoutConstraint?

    /// Subsystem/category so these lines are easy to filter in Console.app and
    /// `log` (see CRASH_LOGS.md). Use `subsystem:app.access.keyboard`.
    private static let log = Logger(subsystem: "app.access.keyboard", category: "extension")

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.log.notice("viewDidLoad fullAccess=\(self.hasFullAccess, privacy: .public) mem=\(Self.residentMemoryMB(), privacy: .public)MB")
        view.backgroundColor = .clear
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        keyboard.engine.document = DocumentProxyAdapter(textDocumentProxy)
        keyboard.engine.host = self
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        keyboard.engine.fixClient = URLSessionFixClient.fromBundle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard.engine.document = DocumentProxyAdapter(textDocumentProxy)
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        keyboard.engine.networkAllowed = hasFullAccess
        KeyboardPreferences.extensionHasFullAccess = hasFullAccess
        keyboard.applyCurrentPreferences()
        keyboard.engine.documentDidChange()
        updateHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        if let textInput {
            keyboard.engine.traits = .from(textInput)
        }
        keyboard.engine.documentDidChange()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateHeight()
        })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Keyboard extensions are memory-limited; a warning here often precedes
        // a jetsam kill. Log the footprint (surfaces in device logs / Console)
        // and shed anything transient so a long session is less likely to crash.
        Self.log.error("memory warning mem=\(Self.residentMemoryMB(), privacy: .public)MB — releasing transient resources")
        keyboard.releaseTransientResources()
    }

    private func updateHeight() {
        keyboard.extraBottomInset = view.safeAreaInsets.bottom
        let height = keyboard.preferredHeight
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    /// Resident memory in MB, for crash/leak triage in the device logs. A steady
    /// climb across a long session points at a leak; a spike near the extension
    /// limit (~40-60 MB) that precedes a disappearance is a jetsam kill.
    private static func residentMemoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint) / (1024 * 1024)
    }
}
