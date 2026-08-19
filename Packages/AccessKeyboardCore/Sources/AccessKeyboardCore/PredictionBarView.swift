import UIKit

final class PredictionBarView: UIView {
    var onSelect: ((Prediction) -> Void)?

    private var predictions: [Prediction] = []
    private let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
    private let separators = [UIView(), UIView()]

    override init(frame: CGRect) {
        super.init(frame: frame)
        buttons.enumerated().forEach { index, button in
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            button.tag = index
            button.isAccessibilityElement = true
            addSubview(button)
        }
        separators.forEach { separator in
            addSubview(separator)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(predictions: [Prediction], appearance: KeyboardAppearance, fontSize: CGFloat) {
        self.predictions = predictions
        for (index, button) in buttons.enumerated() {
            if predictions.indices.contains(index) {
                let item = predictions[index]
                button.setTitle(item.displayText, for: .normal)
                button.isEnabled = true
                button.accessibilityLabel = item.isVerbatim
                    ? "Use as typed, \(item.insertion)"
                    : "Predicted word, \(item.insertion)"
                button.accessibilityTraits = .button
                let weight: UIFont.Weight = item.isVerbatim ? .regular : .medium
                button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: weight)
                button.setTitleColor(appearance.textColor, for: .normal)
                button.alpha = 1
            } else {
                button.setTitle("", for: .normal)
                button.isEnabled = false
                button.accessibilityLabel = "No prediction"
                button.alpha = 0.35
            }
        }
        let line = appearance.secondaryTextColor.withAlphaComponent(0.45)
        separators.forEach { $0.backgroundColor = line }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let slotWidth = bounds.width / 3
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * slotWidth, y: 0, width: slotWidth, height: bounds.height)
        }
        let separatorWidth: CGFloat = 1 / max(traitCollection.displayScale, 1)
        for (index, separator) in separators.enumerated() {
            let x = slotWidth * CGFloat(index + 1)
            separator.frame = CGRect(x: x, y: bounds.height * 0.22, width: separatorWidth, height: bounds.height * 0.56)
        }
    }

    @objc private func tap(_ sender: UIButton) {
        guard predictions.indices.contains(sender.tag) else { return }
        onSelect?(predictions[sender.tag])
    }
}
