---
name: bootstrap-scss
description: Use when working with Bootstrap 5 + custom SCSS in C-Mo frontend projects. Covers when to pick Bootstrap vs the C-Mo Internal Design System, SCSS file structure, theming via Bootstrap's Sass variables, utility-first vs custom CSS, override patterns, build setup, and common SCSS pitfalls. Internal apps should prefer cmo-design-system over Bootstrap.
---

# Bootstrap 5 + SCSS

Conventions for Bootstrap 5 + custom SCSS in C-Mo frontend projects.

## When to use Bootstrap

- **Customer-facing apps** — Bootstrap 5 is the default for any C-Mo app shipped to external users (medical professionals, patients, partner integrations).
- **Internal apps** — strongly prefer the **C-Mo Internal Design System** (`@c-mo-medical-solutions/cmo-internal-design-system`). See `cmo-design-system` skill. The two can coexist (Cmo namespaces under `.cmo-*`), so migration can be incremental — but new internal work should reach for Cmo components first.
- **Mobile apps (Ionic)** — Ionic ships its own component library tuned for native look-and-feel. Don't drop Bootstrap into an Ionic app; the visual model fights with Ionic's. See `ionic-capacitor` skill.

## File structure

```
src/styles/
├── main.scss            ← entry — imports everything in order
├── _variables.scss      ← override Bootstrap's variables BEFORE @import
├── _custom-mixins.scss
├── _utilities.scss      ← extend Bootstrap utilities API
├── components/
│   ├── _card.scss
│   └── _form.scss
└── pages/
    └── _dashboard.scss
```

`main.scss` is the single entry point loaded by the bundler (`import './styles/main.scss'` from `main.ts`).

## Override order matters

Bootstrap exposes its tokens as Sass variables that compile to CSS. Override them **before** importing Bootstrap; nothing else works.

```scss
// main.scss

// 1. Your overrides — must come first
@import './variables';        // $primary, $font-family-base, …
@import './custom-mixins';

// 2. Bootstrap
@import 'bootstrap/scss/bootstrap';

// 3. Your additions on top
@import './utilities';        // extend the utilities API
@import './components/card';
@import './pages/dashboard';
```

If you `@import 'bootstrap'` first and then try to override, you're fighting Bootstrap's compiled CSS with specificity tricks. Don't.

## Theming via Bootstrap's Sass variables

Use Bootstrap's variables; don't invent parallel ones.

```scss
// _variables.scss
$primary:   #0d6efd;
$secondary: #6c757d;
$success:   #198754;

$font-family-sans-serif: 'Inter', system-ui, sans-serif;
$body-bg: #f8f9fa;

$border-radius: 0.5rem;
$border-radius-sm: 0.25rem;
$border-radius-lg: 0.75rem;
```

Bootstrap re-derives dozens of downstream values (`btn-primary`, `bg-primary`, alert variants, etc.) from these. Override the source; don't restyle the leaves.

## Layout hierarchy — always `.container > .row > .col`

Bootstrap's grid is the only sanctioned way to lay out a page. Every layout must follow the strict hierarchy:

```html
<div class="container">          <!-- or .container-fluid / .container-{breakpoint} -->
  <div class="row">
    <div class="col-12 col-md-6">…</div>
    <div class="col-12 col-md-6">…</div>
  </div>
</div>
```

Rules:

- **A `.row` only ever lives directly inside a `.container` (or another `.col`, for nested grids).** Never a bare `.row` at the page root — it produces negative-margin overflow and breaks the page width on small screens.
- **A `.col` only ever lives directly inside a `.row`.** Cols outside a row lose their flex behaviour and their gutter math.
- **Don't reach for `d-flex` / `d-grid` as a substitute for the grid** when you're laying out a page section. The grid handles responsive breakpoints, gutters, and ordering for free. Use `d-flex` for *intra-component* layout (button row, card header), not for page structure.
- **Pick the right container** — `.container` (fixed-width, recommended default), `.container-fluid` (full-width edge-to-edge), `.container-{breakpoint}` (fluid up to a breakpoint, then fixed). One container per page section; don't nest containers.
- **One `.row` per logical row of content.** Don't cram unrelated cols into the same row to "save markup" — it makes responsive behaviour incoherent.

If you find a layout where this hierarchy doesn't fit, the answer is almost always "use the grid correctly" — not "skip the grid." Open a discussion before introducing bespoke layout primitives.

## Utility-first vs custom CSS

