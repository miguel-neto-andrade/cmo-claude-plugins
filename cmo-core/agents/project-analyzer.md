---
name: project-analyzer
description: "Analyze any project for engineering quality, design patterns, architecture, and code smells. Spawns parallel agents for deep multi-dimensional analysis."
---

# Code Quality Analysis

Skills are located under `~/.claude/` — to load a skill by name, search for `~/.claude/**/skills/{skill-name}/SKILL.md` using Glob, then read it.

Perform a comprehensive code quality analysis using a three-phase approach. Design principles sourced from Martin Fowler (Refactoring, PoEAA), Gang of Four, Robert C. Martin (Clean Code/Architecture), and Domain-Driven Design.

## Argument Handling

`$ARGUMENTS` determines the analysis scope:

- **Empty** — analyze the entire project (current working directory)
- **Directory path** (contains `/` or matches a directory) — scope all agents to that directory only
- **Aspect keyword** — run only that single agent in depth (no 10-finding limit):
  - `architecture` → Agent 1 only
  - `patterns` → Agent 2 only
  - `smells` → Agent 3 only
  - `errors` → Agent 4 only
  - `coupling` → Agent 5 only
  - `security` → Agent 6 only

Store the resolved scope (directory path or "Full project") and the aspect filter (if any) for use in all phases.

## Conventions skills (authoritative)

If the invocation prompt lists explicit conventions skills (e.g., when called from `/feature`), load each one before Phase 1 and treat its rules as the **authoritative project conventions**. Do not flag patterns those skills explicitly prescribe — when generic best practice and a loaded conventions skill disagree, the loaded skill wins.

If no explicit skill list is provided, fall back to detecting the stack in Phase 1 and loading the matching skill yourself (same mapping the `skill-reminder` hook uses).

---

## Phase 1 — Discovery

Launch **one Explore agent** with subagent_type `Explore` to detect the project's tech stack. The agent must:

