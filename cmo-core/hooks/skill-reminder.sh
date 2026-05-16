#!/bin/bash
# Skill-loading reminder — injected on every user prompt submission.
# Outputs a <system-reminder> block that becomes authoritative context for the model.
#
# MAINTAINER NOTE: When adding a new skill to any plugin's skills/ directory,
# update the skill list below so the model knows about it.

cat <<'EOF'
<system-reminder>
You MUST load the appropriate skill(s) via the Skill tool BEFORE writing, reviewing, or modifying any code. If you have not loaded the relevant skills yet, do so NOW before proceeding.

Invoke as: Skill(skill="<name>") — e.g., Skill(skill="git-operations")

Available skills and when to load them:
- coding-standards — ANY code work (universal, load alongside language-specific skills)
- testing-standards — ANY test work (universal: tier model, two-level Jira traceability, parallelism, scenario coverage); load alongside the language-specific testing skill
- git-operations — ANY git/GitHub operation (commit, push, branch, PR, issue)
- security-review — Security audits, auth/input validation review
- python-conventions — Python ≥ 3.10 (naming, type hints, docstrings, pytest, ruff/mypy, project layout)
- vue-conventions — Vue 3 frontend work (SFCs, Composition API, Pinia, Vue Router, TypeScript)
- react-conventions — React frontend work (function components, hooks, React Router, TanStack Query, TypeScript)
- bootstrap-scss — Bootstrap 5 + custom SCSS (utility usage, theming, overrides, SCSS file structure)
- cmo-design-system — C-Mo internal apps importing the C-Mo Internal Design System (component imports, theme tokens, migration off raw Bootstrap)
- ionic-capacitor — Ionic + Capacitor mobile apps (Ionic components, Capacitor plugins, platform-specific code, native build)
- frontend-testing — Frontend tests (Vitest, Vue Test Utils / React Testing Library, Playwright/Cypress, Capacitor testing) — load with testing-standards
- dotnet-conventions — C# / .NET Core (ASP.NET Core, EF Core)
- dotnet-testing — Writing, reviewing, or scaffolding .NET tests (xUnit on MTP, WebApplicationFactory, Testcontainers, CQRS handlers, Razor view/form probes, BenchmarkDotNet) — load with testing-standards
- firmware-conventions — Embedded firmware work (C/C++, PlatformIO, CMake)

Multiple skills often apply together — e.g.:
- .NET code: coding-standards + dotnet-conventions
- .NET tests: coding-standards + testing-standards + dotnet-testing (+ dotnet-conventions if also touching production code)
- Vue frontend: coding-standards + vue-conventions + bootstrap-scss (+ cmo-design-system on internal apps, + ionic-capacitor on mobile apps)
- React frontend: coding-standards + react-conventions + bootstrap-scss (+ cmo-design-system on internal apps, + ionic-capacitor on mobile apps)
- Frontend tests: coding-standards + testing-standards + frontend-testing (+ the relevant framework skill if also touching production code)
- Any language tests: coding-standards + testing-standards + the stack's testing skill

Load ALL that match.
</system-reminder>
EOF
