import UIKit
import AccessKeyboardCore

final class KeyboardViewController: UIInputViewController, KeyboardHost {
    private var keyboard: KeyboardView!
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        DiagnosticsLog.memory("viewDidLoad fullAccess=\(hasFullAccess)", category: "extension")
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
        board.onOpenContainingApp = { [weak self] in
            self?.openContainingApp()
        }
        board.engine.document = DocumentProxyAdapter(textDocumentProxy)
        board.engine.host = self
        board.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        board.engine.fixClient = URLSessionFixClient.fromBundle()
        applyAccess()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DiagnosticsLog.memory("viewWillAppear", category: "extension")
        keyboard.engine.document = DocumentProxyAdapter(textDocumentProxy)
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        applyAccess()
        keyboard.engine.documentDidChange()
        updateHeight()
    }

    /// Opens the containing app on the paywall. Tries the extension context first,
    /// then the responder chain. The keyboard never presents a purchase sheet.
    private func openContainingApp() {
        guard let url = SubscriptionConfig.paywallURL else { return }
        guard let context = extensionContext else {
            openURLThroughResponderChain(url)
            return
        }
        context.open(url) { [weak self] opened in
            guard !opened else { return }
            DispatchQueue.main.async {
                self?.openURLThroughResponderChain(url)
            }
        }
    }

    private func openURLThroughResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    /// Full Access lets the extension read the subscription record, shared settings,
    /// and the Fix network call. Without it the board stays on the locked panel.
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
        DiagnosticsLog.memory("memory warning — releasing transient resources", category: "extension")
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
}
