---
name: coding-standards
description: Universal coding standards — SOLID principles, Fowler's refactoring catalog, and clean code fundamentals. Use when writing, reviewing, refactoring, or discussing code quality, design patterns, or architecture in any language. Requires running the project-analyzer agent after implementing new functionality.
---

# Coding Standards

Universal principles that apply regardless of language or framework. Stack-specific rules live in dedicated skills (e.g., `dotnet-standards`).

## SOLID Principles

- **SRP** — A class/module has one reason to change. Split when responsibilities diverge.
- **OCP** — Extend behavior without modifying existing code. Use abstractions, strategy patterns, or composition.
- **LSP** — Subtypes must be substitutable for their base types without breaking behavior.
- **ISP** — Prefer small, focused interfaces over fat ones that force unnecessary implementations.
- **DIP** — Depend on abstractions, not concretions. High-level modules should not import low-level details.

## Clean Code Essentials

- Functions should do one thing and be short (<30 lines of logic)
- Classes should be small (<300 lines) and cohesive
- Use early returns to reduce nesting (max 3 levels)
- Name things clearly — no abbreviations, no single-letter variables in non-trivial contexts
- No magic numbers — use named constants
- No dead code — delete it, don't comment it out

## Fowler's Code Smells

Watch for and refactor these:

- **Feature Envy** — method uses another class's data more than its own
- **Primitive Obsession** — raw strings/ints where value objects belong
- **Data Clumps** — same group of parameters passed together repeatedly
- **Shotgun Surgery** — one change requires edits across many files
- **Middle Man** — class that only delegates without adding value
- **Duplicated Code** — extract shared logic into reusable functions

## Error Handling

- Never swallow exceptions (empty catch blocks)
- Don't catch overly broad exceptions — be specific
- Clean up resources properly (`using`, `try-finally`, `defer`, `with`)
- Validate at system boundaries (user input, external APIs), trust internal code

## Prefer Proven Libraries

Before implementing non-trivial functionality from scratch, search for well-maintained open-source libraries that solve the problem. Evaluate by npm downloads / NuGet downloads, GitHub stars, bundle size, and maintenance activity. Use a proven library when it covers 80%+ of the requirement — only build custom when no suitable library exists or when the dependency cost outweighs the implementation effort.

## Mandatory Post-Implementation Review

After implementing any new feature, module, or significant code change, you **MUST** run the `project-analyzer` agent before considering the task done.

**When to run:**
- New features, endpoints, modules, services, or components
- Significant refactors or non-trivial bug fixes

**Do NOT run after:** Q&A, read-only exploration, trivial changes (typos, import reordering)

**How to run:** `@agent-cmo-core:project-analyzer <path>` scoped to changed directory, or at project root if changes span multiple directories.

**Handling findings:** Critical/High must be fixed. Medium should be fixed unless deprioritized by user. Low is informational.
