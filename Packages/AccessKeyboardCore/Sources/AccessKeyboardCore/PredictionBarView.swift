import UIKit

final class PredictionBarView: UIView {
    var onSelect: ((Prediction) -> Void)?
    var onFix: (() -> Void)?

    private var predictions: [Prediction] = []
    private let fixButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let buttons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
    private let separators = [UIView(), UIView(), UIView()]

    override init(frame: CGRect) {
        super.init(frame: frame)
        fixButton.addTarget(self, action: #selector(tapFix), for: .touchUpInside)
        fixButton.isAccessibilityElement = true
        fixButton.clipsToBounds = true
        addSubview(fixButton)
        spinner.hidesWhenStopped = true
        spinner.isUserInteractionEnabled = false
        addSubview(spinner)
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

    func update(
        predictions: [Prediction],
        fixStatus: FixStatus,
        appearance: KeyboardAppearance,
        fontSize: CGFloat
    ) {
        self.predictions = predictions
        let running = fixStatus == .running
        fixButton.setTitle(running ? "" : "Fix", for: .normal)
        fixButton.isEnabled = !running
        fixButton.backgroundColor = appearance.primaryFill
        fixButton.setTitleColor(appearance.primaryTextColor, for: .normal)
        fixButton.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .semibold)
        fixButton.accessibilityLabel = running
            ? "Fix in progress"
            : (fixStatus == .failed ? "Fix failed, try again" : "Fix typing errors")
        fixButton.accessibilityTraits = .button
        if running {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        spinner.color = appearance.primaryTextColor

        for (index, button) in buttons.enumerated() {
            if predictions.indices.contains(index) {
                let item = predictions[index]
                button.setTitle(item.displayText, for: .normal)
                button.isEnabled = !running
                button.accessibilityLabel = item.isVerbatim
                    ? "Use as typed, \(item.insertion)"
                    : "Predicted word, \(item.insertion)"
                button.accessibilityTraits = .button
                let weight: UIFont.Weight = item.isVerbatim ? .regular : .medium
                button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: weight)
                button.setTitleColor(appearance.textColor, for: .normal)
                button.alpha = running ? 0.45 : 1
            } else {
                button.setTitle("", for: .normal)
                button.isEnabled = false
                button.accessibilityLabel = "No prediction"
                button.alpha = 0.35
            }
        }
        let line = appearance.secondaryTextColor.withAlphaComponent(0.45)
        separators.forEach { $0.backgroundColor = line }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fixWidth = min(92, max(72, bounds.width * 0.14))
        let height = bounds.height
        fixButton.frame = CGRect(x: 0, y: 2, width: fixWidth, height: height - 4)
        fixButton.layer.cornerRadius = min(8, (height - 4) / 4)
        spinner.center = fixButton.center

        let restMinX = fixButton.frame.maxX
        let restWidth = max(0, bounds.width - restMinX)
        let slotWidth = restWidth / 3
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: restMinX + CGFloat(index) * slotWidth, y: 0, width: slotWidth, height: height)
        }
        let separatorWidth: CGFloat = 1 / max(traitCollection.displayScale, 1)
        separators[0].frame = CGRect(
            x: restMinX,
            y: height * 0.22,
            width: separatorWidth,
            height: height * 0.56
        )
        for index in 0..<2 {
            let x = restMinX + slotWidth * CGFloat(index + 1)
            separators[index + 1].frame = CGRect(x: x, y: height * 0.22, width: separatorWidth, height: height * 0.56)
        }
    }

    @objc private func tap(_ sender: UIButton) {
        guard predictions.indices.contains(sender.tag) else { return }
        onSelect?(predictions[sender.tag])
    }

    @objc private func tapFix() {
        onFix?()
    }
}
