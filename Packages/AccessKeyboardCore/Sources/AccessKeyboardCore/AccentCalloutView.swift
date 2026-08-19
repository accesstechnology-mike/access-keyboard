import UIKit

final class AccentCalloutView: UIView {
    var onSelect: ((String) -> Void)?

    private var options: [String] = []
    private var buttons: [UIButton] = []
    private var appearance: KeyboardAppearance
    private var selectedIndex: Int = 0

    init(appearance: KeyboardAppearance) {
        self.appearance = appearance
        super.init(frame: .zero)
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
        backgroundColor = appearance.calloutFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        options: [String],
        from keyFrame: CGRect,
        in parent: UIView,
        appearance: KeyboardAppearance,
        letterFill: UIColor? = nil
    ) {
        self.options = options
        self.appearance = appearance
        let fill = letterFill ?? appearance.calloutFill
        let text = letterFill.map { BethColorMap.foreground(for: $0) } ?? appearance.textColor
        backgroundColor = fill
        buttons.forEach { $0.removeFromSuperview() }
        buttons = options.enumerated().map { index, value in
            let button = UIButton(type: .system)
            button.setTitle(value, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 22, weight: .regular)
            button.setTitleColor(text, for: .normal)
            button.tag = index
            button.addTarget(self, action: #selector(selectOption(_:)), for: .touchUpInside)
            addSubview(button)
            return button
        }
        selectedIndex = 0
        highlightSelection()

        let width = CGFloat(options.count) * 44
        let height: CGFloat = 52
        var x = keyFrame.midX - width / 2
        x = max(8, min(x, parent.bounds.width - width - 8))
        let y = max(8, keyFrame.minY - height - 8)
        frame = CGRect(x: x, y: y, width: width, height: height)
        parent.addSubview(self)
    }

    func updateSelection(at point: CGPoint) {
        let local = convert(point, from: superview)
        guard let index = buttons.firstIndex(where: { $0.frame.insetBy(dx: -4, dy: -20).contains(local) }) else {
            return
        }
        selectedIndex = index
        highlightSelection()
    }

    func commit() {
        guard options.indices.contains(selectedIndex) else { return }
        onSelect?(options[selectedIndex])
        removeFromSuperview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(max(buttons.count, 1))
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
    }

    @objc private func selectOption(_ sender: UIButton) {
        selectedIndex = sender.tag
        commit()
    }

    private func highlightSelection() {
        for (index, button) in buttons.enumerated() {
            button.backgroundColor = index == selectedIndex ? appearance.primaryFill.withAlphaComponent(0.22) : .clear
            button.layer.cornerRadius = 8
        }
    }
}
