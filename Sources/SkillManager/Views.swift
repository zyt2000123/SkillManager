import SwiftUI
import AppKit
import Translation

// MARK: - Design Tokens

enum Theme {
    static func platformColor(_ platform: String) -> Color {
        platform == "Claude Code" ? .orange : .blue
    }
    static func platformLabel(_ platform: String) -> String {
        platform == "Claude Code" ? "Claude" : "Codex"
    }
}

// MARK: - Resizable divider (narrow by default, detail pane takes remaining space)

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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let b = base ?? width                     // Lock the baseline when the gesture begins.
                        if base == nil { base = width }
                        width = min(max(b + v.translation.width, range.lowerBound), range.upperBound)
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

    var body: some View {
        List(selection: $selection) {
            Section("Navigation") {
                row("Skill Map", image: "map", tag: .skillMap, count: store.skills.count)
            }
            Section("Claude Code") {
                row("All", image: "square.grid.2x2", tag: .allPlatform("Claude Code"),
                    count: store.count(platform: "Claude Code"))
            }
            Section("Codex") {
                row("All", image: "chevron.left.forwardslash.chevron.right", tag: .allPlatform("Codex"),
                    count: store.count(platform: "Codex"))
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ title: String, image: String, tag: SidebarSelection, count: Int) -> some View {
        Label(title, systemImage: image).badge(count).tag(tag)
    }
}

// MARK: - Skill List

struct SkillListView: View {
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
                }
                if !skill.description.isEmpty {
                    Text(skill.description)
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
    @State private var fileTree: [FileTreeNode] = []   // Build once after loading; previews do not rebuild the tree.
    @State private var treeWidth: CGFloat = 240   // Default resizable file-tree width.
    @Environment(Translator.self) private var translator

    private var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()

            HStack(spacing: 0) {
                tabButton("Overview", tag: 0)
                tabButton("Files (\(loadedFiles.count))", tag: 1)
                Spacer()
            }
            .padding(.horizontal)
            .onChange(of: tab) { _, _ in previewFile = nil }

            Divider()

            if tab == 0 { overviewTab } else { filesTab }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: skill.id) {
            loadedFiles = []; fileTree = []   // Clear stale content immediately when switching skills.
            previewFile = nil; previewContent = ""   // Clear the previous file preview as well.
            // Recursively scan large skill directories off the main thread.
            let s = skill, st = store   // Capture on the main thread before entering the background closure.
            let files = await Task.detached { st.fileList(for: s) }.value
            loadedFiles = files
            fileTree = Self.buildFileTree(files)   // Build once and reuse during subsequent renders.
        }
    }

    private func zhText(_ s: String) -> String { translator.zh(s) }

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
                TagBadge(text: skill.category, color: .secondary)
                if let v = skill.version {
                    Text("v\(v)").font(.caption).foregroundStyle(.secondary)
                }
                if skill.isSymlink {
                    Label("Symbolic Link", systemImage: "arrow.up.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label("Auto-detected", systemImage: "bolt.fill")
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
                actionButton("Finder", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.directoryPath)])
                }
                actionButton("Edit", icon: "pencil") {
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
                    section("Description") {
                        Text(zhText(skill.summary.isEmpty ? skill.description : skill.summary))
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
                if !skill.useWhen.isEmpty {
                    section("When to Use") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(skill.useWhen, id: \.self) { s in
                                Label { Text(zhText(s)) } icon: { Image(systemName: "checkmark.circle") }
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !skill.proactive.isEmpty {
                    section("Proactive Triggers") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(skill.proactive, id: \.self) { s in
                                Label { Text(zhText(s)) } icon: { Image(systemName: "bolt.fill") }
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if !skill.triggers.isEmpty {
                    section("Trigger Keywords") {
                        FlowLayout(spacing: 6) {
                            ForEach(skill.triggers, id: \.self) { t in
                                TagBadge(text: t, color: .green)
                            }
                        }
                    }
                }
                if !skill.allowedTools.isEmpty {
                    section("Available Tools") {
                        FlowLayout(spacing: 6) {
                            ForEach(skill.allowedTools, id: \.self) { t in
                                TagBadge(text: t, color: .blue)
                            }
                        }
                    }
                }
                if !loadedFiles.isEmpty {
                    section("Directory Contents") {
                        let stats = directoryStats()
                        Text("\(stats.dirs) directories · \(stats.fileCount) files")
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
            .frame(width: treeWidth)                          // Start narrow.

            ResizeHandle(width: $treeWidth, range: 160...420)   // Resize from this divider only.

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
                ContentUnavailableView("Select a File to Preview", systemImage: "doc.text.magnifyingglass")
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
                        .fixedSize()                      // Preserve intrinsic width so long extensions do not wrap.
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
    .init(label: "Security & Audit", sfSymbol: "lock.shield", keywords: ["security", "audit", "ciso", "cso", "guard", "threat", "vulnerab"], color: .red),
    .init(label: "Code Review", sfSymbol: "eye", keywords: ["review", "design-review", "pr-review", "lint"], color: .purple),
    .init(label: "Debugging", sfSymbol: "ant", keywords: ["debug", "investigate", "diagnos", "troubleshoot", "health"], color: .orange),
    .init(label: "Planning", sfSymbol: "list.clipboard", keywords: ["plan", "autoplan", "roadmap", "spec", "rfc"], color: .blue),
    .init(label: "Documentation", sfSymbol: "book", keywords: ["doc", "document", "readme", "learn", "onboard"], color: .green),
    .init(label: "Deployment", sfSymbol: "paperplane", keywords: ["deploy", "ship", "land", "release", "ci", "cd"], color: .yellow),
    .init(label: "Testing", sfSymbol: "flask", keywords: ["test", "benchmark", "canary", "e2e", "coverage"], color: .cyan),
    .init(label: "Design", sfSymbol: "paintbrush", keywords: ["design", "ui", "ux", "css", "style", "mockup"], color: .pink),
    .init(label: "AI & Models", sfSymbol: "cpu", keywords: ["ai", "model", "llm", "prompt", "agent", "gpt"], color: .indigo),
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
        // Match only controlled short fields (name and triggers). Two-letter keywords such as ai/ui/ci/ml
        // produce excessive false positives in long descriptions and place skills in the wrong category.
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
            cat: MapCategory(label: "Other", sfSymbol: "shippingbox", keywords: [], color: .gray),
            skills: other
        ))
    }
    return result
}

struct SkillMapView: View {
    @Environment(SkillStore.self) private var store
    let skills: [Skill]
    let onSelect: (Skill) -> Void
    @State private var platformFilter: String? = nil
    @State private var collapsed: Set<String> = []   // Collapsed category IDs; empty means fully expanded.

    private var filtered: [Skill] {
        guard let pf = platformFilter else { return skills }
        return skills.filter { $0.platform == pf }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                filterBar
                    .padding()

                ForEach(categorize(filtered)) { group in
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
                    ContentUnavailableView("No Matching Skills", systemImage: "magnifyingglass")
                        .padding(.top, 40)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterPill("Installed", count: skills.count, active: platformFilter == nil) {
                platformFilter = nil
            }
            filterPill("Claude", count: skills.filter { $0.platform == "Claude Code" }.count,
                       color: .orange, active: platformFilter == "Claude Code") {
                platformFilter = platformFilter == "Claude Code" ? nil : "Claude Code"
            }
            filterPill("Codex", count: skills.filter { $0.platform == "Codex" }.count,
                       color: .blue, active: platformFilter == "Codex") {
                platformFilter = platformFilter == "Codex" ? nil : "Codex"
            }
            Spacer()
            Button("Check for Updates", systemImage: "arrow.clockwise") { Task { await store.scan() } }
                .font(.callout)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
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
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))   // Rotate 90 degrees when expanded.
                Image(systemName: group.cat.sfSymbol)
                    .foregroundStyle(group.cat.color)
                Text(group.cat.label)
                    .font(.headline)
                Spacer()
                Text("\(group.skills.count) skills")
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

    private func filterPill(_ label: String, count: Int, color: Color = .accentColor, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.callout).fontWeight(active ? .semibold : .regular)
                Text("\(count)")
                    .font(.caption.monospaced()).bold()
                    .foregroundStyle(active ? color : .secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(active ? AnyShapeStyle(color.opacity(0.15)) : AnyShapeStyle(.quaternary), in: .capsule)
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
                    }
                    let summary = skill.summary.isEmpty ? skill.description : skill.summary
                    if !summary.isEmpty {
                        Text(translator.zh(summary))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let p = skill.proactive.first {
                        Label { Text(translator.zh(p)) } icon: { Image(systemName: "bolt.fill") }
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
                ActionIconButton(icon: "folder", tip: "Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: skill.directoryPath)])
                }
                ActionIconButton(icon: "doc.on.doc", tip: "Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(skill.directoryPath, forType: .string)
                }
                ActionIconButton(icon: "pencil", tip: "Edit") {
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

    // Icon-only action button with themed hover feedback and a native tooltip.
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
            .help(tip)                                   // Native tooltip describing the action.
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        }
    }
}
