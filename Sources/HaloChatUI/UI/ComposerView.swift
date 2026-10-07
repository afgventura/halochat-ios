#if canImport(UIKit)
import UIKit

/// Attach button, growing text view (max 4096 chars) and send button.
final class ComposerView: UIView, UITextViewDelegate {
    var onSend: ((String) -> Void)?
    var onAttach: ((UIView) -> Void)?

    let textView = UITextView()
    private let placeholder = UILabel()
    private let attachButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let fieldContainer = UIView()
    private let topBorder = UIView()
    private var textHeight: NSLayoutConstraint?

    private static let minHeight: CGFloat = 36
    private static let maxHeight: CGFloat = 120

    var isEnabled = true {
        didSet {
            textView.isEditable = isEnabled
            attachButton.isEnabled = isEnabled
            updateSendState()
            alpha = isEnabled ? 1 : 0.6
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func build() {
        let symbol = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        attachButton.setImage(UIImage(systemName: "paperclip", withConfiguration: symbol), for: .normal)
        attachButton.accessibilityLabel = L10n.accessibilityAttach
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        sendButton.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: symbol), for: .normal)
        sendButton.accessibilityLabel = L10n.accessibilitySend
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        fieldContainer.layer.cornerRadius = 18
        fieldContainer.layer.borderWidth = 1
        fieldContainer.backgroundColor = .clear

        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.delegate = self

        placeholder.text = L10n.composerPlaceholder
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .placeholderText
        placeholder.isAccessibilityElement = false
        textView.accessibilityLabel = L10n.composerPlaceholder

        for view in [topBorder, attachButton, fieldContainer, sendButton, textView, placeholder] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(topBorder)
        addSubview(attachButton)
        addSubview(fieldContainer)
        addSubview(sendButton)
        fieldContainer.addSubview(textView)
        fieldContainer.addSubview(placeholder)

        let height = textView.heightAnchor.constraint(equalToConstant: Self.minHeight)
        textHeight = height
        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            attachButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            attachButton.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 40),
            attachButton.heightAnchor.constraint(equalToConstant: 36),

            fieldContainer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            fieldContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            fieldContainer.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 2),
            fieldContainer.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -2),

            sendButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            sendButton.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            textView.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            textView.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 4),
            textView.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -4),
            height,

            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 11),
            placeholder.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
        ])
        updateSendState()
    }

    func apply(colors: HaloChatColor) {
        backgroundColor = colors.sendContainerBackgroundColor
        topBorder.backgroundColor = colors.fieldChatBorderColor
        fieldContainer.layer.borderColor = colors.fieldChatBorderColor.resolvedColor(with: traitCollection).cgColor
        attachButton.tintColor = colors.sendContainerColor
        sendButton.tintColor = colors.sendContainerColor
        textView.tintColor = colors.sendContainerColor
    }

    func setText(_ text: String) {
        textView.text = String(text.prefix(ComposerRules.maxCharacters))
        textViewDidChange(textView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateHeight()
    }

    private func updateHeight() {
        guard textView.bounds.width > 0 else { return }
        let fitting = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
        let clamped = min(max(Self.minHeight, fitting), Self.maxHeight)
        textView.isScrollEnabled = fitting > Self.maxHeight
        if textHeight?.constant != clamped { textHeight?.constant = clamped }
    }

    private func updateSendState() {
        sendButton.isEnabled = isEnabled && ComposerRules.sendableText(textView.text ?? "") != nil
        placeholder.isHidden = !(textView.text ?? "").isEmpty
    }

    func textViewDidChange(_ textView: UITextView) {
        updateSendState()
        updateHeight()
    }

    /// Caps the text at 4096 characters, truncating a paste that would exceed it.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text as NSString? ?? ""
        let remaining = ComposerRules.maxCharacters - (current.length - range.length)
        if (text as NSString).length <= remaining { return true }
        guard remaining > 0 else { return false }
        let truncated = (text as NSString).substring(to: remaining)
        textView.text = current.replacingCharacters(in: range, with: truncated)
        textViewDidChange(textView)
        return false
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection), let color = topBorder.backgroundColor {
            fieldContainer.layer.borderColor = color.resolvedColor(with: traitCollection).cgColor
        }
    }

    @objc private func attachTapped() {
        onAttach?(attachButton)
    }

    @objc private func sendTapped() {
        guard let text = ComposerRules.sendableText(textView.text ?? "") else { return }
        textView.text = ""
        textViewDidChange(textView)
        onSend?(text)
    }
}
#endif
