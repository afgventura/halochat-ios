#if canImport(UIKit)
import UIKit

/// What one bubble shows (server message or pending item).
struct BubbleModel {
    enum Media {
        /// A server image: thumbnail through a fresh media URL, cached by message id.
        case remoteImage(messageId: String)
        /// A not-yet-sent image: decoded from its local bytes.
        case localImage(Data)
        case file(name: String, mimeType: String?)
    }

    let rowId: String
    let isMine: Bool
    let text: String?
    let time: Date
    let tick: MessageTick?
    let media: Media?
    /// Shown above the first bubble of a business-side run (avatar ENABLED).
    let senderName: String?
    /// Reserve the avatar column (avatar ENABLED, business side).
    let showsAvatarColumn: Bool
    let showsRetryHint: Bool
}

enum ChatFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = false
        return formatter
    }()

    static func label(_ label: ChatDateLabel) -> String {
        switch label {
        case .today: return L10n.dateToday
        case .yesterday: return L10n.dateYesterday
        case let .date(date): return day.string(from: date)
        }
    }
}

/// A rounded label used for date separators and system messages.
final class PillLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let rect = super.textRect(forBounds: bounds.inset(by: insets), limitedToNumberOfLines: numberOfLines)
        return rect.inset(by: UIEdgeInsets(top: -insets.top, left: -insets.left, bottom: -insets.bottom, right: -insets.right))
    }
}

final class DateSeparatorCell: UITableViewCell {
    static let reuseId = "HaloChatDateCell"
    private let pill = PillLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        pill.font = .preferredFont(forTextStyle: .caption1)
        pill.adjustsFontForContentSizeCategory = true
        pill.textAlignment = .center
        pill.layer.cornerRadius = 10
        pill.layer.masksToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            pill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            pill.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        ])
        pill.accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ label: ChatDateLabel, colors: HaloChatColor) {
        pill.text = ChatFormatters.label(label)
        pill.textColor = colors.timeLabelTextColor
        pill.backgroundColor = colors.timeBackgroundColor
    }
}

final class SystemMessageCell: UITableViewCell {
    static let reuseId = "HaloChatSystemCell"
    private let pill = PillLabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        pill.font = .preferredFont(forTextStyle: .footnote)
        pill.adjustsFontForContentSizeCategory = true
        pill.numberOfLines = 0
        pill.textAlignment = .center
        pill.layer.cornerRadius = 12
        pill.layer.borderWidth = 1
        pill.layer.masksToBounds = true
        pill.insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        pill.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            pill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            pill.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pill.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.85),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(text: String, colors: HaloChatColor) {
        pill.text = text
        pill.textColor = colors.systemEventTextColor
        pill.layer.borderColor = colors.systemEventTextColor.withAlphaComponent(0.35).resolvedColor(with: traitCollection).cgColor
        pill.backgroundColor = colors.timeBackgroundColor
    }
}

/// Sending (clock), failed (exclamation), sent/delivered (one check), read (two checks).
final class StatusTickView: UIView {
    private let first = UIImageView()
    private let second = UIImageView()
    private var widthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        for view in [first, second] {
            view.preferredSymbolConfiguration = config
            view.contentMode = .scaleAspectFit
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.centerYAnchor.constraint(equalTo: centerYAnchor),
                view.widthAnchor.constraint(equalToConstant: 12),
                view.heightAnchor.constraint(equalToConstant: 12),
            ])
        }
        NSLayoutConstraint.activate([
            first.leadingAnchor.constraint(equalTo: leadingAnchor),
            second.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            heightAnchor.constraint(equalToConstant: 12),
        ])
        widthConstraint = widthAnchor.constraint(equalToConstant: 12)
        widthConstraint?.isActive = true
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ tick: MessageTick, colors: HaloChatColor) {
        second.isHidden = tick != .read
        widthConstraint?.constant = tick == .read ? 17 : 12
        switch tick {
        case .sending:
            first.image = UIImage(systemName: "clock")
            first.tintColor = colors.timeLabelTextColor
            accessibilityLabel = L10n.statusSending
        case .failed:
            first.image = UIImage(systemName: "exclamationmark.circle")
            first.tintColor = .systemRed
            accessibilityLabel = L10n.statusFailed
        case .sent:
            first.image = UIImage(systemName: "checkmark")
            first.tintColor = colors.timeLabelTextColor
            accessibilityLabel = L10n.statusSent
        case .read:
            first.image = UIImage(systemName: "checkmark")
            second.image = UIImage(systemName: "checkmark")
            first.tintColor = colors.sendContainerColor
            second.tintColor = colors.sendContainerColor
            accessibilityLabel = L10n.statusRead
        }
    }
}

