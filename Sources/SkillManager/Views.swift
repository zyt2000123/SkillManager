import SwiftUI
import AppKit
import Translation

// MARK: - Design Tokens

enum Theme {
    static func platformColor(_ platform: String) -> Color {
        switch platform {
        case SkillPlatform.openClaw: return .teal
        case SkillPlatform.codex: return .blue
        case SkillPlatform.claudeCode: return .orange
        case SkillPlatform.hermess: return .purple
        default: return .accentColor
        }
    }

    static func platformLabel(_ platform: String) -> String {
        switch platform {
        case SkillPlatform.claudeCode: return "Claude"
        default: return platform
        }
    }

    static func platformIcon(_ platform: String) -> String {
        switch platform {
        case SkillPlatform.openClaw: return "pawprint"
        case SkillPlatform.codex: return "chevron.left.forwardslash.chevron.right"
        case SkillPlatform.claudeCode: return "square.grid.2x2"
        case SkillPlatform.hermess: return "bolt.horizontal"
        default: return "sparkles"
        }
    }

    static func installTypeColor(_ installType: String) -> Color {
        installType == SkillInstallType.plugin ? .indigo : .green
    }

    static func installTypeIcon(_ installType: String) -> String {
        installType == SkillInstallType.plugin ? "puzzlepiece.extension" : "folder"
    }
}

// MARK: - 可拖拽分隔条(默认窄,右侧最大)

struct ResizeHandle: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    @State private var base: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 8)
            .overlay(Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1))
            .contentShape(.rect)
            .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if base == nil { base = width }
                        let newWidth = min(max((base ?? width) + v.translation.width, range.lowerBound), range.upperBound)
                        width = newWidth
                    }
                    .onEnded { _ in base = nil }
            )
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (offset, sub) in zip(result.offsets, subviews) {
            sub.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxW = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            offsets.append(CGPoint(x: x, y: y))
            rowH = max(rowH, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (offsets, CGSize(width: maxX, height: y + rowH))
    }
}

// MARK: - Tag Badge

struct TagBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(SkillStore.self) private var store
    @Binding var selection: SidebarSelection?
    @State private var expandedPlatforms = Set(SkillPlatform.all)

    var body: some View {
        List(selection: $selection) {
            Section("导航") {
                row("Skill 地图", image: "map", tag: .skillMap, count: store.skills.count)
                Label("Skill 市场", systemImage: "storefront")
                    .tag(SidebarSelection.skillMarket)
                Label("Skill 分派", systemImage: "paperplane")
                    .tag(SidebarSelection.skillDispatch)
            }
            Section("Agent") {
                ForEach(SkillPlatform.all, id: \.self) { platform in
                    platformRow(platform)
                    if expandedPlatforms.contains(platform) {
                        agentChildRow(SkillInstallType.skill, image: Theme.installTypeIcon(SkillInstallType.skill),
                                      tag: .installType(platform: platform, installType: SkillInstallType.skill),
                                      count: store.count(platform: platform, installType: SkillInstallType.skill))
                        agentChildRow(SkillInstallType.plugin, image: Theme.installTypeIcon(SkillInstallType.plugin),
                                      tag: .installType(platform: platform, installType: SkillInstallType.plugin),
                                      count: store.count(platform: platform, installType: SkillInstallType.plugin))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func platformRow(_ platform: String) -> some View {
        let isExpanded = expandedPlatforms.contains(platform)
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                if isExpanded {
                    expandedPlatforms.remove(platform)
                } else {
                    expandedPlatforms.insert(platform)
                }
            }
        } label: {
            Label {
                Text(platform)
            } icon: {
                Image(systemName: Theme.platformIcon(platform))
                    .foregroundStyle(Theme.platformColor(platform))
            }
            .contentShape(.rect)
        }
        .badge(store.count(platform: platform))
        .buttonStyle(.plain)
        .help(isExpanded ? "收起 \(platform)" : "展开 \(platform)")
    }

    private func agentChildRow(_ title: String, image: String, tag: SidebarSelection, count: Int) -> some View {
        Label(title, systemImage: image)
            .badge(count)
            .padding(.leading, 26)
            .tag(tag)
    }

    private func row(_ title: String, image: String, tag: SidebarSelection, count: Int) -> some View {
        Label(title, systemImage: image).badge(count).tag(tag)
    }
}

// MARK: - Skill Market

struct SkillMarketView: View {
    let search: String
    let market: SkillMarketStore

    private var filteredPlugins: [SkillMarketPlugin] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return market.plugins }
        return market.plugins.filter { plugin in
            plugin.name.lowercased().contains(query)
            || plugin.description.lowercased().contains(query)
            || plugin.sourceTitle.lowercased().contains(query)
            || plugin.platforms.contains { $0.lowercased().contains(query) }
            || plugin.keywords.contains { $0.lowercased().contains(query) }
        }
    }

    private var sourceSummary: String {
        if market.isLoading {
            return "正在从 GitHub 市场源同步..."
        }
        return "\(market.loadedSourceCount)/\(market.sources.count) 个市场源 · \(market.plugins.count) 个插件"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                sourceStrip
                pluginGrid
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await market.refreshIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Skill Market")
                    .font(.largeTitle.bold())
                Text("发现 GitHub 上的 Agent Skill 与 Plugin 市场源，先浏览、评估、复制安装命令。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(sourceSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await market.refresh() }
            } label: {
                Label(market.isLoading ? "同步中" : "刷新", systemImage: "arrow.clockwise")
            }
            .disabled(market.isLoading)
            .buttonStyle(.borderedProminent)
        }
    }

    private var sourceStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("市场源")
                    .font(.headline)
                Spacer()
                if let error = market.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                ForEach(market.sources) { source in
                    SkillMarketSourceCard(source: source)
                }
            }
        }
    }

    private var pluginGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("插件")
                    .font(.headline)
                Spacer()
                Text("\(filteredPlugins.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if market.isLoading && market.plugins.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if filteredPlugins.isEmpty {
                ContentUnavailableView("没有匹配的市场插件", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 12)], spacing: 12) {
                    ForEach(filteredPlugins) { plugin in
                        SkillMarketPluginCard(plugin: plugin)
                    }
                }
            }
        }
    }
}

