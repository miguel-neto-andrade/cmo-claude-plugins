---
name: vue-conventions
description: Use when writing, reviewing, or scaffolding Vue 3 frontend code in C-Mo repos (SFCs, Composition API, `<script setup>`, Pinia, Vue Router, TypeScript).
---

# Vue Conventions

TODO — fill in C-Mo Vue 3 rules. Strict points to capture:

- **No business logic on the frontend.** BL lives on the backend; the frontend's job is rendering, input collection, validation feedback, and orchestrating API calls. Anything that decides "what should happen" (pricing, authorisation, workflow transitions, etc.) belongs server-side.
- **TanStack Query (Vue Query) for server state.** Default to it for data fetching, caching, and mutations — replaces hand-rolled `ref` + `watch` + `fetch` + loading/error scaffolding.
- Vue 3 + `<script setup>` + Composition API; Pinia for client-only state; Vue Router for routing.
- TypeScript strict mode.
- (TODO: more rules — SFC structure, props/emits typing, composables, async components, suspense, testing hand-offs, etc.)
