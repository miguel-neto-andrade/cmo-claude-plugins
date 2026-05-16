---
name: vue-conventions
description: Use when writing, reviewing, refactoring, or scaffolding Vue 3 + TypeScript code in C-Mo repos. Covers the no-business-logic-on-frontend rule, Composition API + `<script setup>`, project layout, naming, Pinia for client state, TanStack Vue Query for server state, props / emits / composables, Vue Router, forms, performance, accessibility, and the tooling chain.
---

# Vue Conventions

Conventions for Vue 3 + TypeScript in C-Mo repositories. Built on the modern Vue defaults (Composition API, `<script setup>`, Vite, Pinia) plus the project-specific rules below.

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

If you find yourself reaching for a lot of conditional logic in a component or composable, ask: *is this a decision the backend would care about?* If yes, it belongs on the backend.

## Vue language fundamentals

- **Vue 3 + Composition API + `<script setup>`** for every new component. Options API and the un-sugared `setup()` function are legacy only; never reach for them in new code.
- **TypeScript with `"strict": true`** in every `tsconfig.json`. `noImplicitAny`, `strictNullChecks`, the lot. Type errors fail the build.
- **`<script setup lang="ts">`** — never `lang="js"`.
- **One component per file.** File name matches the component (`UserCard.vue`).
- **No mixins.** Use composables.
- **No global event bus.** Use props / emits, provide / inject, or a Pinia store.

## Project structure

```
src/
├── main.ts
├── App.vue
├── router/
│   └── index.ts
├── stores/              ← Pinia client-state stores
├── api/                 ← TanStack Query queries + mutations, grouped by resource
├── composables/         ← useThing() reusable Composition API logic
├── components/          ← reusable presentational + container components
├── views/               ← route-target components (or pages/)
├── layouts/             ← app shell, page chrome
├── types/               ← shared TS types and API DTOs
├── assets/              ← images, fonts, global styles
└── plugins/             ← Vue plugin registration (i18n, sentry, …)
```

Group by feature inside `components/`, `views/`, and `stores/` once a folder has more than ~20 components. Avoid one mega-folder of every component in the app.

## Single-file component structure

Order inside an SFC: `<script setup>`, then `<template>`, then `<style scoped>`. Readers reach for the script first to understand what the component is, the template to see what it renders, and the style last.

```vue
<script setup lang="ts">
import { computed } from 'vue';
import type { Invoice } from '@/types/invoice';

const props = defineProps<{
  invoice: Invoice;
  compact?: boolean;
}>();

const emit = defineEmits<{
  (e: 'approve', id: string): void;
  (e: 'reject', id: string, reason: string): void;
}>();

const total = computed(() => formatCurrency(props.invoice.amount, props.invoice.currency));
</script>

<template>
  <article class="invoice-card" :class="{ 'is-compact': compact }">
    <h3>{{ invoice.number }}</h3>
    <p>{{ total }}</p>
    <button @click="emit('approve', invoice.id)">Approve</button>
  </article>
</template>

<style scoped lang="scss">
.invoice-card {
  // …
}
</style>
```

- **`<style scoped>`** by default. Reach for `:deep()` or a global stylesheet only when you genuinely need to style child components.
- **`lang="scss"`** on styles (matches the SCSS conventions — see `bootstrap-scss` skill).
- No inline `style` attributes. Use classes and `:class` bindings.

## Naming

| Thing | Convention | Example |
|---|---|---|
| Component file | PascalCase, matches component name | `UserCard.vue` |
| Component in template | PascalCase (Vue auto-resolves kebab-case too — stay consistent) | `<UserCard :user="u" />` |
| Composable | `camelCase`, prefix `use` | `useInvoiceList()` |
| Store | `camelCase`, prefix `use`, suffix `Store` | `useInvoicesStore` |
| Props | `camelCase` in script, `kebab-case` in template | `userId` / `:user-id` |
| Emit event | `kebab-case` | `update:model-value`, `row-clicked` |

