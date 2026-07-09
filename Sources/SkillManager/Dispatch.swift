import SwiftUI
import AppKit
import Observation

struct DispatchSkill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let directoryURL: URL
}

struct DispatchTarget: Identifiable, Hashable {
    let platform: String
    let directoryURL: URL

    var id: String { platform }
}

@MainActor @Observable
final class SkillDispatchStore {
    var centerURL: URL
    var skills: [DispatchSkill] = []
    var selectedSkillIDs: Set<String> = []
    var selectedPlatforms: Set<String> = Set(SkillPlatform.all)
    var isDispatching = false
    var message: String?

    private static let centerDefaultsKey = "SkillManager.dispatchCenterPath"

    init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        if let saved = UserDefaults.standard.string(forKey: Self.centerDefaultsKey) {
            centerURL = URL(fileURLWithPath: saved)
        } else {
            centerURL = home.appending(path: ".skillmanager/center")
        }
    }

    var targets: [DispatchTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            .init(platform: SkillPlatform.openClaw, directoryURL: home.appending(path: ".openclaw/skills")),
            .init(platform: SkillPlatform.codex, directoryURL: home.appending(path: ".codex/skills")),
            .init(platform: SkillPlatform.claudeCode, directoryURL: home.appending(path: ".claude/skills")),
            .init(platform: SkillPlatform.hermess, directoryURL: home.appending(path: ".hermess/skills")),
        ]
    }

    var selectedSkills: [DispatchSkill] {
        if selectedSkillIDs.isEmpty {
            return skills
        }
        return skills.filter { selectedSkillIDs.contains($0.id) }
    }

    func setCenterURL(_ url: URL) {
        centerURL = url
        UserDefaults.standard.set(url.path, forKey: Self.centerDefaultsKey)
        scan()
    }

    func ensureCenterExists() {
        try? FileManager.default.createDirectory(at: centerURL, withIntermediateDirectories: true)
        scan()
    }

    func scan() {
        ensureDirectory(centerURL)
        let scanned = Self.scanSkills(under: centerURL)
        skills = scanned
        selectedSkillIDs = selectedSkillIDs.intersection(Set(scanned.map(\.id)))
        message = scanned.isEmpty ? "中心仓库还没有可分派的 Skill" : "已扫描 \(scanned.count) 个中心 Skill"
    }

    func toggleSkill(_ skill: DispatchSkill) {
        if selectedSkillIDs.contains(skill.id) {
            selectedSkillIDs.remove(skill.id)
        } else {
            selectedSkillIDs.insert(skill.id)
        }
    }

    func togglePlatform(_ platform: String) {
        if selectedPlatforms.contains(platform) {
            selectedPlatforms.remove(platform)
        } else {
            selectedPlatforms.insert(platform)
        }
    }

    func dispatchSelected() async {
        let skillBatch = selectedSkills
        let targetBatch = targets.filter { selectedPlatforms.contains($0.platform) }
        guard !skillBatch.isEmpty else {
            message = "没有可分派的 Skill"
            return
        }
        guard !targetBatch.isEmpty else {
            message = "请至少选择一个 Agent"
            return
        }

        isDispatching = true
        defer { isDispatching = false }

        do {
            var copied = 0
            for target in targetBatch {
                ensureDirectory(target.directoryURL)
                for skill in skillBatch {
                    try Self.copySkill(skill, to: target.directoryURL)
                    copied += 1
                }
            }
            message = "已分派 \(skillBatch.count) 个 Skill 到 \(targetBatch.count) 个 Agent，共 \(copied) 份"
        } catch {
            message = "分派失败：\(error.localizedDescription)"
        }
    }

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func scanSkills(under root: URL) -> [DispatchSkill] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var dirs: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "SKILL.md" {
            dirs.append(url.deletingLastPathComponent())
        }

        var seen: Set<String> = []
        return dirs.compactMap { dir in
            guard seen.insert(dir.path).inserted,
                  let content = try? String(contentsOf: dir.appending(path: "SKILL.md"), encoding: .utf8)
            else { return nil }
            let fm = Frontmatter.parse(content)
            let description = (fm.string("description") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return DispatchSkill(
                id: dir.path,
                name: fm.string("name") ?? dir.lastPathComponent,
                description: description,
                directoryURL: dir
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func copySkill(_ skill: DispatchSkill, to targetRoot: URL) throws {
        let fm = FileManager.default
        let destination = targetRoot.appending(path: skill.directoryURL.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: skill.directoryURL, to: destination)
    }
}

struct SkillDispatchView: View {
    @Environment(SkillStore.self) private var skillStore
    @Environment(Translator.self) private var translator
    let dispatch: SkillDispatchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                targetStrip
                skillTable
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            dispatch.scan()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Skill 分派")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    chooseCenterRepository()
                } label: {
                    Label("选择中心仓库", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    dispatch.scan()
                } label: {
                    Label("扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await dispatch.dispatchSelected()
                        await skillStore.scan()
                    }
                } label: {
                    Label(dispatch.isDispatching ? "分派中" : "一键分派", systemImage: "paperplane")
                }
                .disabled(dispatch.isDispatching || dispatch.skills.isEmpty)
                .buttonStyle(.borderedProminent)
            }

            Label {
                Text(dispatch.centerURL.path.replacingOccurrences(
                    of: FileManager.default.homeDirectoryForCurrentUser.path,
                    with: "~"
                ))
                .textSelection(.enabled)
            } icon: {
                Image(systemName: "externaldrive")
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            if let message = dispatch.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("目标 Agent")
                .font(.headline)
            FlowLayout(spacing: 8) {
                ForEach(dispatch.targets) { target in
                    Toggle(isOn: Binding(
                        get: { dispatch.selectedPlatforms.contains(target.platform) },
                        set: { _ in dispatch.togglePlatform(target.platform) }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: Theme.platformIcon(target.platform))
                                .foregroundStyle(Theme.platformColor(target.platform))
                            Text(Theme.platformLabel(target.platform))
                            Text("\(skillStore.count(platform: target.platform))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .toggleStyle(.button)
                }
            }
        }
    }

    private var skillTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("中心 Skill")
                    .font(.headline)
                Spacer()
                Text(dispatch.selectedSkillIDs.isEmpty ? "默认分派全部" : "已选 \(dispatch.selectedSkillIDs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dispatch.skills.isEmpty {
                ContentUnavailableView(
                    "中心仓库为空",
                    systemImage: "tray",
                    description: Text("把含 SKILL.md 的 Skill 目录放进中心仓库，或选择已有仓库后扫描。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(dispatch.skills) { skill in
                        skillRow(skill)
                        Divider()
                    }
                }
            }
        }
    }

    private func skillRow(_ skill: DispatchSkill) -> some View {
        Button {
            dispatch.toggleSkill(skill)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: dispatch.selectedSkillIDs.contains(skill.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(dispatch.selectedSkillIDs.contains(skill.id) ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name)
                        .font(.body.bold())
                    if !skill.description.isEmpty {
                        Text(translator.text(skill.description))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text(skill.directoryURL.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func chooseCenterRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = dispatch.centerURL
        panel.prompt = "选择"
        panel.message = "选择中心 Skill 仓库目录"
        if panel.runModal() == .OK, let url = panel.url {
            dispatch.setCenterURL(url)
        }
    }
}
