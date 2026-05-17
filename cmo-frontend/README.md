# cmo-frontend

Frontend skills for the cmo-claude-plugins marketplace. Six skills covering Vue 3 + TypeScript, React 18 + TypeScript, Bootstrap 5 + SCSS, the C-Mo Internal Design System, Ionic + Capacitor, and the frontend testing stack. All enforce the **no-business-logic-on-frontend** rule and TanStack Query for server state.

## What's inside

| Skill | Purpose |
|---|---|
| `vue-conventions` | Vue 3 + Composition API + `<script setup>`, Pinia, TanStack Vue Query, Vue Router, forms, a11y |
| `react-conventions` | React 18 function components + hooks, Zustand, TanStack Query, React Router 6, React Hook Form, a11y |
| `bootstrap-scss` | Bootstrap 5 + SCSS file structure, override order, `.container > .row > .col` layout hierarchy, BEM |
| `cmo-design-system` | When to prefer the C-Mo Internal Design System over Bootstrap; defers to the in-package skill |
| `ionic-capacitor` | Mobile apps on Ionic + Capacitor, plugin wrappers, web fallbacks |
| `frontend-testing` | Vitest, Vue Test Utils / React Testing Library, MSW, TanStack Query in tests, Playwright (E2E) — defers to `cmo-core/testing-standards` for the universal rules |

## Setup

Most skills work out of the box. **Projects whose backend lives in another repo** should add a backends config so E2E tests, codegen, and contract tools resolve sibling-repo paths through one place. Without it, those tools have to hardcode `../some-backend` paths and break on any non-standard checkout layout.

### 1. Add `.cmo/backends.json` to the frontend repo

Create the file at the frontend repo root. Commit it — every dev on the project should get the same defaults.

```json
{
  "backends": {
    "invoices-api": {
      "repo": "git@github.com:c-mo-medical-solutions/invoices-api.git",
      "localPath": "../invoices-api",
      "fixturesPath": "tests/fixtures",
      "openapiPath": "docs/openapi.yaml"
    },
    "auth-api": {
      "repo": "git@github.com:c-mo-medical-solutions/auth-api.git",
      "localPath": "../auth-api",
      "fixturesPath": "tests/fixtures"
    }
  }
}
```

Field reference:

| Field | What it is |
|---|---|
| `backends.<name>` | Stable name your tooling uses to refer to this backend (`getBackend('invoices-api')`). Keep it short, kebab-case, repo-derived |
| `repo` | Clone URL — informational only, so a new dev can run `git clone` if the local path is missing |
| `localPath` | Path to the checked-out backend repo, **relative to the frontend repo root**. Assumes a sibling checkout (`../<repo-name>`); engineers with non-standard layouts override per-dev (see step 2) |
| `fixturesPath` | Path inside the backend repo where its test fixtures live (seed scripts, factory data, JSON dumps). Resolved as `<localPath>/<fixturesPath>` |
| `openapiPath` | Optional. Path inside the backend repo to its OpenAPI spec — for type codegen and contract checks |

Add as many backends as the frontend talks to. If the project has exactly one backend, the file still earns its keep — it documents *which* backend and where to find it.

### 2. (Per-developer) `.cmo/backends.local.json` for non-standard checkouts

Engineers who keep their checkouts somewhere other than `../<repo-name>` override the local path without touching the committed config:

```json
{
  "backends": {
    "invoices-api": { "localPath": "/Users/me/work/c-mo/invoices-api" }
  }
}
```

Only the keys you override need to appear. Add `.cmo/backends.local.json` to `.gitignore` — it's per-developer.

### 3. (CI) Environment-variable overrides

CI mounts sibling repos at known absolute paths. Override the JSON without editing files:

```bash
export CMO_BACKEND_INVOICES_API_PATH=/workspace/invoices-api
export CMO_BACKEND_AUTH_API_PATH=/workspace/auth-api
```

Naming: `CMO_BACKEND_<NAME_UPPER_SNAKE>_PATH`. Tooling reads env first, then `.local.json`, then `.json`.

### 4. Verify

A quick check that resolution works — adapt to whatever helper your repo uses:

```ts
// scripts/check-backends.ts
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const cfg = JSON.parse(readFileSync('.cmo/backends.json', 'utf8'));
for (const [name, b] of Object.entries<any>(cfg.backends)) {
  const envOverride = process.env[`CMO_BACKEND_${name.toUpperCase().replace(/-/g, '_')}_PATH`];
  const path = envOverride ?? resolve(b.localPath);
  console.log(`${name}: ${path} ${existsSync(path) ? 'OK' : 'MISSING'}`);
}
```

```
$ tsx scripts/check-backends.ts
invoices-api: /Users/me/work/c-mo/invoices-api OK
auth-api:     /Users/me/work/c-mo/auth-api OK
```

If a backend resolves to `MISSING`, either clone it next to the frontend repo or add a `localPath` override in `.cmo/backends.local.json`.

## Notes

- **Don't hardcode `../some-backend` paths** anywhere in the frontend repo — read through the config so the per-dev / CI override mechanism keeps working.
- **Fail loudly when a referenced backend isn't checked out.** Better to error with "expected `../invoices-api`, not found — clone it or set `CMO_BACKEND_INVOICES_API_PATH`" than to silently 404 mid-test.
- **The config powers more than tests** — codegen (regenerating TS types from a sibling backend's OpenAPI), local-dev orchestration scripts, contract-test runners. Define backends once; reuse everywhere.
- **`.cmo/backends.local.json` and `.claude/` must stay out of git.** The repo-level `.gitignore` should cover both; `cmo-core/git-operations` enforces it.
