#if canImport(UIKit)
#if SWIFT_PACKAGE
import HaloChat
#endif
import QuickLook
import UIKit

/// The drop-in chat screen. Get it from `HaloChatWidget.initiateChat()…startChat { }`.
///
/// Push it on a `UINavigationController`, or present it wrapped in one (a close button is
/// added). The live timeline runs only while the screen is visible.
public final class HaloChatViewController: UIViewController {
    private enum ScrollIntent {
        case none
        case bottomIfNear
        case bottom
    }

    private let widget: HaloChatWidget
    private let client: HaloChatClient?
    private let settings: ChatScreenSettings
    private var colors: HaloChatColor { widget.color }
    private let mediaLoader: HaloChatMediaLoader?

    private var store = ChatTimelineStore()
    private var pending = PendingQueue()
    private var rows: [ChatRow] = []
    private var heightCache: [String: CGFloat] = [:]

    private var timelineTask: Task<Void, Never>?
    private var olderTask: Task<Void, Never>?
    private var conversationTask: Task<Void, Never>?
    private var initialLoadFinished = false
    private var didScrollInitially = false
    private var sessionExpired = false
    private var didSendAutomaticMessage = false
    private var didApplyManualMessage = false
    private var conversationTitle: String?
    private var savedNavigationTint: UIColor?
    private var previewSource: HaloChatFilePreviewSource?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let composer = ComposerView()
    private let composerFiller = UIView()
    private let banner = UILabel()
    private let bannerContainer = UIView()
    private let emptyLabel = UILabel()
    private let emptyContainer = UIView()
    private let initialSpinner = UIActivityIndicatorView(style: .medium)
    private let olderSpinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let picker = AttachmentPickerCoordinator()
    private var bannerHeight: NSLayoutConstraint?

    init(widget: HaloChatWidget, settings: ChatScreenSettings) {
        self.widget = widget
        client = widget.client
        self.settings = settings
        mediaLoader = widget.client.map { HaloChatMediaLoader(client: $0) }
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = colors.baseColor
        buildHeader()
        buildLayout()
        picker.presenter = self
        picker.onResult = { [weak self] result in self?.handlePick(result) }
        if client == nil {
            enterSessionExpired()
        } else {
            loadConversationTitleIfNeeded()
        }
        if let manual = settings.manualMessage, !didApplyManualMessage {
            didApplyManualMessage = true
            composer.setText(manual)
        }
        reload(scroll: .none)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyNavigationAppearance()
        startTimeline()
        sendAutomaticMessageIfNeeded()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        HaloChatVisibility.appeared()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let savedNavigationTint {
            navigationController?.navigationBar.tintColor = savedNavigationTint
            self.savedNavigationTint = nil
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        HaloChatVisibility.disappeared()
        // The server contract: the timeline (socket / polling) runs only while visible.
        stopTimeline()
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            composer.apply(colors: colors)
            tableView.reloadData()
        }
    }

    // MARK: Header

    private var displayTitle: String {
        settings.roomTitle ?? conversationTitle ?? L10n.defaultTitle
    }

    private var avatarInitial: String {
        displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    private func buildHeader() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.isAccessibilityElement = true
        stack.accessibilityTraits = .header
        navigationItem.titleView = stack
        updateHeader()
    }

    private func updateHeader() {
        titleLabel.text = displayTitle
        titleLabel.textColor = colors.navigationTitleColor
        subtitleLabel.text = settings.subtitleText
        subtitleLabel.textColor = colors.navigationTitleColor.withAlphaComponent(0.75)
        subtitleLabel.isHidden = settings.subtitleText == nil
        navigationItem.titleView?.accessibilityLabel = [displayTitle, settings.subtitleText].compactMap { $0 }.joined(separator: ", ")
        title = displayTitle
    }

    private func applyNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = colors.navigationColor
        appearance.titleTextAttributes = [.foregroundColor: colors.navigationTitleColor]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        if let bar = navigationController?.navigationBar {
            if savedNavigationTint == nil { savedNavigationTint = bar.tintColor }
            bar.tintColor = colors.navigationTitleColor
        }
        let isRoot = navigationController?.viewControllers.first === self
        let isPresented = navigationController?.presentingViewController != nil
        if isRoot, isPresented, navigationItem.leftBarButtonItem == nil {
            let close = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                style: .plain,
                target: self,
                action: #selector(closeTapped)
            )
            close.accessibilityLabel = L10n.close
            navigationItem.leftBarButtonItem = close
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func loadConversationTitleIfNeeded() {
        guard settings.roomTitle == nil, let client else { return }
        conversationTask = Task { [weak self] in
            guard let conversation = try? await client.conversation() else { return }
            self?.conversationTitle = conversation.title
            self?.updateHeader()
            self?.tableView.reloadData()
        }
    }