private struct SkillMarketSourceCard: View {
    @Environment(Translator.self) private var translator
    let source: SkillMarketSource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(source.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    NSWorkspace.shared.open(source.repositoryURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("打开 GitHub 仓库")
            }

            Text(translator.text(source.description))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            FlowLayout(spacing: 6) {
                ForEach(source.platforms, id: \.self) { platform in
                    TagBadge(text: Theme.platformLabel(platform), color: Theme.platformColor(platform))
                }
            }

            if let command = source.marketplaceAddCommands.first {
                commandRow(command, tip: "复制市场添加命令")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(.quaternary.opacity(0.65), in: .rect(cornerRadius: 8))
    }
}

private struct SkillMarketPluginCard: View {
    @Environment(Translator.self) private var translator
    let plugin: SkillMarketPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(plugin.name)
                    .font(.headline)
                    .lineLimit(1)
                if let version = plugin.version {
                    Text("v\(version)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                openButton
            }

            FlowLayout(spacing: 6) {
                ForEach(plugin.platforms, id: \.self) { platform in
                    TagBadge(text: Theme.platformLabel(platform), color: Theme.platformColor(platform))
                }
                if let category = plugin.category {
                    TagBadge(text: translator.text(category), color: .secondary)
                }
                TagBadge(text: plugin.sourceTitle, color: .blue)
            }

            Text(translator.text(plugin.description.isEmpty ? "No description" : plugin.description))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 52, alignment: .topLeading)

            if let author = plugin.author {
                Label(author, systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let command = plugin.installCommands.first {
                commandRow(command, tip: "复制安装命令")
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.75), lineWidth: 1)
        )
    }

    private var openButton: some View {
        Button {
            if let url = plugin.repositoryURL ?? plugin.homepageURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Image(systemName: "arrow.up.right.square")
        }
        .disabled(plugin.repositoryURL == nil && plugin.homepageURL == nil)
        .buttonStyle(.plain)
        .help("打开 GitHub 仓库")
    }
}

