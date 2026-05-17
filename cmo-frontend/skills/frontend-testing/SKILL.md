---
name: frontend-testing
description: Use when writing, reviewing, or scaffolding frontend tests in C-Mo repos — Vitest unit / component tests, Vue Test Utils or React Testing Library, MSW for network mocking, TanStack Query in tests, Playwright (default) or Cypress (legacy) for E2E, plus Capacitor-specific testing notes. Load alongside `cmo-core/testing-standards` for the universal tier model and Jira-traceability rules.
---

# Frontend Testing

Frontend tests for C-Mo repos. Defers to **`cmo-core/testing-standards`** for the universal rules: tier model (Unit / Integration / Functional / Performance), two-level Jira traceability (`Task` for unit + integration, `Requirement` for functional / e2e), test independence, parallel execution, scenario coverage, anti-flake rules, naming, test data, source-mirror layout.

This skill is the frontend-specific *how*.

## Tier mapping

| Tier | What it covers on the frontend | Tool |
|---|---|---|
| **Unit** | Pure functions, composables / hooks, formatters, utils. No DOM, no router, no API. | Vitest |
| **Integration** | A component rendered with its dependencies wired (router, query client, store) and the network mocked. The workhorse tier. | Vitest + Vue Test Utils / React Testing Library + MSW |
| **Functional / E2E** | The built app driven through a real browser against a real (or close-to-real) backend. | Playwright (default), Cypress (legacy projects only) |
| **Performance** | Bundle size, render time, Lighthouse scores. Run in CI, not per-PR. | Vite plugin analyzers, Lighthouse CI |

Most useful tests for most projects are **integration**. A pure-unit test that mocks the framework itself is usually testing the framework, not the code.

## Vitest setup

Vitest is the default runner — fast, ESM-native, drop-in compatible with the Vite config the app already has.

```ts
// vite.config.ts (or vitest.config.ts)
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: 'jsdom',         // 'happy-dom' is fine and faster for most tests
    globals: true,                // describe/it/expect without imports
    setupFiles: ['./test/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],
    },
  },
});
```

- **`environment: 'jsdom'`** for component tests. `'node'` for pure-unit tests that don't touch the DOM (Vitest auto-detects with the `// @vitest-environment node` directive at the top of a file).
- **`globals: true`** — call `describe` / `it` / `expect` without imports. Saves a line per file.
- **`setupFiles`** — register global mocks (MSW server, matchers, fake timers) here, not per-file.

## Vue Test Utils patterns

Mount once per test, assert on the rendered DOM through DOM queries (not Vue internals).

```ts
import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import InvoiceCard from './InvoiceCard.vue';

describe('InvoiceCard', () => {
  it('renders the invoice number and total', () => {
    const wrapper = mount(InvoiceCard, {
      props: { invoice: fakeInvoice({ number: 'INV-001', amount: 100 }) },
    });

    expect(wrapper.text()).toContain('INV-001');
    expect(wrapper.text()).toContain('€100.00');
  });

  it('emits approve when the approve button is clicked', async () => {
    const wrapper = mount(InvoiceCard, { props: { invoice: fakeInvoice({ id: 'abc' }) } });
    await wrapper.get('button[data-test="approve"]').trigger('click');
    expect(wrapper.emitted('approve')?.[0]).toEqual(['abc']);
  });
});
```

- **Query by data-test attribute** (`data-test="approve"`) for stable selectors. Class names change for styling reasons; data-test is part of the test contract.
- **`await` on every `trigger` / `setValue`** — Vue's reactivity flushes asynchronously.
- **Test the public contract** — props in, DOM + emits out. Don't reach into `wrapper.vm.someInternal` to assert.

## React Testing Library patterns

Same philosophy: query the DOM the way a user would, assert on the rendered output.

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { InvoiceCard } from './InvoiceCard';