    // MARK: Layout

    private func buildLayout() {
        bannerContainer.backgroundColor = .clear
        bannerContainer.clipsToBounds = true
        banner.font = .preferredFont(forTextStyle: .footnote)
        banner.adjustsFontForContentSizeCategory = true
        banner.textAlignment = .center
        banner.numberOfLines = 0
        banner.textColor = .white
        banner.accessibilityTraits = .updatesFrequently
        bannerContainer.addSubview(banner)

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.allowsSelection = false
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseId)
        tableView.register(SystemMessageCell.self, forCellReuseIdentifier: SystemMessageCell.reuseId)
        tableView.register(DateSeparatorCell.self, forCellReuseIdentifier: DateSeparatorCell.reuseId)
        olderSpinner.hidesWhenStopped = true
        olderSpinner.frame = CGRect(x: 0, y: 0, width: 44, height: 36)
        tableView.tableHeaderView = olderSpinner

        emptyLabel.text = L10n.emptyMessage
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = colors.emptyTextColor
        emptyContainer.backgroundColor = colors.emptyBackgroundColor
        emptyContainer.addSubview(emptyLabel)
        emptyContainer.addSubview(initialSpinner)
        initialSpinner.hidesWhenStopped = true

        composer.apply(colors: colors)
        composer.onSend = { [weak self] text in self?.sendText(text) }
        composer.onAttach = { [weak self] source in self?.picker.presentMenu(from: source) }
        composerFiller.backgroundColor = colors.sendContainerBackgroundColor

