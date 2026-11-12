import Quartz

/// A PDF scrolling continuously, fitted to the pane's width until the user
/// zooms with a pinch, Cmd+= or Cmd+-; Cmd+0 fits it again.
final class PDFDocumentView: PDFView {
    init() {
        super.init(frame: .zero)
        displayMode = .singlePageContinuous
        displaysPageBreaks = true
        autoScales = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// Shows `document`. `keepingPlace` keeps the page, the point on it at
    /// the top of the view and the zoom, as when an agent writes the file
    /// again.
    func show(_ document: PDFDocument, keepingPlace: Bool) {
        guard keepingPlace, let old = self.document, let place = currentDestination, let page = place.page else {
            self.document = document
            return
        }
        let index = old.index(for: page)
        let scale = autoScales ? nil : scaleFactor
        self.document = document
        if let scale { scaleFactor = scale }
        guard let page = document.page(at: min(index, document.pageCount - 1)) else { return }
        go(to: PDFDestination(page: page, at: place.point))
    }

    @objc func zoomToFit(_ sender: Any?) {
        autoScales = true
    }
}
