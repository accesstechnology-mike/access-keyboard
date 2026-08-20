import UIKit
import AccessKeyboardCore

final class KeyboardViewController: UIInputViewController, KeyboardHost {
    private let keyboard = KeyboardView()
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
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
        configureFixClient()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard.engine.document = DocumentProxyAdapter(textDocumentProxy)
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        KeyboardPreferences.extensionHasFullAccess = hasFullAccess
        configureFixClient()
        keyboard.applyCurrentPreferences()
        keyboard.engine.documentDidChange()
        updateHeight()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        KeyboardPreferences.extensionHasFullAccess = hasFullAccess
        configureFixClient()
        updateHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboard.engine.needsInputModeSwitchKey = needsInputModeSwitchKey
        updateHeight()
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
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

    private func updateHeight() {
        keyboard.extraBottomInset = view.safeAreaInsets.bottom
        let height = keyboard.preferredHeight
        if let heightConstraint {
            if abs(heightConstraint.constant - height) > 0.5 {
                heightConstraint.constant = height
            }
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    /// iOS can report `hasFullAccess` as false on the first appearance even after
    /// the user enabled it. Still attach a client and allow the request; the
    /// system will reject the connection if Open Access is actually off.
    private func configureFixClient() {
        if let client = URLSessionFixClient.fromBundle() {
            URLSessionFixClient.persist(client)
            keyboard.engine.fixClient = client
        } else {
            keyboard.engine.fixClient = URLSessionFixClient.fromAppGroup()
        }
        keyboard.engine.networkAllowed = keyboard.engine.fixClient != nil
    }
}