        for subview in [bannerContainer, tableView, composer, composerFiller, emptyContainer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        initialSpinner.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(emptyContainer)
        view.addSubview(bannerContainer)
        view.addSubview(composerFiller)
        view.addSubview(composer)

        // Collapsed by a required zero height; the label's own constraints yield to it.
        let bannerHeight = bannerContainer.heightAnchor.constraint(equalToConstant: 0)
        self.bannerHeight = bannerHeight
        let bannerTop = banner.topAnchor.constraint(equalTo: bannerContainer.topAnchor, constant: 6)
        bannerTop.priority = .defaultHigh
        let bannerBottom = banner.bottomAnchor.constraint(equalTo: bannerContainer.bottomAnchor, constant: -6)
        bannerBottom.priority = .defaultHigh
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bannerContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            bannerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bannerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bannerHeight,
            banner.leadingAnchor.constraint(equalTo: bannerContainer.leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: bannerContainer.trailingAnchor, constant: -16),
            bannerTop,
            bannerBottom,

            tableView.topAnchor.constraint(equalTo: bannerContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: composer.topAnchor),

            emptyContainer.topAnchor.constraint(equalTo: tableView.topAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
            emptyContainer.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -32),
            initialSpinner.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            initialSpinner.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),

            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // iOS 15 keyboard avoidance: the composer rides the keyboard (or the safe area).
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            composerFiller.topAnchor.constraint(equalTo: composer.bottomAnchor),
            composerFiller.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerFiller.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerFiller.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        emptyContainer.isUserInteractionEnabled = false
    }

    // MARK: Banner

    private func show(banner kind: ChatBanner?) {
        let visible = kind != nil
        guard banner.text != kind?.text || bannerHeight?.isActive == visible else { return }
        banner.text = kind?.text
        bannerContainer.backgroundColor = kind == .sessionExpired ? .systemRed : UIColor.systemGray.withAlphaComponent(0.9)
        bannerHeight?.isActive = !visible
        if visible { UIAccessibility.post(notification: .announcement, argument: kind?.text) }
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    private func enterSessionExpired() {
        sessionExpired = true
        stopTimeline()
        olderTask?.cancel()
        olderTask = nil
        composer.isEnabled = false
        initialLoadFinished = true
        show(banner: .sessionExpired)
        updateEmptyState()
    }

    // MARK: Timeline

    private func startTimeline() {
        guard timelineTask == nil, let client, !sessionExpired else { return }
        if !initialLoadFinished { initialSpinner.startAnimating() }
        let stream = client.timeline(onError: { [weak self] error in
            Task { @MainActor [weak self] in self?.handleTimelineError(error) }
        })
        timelineTask = Task { [weak self] in
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                self?.applyTimeline(snapshot)
            }
        }
    }

    private func stopTimeline() {
        timelineTask?.cancel()
        timelineTask = nil
    }

    private func applyTimeline(_ snapshot: [HaloChatMessage]) {
        guard !sessionExpired else { return }
        store.applyTimeline(snapshot)
        initialLoadFinished = true
        initialSpinner.stopAnimating()
        if !sessionExpired { show(banner: nil) }
        if didScrollInitially {
            reload(scroll: .bottomIfNear)
        } else {
            didScrollInitially = true
            reload(scroll: .bottom, animated: false)
            loadOlderIfContentIsShort()
        }
    }

    private func handleTimelineError(_ error: Error) {
        guard !sessionExpired else { return }
        let kind = ChatBanner(error: error)
        if kind == .sessionExpired {
            enterSessionExpired()
            return
        }
        initialLoadFinished = true
        initialSpinner.stopAnimating()
        show(banner: kind)
        updateEmptyState()
    }

    // MARK: Older pages

    private func loadOlderIfNeeded() {
        guard olderTask == nil, didScrollInitially, !sessionExpired, let client, let request = store.nextOlderRequest else { return }
        olderSpinner.startAnimating()
        olderTask = Task { [weak self] in
            do {
                let page: HaloChatMessagePage
                switch request {
                case .latest: page = try await client.latestMessages()
                case let .before(cursor): page = try await client.messages(before: cursor)
                }
                self?.applyOlder(page)
            } catch {
                self?.olderFailed(error)
            }
        }
    }

    private func applyOlder(_ page: HaloChatMessagePage) {
        olderTask = nil
        olderSpinner.stopAnimating()
        let before = store.messages.count
        store.applyOlder(page)
        if store.messages.count != before {
            reloadKeepingVisiblePosition()
        }
        if store.reachedStart { tableView.tableHeaderView = nil }
        loadOlderIfContentIsShort()
    }

    private func olderFailed(_ error: Error) {
        olderTask = nil
        olderSpinner.stopAnimating()
        if case HaloChatError.unauthorized = error { enterSessionExpired() }
    }

    /// Keeps paging back while the history does not fill the screen yet.
    private func loadOlderIfContentIsShort() {
        tableView.layoutIfNeeded()
        let visibleHeight = tableView.bounds.height - tableView.adjustedContentInset.top - tableView.adjustedContentInset.bottom
        if tableView.contentSize.height < visibleHeight { loadOlderIfNeeded() }
    }

    // MARK: Rows

    private var isNearBottom: Bool {
        let visibleBottom = tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
        return tableView.contentSize.height - visibleBottom < 120
    }

    private func rebuildRows() {
        rows = ChatRowBuilder.rows(
            messages: store.messages,
            pending: pending.items,
            showSystemMessages: settings.showSystemMessage
        )
    }

    private func reload(scroll: ScrollIntent, animated: Bool = true) {
        let wasNearBottom = isNearBottom
        rebuildRows()
        tableView.reloadData()
        updateEmptyState()
        switch scroll {
        case .none: break
        case .bottomIfNear: if wasNearBottom { scrollToBottom(animated: animated) }
        case .bottom: scrollToBottom(animated: animated)
        }
    }

    /// Prepends older rows without moving what the user is looking at.
    private func reloadKeepingVisiblePosition() {
        let anchorId = tableView.indexPathsForVisibleRows?.first.flatMap { rows.indices.contains($0.row) ? rows[$0.row].id : nil }
        let anchorOffset = tableView.indexPathsForVisibleRows?.first.map { tableView.rectForRow(at: $0).minY - tableView.contentOffset.y } ?? 0
        rebuildRows()
        tableView.reloadData()
        updateEmptyState()
        guard let anchorId, let index = rows.firstIndex(where: { $0.id == anchorId }) else { return }
        tableView.layoutIfNeeded()
        let rect = tableView.rectForRow(at: IndexPath(row: index, section: 0))
        tableView.setContentOffset(CGPoint(x: 0, y: rect.minY - anchorOffset), animated: false)
    }

    private func scrollToBottom(animated: Bool) {
        guard !rows.isEmpty else { return }
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: animated)
    }

    private func updateEmptyState() {
        let empty = rows.isEmpty
        emptyContainer.isHidden = !empty
        emptyLabel.isHidden = !initialLoadFinished
        if initialLoadFinished { initialSpinner.stopAnimating() }
    }

    // MARK: Sending

    private func sendAutomaticMessageIfNeeded() {
        guard !didSendAutomaticMessage, client != nil, !sessionExpired,
              let text = settings.automaticMessage.flatMap(ComposerRules.sendableText)
        else { return }
        didSendAutomaticMessage = true
        sendText(text)
    }

    private func sendText(_ text: String) {
        let item = pending.enqueue(.text(text))
        reload(scroll: .bottom)
        perform(item)
    }

    private func sendAttachment(_ picked: PickedAttachment) {
        let item = pending.enqueue(.attachment(PendingAttachment(data: picked.data, filename: picked.filename, mimeType: picked.mimeType, caption: nil)))
        reload(scroll: .bottom)
        perform(item)
    }

    /// Sends a pending item. Retries reuse the item as is: same `clientMessageId`, same bytes.
    private func perform(_ item: PendingMessage) {
        guard let client else {
            pending.failed(item.clientMessageId, .sessionExpired)
            reload(scroll: .none)
            return
        }
        let id = item.clientMessageId
        let content = item.content
        Task { [weak self] in
            let result = await SendPerformer.perform(
                clientMessageId: id,
                send: { clientMessageId in
                    switch content {
                    case let .text(text):
                        return try await client.send(text: text, clientMessageId: clientMessageId)
                    case let .attachment(attachment):
                        return try await client.send(
                            attachment: attachment.data,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType,
                            caption: attachment.caption,
                            clientMessageId: clientMessageId
                        )
                    }
                },
                reread: { [weak self] in await self?.reread() }
            )
            self?.finishSend(id, result)
        }
    }

    /// Re-reads the conversation (after `.sendInProgress`), so a message the first attempt
    /// created shows up before the retry.
    private func reread() async {
        guard let client, let page = try? await client.latestMessages() else { return }
        store.merge(page.messages)
        reload(scroll: .bottomIfNear)
    }

    private func finishSend(_ id: UUID, _ result: Result<HaloChatMessage, Error>) {
        switch result {
        case let .success(message):
            pending.succeeded(id)
            store.merge([message])
            reload(scroll: .bottomIfNear)
        case let .failure(error):
            let failure = SendFailure(error: error)
            pending.failed(id, failure)
            reload(scroll: .none)
            if failure == .sessionExpired {
                enterSessionExpired()
            } else if failure == .tooLarge || failure == .unsupportedType {
                showAlert(failure.localizedMessage)
            }
        }
    }

    private func handlePick(_ result: Result<PickedAttachment, PickFailure>) {
        switch result {
        case let .success(picked): sendAttachment(picked)
        case let .failure(failure): showAlert(failure.message)
        }
    }

    private func showFailedActions(for id: UUID, source: UIView) {
        guard let item = pending.item(id), case let .failed(failure) = item.state else { return }
        let sheet = UIAlertController(title: failure.localizedMessage, message: nil, preferredStyle: .actionSheet)
        if !sessionExpired {
            sheet.addAction(UIAlertAction(title: L10n.messageRetry, style: .default) { [weak self] _ in
                guard let self, let retried = self.pending.retry(id) else { return }
                self.reload(scroll: .none)
                self.perform(retried)
            })
        }
        sheet.addAction(UIAlertAction(title: L10n.messageDelete, style: .destructive) { [weak self] _ in
            self?.pending.remove(id)
            self?.reload(scroll: .none)
        })
        sheet.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        sheet.popoverPresentationController?.sourceRect = source.bounds
        present(sheet, animated: true)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: L10n.errorTitle, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    // MARK: Media

    private func openImage(messageId: String) {
        guard let mediaLoader else { return }
        let placeholder = mediaLoader.cachedImage(for: messageId, size: .thumbnail)
        let viewer = HaloChatImageViewerController(placeholder: placeholder) {
            await mediaLoader.image(for: messageId, size: .full)
        }
        present(viewer, animated: true)
    }

    private func openLocalImage(_ data: Data) {
        let image = ImageDownsampler.image(from: data, maxPixelSize: max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale * 2)
        present(HaloChatImageViewerController(placeholder: image) { image }, animated: true)
    }

    private func openFile(messageId: String, filename: String) {
        guard let mediaLoader else { return }
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()
        view.isUserInteractionEnabled = false
        Task { [weak self] in
            // A fresh 15-minute URL per open; the file lands in the temp dir under its original name.
            let url = try? await mediaLoader.downloadFile(messageId: messageId, filename: filename)
            spinner.removeFromSuperview()
            guard let self else { return }
            self.view.isUserInteractionEnabled = true
            if let url { self.preview(url) } else { self.showAlert(L10n.errorOpenFailed) }
        }
    }

    private func openLocalFile(_ attachment: PendingAttachment, folder: String) {
        guard let url = try? HaloChatMediaLoader.writeTemporaryFile(data: attachment.data, folder: folder, filename: attachment.filename) else {
            showAlert(L10n.errorOpenFailed)
            return
        }
        preview(url)
    }

    private func preview(_ url: URL) {
        let source = HaloChatFilePreviewSource(url: url)
        previewSource = source
        let controller = QLPreviewController()
        controller.dataSource = source
        present(controller, animated: true)
    }

    // MARK: Bubble models

    private func bubbleModel(for row: ChatMessageRow) -> BubbleModel {
        let message = row.message
        let isMine = message.sender == .me
        var media: BubbleModel.Media?
        if message.hasMedia {
            if message.mediaType?.lowercased().hasPrefix("image/") == true {
                media = .remoteImage(messageId: message.id)
            } else {
                media = .file(name: message.mediaFilename ?? L10n.fileAttachment, mimeType: message.mediaType)
            }
        }
        let avatarOn = settings.avatar == .enabled && !isMine
        return BubbleModel(
            rowId: message.id,
            isMine: isMine,
            text: message.text,
            time: message.createdAt,
            tick: isMine ? MessageTick(status: message.status) : nil,
            media: media,
            senderName: avatarOn && row.startsAgentRun ? displayTitle : nil,
            showsAvatarColumn: avatarOn,
            showsRetryHint: false
        )
    }

    private func bubbleModel(for item: PendingMessage) -> BubbleModel {
        var text: String?
        var media: BubbleModel.Media?
        switch item.content {
        case let .text(value):
            text = value
        case let .attachment(attachment):
            text = attachment.caption
            media = attachment.mimeType.hasPrefix("image/") ? .localImage(attachment.data) : .file(name: attachment.filename, mimeType: attachment.mimeType)
        }
        return BubbleModel(
            rowId: item.id,
            isMine: true,
            text: text,
            time: item.createdAt,
            tick: MessageTick(pending: item.state),
            media: media,
            senderName: nil,
            showsAvatarColumn: false,
            showsRetryHint: item.isFailed
        )
    }
}

