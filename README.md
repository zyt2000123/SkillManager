# Skill Manager

> A native macOS app for browsing locally installed Claude Code and Codex skills

Skill Manager is a lightweight, read-only macOS app that automatically scans the [Claude Code](https://claude.com/claude-code) and Codex skills installed on your Mac. It organizes them by topic, supports fuzzy search, and previews Markdown, images, SVG files, and source code.

## ✨ Features

- **Automatic discovery** — Scans locations such as `~/.claude/skills` and `~/.codex/skills`, then parses the frontmatter in each `SKILL.md`
- **Skill Map** — Groups skills into security, code review, debugging, planning, documentation, deployment, testing, design, AI, and other categories
- **Fuzzy search** — Matches name subsequences (`drv` → `design-review`) and searches descriptions and trigger keywords, including translated text
- **File previews** — Provides a file tree, Markdown rendering, syntax-highlighted code, and image and SVG previews; YAML frontmatter is rendered as a code block
- **Optional English-to-Chinese translation** — Uses the macOS Translation framework and persists translations for instant subsequent launches
- **Dark and light themes** — Switch appearance with one click

## 📦 Installation

### Download (recommended)

Download `SkillManager.dmg` from [Releases](https://github.com/zyt2000123/SkillManager/releases), open it, and drag **SkillManager** into **Applications**.

> ⚠️ The app is not notarized by Apple. If macOS cannot verify the developer on first launch, open **System Settings → Privacy & Security** and click **Open Anyway**.

### Build from source

```bash
git clone https://github.com/zyt2000123/SkillManager.git
cd SkillManager
./run.sh          # Development: build, package, and launch a debug build
./make-dmg.sh     # Distribution: build a release and package SkillManager.dmg
```

## 🛠 Requirements

- macOS 15+
- Swift 6 toolchain (Xcode 16+ or the standalone Swift toolchain)

## 📚 Dependencies

SwiftPM automatically resolves the following packages:

| Dependency | Purpose |
|------|------|
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering |
| [Highlightr](https://github.com/raspu/Highlightr) | Source-code syntax highlighting |

## 🗂 Project Structure

```
Sources/SkillManager/
├── App.swift          # App entry point, ContentView, and translation coordination
├── Models.swift       # Skill model, scanning, frontmatter parsing, and search
├── Views.swift        # Sidebar, list, details, and Skill Map
├── FilePreview.swift  # Markdown, image, SVG, and code previews
└── Translator.swift   # Translation cache
```

## 🔒 Security

SVG previews are rendered through an `<img>` data URI with a strict Content Security Policy. Scripts remain disabled even when a third-party SVG contains embedded `<script>` content.

## 📄 License

[MIT](LICENSE) © 2026 zyt2000123
