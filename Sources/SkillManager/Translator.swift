import SwiftUI
import Translation

// ponytail: global translation cache. macOS Translation framework fills it once on launch;
// Views read translated text via zh(); the EN/ZH toolbar toggle flips `enabled`.
@MainActor @Observable
final class Translator {
    var enabled = false
    var cache: [String: String] = [:]

    // Persist translations because skill descriptions rarely change; later launches need no translation work.
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
