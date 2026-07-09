# SkillManager

> Agent SkillOps control panel for discovering, installing, configuring, validating, governing, and migrating skills across AI agents.

SkillManager is a cross-agent skill asset manager. It helps developers manage the capabilities of Agent, Coding Agent, and IDE Agent environments such as OpenClaw, Codex, ClaudeCode, and Hermess.

The product goal is not to become another skill list or plugin marketplace. SkillManager is designed to become the control plane for agent capabilities: what skills exist, where they are installed, how they are configured, whether they are compatible, what permissions they need, and whether they can actually run.

## Core Value

SkillManager solves a practical problem in the current agent ecosystem:

- Skills are scattered across different agents, directories, and plugin systems.
- Skill assets are mixed with plugin assets: direct Skill folders, plugin-provided Skills, MCP entries, CLI setup, and manual configuration all live in different places.
- Configuration state is hard to see: missing API keys, missing dependencies, wrong paths, and insufficient permissions.
- Compatibility is unclear: the same skill may work in one agent but not another.
- Risk is invisible: skills may need shell access, file read/write, network access, browser access, or tokens.
- Environments are hard to migrate: switching agents or machines makes skill state difficult to restore.

The core user workflow should be:

```text
Find Skill -> Install Skill -> Configure Skill -> Validate Skill -> Manage Skill -> Migrate Skill
```

## Product Positioning

SkillManager is an **Agent SkillOps platform**.

It combines:

- Skill Registry
- Agent Platform Adapter
- Installer
- Config Manager
- Permission Inspector
- Version Manager
- Migration Tool

In user terms, it should help people:

- find skills
- install skills
- configure skills
- verify skills
- manage skills
- migrate skills

## Current Capabilities

The current macOS app focuses on local discovery and inspection:

- **Cross-agent discovery**: scans local skills for OpenClaw, Codex, ClaudeCode, and Hermess.
- **Agent asset grouping**: separates direct `Skill` assets from plugin-provided `Plugin` assets under each agent.
- **Host-based plugin classification**: treats plugin caches as installed state for the host agent; embedded adapters for other agents are not counted as installed on those agents.
- **Skill Market**: reads GitHub-hosted marketplace manifests for Claude Code and Codex plugin ecosystems.
- **Skill Map**: groups skills by topic, such as security, review, debugging, planning, documentation, testing, design, deployment, and AI.
- **Local file inspection**: previews Markdown, images, SVG files, YAML, scripts, and source code.
- **Search**: supports fuzzy name matching, descriptions, trigger keywords, and translated text.
- **Multi-language translation**: uses the macOS Translation framework, auto-detects source text, and caches translations per target language.
- **On-demand language downloads**: lets users pre-download the current translation language through the system Translation framework.
- **Theme switching**: supports dark and light appearances.

## Target Product Shape

SkillManager should evolve from a skill browser into an agent capability manager.

### 1. Skill Map

The Skill Map is the local installed-skill discovery surface. It should answer:

- What skills are available?
- Which agents support them?
- How are they installed?
- What are they useful for?
- What permissions and dependencies do they need?
- Are they already installed?
- Are they configured correctly?
- Are they safe to use?

### 2. Skill Market

The Skill Market is the remote discovery surface. It should aggregate GitHub-hosted marketplaces and registries before anything is installed locally.

The first supported marketplace patterns are:

| Pattern | Example |
| --- | --- |
| Claude marketplace manifest | `.claude-plugin/marketplace.json` |
| Codex marketplace manifest | `.agents/plugins/marketplace.json` |
| Registry-first marketplace | `registry/plugins.json` |

The market should show:

- marketplace source
- supported agents
- plugin name, version, category, author, and repository
- installation policy and authentication requirements
- install command per target agent
- whether the plugin is already installed locally

Each skill should eventually expose:

| Field | Purpose |
| --- | --- |
| Name | Human-readable skill name |
| Description | One-line capability summary |
| Supported agents | OpenClaw, Codex, ClaudeCode, Hermess, and future platforms |
| Asset source | Skill, Plugin, MCP, CLI, manual |
| Category | Programming, search, automation, documents, data, security, etc. |
| Dependencies | Node, Python, CLI tools, MCP servers, API keys, local services |
| Permissions | Filesystem, shell, network, browser, GitHub, tokens |
| Version | Installed and latest versions |
| Status | Installed, not installed, needs config, update available, incompatible |
| Risk level | Low, medium, high |

### 3. Platform Profiles

Each agent should be treated as a runtime profile, not just a filter group.

A platform profile should show:

- platform version
- detected config paths
- installed skills
- compatible installable skills
- Skill vs Plugin asset counts
- skills that need configuration
- available updates
- dependency and permission issues

Example target structure:

```text
Codex
├── Overview
├── Installed
├── Needs Config
├── Updates
├── Skill
└── Plugin
```

### 4. Skill Control Panel

A skill detail page should become a control panel, not just a README preview.

It should show:

