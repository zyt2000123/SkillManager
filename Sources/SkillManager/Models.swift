import Foundation
import Observation

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let platform: String
    let category: String
    let installType: String
    let version: String?
    let triggers: [String]
    let allowedTools: [String]
    let directoryPath: String
    let isSymlink: Bool
    // scan 时一次性派生的展示字段,避免 render 热路径重复切句/分类
    let summary: String
    let useWhen: [String]
    let proactive: [String]
}

enum SkillPlatform {
    static let openClaw = "OpenClaw"
    static let codex = "Codex"
    static let claudeCode = "ClaudeCode"
    static let hermess = "Hermess"

    static let all = [openClaw, codex, claudeCode, hermess]
}

enum SkillInstallType {
    static let skill = "Skill"
    static let plugin = "Plugin"

    static let all = [skill, plugin]
}

private struct SkillScanLocation {
    let dir: URL
    let platform: String
    let category: String
    let installType: String
    let excludes: Set<String>
}

// ponytail: heuristic — split description into sentences, classify each. Skill triggering rules
// live in prose ("Use when: …" = applicability; "Proactively … when …" = auto-trigger rule).
extension Skill {
    /// 一次切句并分类:适用场景(useWhen)、主动触发(proactive)、其余归入主体描述(summary)。
    /// scan 时调用一次,结果存进 Skill —— 不要做成 computed property,否则每次 body 求值都重跑。
    static func derive(from description: String) -> (summary: String, useWhen: [String], proactive: [String]) {
        let sentences = description
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 1 }

        var summary: [String] = [], useWhen: [String] = [], proactive: [String] = []
        for s in sentences {
            let use = isUseWhen(s), proa = isProactive(s)
            if use { useWhen.append(s) }
            if proa { proactive.append(s) }
            if !use, !proa, !s.lowercased().contains("voice trigger") { summary.append(s) }
        }
        return (summary.joined(separator: ". "), useWhen, proactive)
    }

    /// 子序列模糊匹配:query 的字符按序出现在 target 即命中。"drv" → "design-review"。query 需已 lowercased。
    static func fuzzyMatch(_ query: String, _ target: String) -> Bool {
        var it = query.makeIterator()
        var cur = it.next()
        if cur == nil { return true }
        for ch in target where ch == cur {
            cur = it.next()
            if cur == nil { return true }
        }
        return false
    }

    /// 统一搜索判定:名字用子序列模糊,描述/触发词用子串(长描述上子序列会误命中一切)。query 需已 lowercased。
    func matches(_ query: String) -> Bool {
        Skill.fuzzyMatch(query, name.lowercased())
        || description.lowercased().contains(query)
        || triggers.contains { $0.lowercased().contains(query) }
    }

    private static func isUseWhen(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.contains("use when") || l.contains("use this when") || l.contains("use it when")
            || l.contains("use for") || l.contains("use before") || l.contains("use after")
            || l.contains("trigger when") || l.contains("triggers on") || l.contains("triggers include")
    }
    private static func isProactive(_ s: String) -> Bool {
        s.lowercased().contains("proactive")
    }
}

enum SidebarSelection: Hashable {
    case skillMap
    case skillMarket
    case skillDispatch
    case allPlatform(String)
    case category(platform: String, category: String)
    case installType(platform: String, installType: String)
}

@MainActor @Observable
final class SkillStore {
    var skills: [Skill] = []

    func scan() async {
        // ponytail: 全部文件 IO(遍历多个目录 + 读每个 SKILL.md + parse)移到后台线程,不阻塞首屏
        skills = await Task.detached { Self.scanAll() }.value
    }

