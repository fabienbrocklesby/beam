import AppKit
import BeamCore
import Quartz
import os

/// One file in a pane, drawn by the view its kind needs, loaded off the main
/// thread and loaded again each time the file changes on disk.
///
/// A file that goes missing keeps its last render, dimmed under a bar,
/// because git checkout and a delete then create pass through a moment with
/// no file; the bar goes when it comes back. A file that fails to load, such
/// as a PDF caught half written, keeps its last render and waits for the
/// next write.
final class DocumentView: NSView, NSMenuItemValidation {
    /// What the pane asks of the window, as a terminal would.
    var onEvent: ((TerminalEvent) -> Bool)?
    /// Called with a file a Markdown link names.
    var onOpenFile: ((URL) -> Void)?
    /// Called when the app the file opens in outside Beam changes.
    var onApplicationChange: (() -> Void)?

    private(set) var url: URL
    /// The app that opens the file outside Beam, and its name. Never Beam:
    /// once Beam is the file's default app, it would come straight back.
    private(set) var application: (url: URL, name: String)?

    /// What a load read, ready to show.
    private enum Loaded: Sendable {
        case missing
        case failed
        case external
        case pdf(Data)
        case markdown(MarkdownDocument)
        case text(String)
        case richText(Data)
        case image(Data)
        case quickLook
    }

    private nonisolated static let queue = DispatchQueue(label: "dev.beam.terminal.documents", qos: .userInitiated)

    private var watcher: FileWatcher?
    private var content: NSView?
    /// The file the content shows, which a reload keeps the place in.
    private var shownURL: URL?
    /// Counts loads, so one that ends after a newer one began is dropped.
    private var generation = 0
    /// Whether the last load found no file. Launch Services names no app
    /// for a file that is not there, so it is asked again once it is.
    private var wasMissing = false
    private let placeholder = Placeholder()
    private let missingBar = MissingBar()

    init(url: URL) {
        self.url = url
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        placeholder.frame = bounds
        placeholder.autoresizingMask = [.width, .height]
        placeholder.onOpen = { [weak self] in self?.openInApplication(nil) }
        addSubview(placeholder)
        missingBar.frame = NSRect(
            x: 0, y: bounds.maxY - MissingBar.height, width: bounds.width, height: MissingBar.height)
        missingBar.autoresizingMask = [.width, .minYMargin]
        missingBar.isHidden = true
        addSubview(missingBar)
        placeholder.show(.loading, file: url, application: nil)
        start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Shows the file at `url` in place of the one shown.
    func show(_ url: URL) {
        guard url != self.url else { return }
        self.url = url
        start()
    }

    /// The view inside that takes keyboard focus for the document.
    var responder: NSView {
        switch content {
        case let view as MarkdownView: view.textView
        case let view as TextDocumentView: view.textView
        case let view as ImageDocumentView: view.imageView
        case let view?: view
        case nil: self
        }
    }

    private func start() {
        application = nil
        wasMissing = false
        onApplicationChange?()
        lookUpApplication()
        // The watcher calls back once as it starts, which loads the file.
        watcher = FileWatcher(path: url.path) { [weak self] in self?.load() }
    }

    // MARK: Loading

    private func load() {
        generation += 1
        let generation = generation
        let url = url
        Self.queue.async { [weak self] in
            let loaded = Self.load(url)
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                self.show(loaded, of: url)
            }
        }
    }

    private nonisolated static func load(_ url: URL) -> Loaded {
        let kind = DocumentKind(file: url, chosen: true)
        switch kind {
        case .external:
            return .external
        case .quickLook:
            return FileManager.default.fileExists(atPath: url.path) ? .quickLook : .missing
        case .pdf, .markdown, .text, .image:
            break
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            return .failed
        }
        switch kind {
        case .pdf:
            return .pdf(data)
        case .image:
            return .image(data)
        case .markdown:
            return text(from: data).map { .markdown(MarkdownDocument(markdown: $0, baseURL: url)) } ?? .failed
        default:
            if url.pathExtension.lowercased() == "rtf" { return .richText(data) }
            return text(from: data).map(Loaded.text) ?? .failed
        }
    }