private func commandRow(_ command: String, tip: String) -> some View {
    HStack(spacing: 8) {
        Text(command)
            .font(.caption.monospaced())
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        Spacer(minLength: 4)
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.plain)
        .help(tip)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(.black.opacity(0.06), in: .rect(cornerRadius: 6))
}

// MARK: - Skill List

struct SkillListView: View {
    @Environment(Translator.self) private var translator
    let skills: [Skill]
    @Binding var selectedId: String?

    var body: some View {
        List(skills, selection: $selectedId) { skill in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(skill.name).font(.body).bold()
                    if let v = skill.version {
                        Text("v\(v)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                    if skill.isSymlink {
                        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(skill.installType)
                        .font(.caption)
                        .foregroundStyle(Theme.installTypeColor(skill.installType))
                }
                if !skill.description.isEmpty {
                    Text(translator.text(skill.summary.isEmpty ? skill.description : skill.summary))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 3)
            .tag(skill.id)
        }
        .listStyle(.inset)
    }
}

// MARK: - Skill Detail

struct SkillDetailView: View {
    let skill: Skill
    @Environment(SkillStore.self) private var store
    @State private var tab = 0
    @State private var previewFile: String?
    @State private var previewContent = ""
    @State private var loadedFiles: [String] = []
    @State private var fileTree: [FileTreeNode] = []   // ponytail: fileList 后建一次,选文件预览不再反复重排
    @State private var treeWidth: CGFloat = 240   // 文件树默认宽度(可拖)
    @Environment(Translator.self) private var translator

    private var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            HStack(spacing: 0) {
                tabButton("概览", tag: 0)
                tabButton("文件 (\(loadedFiles.count))", tag: 1)
                Spacer()
            }
            .padding(.horizontal)
            .onChange(of: tab) { _, _ in previewFile = nil }

            Divider()

