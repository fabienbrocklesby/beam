import Quartz

/// A PDF scrolling continuously, fitted to the pane's width until the user
/// zooms with a pinch, Cmd+= or Cmd+-; Cmd+0 fits it again. Cmd+F shows a
/// find bar above it, since PDFView has none.
final class PDFDocumentView: NSView, NSMenuItemValidation {
    /// Takes keyboard focus for the document.
    let pdfView = PDFView()

    private let findBar = PDFFindBar()
    private var search: PDFSearch?
    /// Every match for the find bar's text so far, in page order.
    private var matches: [PDFSelection] = []
    /// The match shown, an index into `matches`.
    private var current: Int?
    /// A copy of the match shown, highlighted over it in a colour of its
    /// own: the PDF's selection draws inactive while the find field has
    /// focus, and PDFKit does not redraw a selection it holds when its
    /// colour changes.
    private var mark: PDFSelection?
    /// The page the search started from: the first match on it or after it
    /// is shown first, rather than one far back up the document.
    private var startPage = 0

    init() {
        super.init(frame: .zero)
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = true
        findBar.isHidden = true
        findBar.onChange = { [weak self] in self?.find() }
        findBar.onStep = { [weak self] forward in self?.step(forward: forward) }
        findBar.onClose = { [weak self] in self?.closeFindBar() }
        addSubview(pdfView)
        addSubview(findBar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Shows `document`. `keepingPlace` keeps the page, the point on it at
    /// the top of the view and the zoom, as when an agent writes the file
    /// again; an open find bar searches the new document.
    func show(_ document: PDFDocument, keepingPlace: Bool) {
        display(document, keepingPlace: keepingPlace)
        if !findBar.isHidden { find() }
    }

    private func display(_ document: PDFDocument, keepingPlace: Bool) {
        guard keepingPlace, let old = pdfView.document, let place = pdfView.currentDestination,
            let page = place.page
        else {
            pdfView.document = document
            return
        }
        let index = old.index(for: page)
        let scale = pdfView.autoScales ? nil : pdfView.scaleFactor
        pdfView.document = document
        if let scale { pdfView.scaleFactor = scale }
        guard let page = document.page(at: min(index, document.pageCount - 1)) else { return }
        pdfView.go(to: PDFDestination(page: page, at: place.point))
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let bar = findBar.isHidden ? 0 : PDFFindBar.height
        findBar.frame = NSRect(x: 0, y: bounds.height - bar, width: bounds.width, height: bar)
        pdfView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - bar)
    }

    // MARK: Zooming

    @objc func zoomIn(_ sender: Any?) {
        pdfView.zoomIn(sender)
    }

    @objc func zoomOut(_ sender: Any?) {
        pdfView.zoomOut(sender)
    }

    @objc func zoomToFit(_ sender: Any?) {
        pdfView.autoScales = true
    }

    // MARK: Finding

    override func performTextFinderAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag, let action = NSTextFinder.Action(rawValue: tag)
        else { return }
        switch action {
        case .showFindInterface: showFindBar()
        case .nextMatch: step(forward: true)
        case .previousMatch: step(forward: false)
        case .hideFindInterface: closeFindBar()
        default: break
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performTextFinderAction(_:)),
            let action = NSTextFinder.Action(rawValue: menuItem.tag)
        else { return true }
        switch action {
        case .showFindInterface: return true
        case .nextMatch, .previousMatch: return !matches.isEmpty
        case .hideFindInterface: return !findBar.isHidden
        default: return false
        }
    }

    /// Escape in the PDF closes the find bar, as it does in the field.
    override func cancelOperation(_ sender: Any?) {
        guard findBar.isHidden else { return closeFindBar() }
        // NSResponder has no cancelOperation: of its own to call.
        _ = nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
    }

    private func showFindBar() {
        if findBar.isHidden {
            findBar.isHidden = false
            resizeSubviews(withOldSize: bounds.size)
        }
        findBar.focus()
    }

