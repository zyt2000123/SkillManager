import Foundation
import Observation

struct SkillMarketSource: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let platforms: [String]
    let repositoryURL: URL
    let manifestURL: URL
    let marketplaceAddCommands: [String]

    static let builtin: [SkillMarketSource] = [
        .init(
            id: "claude-plugins-official",
            title: "Claude Plugins Official",
            description: "Anthropic-managed Claude Code plugin marketplace.",
            platforms: [SkillPlatform.claudeCode],
            repositoryURL: URL(string: "https://github.com/anthropics/claude-plugins-official")!,
            manifestURL: URL(string: "https://api.github.com/repos/anthropics/claude-plugins-official/contents/.claude-plugin/marketplace.json?ref=main")!,
            marketplaceAddCommands: []
        ),
        .init(
            id: "anthropic-agent-skills",
            title: "Anthropic Agent Skills",
            description: "Example agent skills packaged as a Claude marketplace.",
            platforms: [SkillPlatform.claudeCode],
            repositoryURL: URL(string: "https://github.com/anthropics/skills")!,
            manifestURL: URL(string: "https://api.github.com/repos/anthropics/skills/contents/.claude-plugin/marketplace.json?ref=main")!,
            marketplaceAddCommands: ["claude plugin marketplace add anthropics/skills"]
        ),
        .init(
            id: "xiaolai-claude",
            title: "xiaolai Claude Marketplace",
            description: "Community marketplace with Claude Code plugin manifests.",
            platforms: [SkillPlatform.claudeCode],
            repositoryURL: URL(string: "https://github.com/xiaolai/claude-plugin-marketplace")!,
            manifestURL: URL(string: "https://api.github.com/repos/xiaolai/claude-plugin-marketplace/contents/.claude-plugin/marketplace.json?ref=main")!,
            marketplaceAddCommands: ["claude plugin marketplace add xiaolai/claude-plugin-marketplace"]
        ),
        .init(
            id: "xiaolai-codex",
            title: "xiaolai Codex Marketplace",
            description: "Community marketplace with Codex plugin manifests.",
            platforms: [SkillPlatform.codex],
            repositoryURL: URL(string: "https://github.com/xiaolai/claude-plugin-marketplace")!,
            manifestURL: URL(string: "https://api.github.com/repos/xiaolai/claude-plugin-marketplace/contents/.agents/plugins/marketplace.json?ref=main")!,
            marketplaceAddCommands: ["codex plugin marketplace add xiaolai/claude-plugin-marketplace"]
        ),
        .init(
            id: "avivsinai-skills",
            title: "Aviv Sinai Skills Marketplace",
            description: "Registry-first marketplace for Claude Code and Codex.",
            platforms: [SkillPlatform.claudeCode, SkillPlatform.codex],
            repositoryURL: URL(string: "https://github.com/avivsinai/skills-marketplace")!,
            manifestURL: URL(string: "https://api.github.com/repos/avivsinai/skills-marketplace/contents/registry/plugins.json?ref=main")!,
            marketplaceAddCommands: [
                "claude plugin marketplace add avivsinai/skills-marketplace",
                "codex plugin marketplace add avivsinai/skills-marketplace"
            ]
        )
    ]
}

struct SkillMarketPlugin: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let sourceTitle: String
    let marketplaceName: String
    let platforms: [String]
    let category: String?
    let version: String?
    let author: String?
    let repositoryURL: URL?
    let homepageURL: URL?
    let keywords: [String]
    let installCommands: [String]
}

@MainActor @Observable
final class SkillMarketStore {
    private(set) var sources = SkillMarketSource.builtin
    private(set) var plugins: [SkillMarketPlugin] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var loadedSourceCount = 0
    private(set) var lastRefresh: Date?

    var hasLoaded: Bool { lastRefresh != nil }

    func refreshIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        var loaded: [SkillMarketPlugin] = []
        var failures: [String] = []

        for source in sources {
            do {
                loaded += try await Self.fetchPlugins(from: source)
            } catch {
                failures.append("\(source.title): \(error.localizedDescription)")
            }
        }

        var seen: Set<String> = []
        plugins = loaded
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loadedSourceCount = sources.count - failures.count
        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        lastRefresh = Date()
        isLoading = false
    }

    private static func fetchPlugins(from source: SkillMarketSource) async throws -> [SkillMarketPlugin] {
        var request = URLRequest(url: source.manifestURL)
        request.setValue("SkillManager/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let manifestData = try decodeGitHubContent(data)
        let object = try JSONSerialization.jsonObject(with: manifestData)
        guard let manifest = object as? [String: Any],
              let pluginObjects = manifest["plugins"] as? [[String: Any]]
        else { return [] }

        let marketplaceName = string("name", in: manifest) ?? source.id
        return pluginObjects.compactMap { plugin in
            makePlugin(from: plugin, source: source, marketplaceName: marketplaceName)
        }
    }

    private static func decodeGitHubContent(_ data: Data) throws -> Data {
        let response = try JSONDecoder().decode(GitHubContentResponse.self, from: data)
        let encoded = response.content.replacingOccurrences(of: "\n", with: "")
        guard let decoded = Data(base64Encoded: encoded) else {
            throw URLError(.cannotDecodeContentData)
        }
        return decoded
    }

    private static func makePlugin(
        from plugin: [String: Any],
        source: SkillMarketSource,
        marketplaceName: String
    ) -> SkillMarketPlugin? {
        guard let name = string("name", in: plugin) else { return nil }

        let repository = repositoryURL(from: plugin, fallback: source.repositoryURL)
        let homepage = url(string("homepage", in: plugin)) ?? repository
        let commands = installCommands(for: name, marketplaceName: marketplaceName, platforms: source.platforms)

        return SkillMarketPlugin(
            id: "\(source.id):\(name)",
            name: name,
            description: normalized(string("description", in: plugin) ?? ""),
            sourceTitle: source.title,
            marketplaceName: marketplaceName,
            platforms: source.platforms,
            category: string("category", in: plugin),
            version: string("version", in: plugin),
            author: nestedString(["author", "name"], in: plugin),
            repositoryURL: repository,
            homepageURL: homepage,
            keywords: plugin["keywords"] as? [String] ?? [],
            installCommands: commands
        )
    }

    private static func installCommands(for name: String, marketplaceName: String, platforms: [String]) -> [String] {
        var commands: [String] = []
        if platforms.contains(SkillPlatform.claudeCode) {
            commands.append("/plugin install \(name)@\(marketplaceName)")
        }
        if platforms.contains(SkillPlatform.codex) {
            commands.append("codex plugin install \(name)@\(marketplaceName)")
        }
        return commands
    }

    private static func repositoryURL(from plugin: [String: Any], fallback: URL) -> URL? {
        if let repository = url(string("repository", in: plugin)) {
            return repository
        }
        if let source = plugin["source"] as? [String: Any] {
            if let repo = string("repo", in: source), let url = URL(string: "https://github.com/\(repo)") {
                return url
            }
            if let url = url(string("url", in: source)) {
                return url
            }
        }
        return fallback
    }

    private static func string(_ key: String, in dict: [String: Any]) -> String? {
        dict[key] as? String
    }

    private static func nestedString(_ path: [String], in dict: [String: Any]) -> String? {
        var current: Any = dict
        for key in path {
            guard let object = current as? [String: Any], let value = object[key] else { return nil }
            current = value
        }
        return current as? String
    }

    private static func url(_ string: String?) -> URL? {
        guard let string, string.hasPrefix("http") else { return nil }
        return URL(string: string)
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GitHubContentResponse: Decodable {
    let content: String
}
