import SwiftUI
import AppKit
import WebKit
import MarkdownUI
import Highlightr

// MARK: - 文件预览:Markdown / 图片 / SVG / 代码高亮

/// 文件扩展名 → highlight.js 语言标识;nil = 交给 Highlightr 自动检测。
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

// ponytail: Highlightr 构造昂贵(起 JSContext + 加载 highlight.js + 主题 CSS,几十 ms)。
// 渲染全程主线程,按主题复用单例,省掉每个代码块/每次切文件的重建。非主线程访问不安全,本 app 不会。
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

/// 把 Highlightr 接成 MarkdownUI 的代码块高亮器 → md 里的 ``` 代码块也上色。
struct HljsCodeHighlighter: CodeSyntaxHighlighter {
    let dark: Bool
    func highlightCode(_ code: String, language: String?) -> Text {
        guard let hl = Highlighters.themed(highlightrTheme(dark: dark)),
              let ns = hl.highlight(code, as: language) else { return Text(code) }
        return Text(AttributedString(ns))
    }
}

/// 只读、可选中、自带滚动的代码视图,Highlightr 上色 + 主题底色。
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
        scroll.allowsMagnification = true     // 双指捏合缩放
        scroll.minMagnification = 0.5
        scroll.maxMagnification = 5.0
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.textContainerInset = NSSize(width: 14, height: 14)
            tv.isHorizontallyResizable = true                 // 长行横向滚动,不强制换行
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let hl = Highlighters.themed(highlightrTheme(dark: dark))   // ponytail: 复用池中实例,不再每次新建
        let attr = hl?.highlight(code, as: language)
            ?? NSAttributedString(string: code,
                                  attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        tv.textStorage?.setAttributedString(attr)
        tv.backgroundColor = hl?.theme.themeBackgroundColor ?? .textBackgroundColor
    }
}

// ponytail: SVG 是矢量 web 格式,NSImage 渲染不可靠;用 WKWebView 渲染。
// 安全:skill 多为第三方安装,SVG 可内嵌 <script>/onload。绝不把 svg 内联进可执行 HTML,而是
// base64 塞进 <img>(img 加载的 SVG 浏览器强制禁脚本/禁外部资源) + CSP + baseURL=nil 切断 file:// 本地读。
// 仍居中等比缩放,白底确保任意配色图标可见。
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

/// 按扩展名分流:.md → Markdown;位图 → NSImage;svg → WebView;其余 → 代码高亮。
struct FilePreview: View {
    let directory: String
    let file: String
    let content: String
    @Environment(\.colorScheme) private var scheme

    // 位图:NSImage 可靠加载;svg 是矢量,单独走 WebView。
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
                ContentUnavailableView("无法加载图片", systemImage: "photo")
            }
        } else {
            CodeTextView(code: content, language: hljsLanguage(for: ext), dark: scheme == .dark)
        }
    }

    private var markdownView: some View {
        ScrollView {
            Markdown(frontmatterAsYAML(content))
                .markdownCodeSyntaxHighlighter(HljsCodeHighlighter(dark: scheme == .dark))
                .markdownBlockStyle(\.codeBlock) { configuration in   // 代码块自适应换行,不横向溢出
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

    // ponytail: 开头的 YAML frontmatter,CommonMark 会把 --- 当 hr、字段当段落挤成一团(见反馈)。
    // 转成 ```yaml 代码块 → 走 Highlightr 高亮 + 代码块样式,逐行可读。无 frontmatter 则原样返回。
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
