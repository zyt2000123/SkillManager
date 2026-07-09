import SwiftUI
import AppKit
import Translation

@main
struct SkillManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("isDarkMode") private var isDark = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 550)
                .preferredColorScheme(isDark ? .dark : .light)
        }
        .defaultSize(width: 1200, height: 750)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum TranslationTaskMode {
    case translate
    case prepare
}

private enum TranslationLanguageAlertKind {
    case download
    case unsupported
    case failed
}

private struct TranslationLanguageAlert {
    let target: TranslationTarget
    let kind: TranslationLanguageAlertKind
}

struct ContentView: View {
    @State private var store = SkillStore()
    @State private var market = SkillMarketStore()
    @State private var dispatch = SkillDispatchStore()
    @State private var selection: SidebarSelection? = .skillMap
    @State private var selectedSkillId: String?
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var listWidth: CGFloat = 280   // 技能列表默认宽度(可拖)
    @AppStorage("isDarkMode") private var isDark = true
    @State private var translator = Translator()
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var translationTaskMode: TranslationTaskMode = .translate
    @State private var translationLanguageAlert: TranslationLanguageAlert?

    private var selectedSkill: Skill? {
        guard let id = selectedSkillId else { return nil }
        return store.skills.first { $0.id == id }
    }

    private func skillBelongs(_ id: String?, to sel: SidebarSelection?) -> Bool {
        guard let id, let skill = store.skills.first(where: { $0.id == id }), let sel else { return false }
        switch sel {
        case .skillMap, .skillMarket, .skillDispatch: return false
        case .allPlatform(let p): return skill.platform == p
        case .category(let p, let c): return skill.platform == p && skill.category == c
        case .installType(let p, let t): return skill.platform == p && skill.installType == t
        }
    }

    private var searchedSkills: [Skill] {
        store.filtered(by: .skillMap, search: debouncedSearch, translate: translator.text)
    }

