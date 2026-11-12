import BeamCore
import Testing

/// Type identifiers as `UTType` lists them on macOS 27: each extension's own
/// type, then what it conforms to.
struct DocumentKindTests {
    static let types: [String: Set<String>] = [
        "md": ["net.daringfireball.markdown", "public.utf8-plain-text", "public.plain-text", "public.text"],
        "mdown": ["dyn.ah62d4rv4ge8043dts71a", "public.data"],
        "txt": ["public.plain-text", "public.text", "public.data"],
        "log": ["com.apple.log", "public.log", "public.plain-text", "public.text", "public.data"],
        "csv": ["public.comma-separated-values-text", "public.plain-text", "public.text", "public.data"],
        "rtf": ["public.rtf", "public.text", "public.data"],
        "pdf": ["com.adobe.pdf", "public.data"],
        "png": ["public.png", "public.image", "public.data"],
        "heic": ["public.heic", "public.image", "public.data"],
        "svg": ["public.svg-image", "public.image", "public.xml", "public.text", "public.data"],
        "docx": ["org.openxmlformats.wordprocessingml.document", "public.data"],
        "pages": ["com.apple.iwork.pages.sffpages", "public.data"],
        "mov": ["com.apple.quicktime-movie", "public.movie", "public.audiovisual-content", "public.data"],
        "m4a": ["com.apple.m4a-audio", "public.audio", "public.audiovisual-content", "public.data"],
        "ts": ["public.mpeg-2-transport-stream", "public.movie", "public.audiovisual-content", "public.data"],
        "swift": ["public.swift-source", "public.source-code", "public.plain-text", "public.text", "public.data"],
        "js": [
            "com.netscape.javascript-source", "public.script", "public.source-code", "public.plain-text",
            "public.text", "public.data",
        ],
        "sh": ["public.shell-script", "public.script", "public.source-code", "public.plain-text", "public.text"],
        "json": ["public.json", "public.text", "public.data"],
        "yaml": ["public.yaml", "public.text", "public.data"],
        "toml": ["public.toml", "public.text", "public.data"],
        "xml": ["public.xml", "public.text", "public.data"],
        "plist": ["com.apple.property-list", "public.data"],
        "html": ["public.html", "public.text", "public.data"],
        "go": ["dyn.ah62d4rv4ge80s52", "public.data"],
    ]

    func kind(_ name: String, chosen: Bool = false) -> DocumentKind {
        let ext = String(name.split(separator: ".").last ?? "")
        return DocumentKind(
            path: "/Users/me/project/" + name, types: Self.types[ext] ?? ["public.data"], chosen: chosen)
    }

    @Test func documentsShowInBeam() {
        #expect(kind("plan.md") == .markdown)
        #expect(kind("notes.txt") == .text)
        #expect(kind("build.log") == .text)
        #expect(kind("data.csv") == .text)
        #expect(kind("letter.rtf") == .text)
        #expect(kind("report.pdf") == .pdf)
        #expect(kind("shot.png") == .image)
        #expect(kind("photo.heic") == .image)
        #expect(kind("clip.mov") == .quickLook)
        #expect(kind("voice.m4a") == .quickLook)
    }

    /// CoreSVG draws it; it is also XML, which would otherwise send it to the
    /// editor.
    @Test func svgIsAnImage() {
        #expect(kind("diagram.svg") == .image)
    }

    /// Two of these are dynamic types macOS knows nothing about.
    @Test func markdownGoesByItsExtensionsToo() {
        #expect(kind("notes.mdown") == .markdown)
        #expect(kind("notes.mkd") == .markdown)
        #expect(kind("NOTES.MARKDOWN") == .markdown)
    }

    @Test func codeAndConfigGoToTheEditorFromAClick() {
        for name in [
            "main.swift", "app.js", "run.sh", "package.json", "config.yaml", "Cargo.toml", "layout.xml", "Info.plist",
            "main.go",
        ] {
            #expect(kind(name) == .external, "\(name)")
        }
    }

    /// macOS files them as transport stream video.
    @Test func typeScriptIsCodeNotVideo() {
        #expect(kind("src/app.ts") == .external)
        #expect(kind("src/app.ts", chosen: true) == .text)
    }

    @Test func officeAndIWorkGoToTheirApp() {
        #expect(kind("brief.docx") == .external)
        #expect(kind("poster.pages") == .external)
    }

    @Test func webPagesNeverShowInBeamFromAClick() {
        #expect(kind("index.html") == .external)
    }

    /// The user picked Beam, so it shows what it can and says when it cannot.
    @Test func aChosenFileShowsCodeAndUnknownFilesAsText() {
        #expect(kind("main.swift", chosen: true) == .text)
        #expect(kind("index.html", chosen: true) == .text)
        #expect(kind("main.go", chosen: true) == .text)
        #expect(kind("brief.docx", chosen: true) == .text)
        #expect(kind("report.pdf", chosen: true) == .pdf)
        #expect(kind("diagram.svg", chosen: true) == .image)
    }
}