Bootstrap 5's utility classes (`d-flex`, `gap-3`, `text-truncate`, `mb-4`) are the default for **layout and spacing**. Custom CSS is for things utilities can't express (animations, complex selectors, deep theming, brand-specific patterns).

| Use a utility class | Write custom CSS |
|---|---|
| Spacing (`m-`, `p-`) | Animations / transitions |
| Flex / grid layout | Pseudo-elements |
| Display / visibility | Brand-specific component styles |
| Text alignment, weight, colour | State machines driven by JS classes |
| Border, shadow, radius (presets) | One-off custom shapes |

The rule: if a utility exists, use the utility. Don't reinvent it with a custom class.

## Extending the utilities API

For project-specific utility classes (custom z-index scale, brand colour text utilities), use Bootstrap's `$utilities` map rather than writing class definitions by hand. Bootstrap will generate the responsive variants for you.

```scss
// _utilities.scss
@import 'bootstrap/scss/utilities';

$utilities: map-merge(
  $utilities,
  (
    'cursor': (
      property: cursor,
      class: cursor,
      values: pointer not-allowed wait,
    ),
  )
);

@import 'bootstrap/scss/utilities/api';
```

## Component overrides

When you need to change a Bootstrap component beyond what its Sass variables expose, write a partial under `components/` and target the Bootstrap class directly. Avoid wrapping with a custom class that adds specificity tricks — it makes the next person fight your CSS too.

```scss
// _card.scss
.card {
  // Brand-specific shadow that isn't expressible via $card-* variables
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.06);

  &__brand-badge {        // BEM modifier for project-specific element
    position: absolute;
    top: 1rem;
    right: 1rem;
  }
}
```

If you find yourself overriding the same component in three places, push the change up into `_variables.scss` (if possible) or extract a custom Bootstrap-style component class.

## Naming

- **BEM** for custom components: `block`, `block__element`, `block--modifier`.
- **Bootstrap classes stay as Bootstrap classes** — don't rename them or shadow with `@extend`.
- **State classes** — `is-loading`, `is-active`, `has-error`. Toggled by JS.

## Common pitfalls

- **`!important`** is a smell. The only acceptable use is overriding a third-party utility that ships with `!important` itself (rare). Otherwise, fix the specificity / import order.
- **Deep nesting (> 3 levels)** — compiles to brittle selectors that break on the smallest markup change. Refactor with BEM.
- **`@extend`** — produces surprising output (Bootstrap itself warns against it). Use mixins or duplicate the few properties you need.
- **Don't `@import` Bootstrap twice.** Slows the build and risks duplicated CSS in the bundle.
- **Don't ship the full Bootstrap CSS if you only use a subset** — `@import 'bootstrap/scss/bootstrap'` includes everything. For bundle-size-sensitive projects, import only the partials you use (`bootstrap/scss/grid`, `bootstrap/scss/utilities`, etc.).

## Build setup

- **Vite** — install `sass` (the modern Dart Sass package); import the entry SCSS from `main.ts`. Vite auto-rebuilds on save.
- **PostCSS** — `autoprefixer` is required (Bootstrap depends on it). Vite includes it by default.
- **CSS source maps** — on in dev, off in prod.
- **CSS code-splitting** — Vite splits CSS per dynamic-import boundary. Don't fight it; lazy-load route components and CSS comes along for free.

## Accessibility

Bootstrap's components are accessible out of the box if you use them correctly:

- **Don't strip ARIA attributes from Bootstrap components.** The accordion's `aria-expanded`, the modal's `aria-modal`, etc. are part of the contract.
- **Colour contrast** — Bootstrap's defaults meet WCAG AA. If you override `$primary` to a low-contrast brand colour, re-check buttons and links.
- **Focus indicators** — Bootstrap restores the focus outline; don't remove it in your overrides.

## Quick reference

| Aspect | Rule |
|---|---|
| When to pick Bootstrap | Customer-facing apps. Internal apps prefer `cmo-design-system`. |
| Override order | Variables → Bootstrap → custom |
| Theming | Override Bootstrap's Sass variables, not the compiled CSS |
| Utility-first | Yes for layout / spacing; custom CSS for what utilities can't express |
| Custom classes | BEM (`block__element--modifier`) |
| State classes | `is-*`, `has-*` |
| `!important` | Avoid except to override third-party `!important` |
| Nesting | ≤ 3 levels |
| `@extend` | Avoid |
| Build | Vite + Dart Sass + Autoprefixer |
| A11y | Don't strip Bootstrap's ARIA / focus styles |