describe('InvoiceCard', () => {
  it('renders the invoice number and total', () => {
    render(<InvoiceCard invoice={fakeInvoice({ number: 'INV-001', amount: 100 })} onApprove={vi.fn()} onReject={vi.fn()} />);
    expect(screen.getByText('INV-001')).toBeInTheDocument();
    expect(screen.getByText('€100.00')).toBeInTheDocument();
  });

  it('calls onApprove when the approve button is clicked', async () => {
    const onApprove = vi.fn();
    render(<InvoiceCard invoice={fakeInvoice({ id: 'abc' })} onApprove={onApprove} onReject={vi.fn()} />);
    await userEvent.click(screen.getByRole('button', { name: /approve/i }));
    expect(onApprove).toHaveBeenCalledWith('abc');
  });
});
```

- **Query by role / label / text first**, by `data-testid` only as a fallback. `getByRole('button', { name: /approve/i })` works for screen reader users too — if your test passes, your a11y is at least partially correct.
- **`userEvent` over `fireEvent`.** `userEvent` simulates the full event sequence a real user produces.
- **`waitFor` / `findBy*` for async** — these poll until the assertion passes or times out.

## Mocking the network

In an integration test, the component under test usually fires real `fetch` / `axios` calls (through its hooks / TanStack Query). Two ways to keep those calls from leaving the suite:

1. **`vi.mock('@/api/invoices')`** — replace your own query/mutation module with a stub. Cheap, zero deps. Right for a narrow unit test that only cares "did the component call `useInvoice`?" — but it skips the real query / cache / error paths, so a bug inside the hook won't fail the test.
2. **MSW (Mock Service Worker)** — intercept at the HTTP boundary. The component, the hook, TanStack Query, the http client all run exactly as they do in production; only the network response is faked. This is what you want for any integration test that exercises a real data path (which is most of them, per the tier mapping above).

**Default to MSW for the integration tier.** It catches bugs the module-mock approach can't (wrong URL, wrong headers, wrong response shape, broken retry/invalidation logic). Reach for `vi.mock` only when you genuinely don't need the HTTP layer in the test.

```ts
// test/setup.ts
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';

export const server = setupServer(
  http.get('/api/invoices/:id', ({ params }) =>
    HttpResponse.json(fakeInvoice({ id: params.id as string })),
  ),
);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

- **`onUnhandledRequest: 'error'`** — any request the tests didn't mock fails loudly. Stops silent network leaks.
- **Override handlers per test** with `server.use(http.get(…))` — defaults from `setup.ts`, overrides per scenario.
- **Don't mock `useInvoice` directly.** Mocking the hook hides bugs in the hook itself; mocking the network exercises the real query / cache / error paths.

## TanStack Query in tests

Tests need their own `QueryClient` — sharing one across tests leaks cache between them and produces flaky failures.

```ts
import { QueryClient, VueQueryPlugin } from '@tanstack/vue-query';

function renderWithQuery(component: any, props = {}) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },   // no retries, no cache across tests
      mutations: { retry: false },
    },
  });

  return mount(component, {
    props,
    global: {
      plugins: [[VueQueryPlugin, { queryClient }]],
    },
  });
}
```

(React equivalent: wrap in `<QueryClientProvider client={queryClient}>` inside a render helper.)

- **`retry: false`** in tests — retries hide errors and slow the suite. Real production behaviour is tested via E2E.
- **Fresh `QueryClient` per test** (a helper like above, or `beforeEach`).
- **Don't `await` query state by polling `isLoading`** — use `findBy*` (RTL) or `flushPromises()` + DOM assertions (VTU). The DOM is the source of truth.

## What to test

Pull from `cmo-core/testing-standards` for the scenario-coverage rules. Concretely on the frontend:

- **Happy path** for every component / page — does it render and respond?
- **Loading state** — does it show a sensible placeholder?
- **Error state** — does it show an error and offer retry (when applicable)?
- **Empty state** — does it show the empty state instead of broken layout?
- **Edge data** — long strings, zero, negative, missing optional fields.
- **User interactions that emit events / call props** — every callback path.

Skip:

- **Style assertions** — `expect(button).toHaveStyle({ color: 'red' })` is brittle and tests the framework. Use visual regression for that.
- **Implementation details** — internal state shape, method counts, etc.

## Locating backend repos

The backend a frontend talks to almost always lives in a separate repo. E2E tests need to reach it for fixtures (seed scripts, OpenAPI specs, test-user factories), and other frontend tooling (codegen, type sync, contract checks) needs the same. Don't hardcode paths — declare them once at the frontend repo root.

Convention: a `.cmo/backends.json` file at the frontend repo root, listing each backend the frontend depends on, with a stable name and the local path (relative to the frontend repo, resolvable from a sibling checkout).