            if tab == 0 { overviewTab } else { filesTab }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: skill.id) {
            loadedFiles = []; fileTree = []   // 切换瞬间清空旧内容,UI 立即响应
            previewFile = nil; previewContent = ""   // 切 skill 也清掉旧文件预览,不残留
            // 递归遍历目录(某些 skill 上百文件)放后台线程跑,不阻塞主线程
            let s = skill, st = store   // 在主线程捕获,再传入后台闭包
            let files = await Task.detached { st.fileList(for: s) }.value
            loadedFiles = files
            fileTree = Self.buildFileTree(files)   // 一次性建树,后续渲染直接复用
        }
    }

    private func translatedText(_ s: String) -> String { translator.text(s) }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(skill.name)
                    .font(.title2).bold()
                Spacer()
            }

            HStack(spacing: 6) {
                TagBadge(text: skill.platform, color: Theme.platformColor(skill.platform))
                TagBadge(text: skill.installType, color: Theme.installTypeColor(skill.installType))
                TagBadge(text: skill.category, color: .secondary)
                if let v = skill.version {
                    Text("v\(v)").font(.caption).foregroundStyle(.secondary)
                }
                if skill.isSymlink {
                    Label("符号链接", systemImage: "arrow.up.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label("自动检测", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: .capsule)
            }

            Label {
                Text(skill.directoryPath.replacingOccurrences(of: homePath, with: "~") + "/")
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                actionButton("访达", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.directoryPath)])
                }
                actionButton("编辑", icon: "pencil") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: skill.directoryPath + "/SKILL.md"))
                }
            }
        }
    }

    private func tabButton(_ title: String, tag: Int) -> some View {
        Button {
            tab = tag
        } label: {
            VStack(spacing: 5) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(tab == tag ? Color.primary : .secondary)
                Rectangle()
                    .fill(tab == tag ? Color.accentColor : .clear)
                    .frame(height: 2)
            }
            .frame(width: 96)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !skill.description.isEmpty {
                    section("描述") {
                        Text(translatedText(skill.summary.isEmpty ? skill.description : skill.summary))
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
                if !skill.useWhen.isEmpty {
                    section("适用场景") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(skill.useWhen, id: \.self) { s in
                                Label { Text(translatedText(s)) } icon: { Image(systemName: "checkmark.circle") }
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !skill.proactive.isEmpty {
                    section("主动触发规则") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(skill.proactive, id: \.self) { s in
                                Label { Text(translatedText(s)) } icon: { Image(systemName: "bolt.fill") }
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if !skill.triggers.isEmpty {
                    section("触发词") {
                        FlowLayout(spacing: 6) {
                            ForEach(skill.triggers, id: \.self) { t in
                                TagBadge(text: t, color: .green)
                            }
                        }
                    }
                }
                if !skill.allowedTools.isEmpty {
                    section("可用工具") {
                        FlowLayout(spacing: 6) {
                            ForEach(skill.allowedTools, id: \.self) { t in
                                TagBadge(text: t, color: .blue)
                            }
                        }
                    }
                }
                if !loadedFiles.isEmpty {
                    section("目录内容") {
                        let stats = directoryStats()
                        Text("\(stats.dirs) 个目录 · \(stats.fileCount) 个文件")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(fileSummary(), id: \.ext) { item in
                                HStack(spacing: 5) {
                                    Text(item.ext)
                                        .font(.caption.monospaced().bold())
                                        .foregroundStyle(extColor(item.ext))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(extColor(item.ext).opacity(0.15), in: .rect(cornerRadius: 4))
                                    Text("\(extLabel(item.ext)): \(item.count)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Files (tree)

    @ViewBuilder
    private var filesTab: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(fileTree) { node in
                        fileTreeRow(node)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(width: treeWidth)

            ResizeHandle(width: $treeWidth, range: 160...420)
                .transaction { t in t.animation = nil }

            if let file = previewFile {
                VStack(alignment: .leading, spacing: 0) {
                    Text(file)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(10)
                    Divider()
                    FilePreview(directory: skill.directoryPath, file: file, content: previewContent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("选择文件以预览", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func fileTreeRow(_ node: FileTreeNode) -> some View {
        if node.isDirectory {
            Label(node.name + "/", systemImage: "folder.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, CGFloat(node.depth) * 16 + 10)
                .padding(.vertical, 3)
        } else {
            Button {
                previewFile = node.path
                previewContent = store.readFile(directory: skill.directoryPath, relative: node.path)
            } label: {
                HStack(spacing: 6) {
                    let ext = URL(fileURLWithPath: node.name).pathExtension.lowercased()
                    Text(ext.isEmpty ? "?" : ext)
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(extColor(ext))
                        .fixedSize()                      // ponytail: 用理想宽度,长扩展名(yaml)不再折行
                        .frame(minWidth: 22)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(extColor(ext).opacity(0.15), in: .rect(cornerRadius: 4))
                    Text(node.name)
                        .font(.callout.monospaced())
                        .foregroundStyle(previewFile == node.path ? Color.primary : .secondary)
                }
                .padding(.leading, CGFloat(node.depth) * 16 + 10)
                .padding(.vertical, 4)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(previewFile == node.path ? Color.accentColor.opacity(0.15) : .clear,
                            in: .rect(cornerRadius: 5))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private struct FileStat: Hashable { let ext: String; let count: Int }

    private func fileSummary() -> [FileStat] {
        var groups: [String: Int] = [:]
        for f in loadedFiles {
            let ext = URL(fileURLWithPath: f).pathExtension.lowercased()
            groups[ext.isEmpty ? "other" : ext, default: 0] += 1
        }
        return groups.map { FileStat(ext: $0.key, count: $0.value) }.sorted { $0.ext < $1.ext }
    }

    private func directoryStats() -> (dirs: Int, fileCount: Int) {
        var dirs: Set<String> = []
        for f in loadedFiles {
            let parts = f.split(separator: "/")
            if parts.count > 1 {
                for i in 0..<(parts.count - 1) {
                    dirs.insert(parts[0...i].joined(separator: "/"))
                }
            }
        }
        return (dirs.count, loadedFiles.count)
    }

    private func extColor(_ ext: String) -> Color {
        switch ext {
        case "py": return .green
        case "md": return .blue
        case "yaml", "yml": return .orange
        case "sh": return .purple
        case "ts", "tsx", "js": return .yellow
        default: return .gray
        }
    }

    private func extLabel(_ ext: String) -> String {
        switch ext {
        case "py": return "Python"
        case "md": return "Markdown"
        case "yaml", "yml": return "YAML"
        case "sh": return "Shell"
        case "ts": return "TypeScript"
        case "tsx": return "TSX"
        case "js": return "JavaScript"
        default: return ext.uppercased()
        }
    }

    struct FileTreeNode: Identifiable {
        let id: String
        let name: String
        let path: String
        let depth: Int
        let isDirectory: Bool
    }

    static func buildFileTree(_ files: [String]) -> [FileTreeNode] {
        var nodes: [FileTreeNode] = []
        var seenDirs: Set<String> = []

        for file in files.sorted() {
            let parts = file.split(separator: "/").map(String.init)
            for i in 0..<(parts.count - 1) {
                let dirPath = parts[0...i].joined(separator: "/")
                if !seenDirs.contains(dirPath) {
                    seenDirs.insert(dirPath)
                    nodes.append(FileTreeNode(
                        id: "dir-\(dirPath)",
                        name: parts[i],
                        path: dirPath,
                        depth: i,
                        isDirectory: true
                    ))
                }
            }
            nodes.append(FileTreeNode(
                id: "file-\(file)",
                name: parts.last ?? file,
                path: file,
                depth: parts.count - 1,
                isDirectory: false
            ))
        }
        return nodes
    }
}

// MARK: - Skill Map

private struct MapCategory {
    let label: String
    let sfSymbol: String
    let keywords: [String]
    let color: Color
}

private let mapCategories: [MapCategory] = [
    .init(label: "安全与审计", sfSymbol: "lock.shield", keywords: ["security", "audit", "ciso", "cso", "guard", "threat", "vulnerab"], color: .red),
    .init(label: "代码审查", sfSymbol: "eye", keywords: ["review", "design-review", "pr-review", "lint"], color: .purple),
    .init(label: "调试排查", sfSymbol: "ant", keywords: ["debug", "investigate", "diagnos", "troubleshoot", "health"], color: .orange),
    .init(label: "规划", sfSymbol: "list.clipboard", keywords: ["plan", "autoplan", "roadmap", "spec", "rfc"], color: .blue),
    .init(label: "文档", sfSymbol: "book", keywords: ["doc", "document", "readme", "learn", "onboard"], color: .green),
    .init(label: "部署发布", sfSymbol: "paperplane", keywords: ["deploy", "ship", "land", "release", "ci", "cd"], color: .yellow),
    .init(label: "测试", sfSymbol: "flask", keywords: ["test", "benchmark", "canary", "e2e", "coverage"], color: .cyan),
    .init(label: "设计", sfSymbol: "paintbrush", keywords: ["design", "ui", "ux", "css", "style", "mockup"], color: .pink),
    .init(label: "AI 与模型", sfSymbol: "cpu", keywords: ["ai", "model", "llm", "prompt", "agent", "gpt"], color: .indigo),
]

private struct CatGroup: Identifiable {
    let id: String
    let cat: MapCategory
    let skills: [Skill]
}

private func categorize(_ skills: [Skill]) -> [CatGroup] {
    var buckets = [[Skill]](repeating: [], count: mapCategories.count)
    var other: [Skill] = []

    for s in skills {
        // ponytail: 只匹配受控短字段(名字+触发词)。description 太长,2-字母关键词(ai/ui/ci/ml)
        // 会在 "html"/"build"/"especially" 里满世界误命中,把技能塞错格子。
        let haystack = "\(s.name) \(s.triggers.joined(separator: " "))".lowercased()
        if let i = mapCategories.firstIndex(where: { $0.keywords.contains { haystack.contains($0) } }) {
            buckets[i].append(s)
        } else {
            other.append(s)
        }
    }

    var result = zip(mapCategories, buckets)
        .filter { !$0.1.isEmpty }
        .map { CatGroup(id: $0.0.label, cat: $0.0, skills: $0.1) }
    if !other.isEmpty {
        result.append(CatGroup(
            id: "Other",
            cat: MapCategory(label: "其他", sfSymbol: "shippingbox", keywords: [], color: .gray),
            skills: other
        ))
    }
    return result
}

struct SkillMapView: View {
    @Environment(SkillStore.self) private var store
    let skills: [Skill]
    let onSelect: (Skill) -> Void
    @State private var selectedPlatform: String?
    @State private var collapsed: Set<String> = []
    @State private var cachedCounts: [String: Int] = [:]
    @State private var categorizedGroups: [CatGroup] = []

    private var filtered: [Skill] {
        guard let selectedPlatform else { return skills }
        return skills.filter { $0.platform == selectedPlatform }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(categorizedGroups) { group in
                        Section {
                            if !collapsed.contains(group.id) {
                                ForEach(group.skills) { skill in
                                    SkillMapRow(skill: skill, onSelect: onSelect)
                                }
                                .padding(.horizontal)
                            }
                        } header: {
                            sectionHeader(group)
                        }
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView("没有匹配的技能", systemImage: "magnifyingglass")
                            .padding(.top, 40)
                    }
                }
                .padding(.top)
            }
        }
        .onChange(of: skills) { _, _ in
            refresh()
        }
        .onChange(of: selectedPlatform) { _, _ in
            updateCategories()
        }
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        updateCounts()
        updateCategories()
    }

    private func updateCounts() {
        var counts = ["__all": skills.count]
        for platform in SkillPlatform.all {
            counts[platform] = skills.filter { $0.platform == platform }.count
        }
        cachedCounts = counts
    }

    private func updateCategories() {
        categorizedGroups = categorize(filtered)
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            tabButton("已安装", count: cachedCounts["__all"] ?? skills.count, platform: nil)
            ForEach(SkillPlatform.all, id: \.self) { platform in
                tabButton(
                    Theme.platformLabel(platform),
                    count: cachedCounts[platform] ?? 0,
                    color: Theme.platformColor(platform),
                    platform: platform
                )
            }
            Spacer()
            Button("检查更新", systemImage: "arrow.clockwise") {
                Task { await store.scan() }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding()
        .background(.bar)
    }

    private func tabButton(_ label: String, count: Int, color: Color = .accentColor, platform: String?) -> some View {
        let isSelected = selectedPlatform == platform
        return Button {
            selectedPlatform = platform
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption.monospaced())
                    .bold()
                    .foregroundStyle(isSelected ? color : .secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                isSelected ? AnyShapeStyle(color.opacity(0.15)) : AnyShapeStyle(.quaternary),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ group: CatGroup) -> some View {
        let isCollapsed = collapsed.contains(group.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isCollapsed { collapsed.remove(group.id) } else { collapsed.insert(group.id) }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))   // 展开转 90°
                Image(systemName: group.cat.sfSymbol)
                    .foregroundStyle(group.cat.color)
                Text(group.cat.label)
                    .font(.headline)
                Spacer()
                Text("\(group.skills.count) 个技能")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(.rect)
            .background(.bar)
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Skill Map Row (own hover state, per views.md guidance)

private struct SkillMapRow: View {
    @Environment(Translator.self) private var translator
    let skill: Skill
    let onSelect: (Skill) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button { onSelect(skill) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(skill.name).font(.body).bold()
                        Text(Theme.platformLabel(skill.platform))
                            .font(.caption)
                            .foregroundStyle(Theme.platformColor(skill.platform))
                        Text(skill.installType)
                            .font(.caption)
                            .foregroundStyle(Theme.installTypeColor(skill.installType))
                    }
                    let summary = skill.summary.isEmpty ? skill.description : skill.summary
                    if !summary.isEmpty {
                        Text(translator.text(summary))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let p = skill.proactive.first {
                        Label { Text(translator.text(p)) } icon: { Image(systemName: "bolt.fill") }
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Action icons — always visible
            HStack(spacing: 10) {
                ActionIconButton(icon: "folder", tip: "在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.directoryPath)])
                }
                ActionIconButton(icon: "doc.on.doc", tip: "拷贝路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(skill.directoryPath, forType: .string)
                }
                ActionIconButton(icon: "pencil", tip: "编辑") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: skill.directoryPath + "/SKILL.md"))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
        }
    }

    // 纯图标操作按钮:悬浮时变主题色 + 圆角高亮底,并带原生 tooltip 说明用途。
    private struct ActionIconButton: View {
        let icon: String
        let tip: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .foregroundStyle(hovering ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tip)                                   // 原生悬浮提示:说明按钮用途
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        }
    }
}
