import AppKit

@MainActor enum AppInterface {
    static func text(_ value: String, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: secondary ? NSFont.smallSystemFontSize : NSFont.systemFontSize)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.isSelectable = true
        return label
    }
    static func column(spacing: CGFloat = 12) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        return stack
    }
    static func fill(_ parent: NSStackView, _ child: NSView) {
        parent.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
    }
    static func section(_ title: String, views: [NSView]) -> NSStackView {
        let stack = column(spacing: 10)
        let heading = text(title); heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        fill(stack, heading)
        for view in views { fill(stack, view) }
        return stack
    }
    static func row(_ title: String, control: NSView) -> NSStackView {
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .firstBaseline; row.spacing = 12
        let label = text(title); label.alignment = .right; label.widthAnchor.constraint(equalToConstant: 88).isActive = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setAccessibilityLabel(title)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(label); row.addArrangedSubview(control)
        return row
    }
    static func tab(_ title: String, body: NSStackView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title); item.label = title
        let view = NSView(); view.addSubview(body); body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            body.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24)
        ])
        item.view = view; return item
    }
    static func separator() -> NSBox {
        let line = NSBox(); line.boxType = .separator; return line
    }
    static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action); button.bezelStyle = .rounded
        return button
    }
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
