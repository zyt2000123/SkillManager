import SwiftUI
import Translation

// ponytail: global translation cache. macOS Translation framework fills it once on launch;
// views read translated text via zh(); the EN/中 toolbar toggle flips `enabled`.
@MainActor @Observable
final class Translator {
    var enabled = true
    var cache: [String: String] = [:]

    // ponytail: 缓存持久化到磁盘。skill 描述基本不变,翻一次存盘,之后冷启动零翻译。
    private static let cacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "SkillManager-zh.json")

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = dict
        }
    }

    func zh(_ s: String) -> String {
        guard enabled, !s.isEmpty else { return s }
        return cache[s] ?? s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL)
    }
}