final class MessageCell: UITableViewCell {
    static let reuseId = "HaloChatMessageCell"

    var onTapMedia: (() -> Void)?
    var onTapBubble: (() -> Void)?
    /// The row the async thumbnail belongs to (cells are reused).
    private(set) var representedRowId: String?

    private let avatarLabel = UILabel()
    private let column = UIStackView()
    private let senderLabel = UILabel()
    private let bubble = UIView()
    private let content = UIStackView()
    private let imageViewMedia = UIImageView()
    private let fileCard = UIStackView()
    private let fileIcon = UIImageView()
    private let fileName = UILabel()
    private let fileHint = UILabel()
    private let messageLabel = UILabel()
    private let timeLabel = UILabel()
    private let tickView = StatusTickView()
    private let retryLabel = UILabel()

    private var mineConstraints: [NSLayoutConstraint] = []
    private var agentConstraints: [NSLayoutConstraint] = []
    private var agentAvatarLeading: NSLayoutConstraint?
    private var agentPlainLeading: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedRowId = nil
        imageViewMedia.image = nil
        onTapMedia = nil
        onTapBubble = nil
    }

    private func build() {
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarLabel.textAlignment = .center
        avatarLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        avatarLabel.layer.cornerRadius = 15
        avatarLabel.layer.masksToBounds = true
        avatarLabel.isAccessibilityElement = false
        contentView.addSubview(avatarLabel)

        column.axis = .vertical
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)

        senderLabel.font = .preferredFont(forTextStyle: .caption1)
        senderLabel.adjustsFontForContentSizeCategory = true

        bubble.layer.cornerRadius = 14
        bubble.layer.cornerCurve = .continuous

        content.axis = .vertical
        content.spacing = 4
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(content)

        imageViewMedia.contentMode = .scaleAspectFill
        imageViewMedia.clipsToBounds = true
        imageViewMedia.layer.cornerRadius = 10
        imageViewMedia.backgroundColor = UIColor.secondarySystemFill
        imageViewMedia.isUserInteractionEnabled = true
        imageViewMedia.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mediaTapped)))
        let imageWidth = imageViewMedia.widthAnchor.constraint(equalToConstant: 220)
        imageWidth.priority = UILayoutPriority(999)
        let imageHeight = imageViewMedia.heightAnchor.constraint(equalToConstant: 220)
        imageHeight.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([imageWidth, imageHeight])

        fileIcon.contentMode = .scaleAspectFit
        fileIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26)
        fileIcon.setContentHuggingPriority(.required, for: .horizontal)
        fileName.font = .preferredFont(forTextStyle: .subheadline)
        fileName.numberOfLines = 2
        fileName.lineBreakMode = .byTruncatingMiddle
        fileHint.font = .preferredFont(forTextStyle: .caption1)
        let fileText = UIStackView(arrangedSubviews: [fileName, fileHint])
        fileText.axis = .vertical
        fileText.spacing = 2
        fileCard.addArrangedSubview(fileIcon)
        fileCard.addArrangedSubview(fileText)
        fileCard.axis = .horizontal
        fileCard.spacing = 10
        fileCard.alignment = .center
        fileCard.isLayoutMarginsRelativeArrangement = true
        fileCard.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        fileCard.backgroundColor = UIColor.secondarySystemFill
        fileCard.layer.cornerRadius = 10
        fileCard.isUserInteractionEnabled = true
        fileCard.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(mediaTapped)))
        let fileWidth = fileCard.widthAnchor.constraint(equalToConstant: 220)
        fileWidth.priority = UILayoutPriority(999)
        fileWidth.isActive = true

        messageLabel.numberOfLines = 0
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true

        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.adjustsFontForContentSizeCategory = true
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = UIStackView(arrangedSubviews: [spacer, timeLabel, tickView])
        footer.axis = .horizontal
        footer.spacing = 4
        footer.alignment = .center

        content.addArrangedSubview(imageViewMedia)
        content.addArrangedSubview(fileCard)
        content.addArrangedSubview(messageLabel)
        content.addArrangedSubview(footer)

        retryLabel.font = .preferredFont(forTextStyle: .caption1)
        retryLabel.textColor = .systemRed
        retryLabel.text = L10n.messageTapToRetry

        column.addArrangedSubview(senderLabel)
        column.addArrangedSubview(bubble)
        column.addArrangedSubview(retryLabel)

        bubble.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bubbleTapped)))

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 7),
            content.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
            content.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),
            bubble.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            avatarLabel.widthAnchor.constraint(equalToConstant: 30),
            avatarLabel.heightAnchor.constraint(equalToConstant: 30),
            avatarLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            avatarLabel.topAnchor.constraint(equalTo: bubble.topAnchor),
        ])

        mineConstraints = [
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 56),
        ]
        agentAvatarLeading = column.leadingAnchor.constraint(equalTo: avatarLabel.trailingAnchor, constant: 6)
        agentPlainLeading = column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10)
        agentConstraints = [column.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -56)]
    }

    func configure(_ model: BubbleModel, colors: HaloChatColor, avatarInitial: String, loader: HaloChatMediaLoader?) {
        representedRowId = model.rowId

        NSLayoutConstraint.deactivate(mineConstraints + agentConstraints)
        agentAvatarLeading?.isActive = false
        agentPlainLeading?.isActive = false
        if model.isMine {
            NSLayoutConstraint.activate(mineConstraints)
            column.alignment = .trailing
        } else {
            NSLayoutConstraint.activate(agentConstraints)
            (model.showsAvatarColumn ? agentAvatarLeading : agentPlainLeading)?.isActive = true
            column.alignment = .leading
        }

        let textColor = model.isMine ? colors.rightBubbleTextColor : colors.leftBubbleTextColor
        bubble.backgroundColor = model.isMine ? colors.rightBubbleColor : colors.leftBubbleColor
        messageLabel.textColor = textColor
        fileName.textColor = textColor
        fileHint.textColor = colors.timeLabelTextColor
        fileIcon.tintColor = colors.sendContainerColor
        timeLabel.textColor = colors.timeLabelTextColor
        senderLabel.textColor = colors.timeLabelTextColor

        avatarLabel.isHidden = model.isMine || !model.showsAvatarColumn || model.senderName == nil
        avatarLabel.text = avatarInitial
        avatarLabel.backgroundColor = colors.sendContainerColor
        avatarLabel.textColor = .white

        senderLabel.text = model.senderName
        senderLabel.isHidden = model.senderName == nil

        let text = model.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        messageLabel.text = text
        messageLabel.isHidden = text.isEmpty

        imageViewMedia.isHidden = true
        fileCard.isHidden = true
        switch model.media {
        case let .remoteImage(messageId):
            imageViewMedia.isHidden = false
            if let cached = loader?.cachedImage(for: messageId, size: .thumbnail) {
                imageViewMedia.image = cached
            } else if let loader {
                imageViewMedia.image = nil
                let rowId = model.rowId
                Task { [weak self] in
                    let image = await loader.image(for: messageId, size: .thumbnail)
                    guard let self, self.representedRowId == rowId else { return }
                    self.imageViewMedia.image = image ?? UIImage(systemName: "photo")
                }
            }
        case let .localImage(data):
            imageViewMedia.isHidden = false
            imageViewMedia.image = ImageDownsampler.image(from: data, maxPixelSize: 240 * UIScreen.main.scale)
        case let .file(name, mimeType):
            fileCard.isHidden = false
            fileName.text = name
            fileHint.text = L10n.fileTapToOpen
            fileIcon.image = UIImage(systemName: Self.symbol(for: mimeType))
        case nil:
            break
        }

        timeLabel.text = ChatFormatters.time.string(from: model.time)
        if let tick = model.tick {
            tickView.isHidden = false
            tickView.configure(tick, colors: colors)
        } else {
            tickView.isHidden = true
        }
        retryLabel.isHidden = !model.showsRetryHint

        accessibilityElements = [senderLabel, bubble, retryLabel].filter { !$0.isHidden }
        bubble.isAccessibilityElement = true
        bubble.accessibilityLabel = [
            model.senderName,
            text.isEmpty ? nil : text,
            model.media.map { media -> String in
                if case let .file(name, _) = media { return name }
                return L10n.fileAttachment
            },
            timeLabel.text,
            model.tick.map { _ in tickView.accessibilityLabel ?? "" },
        ].compactMap { $0 }.joined(separator: ", ")
    }

    static func symbol(for mimeType: String?) -> String {
        let mime = mimeType ?? ""
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.contains("spreadsheet") { return "tablecells" }
        if mime.hasPrefix("text/") { return "doc.plaintext" }
        return "doc"
    }

    @objc private func mediaTapped() {
        if let onTapMedia { onTapMedia() } else { onTapBubble?() }
    }
    @objc private func bubbleTapped() { onTapBubble?() }
}
#endif
