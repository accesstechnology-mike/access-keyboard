import UIKit

/// Shown in the keyboard extension when the subscription record is missing or expired.
/// The globe key stays so the user can leave for another keyboard.
final class KeyboardLockedPanel: UIView {
    var onOpenApp: (() -> Void)?
    var onNextKeyboard: (() -> Void)?

    private let messageLabel = UILabel()
    private let openAppButton = UIButton(type: .system)
    private let nextKeyboardButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.isAccessibilityElement = true
        messageLabel.accessibilityIdentifier = "keyboard.lock.message"
        addSubview(messageLabel)

        openAppButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openAppButton.titleLabel?.adjustsFontForContentSizeCategory = true
        openAppButton.titleLabel?.numberOfLines = 0
        openAppButton.titleLabel?.textAlignment = .center
        openAppButton.setTitle(KeyboardLock.openAppButtonTitle, for: .normal)
        openAppButton.accessibilityLabel = KeyboardLock.openAppButtonTitle
        openAppButton.accessibilityIdentifier = "keyboard.lock.openApp"
        openAppButton.accessibilityTraits = .button
        openAppButton.layer.cornerRadius = 10
        openAppButton.addTarget(self, action: #selector(openApp), for: .touchUpInside)
        addSubview(openAppButton)

        nextKeyboardButton.setImage(UIImage(systemName: "globe"), for: .normal)
        nextKeyboardButton.accessibilityLabel = KeyboardLock.nextKeyboardTitle
        nextKeyboardButton.accessibilityIdentifier = "keyboard.lock.nextKeyboard"
        nextKeyboardButton.accessibilityTraits = .button
        nextKeyboardButton.addTarget(self, action: #selector(nextKeyboard), for: .touchUpInside)
        addSubview(nextKeyboardButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(message: String, appearance: KeyboardAppearance) {
        backgroundColor = appearance.backgroundColor
        messageLabel.text = message
        messageLabel.textColor = appearance.textColor
        messageLabel.accessibilityLabel = message
        openAppButton.backgroundColor = appearance.primaryFill
        openAppButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        nextKeyboardButton.tintColor = appearance.modifierTextColor
        nextKeyboardButton.backgroundColor = appearance.modifierFill
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin: CGFloat = 16
        let width = max(0, bounds.width - margin * 2)
        let messageHeight = messageLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        messageLabel.frame = CGRect(x: margin, y: margin, width: width, height: messageHeight)
        let buttonY = messageLabel.frame.maxY + 12
        let openHeight = max(44, openAppButton.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height + 12)
        openAppButton.frame = CGRect(x: margin, y: buttonY, width: width, height: openHeight)
        let globeSize: CGFloat = 44
        nextKeyboardButton.frame = CGRect(
            x: margin,
            y: bounds.height - globeSize - margin,
            width: globeSize,
            height: globeSize
        )
        nextKeyboardButton.layer.cornerRadius = 8
    }

    @objc private func openApp() {
        onOpenApp?()
    }

    @objc private func nextKeyboard() {
        onNextKeyboard?()
    }
}