    /// The text `data` holds, or nil when it is not text.
    private nonisolated static func text(from data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        // A NUL byte early on means binary, as git decides.
        guard !data.prefix(8192).contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        var converted: NSString?
        let encoding = NSString.stringEncoding(
            for: data, encodingOptions: [.allowLossyKey: false], convertedString: &converted, usedLossyConversion: nil)
        return encoding == 0 ? nil : converted as String?
    }

    private func show(_ loaded: Loaded, of loadedURL: URL) {
        let keepingPlace = shownURL == loadedURL
        if case .missing = loaded {
            wasMissing = true
        } else if wasMissing {
            wasMissing = false
            lookUpApplication()
        }
        switch loaded {
        case .missing:
            if keepingPlace, content != nil {
                setMissing(true)
            } else {
                setContent(nil)
                shownURL = nil
                placeholder.show(.missing, file: url, application: application?.name)
            }
            return
        case .failed:
            showFailure(keepingPlace: keepingPlace)
            return
        case .external:
            setContent(nil)
            placeholder.show(.cannotShow, file: url, application: application?.name)
        case .pdf(let data):
            guard let document = PDFDocument(data: data) else { return showFailure(keepingPlace: keepingPlace) }
            reuse(PDFDocumentView.init).show(document, keepingPlace: keepingPlace)
        case .markdown(let document):
            let view = reuse(MarkdownView.init)
            view.onOpenFile = { [weak self] url in self?.onOpenFile?(url) }
            view.show(document, of: loadedURL)
        case .text(let text):
            reuse(TextDocumentView.init).show(text, keepingPlace: keepingPlace)
        case .richText(let data):
            guard let text = NSAttributedString(rtf: data, documentAttributes: nil) else {
                return showFailure(keepingPlace: keepingPlace)
            }
            reuse(TextDocumentView.init).show(text, keepingPlace: keepingPlace)
        case .image(let data):
            guard let image = NSImage(data: data) else { return showFailure(keepingPlace: keepingPlace) }
            reuse(ImageDocumentView.init).show(image)
        case .quickLook:
            reuse(QuickLookDocumentView.init).show(loadedURL)
        }
        shownURL = loadedURL
        setMissing(false)
    }

    /// Keeps the file's last render, as for a PDF caught half written, or
    /// says the file cannot be shown when there is none.
    private func showFailure(keepingPlace: Bool) {
        Logger.app.info("could not load a document")
        setMissing(false)
        guard !keepingPlace || content == nil else { return }
        setContent(nil)
        shownURL = nil
        placeholder.show(.cannotShow, file: url, application: application?.name)
    }

    /// The content view of type `View`, made if another kind is showing.
    private func reuse<View: NSView>(_ make: () -> View) -> View {
        if let view = content as? View { return view }
        let view = make()
        setContent(view)
        return view
    }

