import UIKit
import os
import AccessKeyboardCore

final class KeyboardViewController: UIInputViewController, KeyboardHost {
    private var keyboard: KeyboardView!
    private var heightConstraint: NSLayoutConstraint?

    /// Subsystem/category so these lines are easy to filter in Console.app and
    /// `log` (see CRASH_LOGS.md). Use `subsystem:app.access.keyboard`.
    private static let log = Logger(subsystem: "app.access.keyboard", category: "extension")

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.log.notice("viewDidLoad fullAccess=\(self.hasFullAccess, privacy: .public) mem=\(Self.residentMemoryMB(), privacy: .public)MB")
        view.backgroundColor = .clear
        // Create the board only once we know Full Access. Without it the
        // extension must not open the shared App Group.
        let board = KeyboardView(sharesPredictionMemory: hasFullAccess)
        keyboard = board
        board.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(board)
        NSLayoutConstraint.activate([
            board.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            board.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            board.topAnchor.constraint(equalTo: view.topAnchor),
            board.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        board.onPreferredHeightChange = { [weak self] in
            self?.updateHeight()
        }
        board.engine.document = DocumentProxyAdapter(textDocumentProxy)
        board.engine.host = self
        board.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        board.engine.fixClient = URLSessionFixClient.fromBundle()
        applyAccess()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard.engine.document = DocumentProxyAdapter(textDocumentProxy)
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        applyAccess()
        keyboard.engine.documentDidChange()
        updateHeight()
    }

    /// Full Access gates the shared prediction memory and the Fix network call.
    /// Typing does not use either, so a denied switch leaves the keys working.
    private func applyAccess() {
        keyboard.engine.sharedPreferencesAvailable = hasFullAccess
        keyboard.engine.networkAllowed = hasFullAccess
        keyboard.setSharesPredictionMemory(hasFullAccess)
        if hasFullAccess {
            KeyboardPreferences.extensionHasFullAccess = true
        }
        keyboard.applyCurrentPreferences()
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