    private func closeFindBar() {
        guard !findBar.isHidden else { return }
        endSearch()
        pdfView.setCurrentSelection(nil, animate: false)
        findBar.isHidden = true
        resizeSubviews(withOldSize: bounds.size)
        window?.makeFirstResponder(pdfView)
    }

    /// Searches for the find bar's text from the start, in place of the last
    /// search.
    private func find() {
        endSearch()
        guard !findBar.text.isEmpty, let document = pdfView.document else { return }
        // The page at the top of the view, where the user is reading;
        // `currentPage` is the one filling most of it.
        startPage = (pdfView.currentDestination?.page ?? pdfView.currentPage).map(document.index(for:)) ?? 0
        search = PDFSearch(
            finding: findBar.text, in: document,
            onMatch: { [weak self] match in self?.found(match) },
            onPage: { [weak self] in self?.showProgress() },
            onEnd: { [weak self] in self?.finish() })
    }

    private func endSearch() {
        search?.cancel()
        search = nil
        matches = []
        current = nil
        mark = nil
        pdfView.highlightedSelections = nil
        findBar.count = nil
    }

    private func found(_ match: PDFSelection) {
        match.color = .findHighlightColor
        matches.append(match)
        guard current == nil, let page = match.pages.first, let document = pdfView.document,
            document.index(for: page) >= startPage
        else { return }
        show(match: matches.count - 1)
    }

    // Highlighting every match as it arrives would copy the list each time,
    // thousands of times in a long PDF, so they are shown a page at a time.
    private func showProgress() {
        highlight()
        findBar.count = matches.isEmpty ? nil : matches.count
    }

    private func finish() {
        search = nil
        // No match after the starting page: the search wraps to the first.
        if current == nil, !matches.isEmpty { show(match: 0) }
        highlight()
        findBar.count = matches.count
    }

    private func step(forward: Bool) {
        guard !matches.isEmpty else { return }
        let next = current.map { ($0 + (forward ? 1 : matches.count - 1)) % matches.count } ?? 0
        show(match: next)
    }

    private func show(match index: Int) {
        current = index
        mark = matches[index].copy() as? PDFSelection
        mark?.color = .systemOrange
        highlight()
        pdfView.setCurrentSelection(matches[index], animate: true)
        pdfView.go(to: matches[index])
        findBar.count = matches.count
    }

    private func highlight() {
        pdfView.highlightedSelections = matches + (mark.map { [$0] } ?? [])
    }
}

/// One search of a PDF, its document's delegate while it runs. PDFKit sends
/// a match to the delegate the document had when it found it, so each
/// search has its own: matches still on their way from a cancelled search
/// land here and are dropped, rather than mixing into the next.
private final class PDFSearch: NSObject {
    private let document: PDFDocument
    private var onMatch: ((PDFSelection) -> Void)?
    private var onPage: (() -> Void)?
    private var onEnd: (() -> Void)?

    /// Starts finding `text` in `document`, ignoring case and accents.
    /// `onPage` follows each page searched, and `onEnd` the last.
    init(
        finding text: String, in document: PDFDocument, onMatch: @escaping (PDFSelection) -> Void,
        onPage: @escaping () -> Void, onEnd: @escaping () -> Void
    ) {
        self.document = document
        self.onMatch = onMatch
        self.onPage = onPage
        self.onEnd = onEnd
        super.init()
        document.delegate = self
        document.beginFindString(text, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    func cancel() {
        onMatch = nil
        onPage = nil
        onEnd = nil
        document.cancelFindString()
        if document.delegate === self { document.delegate = nil }
    }
}

// PDFKit begins a find on the calling thread and calls the delegate on the
// main thread, as checked against PDFKit on macOS 27.
extension PDFSearch: @preconcurrency PDFDocumentDelegate {
    func didMatchString(_ instance: PDFSelection) {
        onMatch?(instance)
    }

    func documentDidEndPageFind(_ notification: Notification) {
        onPage?()
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        onEnd?()
    }
}