Composables always return an object, even for a single value (`return { items }`, not `return items`) — leaves room to add returns later without breaking callers.

English everywhere — names, comments, log messages, copy.

## State management

Three buckets — pick the one that fits, don't reach for a heavier tool than needed.

### Server state — TanStack Vue Query (default)

Use TanStack Vue Query for anything fetched from an API: caching, deduplication, background refetch, loading / error states, optimistic updates. Replaces hand-rolled `ref` + `watch` + `fetch` + `loading` scaffolding.

```ts
// src/api/invoices.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/vue-query';
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
- **One file per resource** under `api/` — co-locate the queries, mutations, and the query-key object for that resource.
- **Never call `fetch` / `axios` directly from a component.** Always go through a TanStack Query hook so the cache layer stays consistent.
- **No global loading flag.** Each query exposes its own `isLoading` / `isFetching`. Compose them in the component if you really need an aggregate.

### Client state — Pinia

Pinia is for state that is shared across components and doesn't come from the server: the current theme, the authenticated user profile, app-wide UI toggles, a multi-step form draft. Use the **setup syntax** — it mirrors `<script setup>` and types more cleanly.

```ts
// src/stores/auth.ts
import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import type { User } from '@/types/user';

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null);
  const isAuthenticated = computed(() => user.value !== null);

  function setUser(u: User | null) {
    user.value = u;
  }

  return { user, isAuthenticated, setUser };
});
```

- One store per concern. Don't make a single `useAppStore` that holds everything.
- **Don't keep server data in Pinia.** That's TanStack Query's job. Pinia stores that mirror server entities go stale and cause double-source bugs.

### Local state — `ref` / `reactive`

The default for anything that lives and dies with the component. Prefer `ref` over `reactive` — `ref` always works (objects, primitives, arrays), composes cleanly, and never silently loses reactivity when destructured.

## Props, emits, slots

- **Typed `defineProps` / `defineEmits`** using the generic (TS-native) syntax, not the runtime declaration:
  ```ts
  const props = defineProps<{ user: User; compact?: boolean }>();
  ```
- **Defaults via `withDefaults`** when the prop is optional and the component needs a value:
  ```ts
  const props = withDefaults(defineProps<{ compact?: boolean }>(), { compact: false });
  ```
- **Never mutate props.** If you need a derived local copy, wrap or compute: `const localCompact = ref(props.compact)`.
- **Typed emits with payload signatures** — see the SFC example above.
- **`v-model` on custom components** — use `defineModel()` (Vue 3.4+). It's a one-liner, reactive both ways, and supersedes the `update:modelValue` boilerplate.
- **Slots** — typed via `defineSlots` when the contract matters. Prefer named slots over a generic default slot when the component has multiple insertion points.

## Composables

A composable is a function that uses Composition API primitives to encapsulate reusable logic.

- **Naming** — `useThing()`. The `use` prefix isn't decoration; it signals reactivity rules apply.
- **Return an object**, even for a single value. Forces destructure-by-name, leaves room to add returns later.
- **Return refs, not their `.value`.** Callers should be able to `watch` the returned values.
- **No side effects on import** — register listeners / start intervals inside the composable, and clean up via `onScopeDispose` / `onUnmounted`.
- **One file per composable**, named after the function: `composables/useInvoiceList.ts`.

## Routing — Vue Router 4

- **Named routes + `router.push({ name, params })`.** Avoid building paths by string concatenation.
- **Lazy-load route components** — `component: () => import('@/views/InvoiceDetail.vue')`. Splits the bundle per route, which matters on slow mobile networks.
- **Guards stay thin.** A route guard checks authentication and redirects; it doesn't fetch data or run business logic. Fetching belongs in the view (so TanStack Query can manage it).
- **`<RouterLink>`** — never hand-roll `<a href="/...">` for in-app navigation. Hand-rolled anchors break the SPA and bypass guards.

## Forms

- **Use a form library.** VeeValidate or Vorms. Hand-rolled `ref` + `errors` objects don't scale past two fields and always end up reimplementing validation.
- **Schema-first validation** — Zod or Yup for the schema, the form library binds it. The same schema can drive the backend DTO check if both sides are TS.
- **Client validation is a UX hint, never a security boundary.** The backend re-validates every field. See "Where logic lives."
- **Submit handler dispatches a TanStack Query mutation.** The mutation owns loading / error / success state — don't duplicate it in the form.

## Performance

Premature optimisation is the usual hazard, but a few patterns are worth knowing:

- **`shallowRef` for large objects** that are replaced wholesale but never mutated in place (e.g. a 5 000-row dataset). Deep reactivity on big arrays is expensive.
- **`v-memo` on expensive list items** that re-render often but rarely change. Use a stable item key.
- **Async components** — `defineAsyncComponent` for components only shown on user action (heavy modals, editors). Code-splits them out of the initial bundle.
- **`computed` for derived state**, not methods called from the template. Computed caches; a method runs every render.
- **`<script setup>` is already optimal** — don't reach for `markRaw` / `toRaw` unless you have a profile showing a real hot path.

## Accessibility

The frontend is the only place a11y exists. Take it seriously.

- **Semantic HTML first.** `<button>` not `<div onclick>`. `<nav>`, `<main>`, `<article>`, `<aside>` for landmarks. ARIA only when no semantic element fits.
- **Every interactive element is keyboard reachable.** Tab order matches visual order. Focus is visible — don't strip the outline without replacing it.
- **Labels** — every form input has a `<label>` (`for` + `id`) or `aria-label`.
- **Live regions** — `aria-live="polite"` on toast / inline alert containers so screen readers announce them.
- **Colour contrast** — meet WCAG AA at minimum (4.5:1 for body text, 3:1 for large text and UI). Don't rely on colour alone for state — pair with an icon or label.
- **`<img>` always has `alt`.** Decorative images get `alt=""`, not no attribute.

Run `axe-core` or Lighthouse against new pages before merge.

## Linting, formatting, type checking

| Concern | Tool |
|---|---|
| Linter | ESLint + `eslint-plugin-vue` + `@typescript-eslint` |
| Formatter | Prettier (or Biome) — never manual style debates in PRs |
| Type check | `vue-tsc --noEmit` |
| Build | Vite |

CI runs all four. Failing any of them fails the build.

## Testing

Frontend test conventions live in their own skill — load it when writing or reviewing tests:

- **`cmo-core/testing-standards`** — universal rules (tier model, two-level Jira traceability, parallelism, scenario coverage, anti-flake, naming, test data, source-mirror layout).
- **`cmo-frontend/frontend-testing`** — the frontend-specific *how*: Vitest, Vue Test Utils, MSW, TanStack Query in tests, Playwright for E2E.

## Quick reference

| Aspect | Rule |
|---|---|
| Business logic | Backend only. Frontend mirrors for UX. |
| Vue API | Composition API + `<script setup>`; no Options API in new code |
| TypeScript | `"strict": true`, `lang="ts"` always |
| File-per-component | One component per `.vue` file, PascalCase name |
| Server state | TanStack Vue Query — never `fetch` / `axios` direct from a component |
| Client state | Pinia (setup syntax), one store per concern, never mirror server data |
| Local state | `ref` (preferred over `reactive`) |
| Props | Typed `defineProps`, `withDefaults` for defaults, never mutated |
| Emits | Typed `defineEmits` with payload signatures |
| v-model | `defineModel()` on custom components |
| Composables | `useThing()`, return an object of refs, one per file |
| Routing | Vue Router 4, named routes + `router.push`, lazy-load components |
| Forms | Form library + schema validator; client-side is a hint, not a boundary |
| Styles | `scoped lang="scss"` by default; no inline `style` |
| Accessibility | Semantic HTML, labels, contrast, keyboard reachability |
| Lint / format / types | ESLint + plugin-vue, Prettier/Biome, `vue-tsc --noEmit` — CI gates all |
| Tests | See `cmo-core/testing-standards` + `cmo-frontend/frontend-testing` |
