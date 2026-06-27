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

struct ContentView: View {
    @State private var store = SkillStore()
    @State private var selection: SidebarSelection? = .skillMap
    @State private var selectedSkillId: String?
    @State private var search = ""
    @State private var listWidth: CGFloat = 280   // 技能列表默认宽度(可拖)
    @AppStorage("isDarkMode") private var isDark = true
    @State private var translator = Translator()
    @State private var zhConfig: TranslationSession.Configuration?

    private var selectedSkill: Skill? {
        guard let id = selectedSkillId else { return nil }
        return store.skills.first { $0.id == id }
    }

    private func skillBelongs(_ id: String?, to sel: SidebarSelection?) -> Bool {
        guard let id, let skill = store.skills.first(where: { $0.id == id }), let sel else { return false }
        switch sel {
        case .skillMap: return false
        case .allPlatform(let p): return skill.platform == p
        case .category(let p, let c): return skill.platform == p && skill.category == c
        }
    }

    private var searchedSkills: [Skill] {
        store.filtered(by: .skillMap, search: search, zh: translator.zh)
    }

    @ViewBuilder
    private var detailContent: some View {
        if selection == .skillMap || selection == nil {
            SkillMapView(skills: searchedSkills) { skill in
                selectedSkillId = skill.id
                selection = .allPlatform(skill.platform)
            }
        } else {
            HStack(spacing: 0) {
                SkillListView(
                    skills: store.filtered(by: selection ?? .skillMap, search: search, zh: translator.zh),
                    selectedId: $selectedSkillId
                )
                .frame(width: listWidth)                            // 默认窄
                ResizeHandle(width: $listWidth, range: 220...600)   // 只拖这根线
                if let skill = selectedSkill {
                    SkillDetailView(skill: skill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)   // 右侧最大
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
            Button {
                isDark.toggle()
            } label: {
                Image(systemName: isDark ? "sun.max" : "moon.fill")
            }
            .buttonStyle(.plain)
            .help(isDark ? "切换到浅色外观" : "切换到深色外观")
        }
        ToolbarItem(placement: .automatic) {
            Button(translator.enabled ? "EN" : "中") {
                translator.enabled.toggle()
            }
            .buttonStyle(.plain)
            .help(translator.enabled ? "显示英文原文" : "显示中文翻译")
        }
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("搜索技能…", text: $search)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .environment(store)
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
        .task {
            await store.scan()
            zhConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans"))
        }
        .translationTask(zhConfig) { session in
            await runTranslation(session)
        }
    }

    private func runTranslation(_ session: TranslationSession) async {
        let texts = Set(store.skills.flatMap { [$0.summary] + $0.useWhen + $0.proactive })
            .filter { !$0.isEmpty && translator.cache[$0] == nil }
        guard !texts.isEmpty else { return }   // 缓存已全命中 → 本次零翻译,启动瞬间
        var batch = translator.cache
        do {
            // 批量并发翻译,而非逐条串行 await —— 首次翻译从数秒压到数百毫秒
            let requests = texts.map { TranslationSession.Request(sourceText: $0) }
            for response in try await session.translations(from: requests) {
                batch[response.sourceText] = response.targetText
            }
        } catch {
            FileHandle.standardError.write(Data("ZH_ERR \(error)\n".utf8))
        }
        translator.cache = batch   // 一次性赋值 → 只触发一次重渲染
        translator.save()          // 落盘 → 下次启动直接命中
    }
}
