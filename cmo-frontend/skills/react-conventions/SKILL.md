---
name: react-conventions
description: Use when writing, reviewing, refactoring, or scaffolding React + TypeScript code in C-Mo repos. Covers the no-business-logic-on-frontend rule, function components and hooks (no class components), project layout, naming, TanStack Query for server state, Zustand for client state, React Router 6, React Hook Form, performance, accessibility, and the tooling chain.
---

# React Conventions

Conventions for React 18+ + TypeScript in C-Mo repositories. Built on the modern React defaults (function components, hooks, Vite or Next.js) plus the project-specific rules below.

## Where logic lives — the rule that comes first

**No business logic on the frontend.** The frontend renders state, collects input, shows validation feedback, and orchestrates API calls — nothing more. Anything that decides *what should happen* lives on the backend.

Business logic is anything that would:

- Compute a value the backend will also need to trust (pricing, taxes, fees, eligibility, scoring).
- Decide whether an action is permitted (authorisation, role checks, business-rule enforcement).
- Persist or transform domain state (workflow transitions, status changes, derived records).
- Enforce a domain invariant (e.g. "an order can't have more than 10 line items").

The frontend may **mirror** that logic for UX (disable a button while the API call is in flight, hide a menu item the user can't use, surface inline validation hints) — but the source of truth is the backend, and the backend must re-check every constraint. If the frontend is the only place a rule exists, the rule does not exist.

What's allowed on the frontend:

- **Presentation logic** — sorting / filtering an already-loaded list, formatting dates, currency, addresses.
- **UX state** — modal open/closed, accordion expanded, current tab, form draft.
- **Input validation as a hint** — `required`, `min`, `max`, basic shape checks. Always re-validated server-side.
- **API call orchestration** — when to fetch, when to retry, when to invalidate (TanStack Query handles most of this).

If you find yourself reaching for a lot of conditional logic in a component or custom hook, ask: *is this a decision the backend would care about?* If yes, it belongs on the backend.

## React language fundamentals

- **Function components + hooks** for every new component. Class components are legacy only.
- **TypeScript with `"strict": true`** in every `tsconfig.json`. Type errors fail the build.
- **One component per file**, file name matches the component (`UserCard.tsx`).
- **No HOC towers**, no render-prop gymnastics. Use hooks.
- **No global event bus.** Use props, context, or a store.

## Project structure

```
src/
├── main.tsx
├── App.tsx
├── router/             ← React Router config
├── stores/             ← Zustand stores (or Context for narrow trees)
├── api/                ← TanStack Query queries + mutations, grouped by resource
├── hooks/              ← useFoo() reusable hooks
├── components/         ← reusable components
├── pages/              ← route-target components
├── layouts/            ← app shell
├── types/              ← shared TS types and API DTOs
├── assets/             ← images, fonts, global styles
└── lib/                ← http client, utils
```

Group by feature inside `components/`, `pages/`, and `stores/` once a folder has more than ~20 components. Avoid one mega-folder of every component in the app.

## Component structure

```tsx
import { useMemo } from 'react';
import type { Invoice } from '@/types/invoice';
import './InvoiceCard.scss';

type InvoiceCardProps = {
  invoice: Invoice;
  compact?: boolean;
  onApprove: (id: string) => void;
  onReject: (id: string, reason: string) => void;
};

export function InvoiceCard({ invoice, compact = false, onApprove, onReject }: InvoiceCardProps) {
  const total = useMemo(
    () => formatCurrency(invoice.amount, invoice.currency),
    [invoice.amount, invoice.currency],
  );

  return (
    <article className={`invoice-card ${compact ? 'invoice-card--compact' : ''}`}>
      <h3>{invoice.number}</h3>
      <p>{total}</p>
      <button onClick={() => onApprove(invoice.id)}>Approve</button>
    </article>
  );
}
```

```
components/InvoiceCard/
├── InvoiceCard.tsx
└── InvoiceCard.scss
```

- **Named exports**, not default. Better for refactors, IDE rename, and grep.
- **`Props` type alias** with the `Props` suffix. Use `interface` only when actually extending one.
- **Don't destructure all props in the signature** when there are many — pull them inside the body for readability.

## Styles

**SCSS lives in its own `.scss` file, never as a string literal, styled-component, or `style={{…}}` block.** Import the sibling file at the top of the `.tsx` (`import './InvoiceCard.scss';`) and target it via `className`.

- **One `.scss` file per component**, named the same as the component, in the same folder.
- **Use BEM** to scope styles (`.invoice-card`, `.invoice-card__header`, `.invoice-card--compact`). BEM gives you scoping without CSS-in-JS overhead.
- **No CSS-in-JS** (`styled-components`, `emotion`, `@stitches`). Adds runtime cost, splits the SCSS conventions in `bootstrap-scss`, and makes styles ungreppable.
- **No inline `style={{…}}`** except for a genuinely dynamic numeric value (`style={{ width: `${progress}%` }}`) that can't be expressed as a class.
- **Global styles, design tokens, and Bootstrap overrides** live under `src/styles/` per `bootstrap-scss`.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Component file | PascalCase, matches component | `UserCard.tsx` |
| Hook | `camelCase`, prefix `use` | `useInvoiceList` |
| Store | `camelCase`, prefix `use`, suffix `Store` | `useInvoicesStore` |
| Props type | PascalCase, suffix `Props` | `UserCardProps` |
| Event handler prop | prefix `on`, PascalCase verb | `onSubmit`, `onRowClick` |
| Boolean prop | prefix `is`/`has`/`can` | `isLoading`, `hasError`, `canEdit` |

English everywhere — names, comments, log messages, copy.

## State management

Three buckets — pick the one that fits, don't reach for a heavier tool than needed.

### Server state — TanStack Query (default)

Use TanStack Query for anything fetched from an API: caching, deduplication, background refetch, loading / error states, optimistic updates. Replaces hand-rolled `useEffect` + `useState` loading/error scaffolding.

```ts
// src/api/invoices.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { http } from '@/lib/http';
import type { Invoice } from '@/types/invoice';

export const invoicesQueryKeys = {
  all: ['invoices'] as const,
  list: (filters: { status?: string } = {}) =>
    [...invoicesQueryKeys.all, 'list', filters] as const,
  detail: (id: string) => [...invoicesQueryKeys.all, 'detail', id] as const,
};

export function useInvoices(filters: { status?: string } = {}) {
  return useQuery({
    queryKey: invoicesQueryKeys.list(filters),
    queryFn: () => http.get<Invoice[]>('/api/invoices', { params: filters }),
  });
}

export function useApproveInvoice() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => http.post<Invoice>(`/api/invoices/${id}/approve`),
    onSuccess: (data, id) => {
      qc.invalidateQueries({ queryKey: invoicesQueryKeys.all });
      qc.setQueryData(invoicesQueryKeys.detail(id), data);
    },
  });
}
```

Conventions:

- **Hierarchical query keys** — `[resource, scope, params]` — so `invalidateQueries({ queryKey: ['invoices'] })` invalidates everything under `invoices`. Wrap them in a `queryKeys` object per resource so you never typo a key in two places.
- **One file per resource** under `api/` — co-locate queries, mutations, and the query-key object.
- **Never call `fetch` / `axios` directly from a component.** Always go through a TanStack Query hook so the cache layer stays consistent.
- **No global loading flag.** Each query exposes its own `isLoading` / `isFetching`. Compose in the component if you really need an aggregate.

### Client state — Zustand (default) / Context (narrow)

Zustand for cross-component client state. Context for narrow trees (theme, current user) where you don't need selectors. Redux Toolkit only in existing projects that already use it.

```ts
// src/stores/auth.ts
import { create } from 'zustand';
import type { User } from '@/types/user';

type AuthState = {
  user: User | null;
  setUser: (u: User | null) => void;
};

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  setUser: (user) => set({ user }),
}));
```

- One store per concern. Don't make a single `useAppStore` that holds everything.
- **Don't keep server data in Zustand.** TanStack Query owns it. Stores that mirror server entities go stale and cause double-source bugs.

### Local state — `useState` / `useReducer`

Default. Anything that lives and dies with the component. `useReducer` for multi-field state machines or when next-state depends on previous-state.

## Props, children, refs

- **Typed props** with a `Props` type alias.
- **`children: ReactNode`** when the component accepts arbitrary children.
- **Never mutate props.** Compute via `useMemo` or seed `useState` with a prop value (then it becomes local state).
- **`forwardRef`** only when a parent genuinely needs to reach into a DOM node. Don't expose refs as a generic API.
- **Boolean props default to `false`.** Don't pass `={true}` — just write the prop name.

## Hooks

- **Rules of Hooks** — top level only, never in conditionals, never in loops. The ESLint plugin enforces this; don't disable it.
- **Custom hooks return an object**, not an array (unless mirroring `useState`'s tuple).
- **`useEffect` is a last resort.** Most reasons you'd reach for it (data fetching, derived state from props) belong in TanStack Query or a `useMemo`. Use `useEffect` only for genuine side effects (subscriptions, imperative DOM, third-party libs).
- **`useCallback` / `useMemo`** — only when a measured profile shows a problem, or when the value feeds into a dependency array of another hook. Reflexive memoisation everywhere is noise.
- **One file per custom hook**, named after the function.

## Routing — React Router 6

- **Data routers (`createBrowserRouter`)** for new apps. The legacy `<BrowserRouter>` + `<Routes>` pattern works but loses loaders / actions.
- **Lazy-load route elements** — `lazy: () => import('@/pages/InvoiceDetail').then(m => ({ Component: m.InvoiceDetail }))`.
- **Loaders for navigation gating only** (e.g. redirect unauthenticated users), not for primary data fetching — TanStack Query owns that, and mixing loaders with the query cache produces coordination bugs. Let the page's `useQuery` fetch the data.
- **`<Link>` / `<NavLink>`** — never hand-roll `<a href>` for in-app navigation. Hand-rolled anchors break the SPA.

## Forms

- **React Hook Form** + Zod resolver as the default. Performant (uncontrolled by default), TS-friendly, plays well with TanStack Query mutations.
- **Schema-first validation** with Zod. The schema is the contract; the form derives field types and validation from it.
- **Client validation is a UX hint, never a security boundary.** The backend re-validates every field.
- **Submit handler calls a TanStack Query mutation.** The mutation owns loading / error / success state.

## Performance

- **Don't reach for `React.memo` reflexively.** It only helps when re-renders are measurable and the component is genuinely pure.
- **`useMemo` / `useCallback`** — same caveat. Profile first.
- **Code-split routes** (lazy-load, above).
- **Virtualised lists** — `@tanstack/react-virtual` for thousands of rows. Don't render 5 000 DOM nodes.
- **Suspense + Error Boundaries** for async UI — wrap routes / sections, not individual components.

## Accessibility

The frontend is the only place a11y exists. Take it seriously.

- **Semantic HTML first.** `<button>` not `<div onClick>`. `<nav>`, `<main>`, `<article>`, `<aside>` for landmarks. ARIA only when no semantic element fits.
- **Every interactive element is keyboard reachable.** Tab order matches visual order. Focus is visible — don't strip the outline without replacing it.
- **Labels** — every form input has a `<label htmlFor>` or `aria-label`.
- **Live regions** — `aria-live="polite"` on toast / inline alert containers so screen readers announce them.
- **Colour contrast** — meet WCAG AA at minimum (4.5:1 for body text, 3:1 for large text and UI). Don't rely on colour alone for state — pair with an icon or label.
- **`<img>` always has `alt`.** Decorative images get `alt=""`, not no attribute.

Run `axe-core` or Lighthouse against new pages before merge.

## Linting, formatting, type checking

| Concern | Tool |
|---|---|
| Linter | ESLint + `eslint-plugin-react` + `eslint-plugin-react-hooks` + `@typescript-eslint` |
| Formatter | Prettier (or Biome) |
| Type check | `tsc --noEmit` |
| Build | Vite (or Next.js) |

CI runs all four. Failing any of them fails the build.

## Testing

Frontend test conventions live in their own skill — load it when writing or reviewing tests:

- **`cmo-core/testing-standards`** — universal rules (tier model, two-level Jira traceability, parallelism, scenario coverage, anti-flake, naming, test data, source-mirror layout).
- **`cmo-frontend/frontend-testing`** — the frontend-specific *how*: Vitest, React Testing Library, MSW, TanStack Query in tests, Playwright for E2E.

## Quick reference

| Aspect | Rule |
|---|---|
| Business logic | Backend only. Frontend mirrors for UX. |
| Component style | Function components + hooks; no class components in new code |
| TypeScript | `"strict": true`, `.tsx` always |
| File-per-component | One component per `.tsx` file, PascalCase name |
| Exports | Named, not default |
| Server state | TanStack Query — never `fetch` / `axios` direct from a component |
| Client state | Zustand (default) or Context (narrow); never mirror server data |
| Local state | `useState` (or `useReducer` for state machines) |
| Props | `Props` type alias, never mutated, booleans default `false` |
| `useEffect` | Last resort — most uses belong in TanStack Query or `useMemo` |
| Memoisation | `memo` / `useMemo` / `useCallback` only with a profile or dep-array reason |
| Styles | Sibling `.scss` file per component (BEM-scoped); no CSS-in-JS; no inline `style` |
| Routing | React Router 6 data routers, lazy-loaded route elements |
| Forms | React Hook Form + Zod; client-side validation is a hint, not a boundary |
| Accessibility | Semantic HTML, labels, contrast, keyboard reachability |
| Lint / format / types | ESLint + plugins, Prettier/Biome, `tsc --noEmit` — CI gates all |
| Tests | See `cmo-core/testing-standards` + `cmo-frontend/frontend-testing` |