    private func setContent(_ view: NSView?) {
        let hadFocus = (window?.firstResponder as? NSView)?.isDescendant(of: self) == true
        content?.removeFromSuperview()
        content = view
        placeholder.isHidden = view != nil
        guard let view else { return }
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view, positioned: .below, relativeTo: missingBar)
        if hadFocus { window?.makeFirstResponder(responder) }
    }

    private func setMissing(_ missing: Bool) {
        missingBar.isHidden = !missing
        content?.alphaValue = missing ? 0.4 : 1
    }

    // MARK: Outside Beam

    private func lookUpApplication() {
        let url = url
        let beam = Bundle.main.bundleURL
        Self.queue.async { [weak self] in
            let found = Self.externalApplication(for: url, besides: beam)
            DispatchQueue.main.async {
                guard let self, self.url == url else { return }
                self.application = found
                self.placeholder.application = found?.name
                self.onApplicationChange?()
            }
        }
    }

    /// The file's default app unless that is a copy of Beam, then the first
    /// other app Launch Services lists for it.
    private nonisolated static func externalApplication(
        for url: URL, besides beam: URL
    ) -> (url: URL, name: String)? {
        let workspace = NSWorkspace.shared
        let copies = Bundle.main.bundleIdentifier.map { workspace.urlsForApplications(withBundleIdentifier: $0) } ?? []
        let beams = Set((copies + [beam]).map(\.standardizedFileURL))
        let apps =
            [workspace.urlForApplication(toOpen: url)].compactMap { $0 } + workspace.urlsForApplications(toOpen: url)
        guard let app = apps.first(where: { !beams.contains($0.standardizedFileURL) }) else { return nil }
        let name = FileManager.default.displayName(atPath: app.path)
        return (app, name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }

    /// The header's and the placeholder's menu.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [
            ("Open in Another App", #selector(openInApplication(_:))),
            ("Reveal in Finder", #selector(revealInFinder(_:))),
            ("Copy Path", #selector(copyPath(_:))),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        return menu
    }

    @objc func openInApplication(_ sender: Any?) {
        guard let application else { return }
        NSWorkspace.shared.open(
            [url], withApplicationAt: application.url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func revealInFinder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func copyPath(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(openInApplication(_:)) else { return true }
        menuItem.title = application.map { "Open in \($0.name)" } ?? "Open in Another App"
        return application != nil
    }

    // MARK: Keys and focus

    /// Cmd+=, Cmd+- and Cmd+0 zoom a PDF or an image, as in Preview.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, (window?.firstResponder as? NSView)?.isDescendant(of: self) == true,
            event.modifierFlags.intersection([.command, .control, .option]) == .command
        else { return super.performKeyEquivalent(with: event) }
        let zoom: Selector
        switch event.charactersIgnoringModifiers {
        case "=", "+": zoom = #selector(PDFView.zoomIn(_:))
        case "-": zoom = #selector(PDFView.zoomOut(_:))
        case "0": zoom = #selector(PDFDocumentView.zoomToFit(_:))
        default: return super.performKeyEquivalent(with: event)
        }
        guard let content, content.responds(to: zoom) else { return super.performKeyEquivalent(with: event) }
        content.perform(zoom, with: nil)
        return true
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(responder)
    }
}

/// What a document pane says while it has nothing to draw.
private final class Placeholder: NSView {
    enum Status {
        case loading
        case missing
        case cannotShow
    }

    var onOpen: (() -> Void)?
    /// The app the open button names.
    var application: String? {
        didSet { updateButton() }
    }

    private var status = Status.loading
    private let spinner = NSProgressIndicator()
    private let symbol = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let button = NSButton()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        spinner.style = .spinning
        spinner.controlSize = .small
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
        symbol.contentTintColor = .tertiaryLabelColor
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .tertiaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.bezelStyle = .push
        button.target = self
        button.action = #selector(open)

        let stack = NSStackView(views: [spinner, symbol, title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: symbol)
        stack.setCustomSpacing(14, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    func show(_ status: Status, file: URL, application: String?) {
        self.status = status
        self.application = application
        isHidden = false
        let isLoading = status == .loading
        spinner.isHidden = !isLoading
        symbol.isHidden = isLoading
        title.isHidden = isLoading
        detail.isHidden = isLoading
        if isLoading {
            spinner.startAnimation(nil)
            // Most files load at once, so the spinner only shows for a slow
            // one, rather than flashing.
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.beginTime = CACurrentMediaTime() + 0.4
            appear.duration = 0.2
            appear.fillMode = .backwards
            spinner.wantsLayer = true
            spinner.layer?.add(appear, forKey: "appear")
        } else {
            spinner.stopAnimation(nil)
        }
        switch status {
        case .loading:
            break
        case .missing:
            symbol.image = NSImage(systemSymbolName: "questionmark.folder", accessibilityDescription: nil)
            title.stringValue = "Moved or deleted"
            detail.stringValue = (file.path as NSString).abbreviatingWithTildeInPath
        case .cannotShow:
            symbol.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
            title.stringValue = "Cannot show this file"
            detail.stringValue = file.lastPathComponent
        }
        updateButton()
    }

    private func updateButton() {
        button.title = application.map { "Open in \($0)" } ?? ""
        button.isHidden = status != .cannotShow || application == nil
    }

    @objc private func open() {
        onOpen?()
    }
}

/// Lies over the top of a document whose file has gone, while its last
/// render shows dimmed below.
private final class MissingBar: NSView {
    static let height = 28.0

    init() {
        super.init(frame: .zero)
        let icon = NSImageView(
            image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
                ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        icon.contentTintColor = .systemYellow
        let label = NSTextField(labelWithString: "Moved or deleted")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2)).fill()
    }
}
