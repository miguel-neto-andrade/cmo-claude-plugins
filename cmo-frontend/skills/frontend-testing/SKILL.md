---
name: frontend-testing
description: Use when writing, reviewing, or scaffolding frontend tests (Vitest, Vue Test Utils / React Testing Library, Playwright or Cypress for E2E, Capacitor-specific testing). Load alongside cmo-core/testing-standards.
---

# Frontend Testing

Defers to **`cmo-core/testing-standards`** for the universal rules: tier model (Unit / Integration / Functional / Performance), two-level Jira traceability (`Task` for unit + integration, `Requirement` for functional / e2e), independence and parallelism, scenario coverage, anti-flake rules, naming, test data, source-mirror layout.

This skill captures the frontend-specific *how*.

TODO — fill in:

- **Unit / component tests** — Vitest as the runner. Vue Test Utils for Vue, React Testing Library for React. What goes in a component test vs a hook/composable test.
- **TanStack Query in tests** — wrapping components in a fresh `QueryClient` per test; mocking the network at the fetch layer, not at the hook layer.
- **E2E** — Playwright vs Cypress decision and per-project standard.
- **Capacitor-specific testing** — web build under E2E, native smoke tests, plugin mocking.
- Coverage thresholds and what's exempt.