- capability summary
- supported platforms
- install status per platform
- install method
- required permissions
- dependency checks
- config schema
- version history
- usage examples
- compatibility matrix
- install, update, uninstall, validate, and migrate actions

Example:

```text
GitHub PR Reviewer

Capability:
Reads pull request diffs, summarizes risks, and helps generate review comments.

Platforms:
Codex: not installed
ClaudeCode: installed v1.2.0
OpenClaw: needs config
Hermess: unsupported

Required config:
GITHUB_TOKEN: missing
DEFAULT_REVIEW_STYLE: strict

Actions:
Install to Codex
Update ClaudeCode
Copy config to OpenClaw
Validate installation
```

### 5. Install and Configure Flow

The product should make complex skills feel one-click installable.

Recommended installation flow:

```text
Select Skill
-> Detect compatibility
-> Show dependencies and permissions
-> Choose target agent
-> Install files or plugin
-> Write agent config
-> Validate runtime availability
-> Complete or rollback
```

This is the product's strongest value: turning scattered files, config, dependencies, and permissions into a visible, reversible workflow.

### 6. My Skills

The app needs a management view separate from discovery.

Recommended sections:

```text
My Skills
├── Installed
├── Needs Config
├── Update Available
├── Failed Installations
└── High Risk
```

This moves the product from "browsing skills" to "managing agent capability state."

## Product Boundaries

SkillManager should do:

- skill discovery
- compatibility detection
- installation
- configuration
- update and uninstall
- validation
- migration and sync
- permission and risk visibility

SkillManager should not start as:

- a full agent runtime
- a workflow builder
- an agent orchestration framework
- a hosted skill execution platform
- a heavy enterprise policy system
- a skill code editor

Product boundary:

> SkillManager does not run the agent for you. It helps you install, configure, validate, govern, and migrate the agent's capabilities.

## MVP Direction

The first strong product loop is:

```text
User finds a skill
-> chooses an agent
-> installs it
-> fills required config
-> validates it works
-> manages updates later
```

MVP priorities:

| Priority | Capability |
| --- | --- |
| P0 | Skill list, agent grouping, Skill/Plugin asset grouping |
| P0 | Skill Market with GitHub marketplace manifests |
| P0 | Skill detail/control panel |
| P0 | Install, uninstall, and update actions |
| P0 | Config form and missing config detection |
| P0 | Install validation |
| P1 | Installed skill management |
| P1 | Compatibility matrix |
| P1 | Permission and risk summary |
| P1 | Batch install |
| P2 | Ratings, favorites, recommendations |
| P2 | Team sharing |
| P2 | Install templates |
| P3 | Organization policies and audit |

## Suggested Information Architecture

The current app is close to the right direction, but it is still mostly agent/category browsing. The target structure should make management states first-class:

```text
Navigation
├── Skill Map
├── Skill Market
├── My Skills
│   ├── Installed
│   ├── Needs Config
│   ├── Updates
│   └── High Risk
├── Platforms
│   ├── OpenClaw
│   ├── Codex
│   ├── ClaudeCode
│   └── Hermess
├── Install Tasks
├── Config Center
└── Security & Permissions
```

If keeping the current sidebar style, the next step should be:

```text
Skill Map
Skill Market
My Skills
├── Installed
├── Needs Config
└── Updates
OpenClaw
├── All
├── Skill
└── Plugin
Codex
├── All
├── Skill
└── Plugin
ClaudeCode
├── All
├── Skill
└── Plugin
Hermess
├── All
├── Skill
└── Plugin
```

## Installation

### Download

Download `SkillManager.dmg` from Releases, open it, and drag **SkillManager** into **Applications**.

The app may not be notarized in early builds. If macOS cannot verify the developer on first launch, open **System Settings -> Privacy & Security** and click **Open Anyway**.

### Build from source

```bash
git clone https://github.com/zyt2000123/SkillManager.git
cd SkillManager
./run.sh
./make-dmg.sh
```

## Requirements

- macOS 15+
- Swift 6 toolchain, Xcode 16+, or standalone Swift toolchain

## Dependencies

| Dependency | Purpose |
| --- | --- |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering |
| [Highlightr](https://github.com/raspu/Highlightr) | Source-code syntax highlighting |

## Project Structure

```text
Sources/SkillManager/
├── App.swift          # App entry point, ContentView, and translation coordination
├── Models.swift       # Skill model, scanning, frontmatter parsing, and search
├── Views.swift        # Sidebar, list, details, and Skill Map
├── FilePreview.swift  # Markdown, image, SVG, and code previews
└── Translator.swift   # Translation cache
```

## Security

Agent skills can request powerful capabilities. SkillManager should make these requirements visible before installation:

- filesystem read/write
- shell execution
- network access
- browser automation
- GitHub or other SaaS tokens
- local services and MCP servers

SVG previews are rendered through an `<img>` data URI with a strict Content Security Policy. Scripts remain disabled even when a third-party SVG contains embedded script content.

## License

[MIT](LICENSE) © 2026 zyt2000123
