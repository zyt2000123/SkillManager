# Skill Manager

> 浏览本机已安装的 Claude Code / Codex skills 的原生 macOS 应用

一个轻量、只读的 macOS App，自动扫描你机器上安装的 [Claude Code](https://claude.com/claude-code) 与 Codex skills，按主题归类、模糊搜索，并提供 Markdown / 图片 / SVG / 代码的文件预览。

## ✨ 功能

- **自动扫描** — 遍历 `~/.claude/skills`、`~/.codex/skills` 等位置，解析每个 `SKILL.md` 的 frontmatter
- **Skill 地图** — 按 安全审计 / 代码审查 / 调试 / 规划 / 文档 / 部署 / 测试 / 设计 / AI 等主题自动归类
- **模糊搜索** — 名字子序列匹配（`drv` → `design-review`）+ 描述/触发词子串，支持中文译文搜索
- **文件预览** — 文件树 + Markdown 渲染、代码语法高亮、图片与 SVG 预览；`SKILL.md` 开头的 YAML frontmatter 也渲染成代码块
- **英→中翻译** — 可选，基于 macOS Translation framework，译文缓存到磁盘，冷启动零延迟
- **深 / 浅色** — 一键切换

## 📦 安装

### 下载（推荐）

从 [Releases](https://github.com/zyt2000123/SkillManager/releases) 下载 `SkillManager.dmg`，打开后把 **SkillManager** 拖进 **Applications** 即可。

> ⚠️ App 未做 Apple 公证。首次打开若提示「无法验证开发者」，去 **系统设置 → 隐私与安全性**，点 **仍要打开**。

### 从源码构建

```bash
git clone https://github.com/zyt2000123/SkillManager.git
cd SkillManager
./run.sh          # 开发:构建(debug) + 打包 + 启动
./make-dmg.sh     # 分发:构建(release) + 打包成 SkillManager.dmg
```

## 🛠 要求

- macOS 15+
- Swift 6 工具链（Xcode 16+ 或独立 Swift toolchain）

## 📚 依赖

由 SwiftPM 自动拉取：

| 依赖 | 用途 |
|------|------|
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown 渲染 |
| [Highlightr](https://github.com/raspu/Highlightr) | 代码语法高亮 |

## 🗂 项目结构

```
Sources/SkillManager/
├── App.swift          # 入口 + ContentView + 翻译协调
├── Models.swift       # Skill 模型、扫描、frontmatter 解析、搜索
├── Views.swift        # 侧栏、列表、详情、Skill 地图
├── FilePreview.swift  # Markdown / 图片 / SVG / 代码预览
└── Translator.swift   # 翻译缓存
```

## 🔒 安全

SVG 预览经 `<img>` + data URI + CSP 渲染，强制禁用脚本——即使预览来自第三方的、内嵌 `<script>` 的恶意 SVG 也不会执行任何代码。

## 📄 许可证

[MIT](LICENSE) © 2026 yutaizhao-max
