import Foundation
import Translation

struct TranslationTarget: Identifiable, Hashable {
    let id: String
    let label: String
    let shortLabel: String

    var language: Locale.Language {
        Locale.Language(identifier: id)
    }

    static let all: [TranslationTarget] = [
        .init(id: "zh-Hans", label: "简体中文", shortLabel: "中"),
        .init(id: "zh-Hant", label: "繁体中文", shortLabel: "繁"),
        .init(id: "en", label: "English", shortLabel: "EN"),
        .init(id: "ja", label: "日本語", shortLabel: "日"),
        .init(id: "ko", label: "한국어", shortLabel: "한"),
        .init(id: "fr", label: "Français", shortLabel: "FR"),
        .init(id: "de", label: "Deutsch", shortLabel: "DE"),
        .init(id: "es", label: "Español", shortLabel: "ES"),
    ]

    static func byID(_ id: String) -> TranslationTarget {
        all.first { $0.id == id } ?? all[0]
    }

    static func id(matching language: Locale.Language?) -> String? {
        guard let language else { return nil }
        return all.first { $0.language == language }?.id
    }
}

// ponytail: global translation cache. macOS Translation framework fills it once per target language;
// views read translated text via text(), and the toolbar controls original/target language.
@MainActor @Observable
final class Translator {
    var enabled = true
    var targetID: String
    var caches: [String: [String: String]] = [:]

    // ponytail: 缓存持久化到磁盘。skill 描述基本不变,按目标语言翻一次存盘。
    private static let cacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "SkillManager-translations-v2.json")
    private static let legacyZhCacheURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "SkillManager-zh.json")
    private static let targetDefaultsKey = "SkillManager.translationTarget"

    init() {
        let savedTargetID = UserDefaults.standard.string(forKey: Self.targetDefaultsKey) ?? TranslationTarget.all[0].id
        targetID = TranslationTarget.byID(savedTargetID).id
        if let data = try? Data(contentsOf: Self.cacheURL),
           let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            caches = dict
        } else if let data = try? Data(contentsOf: Self.legacyZhCacheURL),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            caches[TranslationTarget.all[0].id] = dict
        }
    }

    var target: TranslationTarget {
        TranslationTarget.byID(targetID)
    }

    var toolbarLabel: String {
        enabled ? target.shortLabel : "原文"
    }

    func setTarget(_ id: String) {
        targetID = TranslationTarget.byID(id).id
        enabled = true
        UserDefaults.standard.set(targetID, forKey: Self.targetDefaultsKey)
    }

    func text(_ s: String) -> String {
        guard enabled, !s.isEmpty else { return s }
        return caches[targetID]?[s] ?? s
    }

    func needsTranslation(_ s: String) -> Bool {
        needsTranslation(s, for: targetID)
    }

    func needsTranslation(_ s: String, for targetID: String) -> Bool {
        !s.isEmpty && caches[targetID]?[s] == nil
    }

    func merge(_ translations: [String: String], for targetID: String) {
        var targetCache = caches[targetID] ?? [:]
        for (source, translated) in translations {
            targetCache[source] = translated
        }
        caches[targetID] = targetCache
    }

    func save() {
        guard let data = try? JSONEncoder().encode(caches) else { return }
        try? data.write(to: Self.cacheURL)
    }
}