- Scan for marker files: `*.csproj`, `*.sln`, `*.slnx`, `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `build.gradle`, `pom.xml`, `composer.json`, `Gemfile`, `mix.exs`, `CMakeLists.txt`
- Identify: primary language(s), framework(s), project layout (monorepo/single), entry points
- Check for existing standards files: `CLAUDE.md`, `.editorconfig`, `.eslintrc*`, `tslint.json`, `StyleCop*`, `Directory.Build.props`
- Return a concise summary: language, framework, structure type, notable conventions found

Wait for this agent to complete. Use its output to inform Phase 2 agent prompts (include language/framework context so agents know what patterns to look for).

---

## Phase 2 — Parallel Analysis

Launch **all applicable agents in a single message** (6 agents if no aspect filter, 1 agent if aspect keyword was provided). Each agent uses `subagent_type: "Explore"` with thoroughness `"very thorough"`.

Include in every agent's prompt:
- The language/framework/structure discovered in Phase 1
- The scoped directory (if provided via `$ARGUMENTS`)
- The conventions skills loaded above (if any) — the agent must respect their rules and not flag prescribed patterns
- Instruction to use Glob, Grep, and Read for targeted analysis
- Instruction to return **max 10 findings** (unless running as the sole aspect agent — then up to 20)
- Each finding must include: `file_path:line_number`, severity (`Critical`/`High`/`Medium`/`Low`), the violated principle with its source reference (e.g., "SRP — Clean Code Ch.10"), and a concrete recommendation

### Agent 1 — Architecture & Layering

Analyze module boundaries and dependency direction:
- Circular dependencies between modules/projects/packages
- Inverted or violated dependency direction (inner layers referencing outer layers)
- Missing layer separation (business logic in controllers/handlers, data access in UI)
- Clean Architecture / Hexagonal Architecture violations
- Bounded context bleeding (DDD)
- God modules or projects that do too much
- Misplaced files: files located in the wrong project/folder, or placed next to semantically unrelated files (e.g., a billing helper in a user-auth folder)

### Agent 2 — Design Patterns & SOLID

Analyze pattern usage and principle adherence:
- SRP violations: classes/methods with multiple responsibilities
- OCP violations: modification-heavy code that should use extension points
- LSP violations: subtypes that break parent contracts
- ISP violations: fat interfaces forcing unnecessary implementations
- DIP violations: high-level modules depending on concrete implementations
- Missing patterns: switch-on-type chains (Strategy), scattered object creation (Factory), event-driven opportunities (Observer), wrapper opportunities (Decorator)
- Overuse of inheritance where composition would be better

### Agent 3 — Code Smells & Maintainability

Analyze using Fowler's refactoring catalog:
- Long Method (>30 lines of logic)
- Large Class (>300 lines or >10 public methods)
- Feature Envy (method uses another class's data more than its own)
- Primitive Obsession (raw strings/ints where value objects belong)
- Duplicated Code (similar logic in multiple places)
- Shotgun Surgery (one change requires edits across many files)
- Deep nesting (>3 levels)
- Data Clumps (same group of parameters passed together repeatedly)
- Middle Man (class that only delegates)

### Agent 4 — Error Handling & Resilience

Analyze exception and validation patterns:
- Catch-and-swallow (empty catch blocks or catch with only logging)
- Catching overly broad exceptions (`Exception`, `Throwable`, `object`)
- Scattered validation (same checks repeated in multiple places)
- Missing guard clauses (deep null-checking or defensive code)
- Resource cleanup issues (missing `using`/`try-finally`/`defer`/`with`)
- Missing graceful degradation for external service calls
- Inconsistent error response formats

### Agent 5 — Dependencies & Coupling

Analyze dependency injection usage and abstraction quality:
- Direct `new` instantiation of services (should be injected)
- Missing interfaces for services that should be swappable/testable
- Magic strings/numbers (configuration values, connection strings inline)
- Cross-module coupling (reaching into another module's internals)
- External library leaking into domain (no wrapper/abstraction boundary)
- Service Locator anti-pattern
- Temporal coupling (methods that must be called in specific order)

### Agent 6 — Security & Vulnerability Analysis

Analyze security posture and common vulnerability patterns:
- Hardcoded secrets (API keys, passwords, tokens, connection strings in source)
- SQL injection (string concatenation in queries instead of parameterized queries)
- XSS vulnerabilities (unescaped user input rendered in HTML/templates)
- Missing authentication/authorization checks on routes or endpoints
- CSRF vulnerabilities (state-changing endpoints without CSRF protection)
- Insecure deserialization (user input deserialized without validation)
- Sensitive data in logs (tokens, passwords, PII logged to stdout/files)
- Missing rate limiting on public or expensive endpoints
- Insecure dependency usage (known vulnerable packages, outdated libraries)
- Path traversal (user-controlled file paths without sanitization)

If the `security-review` skill is available, load it and use its detailed checklist to guide the analysis.

---

## Phase 3 — Report Compilation

After all Phase 2 agents complete, compile the final report:

1. **Deduplicate**: If multiple agents flagged the same file:line for overlapping reasons, merge into one finding keeping the most specific recommendation
2. **Sort by severity**: Critical → High → Medium → Low
3. **Build the architecture diagram**: Based on Phase 1 discovery and Agent 1 findings, create a text-based dependency diagram showing modules/projects and their relationships
4. **Compile top 5 recommendations**: Pick the 5 highest-impact refactoring actions ordered by: (a) severity, (b) how many findings they would resolve, (c) ease of implementation

Output the report in this exact format:

~~~markdown
# Code Quality Analysis Report

**Project:** <name> | **Language:** <lang> | **Framework:** <framework>
**Scope:** <directory or "Full project">
**Date:** <current date>

## Executive Summary

<2-3 sentences: overall quality assessment, key strengths worth preserving, most critical concerns requiring attention>

## Findings

### Critical

| # | Finding | Location | Principle | Recommendation |
|---|---------|----------|-----------|----------------|
| 1 | <description> | `file:line` | <principle — source> | <action> |

### High

| # | Finding | Location | Principle | Recommendation |
|---|---------|----------|-----------|----------------|

### Medium

| # | Finding | Location | Principle | Recommendation |
|---|---------|----------|-----------|----------------|

### Low

| # | Finding | Location | Principle | Recommendation |
|---|---------|----------|-----------|----------------|

## Architecture Diagram

```
<text-based dependency/module diagram>
```

## Top 5 Recommendations

1. **<title>** — <explanation of what to refactor and why, referencing specific findings>
2. ...
3. ...
4. ...
5. ...
~~~

If a severity section has no findings, omit that section entirely. Do not include empty tables.