    @ViewBuilder
    private var detailContent: some View {
        if selection == .skillMarket {
            SkillMarketView(search: debouncedSearch, market: market)
        } else if selection == .skillDispatch {
            SkillDispatchView(dispatch: dispatch)
        } else if selection == .skillMap || selection == nil {
            SkillMapView(skills: searchedSkills) { skill in
                selectedSkillId = skill.id
                selection = .allPlatform(skill.platform)
            }
        } else {
            HStack(spacing: 0) {
                SkillListView(
                    skills: store.filtered(by: selection ?? .skillMap, search: debouncedSearch, translate: translator.text),
                    selectedId: $selectedSkillId
                )
                .frame(width: listWidth)
                ResizeHandle(width: $listWidth, range: 220...600)
                    .transaction { t in t.animation = nil }
                if let skill = selectedSkill {
                    SkillDetailView(skill: skill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("选择一个技能",
                        systemImage: "square.grid.2x2",
                        description: Text("从左侧列表中选择以查看详情"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) { Spacer() }
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 14) {
                Button {
                    isDark.toggle()
                } label: {
                    Image(systemName: isDark ? "sun.max" : "moon.fill")
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .help(isDark ? "切换到浅色外观" : "切换到深色外观")

                Menu {
                    Button {
                        translator.enabled = false
                        refreshTranslationConfig()
                    } label: {
                        Label("原文", systemImage: translator.enabled ? "doc.text" : "checkmark")
                    }
                    Divider()
                    ForEach(TranslationTarget.all) { target in
                        Button {
                            Task { await selectTranslationTarget(target) }
                        } label: {
                            Label(
                                target.label,
                                systemImage: translator.enabled && translator.targetID == target.id ? "checkmark" : "translate"
                            )
                        }
                    }
                } label: {
                    Label(translator.toolbarLabel, systemImage: "translate")
                }
                .font(.system(size: 14, weight: .medium))
                .buttonStyle(.plain)
                .help(translator.enabled ? "选择翻译目标语言" : "显示原文")

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                TextField("", text: $search,
                    prompt: Text("搜索技能…").foregroundStyle(.secondary))
                    .textFieldStyle(.plain)
                    .frame(width: 160)
                if !search.isEmpty {
                    Button("清除", systemImage: "xmark.circle.fill") { search = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                isDark ? Color(white: 0.2) : .white,
                in: .capsule
            )
            .shadow(color: .black.opacity(isDark ? 0.3 : 0.08), radius: 10, y: 3)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .environment(store)
                .frame(width: 220)
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
        } detail: {
            detailContent
                .environment(store)
                .environment(translator)
                .toolbar { toolbarContent }
        }
        .onChange(of: selection) { _, newSel in
            if !skillBelongs(selectedSkillId, to: newSel) {
                selectedSkillId = nil
            }
        }
        .onChange(of: search) { _, newValue in
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if search == newValue {
                    debouncedSearch = newValue
                }
            }
        }
        .task {
            await store.scan()
            refreshTranslationConfig()
        }
        .onChange(of: store.skills) { _, _ in
            refreshTranslationConfig()
        }
        .onChange(of: market.plugins) { _, _ in
            refreshTranslationConfig()
        }
        .onChange(of: dispatch.skills) { _, _ in
            refreshTranslationConfig()
        }
        .translationTask(translationConfig) { session in
            switch translationTaskMode {
            case .prepare:
                await prepareTranslation(session)
            case .translate:
                await runTranslation(session)
            }
        }
        .alert(isPresented: Binding(
            get: { translationLanguageAlert != nil },
            set: { if !$0 { translationLanguageAlert = nil } }
        )) {
            languageAlert()
        }
    }

    private func refreshTranslationConfig() {
        guard translator.enabled else {
            translationConfig = nil
            return
        }
        triggerTranslationTask(.translate)
    }

    private func triggerTranslationTask(_ mode: TranslationTaskMode) {
        translationTaskMode = mode
        var config = translationConfig ?? TranslationSession.Configuration()
        config.source = translationSourceLanguage(for: translator.target)
        config.target = translator.target.language
        config.invalidate()
        translationConfig = config
    }

    @MainActor
    private func selectTranslationTarget(_ target: TranslationTarget) async {
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: translationSourceLanguage(for: target),
            to: target.language
        )
        switch status {
        case .installed:
            applyTranslationTarget(target)
        case .supported:
            translationLanguageAlert = TranslationLanguageAlert(target: target, kind: .download)
        case .unsupported:
            translationLanguageAlert = TranslationLanguageAlert(target: target, kind: .unsupported)
        @unknown default:
            translationLanguageAlert = TranslationLanguageAlert(target: target, kind: .unsupported)
        }
    }

    private func translationSourceLanguage(for target: TranslationTarget) -> Locale.Language {
        Locale.Language(identifier: target.id == "en" ? "zh-Hans" : "en")
    }

    private func applyTranslationTarget(_ target: TranslationTarget, mode: TranslationTaskMode = .translate) {
        translator.setTarget(target.id)
        triggerTranslationTask(mode)
    }

    private func languageAlert() -> Alert {
        guard let alert = translationLanguageAlert else {
            return Alert(title: Text("无法检查语言包"))
        }

        switch alert.kind {
        case .download:
            return Alert(
                title: Text("需要下载语言包"),
                message: Text("本机还没有安装 \(alert.target.label) 翻译语言包。下载后才能翻译成该语言。"),
                primaryButton: .default(Text("下载")) {
                    applyTranslationTarget(alert.target, mode: .prepare)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case .unsupported:
            return Alert(
                title: Text("暂不支持该语言"),
                message: Text("当前系统暂不支持翻译成 \(alert.target.label)。"),
                dismissButton: .default(Text("好"))
            )
        case .failed:
            return Alert(
                title: Text("语言包未下载完成"),
                message: Text("\(alert.target.label) 语言包没有下载完成，可以稍后再次选择该语言重试。"),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func prepareTranslation(_ session: TranslationSession) async {
        let targetID = TranslationTarget.id(matching: session.targetLanguage)
        do {
            try await session.prepareTranslation()
            translationTaskMode = .translate
            if targetID == translator.targetID {
                triggerTranslationTask(.translate)
            }
        } catch {
            if let targetID {
                translationLanguageAlert = TranslationLanguageAlert(target: TranslationTarget.byID(targetID), kind: .failed)
            }
            translationTaskMode = .translate
            FileHandle.standardError.write(Data("TRANSLATION_PREPARE_ERR \(error)\n".utf8))
        }
    }

    private func runTranslation(_ session: TranslationSession) async {
        guard let targetID = TranslationTarget.id(matching: session.targetLanguage) else { return }
        let texts = Array(Set(translationTexts)
            .filter { translator.needsTranslation($0, for: targetID) }
            .sorted())
        guard !texts.isEmpty else { return }   // 缓存已全命中 → 本次零翻译,启动瞬间

        for chunk in texts.chunked(into: 24) {
            var batch: [String: String] = [:]
            do {
                let requests = chunk.map { TranslationSession.Request(sourceText: $0) }
                for response in try await session.translations(from: requests) {
                    batch[response.sourceText] = response.targetText
                }
            } catch {
                FileHandle.standardError.write(Data("TRANSLATION_BATCH_ERR \(error)\n".utf8))
                for text in chunk {
                    do {
                        let response = try await session.translate(text)
                        batch[response.sourceText] = response.targetText
                    } catch {
                        FileHandle.standardError.write(Data("TRANSLATION_ITEM_ERR \(error)\n".utf8))
                    }
                }
            }

            if !batch.isEmpty {
                translator.merge(batch, for: targetID)   // 分批赋值 → 翻译结果逐步出现在 UI
                translator.save()
            }
        }
    }

    private func translationTexts(for skill: Skill) -> [String] {
        [skill.description, skill.summary] + skill.useWhen + skill.proactive
    }

    private var translationTexts: [String] {
        store.skills.flatMap(translationTexts(for:))
        + market.sources.flatMap(translationTexts(for:))
        + market.plugins.flatMap(translationTexts(for:))
        + dispatch.skills.map(\.description)
        + ["No description"]
    }

    private func translationTexts(for source: SkillMarketSource) -> [String] {
        [source.description]
    }

    private func translationTexts(for plugin: SkillMarketPlugin) -> [String] {
        [plugin.description, plugin.category ?? ""]
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
