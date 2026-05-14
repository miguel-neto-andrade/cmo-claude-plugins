# cmo-claude-plugins — context for Claude Code

This repo is a **Claude Code plugin marketplace**, not application code. Everything here is consumed by other Claude Code sessions in other repos via `/plugin marketplace add` + `/plugin install`. Keep that in mind when editing — a typo in a plugin file breaks every engineer's tooling, not just the local repo.

## What's here

Five plugins published from one marketplace:

- `cmo-core` — language-agnostic. **Fully written.** Agents, commands, skills, and a `UserPromptSubmit` hook that reminds the model to load skills.
- `cmo-python`, `cmo-frontend`, `cmo-dotnet`, `cmo-firmware` — stack-specific. **Scaffolds only.** Files exist with `TODO` bodies; real content gets filled in by Miguel as conventions stabilise.

The top-level `.claude-plugin/marketplace.json` is the registry — every plugin must be listed there to be installable.

## Conventions

- **Plugin layout** — each plugin directory contains `.claude-plugin/plugin.json` (metadata) plus any of `agents/`, `commands/`, `skills/`, `hooks/`. The `cmo-core` plugin is the reference implementation; copy its structure when adding new plugins.
- **Scaffolds stay scaffolds** — when adding new plugins/commands/agents/skills, write `TODO` bodies only. Miguel fills in the real content himself. Do **not** preemptively write plausible content for new components.
- **Don't edit `cmo-core` content unless asked** — it's the only filled plugin and is in active use across multiple C-Mo repos. Treat changes there as production changes.
- **READMEs are real docs, not placeholders** — `cmo-core/README.md` is fleshed out because users read it during plugin setup. The repo-level `README.md` is also fleshed out (installation instructions). Other plugin READMEs can be added as those plugins get filled.
- **Hook scripts must stay executable** — `cmo-core/hooks/skill-reminder.sh` is referenced via `${CLAUDE_PLUGIN_ROOT}`. If you add a new hook script, make sure it has the executable bit set.

## Common tasks

- **Add a new plugin** — create the directory with `.claude-plugin/plugin.json`, scaffold any `agents/commands/skills/hooks` subdirs with TODO bodies, and append an entry to `.claude-plugin/marketplace.json`.
- **Add a new agent/command/skill to an existing plugin** — drop the file under the appropriate subdir. For skills, use the `---\nname: ...\ndescription: ...\n---` frontmatter. For commands, use a Markdown file under `commands/` (the filename becomes the slash command). For agents, use a Markdown file under `agents/`.
- **Bump a version** — update `version` in both the plugin's `plugin.json` and the marketplace entry in `.claude-plugin/marketplace.json`.

## What to ignore

- `.git/` — standard git internals.
- The parent `PycharmProjects/` directory contains many unrelated C-Mo repos; if a search seems to leak outside `cmo-claude-plugins/`, narrow the path.

## Out of scope

This repo doesn't run any application code, doesn't have a test suite, and doesn't have CI beyond GitHub defaults. Don't propose adding any of that unless explicitly asked — the value of this repo is in the plugin definitions themselves, not the surrounding tooling.