// MARK: - Table

extension HaloChatViewController: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch rows[indexPath.row] {
        case let .date(_, label):
            let cell = tableView.dequeueReusableCell(withIdentifier: DateSeparatorCell.reuseId, for: indexPath) as! DateSeparatorCell
            cell.configure(label, colors: colors)
            return cell
        case let .system(message):
            let cell = tableView.dequeueReusableCell(withIdentifier: SystemMessageCell.reuseId, for: indexPath) as! SystemMessageCell
            cell.configure(text: message.text ?? "", colors: colors)
            return cell
        case let .message(row):
            let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
            cell.configure(bubbleModel(for: row), colors: colors, avatarInitial: avatarInitial, loader: mediaLoader)
            let message = row.message
            if message.hasMedia {
                let isImage = message.mediaType?.lowercased().hasPrefix("image/") == true
                let filename = message.mediaFilename ?? "attachment"
                cell.onTapMedia = { [weak self] in
                    if isImage { self?.openImage(messageId: message.id) } else { self?.openFile(messageId: message.id, filename: filename) }
                }
            }
            return cell
        case let .pending(item):
            let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
            cell.configure(bubbleModel(for: item), colors: colors, avatarInitial: avatarInitial, loader: mediaLoader)
            let id = item.clientMessageId
            cell.onTapBubble = { [weak self, weak cell] in
                guard let self, let cell, self.pending.item(id)?.isFailed == true else { return }
                self.showFailedActions(for: id, source: cell)
            }
            if case let .attachment(attachment) = item.content {
                cell.onTapMedia = { [weak self, weak cell] in
                    guard let self else { return }
                    if self.pending.item(id)?.isFailed == true, let cell {
                        self.showFailedActions(for: id, source: cell)
                    } else if attachment.mimeType.hasPrefix("image/") {
                        self.openLocalImage(attachment.data)
                    } else {
                        self.openLocalFile(attachment, folder: item.id)
                    }
                }
            }
            return cell
        }
    }

    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard rows.indices.contains(indexPath.row) else { return 60 }
        return heightCache[rows[indexPath.row].id] ?? 60
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard rows.indices.contains(indexPath.row) else { return }
        heightCache[rows[indexPath.row].id] = cell.frame.height
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Scrolled near the top: page back.
        if scrollView.contentOffset.y + scrollView.adjustedContentInset.top < 200, scrollView.isDragging || scrollView.isDecelerating {
            loadOlderIfNeeded()
        }
    }
}
#endif
