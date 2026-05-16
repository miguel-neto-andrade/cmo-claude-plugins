---
name: react-conventions
description: Use when writing, reviewing, or scaffolding React frontend code in C-Mo repos (function components, hooks, React Router, TanStack Query, TypeScript).
---

# React Conventions

TODO — fill in C-Mo React rules. Strict points to capture:

- **No business logic on the frontend.** BL lives on the backend; the frontend's job is rendering, input collection, validation feedback, and orchestrating API calls. Anything that decides "what should happen" (pricing, authorisation, workflow transitions, etc.) belongs server-side.
- **TanStack Query for server state.** Default to it for data fetching, caching, and mutations — replaces hand-rolled `useEffect` + `useState` loading/error scaffolding.
- Function components and hooks only — no class components.
- TypeScript strict mode.
- (TODO: more rules — component layout, hook ordering, context vs prop drilling, suspense + error boundaries, testing hand-offs, etc.)