```json
// .cmo/backends.json
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

Per-developer overrides go in `.cmo/backends.local.json` (gitignored) — for engineers who keep checkouts in non-standard locations.

Rules:

- **Read the config, don't hardcode.** Playwright `globalSetup`, codegen scripts, and any other tool that needs a backend path resolves it through a small helper (`getBackend('invoices-api').fixturesPath`).
- **Fail loudly if a referenced backend isn't checked out.** Better to error with "expected ../invoices-api, not found — clone it or override in `.cmo/backends.local.json`" than to silently 404 mid-test.
- **CI override via env vars** — `CMO_BACKEND_INVOICES_API_PATH=/workspace/invoices-api` overrides the JSON. CI mounts the sibling repos at known paths; engineers don't have to think about it.
- **Same config powers more than tests** — codegen (regenerating TS types from a sibling backend's OpenAPI), local-dev orchestration (which backends to spin up), contract-test runners. Define it once.

If the project doesn't have a backend in a sibling repo yet, skip this — but add the file the moment a second repo enters the picture.

## E2E — Playwright (default)

Playwright runs the built app in real browsers, drives it through real navigation, asserts on the actual rendered output. Default for new projects.

```ts
import { test, expect } from '@playwright/test';

test('user can approve an invoice', async ({ page }) => {
  await page.goto('/invoices');
  await page.getByRole('link', { name: 'INV-001' }).click();
  await page.getByRole('button', { name: 'Approve' }).click();
  await expect(page.getByText('Invoice approved')).toBeVisible();
});
```

- **Run against the production build**, not the dev server. Catches build-time issues (env vars, CSS purging, code-splitting).
- **One test = one user journey.** Don't bundle five unrelated assertions into one test.
- **Use `page.getByRole` / `getByLabel` / `getByText`** for selectors. Same accessibility-first logic as RTL.
- **Auto-wait is built in.** Don't sprinkle `page.waitForTimeout(500)` — that's a flake waiting to happen.
- **Tag tests with the Jira `Requirement`** (per `cmo-core/testing-standards`).

**Cypress is acceptable in legacy projects only** — don't start a new project with it.

## Capacitor / Ionic testing

- **Unit / component tests run exactly the same** as for web Vue/React (Vitest + VTU/RTL). The Ionic components render in jsdom.
- **Capacitor plugins** — mock the wrapper in `src/plugins/` (see `ionic-capacitor` skill). The wrapper has a web fallback for dev; tests mock the wrapper, not `@capacitor/core` directly.
- **E2E on the web build** — Playwright against `npm run build && npm run preview` catches the lion's share of UI regressions cheaply.
- **Real-device smoke tests** are unavoidable for native paths (camera, push, deep links, file system). Manual is fine; document the test plan in the PR.

## Coverage

Coverage is a smoke alarm, not a goal. Aim for **≥ 80 %** on lines and branches in `src/`. Configure exclusions for:

- Generated files (`.d.ts`, route maps).
- Throwaway scaffolding (Storybook stories, dev tools).
- The Vite / build config.

A test that exists to bump coverage without exercising a real scenario is worse than no test — it locks in implementation.

## Anti-flake

Carried over from `cmo-core/testing-standards`, with frontend specifics:

- **Never `setTimeout` in a test.** Use `vi.useFakeTimers()` + `vi.advanceTimersByTime()` when you genuinely need to test time-based behaviour.
- **No real network calls.** MSW intercepts; the suite must run offline.
- **Fresh `QueryClient` / store** per test — shared state across tests is a flake factory.
- **Fixed dates / IDs.** `Date.now()` and `Math.random()` are non-deterministic; stub them or pass them in.
- **No global mutable state.** If a test changes `localStorage`, restore it in `afterEach`.

## Tooling

| Concern | Tool |
|---|---|
| Runner | Vitest |
| Component (Vue) | Vue Test Utils |
| Component (React) | React Testing Library + `@testing-library/user-event` |
| Network mocking | MSW |
| E2E | Playwright (default); Cypress (legacy) |
| Coverage | Vitest's built-in v8 reporter |
| Visual regression | Playwright screenshots (opt-in per project) |

Run before pushing:

```
npm run lint
npm run typecheck
npm run test
npm run test:e2e   # if Playwright is set up
```

CI runs the same commands.

## Quick reference

| Aspect | Rule |
|---|---|
| Tier rules | See `cmo-core/testing-standards` |
| Default runner | Vitest with jsdom environment |
| Component tests | Vue Test Utils / React Testing Library; query by role / label / data-test |
| Network mocking | MSW with `onUnhandledRequest: 'error'` |
| TanStack Query | Fresh `QueryClient` per test, `retry: false`, `gcTime: 0` |
| E2E | Playwright against the prod build, one user journey per test |
| Capacitor plugins | Mock the wrapper, not `@capacitor/core` |
| Coverage | ≥ 80 % lines + branches in `src/`; smoke alarm, not goal |
| Anti-flake | No real network, no `setTimeout`, fresh state per test, fixed dates / IDs |
| CI | `lint + typecheck + test (+ test:e2e)` — same as local |
