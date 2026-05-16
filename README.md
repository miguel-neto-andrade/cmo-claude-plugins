# cmo-claude-plugins

Claude Code plugin marketplace for C-Mo Solutions. Bundles a language-agnostic core plugin plus per-stack plugins (Python, frontend/Vue, .NET, firmware) so every C-Mo engineer gets the same agents, commands, skills, and hooks regardless of which repo they're in.

## Plugins

| Plugin | Status | Scope |
|---|---|---|
| [`cmo-core`](./cmo-core/README.md) | Filled | Language-agnostic: code review, project analysis, git/PR, Jira task creation, `coding-standards` + `testing-standards` + `security-review` + `git-operations` skills, skill-reminder hook |
| `cmo-python` | Scaffold | Python-specific agents, commands, and skills |
| `cmo-frontend` | Scaffold | Vue, React, Bootstrap+SCSS, internal design system, Ionic+Capacitor, and frontend-testing skill scaffolds (TODO bodies) |
| `cmo-dotnet` | Skill only | `dotnet-conventions` (language, EF Core, ASP.NET Core) and `dotnet-testing` (xUnit on MTP, `WebApplicationFactory<Program>`, Testcontainers, CQRS handler patterns, Razor view/form probes — defers to `cmo-core/testing-standards` for the universal rules) skills filled. `dotnet-reviewer` agent and `/dn-new-controller` command are TODO scaffolds. |
| `cmo-firmware` | Scaffold | Firmware-specific agents, commands, and skills |

`cmo-core` is the only plugin with fully written content today. The stack-specific plugins are placeholders (TODO bodies) that Miguel fills in as conventions stabilise per stack.

## Installation

### 1. Add the marketplace

In any Claude Code session:

```
/plugin marketplace add https://github.com/miguel-neto-andrade/cmo-claude-plugins
```

This registers the marketplace under the name `cmo-claude-plugins` (read from `.claude-plugin/marketplace.json`).

### 2. Install the plugins you want

```
/plugin install cmo-core@cmo-claude-plugins
/plugin install cmo-python@cmo-claude-plugins
/plugin install cmo-frontend@cmo-claude-plugins
/plugin install cmo-dotnet@cmo-claude-plugins
/plugin install cmo-firmware@cmo-claude-plugins
```

Install only what you need — most engineers want `cmo-core` plus one stack plugin matching the repo they're in.

### 3. (Optional) Configure `cmo-core` for Jira

`cmo-core` ships the `/create-jira-task` command, which needs a per-developer API token and a per-project config file. Setup is documented in [`cmo-core/README.md`](./cmo-core/README.md) — skip it if you don't use Jira from Claude Code.

### 4. Updating

```
/plugin marketplace update cmo-claude-plugins
```

then reinstall any plugins you want to refresh.

## Repo layout

```
cmo-claude-plugins/
├── .claude-plugin/
│   └── marketplace.json     # registers all five plugins
├── cmo-core/                # filled
│   ├── .claude-plugin/plugin.json
│   ├── agents/              # code-reviewer, project-analyzer
│   ├── commands/            # /pr, /clear-repo, /create-jira-task
│   ├── skills/              # coding-standards, testing-standards, security-review, git-operations
│   └── hooks/               # skill-reminder
├── cmo-python/              # scaffold — placeholder agents/commands/skills
├── cmo-frontend/            # scaffold — six skill scaffolds split by concern (TODO bodies)
├── cmo-dotnet/              # skills filled (dotnet-conventions, dotnet-testing); agent + command TODO
└── cmo-firmware/            # scaffold
```

Every plugin follows the same layout: `.claude-plugin/plugin.json` for metadata, then any of `agents/`, `commands/`, `skills/`, `hooks/` as needed.

## Contributing

Open a PR. Each plugin's `README.md` (where present) is the source of truth for that plugin's contents and setup. When adding a new plugin, also add an entry to `.claude-plugin/marketplace.json`.
