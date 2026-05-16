---
name: cmo-design-system
description: Use when working on a C-Mo internal app that imports (or should import) the C-Mo Internal Design System (`@c-mo-medical-solutions/cmo-internal-design-system`). Covers when to use it, how to install both the npm package and the in-package Claude Code skill, coexistence with Bootstrap (`.cmo-*` namespace), adoption modes, and migration patterns. The canonical component catalog lives in the in-package skill — this skill points at it.
---

# C-Mo Internal Design System

Upstream: https://github.com/C-mo-Medical-Solutions/cmo-internal-design-system

The C-Mo Internal Design System (codename **Cmo**) is the design system for our **internal enterprise applications** — the ERP, the CMS configuration platform, the client-support platform. It ships colour, type, spacing, components, and patterns as a versioned npm package, with the design tokens compiled into a single CSS bundle and all selectors namespaced under `.cmo-*`.

## When this skill applies

Load this skill when **any** of:

- The repo's `package.json` includes `@c-mo-medical-solutions/cmo-internal-design-system`.
- The repo is described as an internal app (ERP, CMS, client-support, ops tools — anything not shipped to external medical professionals or patients).
- The user is starting a new internal app and asking what to use for styling.

For **customer-facing apps**, use Bootstrap (see `bootstrap-scss` skill) — Cmo is not built for them.

For **Ionic mobile apps**, use Ionic's own components — see `ionic-capacitor`.

## The in-package skill is the source of truth for components

Cmo ships its own Claude Code skill at `.claude/skills/cmo-internal-design-system/SKILL.md` inside the npm package. That skill is **auto-generated** from `nav.mjs` in the design-system repo (the canonical component registry), so it always reflects the components actually shipped by the installed version.

After installing the package in a consumer app, run:

```bash
npx cmo-install-skill            # copies the skill into .claude/skills/
# or:
npx cmo-install-skill --link     # symlink — updates flow through `npm install`
```

`--link` is preferred for consumer apps that intend to track the design-system version; plain copy is fine for one-off snapshots.

**This skill (in `cmo-frontend`) only covers integration concerns.** For the actual component catalog — which buttons exist, which props they take, which utility classes to reach for — load the in-package skill (`cmo-internal-design-system`) instead. If both are loaded, the in-package skill wins on component details.

## Installation

Cmo is published as a **private package** to GitHub Packages. Two-step setup:

```bash
# 1. Drop the .npmrc.example from the design-system repo into your app as `.npmrc`
#    (it points the @c-mo-medical-solutions scope at GitHub Packages).
# 2. Export a token with read:packages scope:
export GITHUB_PACKAGES_TOKEN=ghp_…

npm install @c-mo-medical-solutions/cmo-internal-design-system
npx cmo-install-skill --link
```

Then link the bundle in the layout:

```html
<link rel="stylesheet" href="/node_modules/@c-mo-medical-solutions/cmo-internal-design-system/styles/cmo.css" />
<script src="/node_modules/@c-mo-medical-solutions/cmo-internal-design-system/js/docs.js" defer></script>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet" />
```

Or via your bundler:

```js
import '@c-mo-medical-solutions/cmo-internal-design-system/css';
import '@c-mo-medical-solutions/cmo-internal-design-system/js';
```

## Adoption modes

Cmo supports three adoption levels — pick the lowest that meets the need:

1. **CSS bundle (recommended)** — `npm install` + `<link>` / `import` the compiled `cmo.css`. Versioned, reproducible, painless upgrades.
2. **SCSS source** — when you need to override design tokens at build time (e.g. a sub-brand needs a different `$color-cobalt-500`):
   ```scss
   $color-cobalt-500: oklch(50% 0.18 220);
   @use "@c-mo-medical-solutions/cmo-internal-design-system/scss/tokens";
   @use "@c-mo-medical-solutions/cmo-internal-design-system/scss/components";
   ```
3. **Drop-in `cmo.css`** — copy the compiled bundle into static assets. Simplest, no Node required, but you have to re-copy to upgrade. Reserve for one-off prototypes.

## Coexistence with Bootstrap

All Cmo selectors are namespaced under `.cmo-*`, so Cmo and Bootstrap can coexist in the same page without colliding. This is by design: it enables **incremental migration** from a Bootstrap-styled internal app to a Cmo-styled one.

- New components go in Cmo (`.cmo-button`, `.cmo-card`, `.cmo-table`).
- Old Bootstrap markup stays until the page is migrated.
- Don't mix the two within a single component — pick one and finish that component.

## Migration patterns

When migrating an existing Bootstrap internal app to Cmo:

1. **Install Cmo + the skill** (above).
2. **Page-by-page**, not component-by-component. A half-migrated page (Cmo buttons inside a Bootstrap card) looks broken.
3. **Start with the highest-traffic pages** — most user value per migration hour.
4. **Replace primitives first** (buttons, inputs, cards, modals), then layout, then bespoke patterns.
5. **Keep Bootstrap installed** until the last page is migrated. Removing it prematurely orphans the un-migrated pages.

## Conventions enforced by Cmo

These are baked into the design system; don't fight them:

- **Tokens, not hex codes.** Colours live in `_tokens.scss` and are re-exported as `--cmo-*` CSS variables. Never hard-code a hex colour in component CSS — use `var(--cmo-cobalt-500)` or the matching utility class.
- **One brand accent (cobalt)** and **one secondary accent (ember)**. Don't introduce new hues; if you need one, push it upstream into Cmo.
- **Component radius rules:** inline elements (buttons, inputs, badges) use `radius-md` (8px); surfaces (cards, modals) use `radius-xl` (16px). Cmo's classes apply these automatically — don't override.
- **Type scale:** body text 15px; helper text 12–13px; KPIs 28–32px in Geist with tabular numerics. Use the Cmo type utilities; don't size with arbitrary pixel values.
- **One source of truth.** If Cmo doesn't ship a component you need, **add it to Cmo upstream** — don't fork it locally. Local forks fragment the system and someone has to regenerate them in six months.

## Theme switching

Set `data-theme="dark"` on `<html>` to switch themes. Cmo listens to `prefers-color-scheme` on first visit; explicit theme choice overrides.

## Upgrading

```bash
npm update @c-mo-medical-solutions/cmo-internal-design-system
# if you used --link, the skill updates with the package automatically.
# otherwise: npx cmo-install-skill   (re-copy)
```

After upgrading, scan the design-system repo's release notes for breaking changes — Cmo follows semver, but a major-version bump may rename component classes or remove deprecated tokens.

## Quick reference

| Aspect | Rule |
|---|---|
| When to use Cmo | Internal C-Mo apps only |
| Component catalog | Load the in-package skill (`npx cmo-install-skill --link`) |
| Install mode | CSS bundle (default); SCSS source for token overrides; drop-in for prototypes |
| Coexistence | Bootstrap can stay during migration; Cmo lives under `.cmo-*` namespace |
| Migration cadence | Page-by-page, never component-by-component within a page |
| Colour tokens | Always `var(--cmo-*)`; never hard-coded hex |
| New components | Push upstream into Cmo; don't fork locally |
