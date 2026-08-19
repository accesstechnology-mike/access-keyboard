import SwiftUI
import UIKit
import AccessKeyboardCore

struct TypingViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TypingViewController {
        TypingViewController()
    }

    func updateUIViewController(_ uiViewController: TypingViewController, context: Context) {}
}

final class TypingTextView: UITextView {
    var locksFirstResponder = true

    override func resignFirstResponder() -> Bool {
        if locksFirstResponder {
            return false
        }
        return super.resignFirstResponder()
    }
}

final class TypingViewController: UIViewController, KeyboardHost {
    private let textView: TypingTextView
    private let keyboardView = KeyboardView()
    private let document: TextViewDocument
    private var keyboardHeightConstraint: NSLayoutConstraint?

    init() {
        let editor = TypingTextView()
        textView = editor
        document = TextViewDocument(textView: editor)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.inputView = UIView(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.accessibilityLabel = "Document"

        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.engine.document = document
        keyboardView.engine.host = self
        keyboardView.engine.needsInputModeSwitchKey = true
        keyboardView.engine.traits = KeyboardTraits.from(textView)
        keyboardView.engine.fixClient = URLSessionFixClient.fromBundle()
        keyboardView.engine.networkAllowed = true

        let caption = UILabel()
        caption.text = "This is the same keyboard you’ll enable for other apps. Tap below and type."
        caption.font = .preferredFont(forTextStyle: .subheadline)
        caption.textColor = .secondaryLabel
        caption.numberOfLines = 0
        caption.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(caption)
        view.addSubview(textView)
        view.addSubview(keyboardView)

        let height = keyboardView.heightAnchor.constraint(equalToConstant: 320)
        keyboardHeightConstraint = height

        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            caption.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),

            textView.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: keyboardView.topAnchor, constant: -8),

            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.locksFirstResponder = true
        textView.becomeFirstResponder()
        keyboardView.engine.documentDidChange()
    }

    override func viewWillDisappear(_ animated: Bool) {
        textView.locksFirstResponder = false
        super.viewWillDisappear(animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        keyboardView.extraBottomInset = view.safeAreaInsets.bottom
        keyboardHeightConstraint?.constant = keyboardView.preferredHeight
    }

    func advanceToNextInputMode() {
        let alert = UIAlertController(
            title: "Next keyboard",
            message: "In other apps, this globe key switches keyboards. Enable access: keyboard in Settings to use it system-wide.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func dismissKeyboard() {}

    var needsInputModeSwitchKey: Bool { true }
}
