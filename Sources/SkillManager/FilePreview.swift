import SwiftUI
import AppKit
import WebKit
import MarkdownUI
import Highlightr

// MARK: - File preview: Markdown, images, SVG, and syntax-highlighted code

/// Maps file extensions to highlight.js language identifiers; nil lets Highlightr auto-detect.
func hljsLanguage(for ext: String) -> String? {
    switch ext {
    case "js", "mjs", "cjs", "jsx": return "javascript"
    case "ts", "tsx": return "typescript"
    case "py": return "python"
    case "sh", "bash", "zsh", "env": return "bash"
    case "yaml", "yml": return "yaml"
    case "json": return "json"
    case "swift": return "swift"
    case "rb": return "ruby"
    case "go": return "go"
    case "rs": return "rust"
    case "java": return "java"
    case "c", "h": return "c"
    case "cpp", "cc", "hpp": return "cpp"
    case "html", "xml": return "xml"
    case "css": return "css"
    case "sql": return "sql"
    case "toml": return "ini"
    default: return nil
    }
}

private func highlightrTheme(dark: Bool) -> String { dark ? "atom-one-dark" : "atom-one-light" }

// Highlightr initialization is expensive because it starts a JSContext and loads highlight.js and theme CSS.
// Rendering stays on the main thread, so reuse one instance per theme instead of rebuilding it for every block.
enum Highlighters {
    nonisolated(unsafe) private static var pool: [String: Highlightr] = [:]
    static func themed(_ theme: String) -> Highlightr? {
        if let h = pool[theme] { return h }
        guard let h = Highlightr() else { return nil }
        h.setTheme(to: theme)
        pool[theme] = h
        return h
    }
}

/// Connects Highlightr to MarkdownUI so fenced code blocks receive syntax highlighting.
struct HljsCodeHighlighter: CodeSyntaxHighlighter {
    let dark: Bool
    func highlightCode(_ code: String, language: String?) -> Text {
        guard let hl = Highlighters.themed(highlightrTheme(dark: dark)),
              let ns = hl.highlight(code, as: language) else { return Text(code) }
        return Text(AttributedString(ns))
    }
}

/// A read-only, selectable, scrollable code view with syntax highlighting and a themed background.
struct CodeTextView: NSViewRepresentable {
    let code: String
    let language: String?
    let dark: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.allowsMagnification = true     // Support pinch-to-zoom.
        scroll.minMagnification = 0.5
        scroll.maxMagnification = 5.0
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.textContainerInset = NSSize(width: 14, height: 14)
            tv.isHorizontallyResizable = true                 // Scroll long lines horizontally instead of wrapping.
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let hl = Highlighters.themed(highlightrTheme(dark: dark))   // Reuse the pooled instance.
        let attr = hl?.highlight(code, as: language)
            ?? NSAttributedString(string: code,
                                  attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        tv.textStorage?.setAttributedString(attr)
        tv.backgroundColor = hl?.theme.themeBackgroundColor ?? .textBackgroundColor
    }
}

// SVG is a vector web format that NSImage does not render reliably, so use WKWebView.
// Security: skills often come from third parties, and SVG can embed scripts or onload handlers. Never inline
// the SVG into executable HTML. Load its base64 data through <img>, apply a strict CSP, and use a nil base URL
// to prevent file:// access. Keep the image centered and scaled on white so any icon palette remains visible.
struct WebFilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ web: WKWebView, context: Context) {
        let b64 = ((try? Data(contentsOf: url)) ?? Data()).base64EncodedString()
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>html,body{margin:0;height:100%;background:#fff}
        body{display:flex;align-items:center;justify-content:center;box-sizing:border-box;padding:24px}
        img{max-width:100%;max-height:100%;width:auto;height:auto}</style>
        </head><body><img src="data:image/svg+xml;base64,\(b64)"></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }
}

/// Routes by extension: Markdown, bitmap images, SVG through WebView, and syntax-highlighted code otherwise.
struct FilePreview: View {
    let directory: String
    let file: String
    let content: String
    @Environment(\.colorScheme) private var scheme

    // NSImage reliably loads bitmap formats; SVG uses the dedicated WebView path.
    private static let bitmapExts: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp", "ico"]

    var body: some View {
        let ext = (file as NSString).pathExtension.lowercased()
        let url = URL(fileURLWithPath: directory).appending(path: file)
        if ext == "md" || ext == "markdown" {
            markdownView
        } else if ext == "svg" {
            WebFilePreview(url: url)
        } else if Self.bitmapExts.contains(ext) {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ContentUnavailableView("Unable to Load Image", systemImage: "photo")
            }
        } else {
            CodeTextView(code: content, language: hljsLanguage(for: ext), dark: scheme == .dark)
        }
    }

    private var markdownView: some View {
        ScrollView {
            Markdown(frontmatterAsYAML(content))
                .markdownCodeSyntaxHighlighter(HljsCodeHighlighter(dark: scheme == .dark))
                .markdownBlockStyle(\.codeBlock) { configuration in   // Wrap code blocks to avoid horizontal overflow.
                    configuration.label
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
                        .padding(.vertical, 6)
                }
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // CommonMark treats opening YAML frontmatter as a horizontal rule followed by dense paragraphs.
    // Convert it to a fenced YAML block for readable highlighting; return content unchanged when absent.
    private func frontmatterAsYAML(_ raw: String) -> String {
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return raw }
        let yaml = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...].joined(separator: "\n")
        return "```yaml\n\(yaml)\n```\n\n\(body)"
    }
}
