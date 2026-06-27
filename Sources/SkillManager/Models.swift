import Foundation
import Observation

struct Skill: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let platform: String
    let category: String
    let version: String?
    let triggers: [String]
    let allowedTools: [String]
    let directoryPath: String
    let isSymlink: Bool
    // Derive display fields once during scanning to avoid repeated parsing in the render path.
    let summary: String
    let useWhen: [String]
    let proactive: [String]
}

// ponytail: heuristic — split description into sentences, classify each. Skill triggering rules
// live in prose ("Use when: …" = applicability; "Proactively … when …" = auto-trigger rule).
extension Skill {
    /// Splits and classifies sentences once: use cases, proactive triggers, and the remaining summary.
    /// Called during scanning and stored on Skill; a computed property would repeat work on every body update.
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

    /// Subsequence fuzzy matching: query characters must appear in order. "drv" matches "design-review".
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

    /// Uses subsequence matching for names and substring matching for descriptions and triggers.
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
    case allPlatform(String)
    case category(platform: String, category: String)
}

@MainActor @Observable
final class SkillStore {
    var skills: [Skill] = []

    func scan() async {
        // Move directory traversal, SKILL.md reads, and parsing off the main thread to keep launch responsive.
        skills = await Task.detached { Self.scanAll() }.value
    }

    nonisolated static func scanAll() -> [Skill] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations: [(URL, String, String, Set<String>)] = [
            (home.appending(path: ".claude/skills"), "Claude Code", "Standalone", ["gstack"]),
            (home.appending(path: ".claude/skills/gstack"), "Claude Code", "GStack", []),
            (home.appending(path: ".codex/skills"), "Codex", "User", [".system"]),
            (home.appending(path: ".codex/skills/.system"), "Codex", "System", []),
            (home.appending(path: ".codex/vendor_imports/skills/skills/.curated"), "Codex", "Curated", []),
        ]
        var all: [Skill] = []
        for (dir, platform, category, excludes) in locations {
            all += scanDir(dir, platform: platform, category: category, excludes: excludes)
        }
        // Deduplicate by name+platform, keep the first (more specific category)
        var seen: Set<String> = []
        all = all.filter { s in
            let key = "\(s.platform):\(s.name)"
            return seen.insert(key).inserted
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return all
    }

    // The single search entry point injects translated text so the map and list behave consistently.
    func filtered(by sel: SidebarSelection, search: String,
                  zh: (String) -> String = { $0 }) -> [Skill] {
        skills.filter { s in
            switch sel {
            case .skillMap: break
            case .allPlatform(let p): if s.platform != p { return false }
            case .category(let p, let c): if s.platform != p || s.category != c { return false }
            }
            guard !search.isEmpty else { return true }
            return s.matches(search.lowercased())
                || zh(s.summary).contains(search)
                || s.proactive.contains { zh($0).contains(search) }
        }
    }

    func count(platform: String, category: String? = nil) -> Int {
        skills.filter { $0.platform == platform && (category == nil || $0.category == category) }.count
    }

    func readFile(directory: String, relative: String) -> String {
        let url = URL(fileURLWithPath: directory).appending(path: relative)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Unable to read file"
    }

    nonisolated private static func scanDir(_ dir: URL, platform: String, category: String, excludes: Set<String>) -> [Skill] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        ) else { return [] }

        return entries.flatMap { entry -> [Skill] in
            let dirName = entry.lastPathComponent
            guard !excludes.contains(dirName) else { return [] }

            if let skill = Self.makeSkill(at: entry, dirName: dirName, platform: platform, category: category) {
                return [skill]
            }

            // .claude-plugin format: SKILL.md nested one level deeper
            if FileManager.default.fileExists(atPath: entry.appending(path: ".claude-plugin").path) {
                guard let subs = try? FileManager.default.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ) else { return [] }
                return subs.compactMap { sub in
                    Self.makeSkill(at: sub, dirName: sub.lastPathComponent, platform: platform, category: category)
                }
            }

            return []
        }
    }

    nonisolated private static func makeSkill(at entry: URL, dirName: String, platform: String, category: String) -> Skill? {
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
        Self.listFiles(in: URL(fileURLWithPath: skill.directoryPath))   // List now; load file contents on demand.
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
            // fileExists follows symbolic links, so an existing non-directory target counts as a file.
            // This keeps linked SKILL.md files from being omitted from the file count.
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