    nonisolated static func scanAll() -> [Skill] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations: [SkillScanLocation] = [
            .init(dir: home.appending(path: ".openclaw/skills"), platform: SkillPlatform.openClaw, category: "User", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: ".config/openclaw/skills"), platform: SkillPlatform.openClaw, category: "Config", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: "Library/Application Support/OpenClaw/skills"), platform: SkillPlatform.openClaw, category: "App Support", installType: SkillInstallType.skill, excludes: []),

            .init(dir: home.appending(path: ".codex/skills"), platform: SkillPlatform.codex, category: "User", installType: SkillInstallType.skill, excludes: [".system"]),
            .init(dir: home.appending(path: ".codex/skills/.system"), platform: SkillPlatform.codex, category: "System", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: ".codex/vendor_imports/skills/skills/.curated"), platform: SkillPlatform.codex, category: "Curated", installType: SkillInstallType.skill, excludes: []),

            .init(dir: home.appending(path: ".claude/skills"), platform: SkillPlatform.claudeCode, category: "Standalone", installType: SkillInstallType.skill, excludes: ["gstack"]),
            .init(dir: home.appending(path: ".claude/skills/gstack"), platform: SkillPlatform.claudeCode, category: "GStack", installType: SkillInstallType.skill, excludes: []),

            .init(dir: home.appending(path: ".hermess/skills"), platform: SkillPlatform.hermess, category: "User", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: ".hermes/skills"), platform: SkillPlatform.hermess, category: "Hermes", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: ".config/hermess/skills"), platform: SkillPlatform.hermess, category: "Config", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: ".config/hermes/skills"), platform: SkillPlatform.hermess, category: "Config", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: "Library/Application Support/Hermess/skills"), platform: SkillPlatform.hermess, category: "App Support", installType: SkillInstallType.skill, excludes: []),
            .init(dir: home.appending(path: "Library/Application Support/Hermes/skills"), platform: SkillPlatform.hermess, category: "App Support", installType: SkillInstallType.skill, excludes: []),
        ]
        var all: [Skill] = []
        for location in locations {
            all += scanDir(
                location.dir,
                platform: location.platform,
                category: location.category,
                installType: location.installType,
                excludes: location.excludes
            )
        }
        all += scanRecursiveSkills(under: home.appending(path: ".codex/plugins/cache"), platform: SkillPlatform.codex, category: "Plugin", installType: SkillInstallType.plugin)
        all += scanClaudePluginCache(home.appending(path: ".claude/plugins/cache"))

        // Deduplicate within each agent/source bucket, so direct Skill and Plugin copies stay visible.
        var seen: Set<String> = []
        all = all.filter { s in
            let key = "\(s.platform):\(s.installType):\(s.name)"
            return seen.insert(key).inserted
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return all
    }

    // ponytail: 唯一搜索入口。注入译文查询(默认恒等),让地图与列表行为一致:翻译搜索处处生效。
    func filtered(by sel: SidebarSelection, search: String,
                  translate: (String) -> String = { $0 }) -> [Skill] {
        skills.filter { s in
            switch sel {
            case .skillMap, .skillMarket, .skillDispatch: break
            case .allPlatform(let p): if s.platform != p { return false }
            case .category(let p, let c): if s.platform != p || s.category != c { return false }
            case .installType(let p, let t): if s.platform != p || s.installType != t { return false }
            }
            guard !search.isEmpty else { return true }
            return s.matches(search.lowercased())
                || translate(s.summary).contains(search)
                || s.proactive.contains { translate($0).contains(search) }
        }
    }

    func count(platform: String, category: String? = nil) -> Int {
        skills.filter { $0.platform == platform && (category == nil || $0.category == category) }.count
    }

    func count(platform: String, installType: String) -> Int {
        skills.filter { $0.platform == platform && $0.installType == installType }.count
    }

    func readFile(directory: String, relative: String) -> String {
        let url = URL(fileURLWithPath: directory).appending(path: relative)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Unable to read file"
    }

    nonisolated private static func scanDir(
        _ dir: URL,
        platform: String,
        category: String,
        installType: String,
        excludes: Set<String>
    ) -> [Skill] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        ) else { return [] }

        return entries.flatMap { entry -> [Skill] in
            let dirName = entry.lastPathComponent
            guard !excludes.contains(dirName) else { return [] }

            if let skill = Self.makeSkill(at: entry, dirName: dirName, platform: platform, category: category, installType: installType) {
                return [skill]
            }

            // .claude-plugin format: SKILL.md nested one level deeper
            if FileManager.default.fileExists(atPath: entry.appending(path: ".claude-plugin").path) {
                guard let subs = try? FileManager.default.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else { return [] }
                return subs.compactMap { sub in
                    Self.makeSkill(at: sub, dirName: sub.lastPathComponent, platform: platform, category: category, installType: installType)
                }
            }

            return []
        }
    }

    nonisolated private static func scanRecursiveSkills(under root: URL, platform: String, category: String, installType: String) -> [Skill] {
        recursiveSkillDirs(under: root).compactMap { entry in
            makeSkill(at: entry, dirName: entry.lastPathComponent, platform: platform, category: category, installType: installType)
        }
    }

    nonisolated private static func scanClaudePluginCache(_ root: URL) -> [Skill] {
        recursiveSkillDirs(under: root).compactMap { entry in
            guard let target = classifyClaudePluginSkill(at: entry, under: root) else { return nil }
            return makeSkill(at: entry, dirName: entry.lastPathComponent, platform: target.platform, category: target.category, installType: SkillInstallType.plugin)
        }
    }

    nonisolated private static func recursiveSkillDirs(under root: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue,
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
              )
        else { return [] }

        let skippedDirectories = Set([".git", ".build", "build", "dist", "node_modules"])
        var dirs: [URL] = []
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               values.isDirectory == true {
                if skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard url.lastPathComponent == "SKILL.md" else { continue }
            dirs.append(url.deletingLastPathComponent())
        }
        return dirs.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    nonisolated private static func classifyClaudePluginSkill(
        at skillDir: URL,
        under root: URL
    ) -> (platform: String, category: String)? {
        let comps = relativeComponents(of: skillDir, under: root)
        let lowered = comps.map { $0.lowercased() }
        let parents = lowered.dropLast()

        let nonClaudeAgentFolders = Set([
            ".agents", "agents", ".codex", "codex", ".cursor", "cursor", ".openclaw", "openclaw",
            ".trae", "trae", ".opencode", "opencode", ".hermes", "hermes", ".hermess", "hermess",
            "codebuddy", ".codebuddy", "kimi", ".kimi", ".gemini", "gemini", ".qwen", "qwen",
            ".zed", "zed", ".kiro", "kiro", "vscode", ".vscode"
        ])
        if parents.contains(where: { nonClaudeAgentFolders.contains($0) }) {
            return nil
        }

        if isClaudePluginSkillPath(lowered) {
            return (SkillPlatform.claudeCode, "Plugin")
        }

        return nil
    }

    nonisolated private static func isClaudePluginSkillPath(_ components: [String]) -> Bool {
        guard let skillsIndex = components.lastIndex(of: "skills") else { return false }
        let beforeSkills = components[..<skillsIndex]

        if beforeSkills.last == ".claude" {
            return true
        }

        let nonRuntimeFolders = Set(["benchmarks", "build", "dist", "docs", "examples", "hooks", "node_modules", "scripts", "tests"])
        return !beforeSkills.contains(where: { nonRuntimeFolders.contains($0) })
    }

    nonisolated private static func relativeComponents(of url: URL, under root: URL) -> [String] {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let relative: String
        if path == rootPath {
            relative = ""
        } else if path.hasPrefix(rootPath + "/") {
            relative = String(path.dropFirst(rootPath.count + 1))
        } else {
            relative = path
        }
        return relative.split(separator: "/").map(String.init)
    }

    nonisolated private static func makeSkill(at entry: URL, dirName: String, platform: String, category: String, installType: String) -> Skill? {
        guard let content = try? String(contentsOf: entry.appending(path: "SKILL.md"), encoding: .utf8) else { return nil }
        let fm = Frontmatter.parse(content)
        let symlink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        let description = (fm.string("description") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fmTriggers = fm.array("triggers")
        let triggers = fmTriggers.isEmpty ? extractTriggers(from: description) : fmTriggers
        let derived = Skill.derive(from: description)
        return Skill(
            id: entry.path,
            name: fm.string("name") ?? dirName,
            description: description,
            platform: platform,
            category: category,
            installType: installType,
            version: fm.string("version"),
            triggers: triggers,
            allowedTools: fm.array("allowed-tools"),
            directoryPath: entry.path,
            isSymlink: symlink,
            summary: derived.summary,
            useWhen: derived.useWhen,
            proactive: derived.proactive
        )
    }

    nonisolated func fileList(for skill: Skill) -> [String] {
        Self.listFiles(in: URL(fileURLWithPath: skill.directoryPath))   // 只列文件;SKILL.md 内容由文件预览点击时按需读
    }

    // ponytail: heuristic — most skills lack a `triggers:` field; their triggers live in the
    // description as 'Use when: "x"' / 'Voice triggers: "y"'. Pull quoted phrases after a marker.
    nonisolated static func extractTriggers(from description: String) -> [String] {
        let markers = ["use when", "triggers on", "trigger on", "voice trigger",
                       "triggers include", "trigger when", "use this when", "triggers ("]
        guard let start = markers.compactMap({
            description.range(of: $0, options: .caseInsensitive)?.lowerBound
        }).min() else { return [] }

        var out: [String] = []
        var seen = Set<String>()
        var current = ""
        var open: Character? = nil
        for ch in description[start...] {
            if let o = open {
                if ch == o {
                    let t = current.trimmingCharacters(in: .whitespaces)
                    if t.count >= 2, t.count <= 40, seen.insert(t.lowercased()).inserted {
                        out.append(t)
                    }
                    current = ""; open = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                open = ch
                current = ""
            }
        }
        return Array(out.prefix(12))
    }

    nonisolated private static func listFiles(in dir: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        let fm = FileManager.default
        let prefix = dir.path
        var files: [String] = []
        for case let url as URL in enumerator {
            // fileExists 会跟随符号链接:存在且非目录即算文件。
            // 否则指向文件的 symlink(如纯链接型 skill 的 SKILL.md)会被漏算,显示「文件 (0)」。
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let p = url.path
            guard p.count > prefix.count + 1 else { continue }
            files.append(String(p.dropFirst(prefix.count + 1)))
        }
        return files.sorted()
    }
}

// ponytail: manual YAML-subset parser, covers key:value + arrays. Yams dep not needed.
struct Frontmatter {
    let values: [String: Any]
    let body: String

    func string(_ key: String) -> String? { values[key] as? String }
    func array(_ key: String) -> [String] { (values[key] as? [String]) ?? [] }

    static func parse(_ content: String) -> Frontmatter {
        let lines = content.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return Frontmatter(values: [:], body: content)
        }
        guard let second = lines[(first + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return Frontmatter(values: [:], body: content)
        }
        let yamlLines = Array(lines[(first + 1)..<second])
        let body = lines[(second + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        var dict: [String: Any] = [:]
        var curKey: String?
        var curArr: [String] = []
        var isBlock = false
        let quotes = CharacterSet(charactersIn: "\"'")

        for line in yamlLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isIndented = line.hasPrefix(" ") || line.hasPrefix("\t")

            // Continuation of block scalar or array
            if curKey != nil, isIndented {
                if trimmed.hasPrefix("- ") {
                    curArr.append(
                        String(trimmed.dropFirst(2))
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: quotes)
                    )
                } else if !trimmed.isEmpty {
                    curArr.append(trimmed)
                }
                continue
            }

            if trimmed.isEmpty { continue }

            // Flush previous key
            if let key = curKey, !curArr.isEmpty {
                if isBlock {
                    dict[key] = curArr.joined(separator: " ")
                } else {
                    dict[key] = curArr
                }
                curArr = []
                curKey = nil
                isBlock = false
            }

            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let val = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            if val == "|" || val == ">" {
                curKey = key
                curArr = []
                isBlock = true
            } else if val.isEmpty {
                curKey = key
                curArr = []
                isBlock = false
            } else if val.hasPrefix("["), val.hasSuffix("]") {
                dict[key] = String(val.dropFirst().dropLast())
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: quotes) }
            } else {
                dict[key] = val.trimmingCharacters(in: quotes)
            }
        }
        if let key = curKey, !curArr.isEmpty {
            dict[key] = isBlock ? curArr.joined(separator: " ") : curArr
        }
        return Frontmatter(values: dict, body: body)
    }
}
