---
name: ionic-capacitor
description: Use when working on Ionic + Capacitor mobile apps in C-Mo repos (Vue or React under Ionic, deployed as iOS / Android via Capacitor). Covers when to use Ionic vs a plain web app or PWA, project structure, Ionic component usage, page lifecycle, Capacitor plugins (official-first + custom plugin patterns), platform-specific code, native build/run workflow, and mobile UX rules (safe-area insets, keyboard, hardware back button).
---

# Ionic + Capacitor

Conventions for Ionic + Capacitor mobile apps in C-Mo repos. Built on Ionic 7+ and Capacitor 6+ with Vue or React inside.

## When to reach for Ionic + Capacitor

- **Native iOS and / or Android delivery is a hard requirement.** App-store distribution, native APIs (Bluetooth, push, foreground service), offline-first with native storage. If a PWA would do, ship a PWA — fewer moving parts.
- **One codebase across iOS + Android (+ web)** with a UI that should feel native. Ionic's components mirror platform conventions automatically (iOS-style on iOS, Material-style on Android).
- **Existing Vue or React skills.** Both are first-class hosts inside Ionic.

When *not* to use Ionic:

- **Customer-facing web apps that don't need an installed mobile app.** Use plain Vue / React + Bootstrap or Cmo. Don't pull Ionic into a web-only project — the visual model fights with Bootstrap / Cmo, and the bundle-size cost isn't justified.
- **Heavy native integrations beyond Capacitor's reach** (AR, low-level camera control, custom rendering pipelines). Consider React Native or fully native.

## Stack pick

- **Ionic + Vue** is the default for new mobile work — matches the team's Vue expertise and our `vue-conventions` skill.
- **Ionic + React** when an existing C-Mo React codebase is being mobilised.
- Both share the same Ionic component library; differences are mainly in routing and reactivity.

## Project structure

```
src/
├── main.ts                ← Ionic + Capacitor bootstrap
├── App.vue / App.tsx
├── router/                ← Ionic-aware routing (IonRouterOutlet)
├── pages/                 ← route-target pages (each is an IonPage)
├── components/            ← reusable UI
├── composables/ or hooks/
├── stores/                ← Pinia / Zustand client state
├── api/                   ← TanStack Query queries + mutations
├── plugins/               ← Capacitor plugin wrappers (with web fallbacks)
├── theme/                 ← Ionic CSS variables overrides + custom SCSS
└── types/

ios/                       ← Capacitor-generated iOS project (commit it)
android/                   ← Capacitor-generated Android project (commit it)
capacitor.config.ts
```

`ios/` and `android/` are generated, **but you commit them** — they hold native config, signing references, and any native code you've added. They're not throwaway.

## Use Ionic components, don't reimplement

Reach for Ionic components for anything that has a native counterpart:

- **Layout** — `IonPage`, `IonHeader`, `IonContent`, `IonFooter`, `IonToolbar`.
- **Navigation** — `IonRouterOutlet`, `IonTabs`, `IonMenu`, `IonNav`.
- **Input** — `IonInput`, `IonTextarea`, `IonSelect`, `IonDatetime`, `IonRange`, `IonToggle`, `IonCheckbox`.
- **Lists** — `IonList`, `IonItem`, `IonItemSliding` (swipe actions), `IonRefresher` (pull-to-refresh).
- **Modals / overlays** — `IonModal`, `IonAlert`, `IonActionSheet`, `IonPopover`, `IonToast`, `IonLoading`.

Don't roll your own button when `IonButton` exists. Ionic handles platform-specific look, ripple, haptics, and a11y; reinventing means doing all of that wrong on at least one platform.

**Don't drop Bootstrap or the C-Mo design system into an Ionic app.** The visual model collides with Ionic's, and you'll spend more time fighting CSS than building features.

## Page structure (Vue)

```vue
<script setup lang="ts">
import { IonPage, IonHeader, IonToolbar, IonTitle, IonContent, IonButton } from '@ionic/vue';
import { useRouter } from 'vue-router';
import { useInvoice } from '@/api/invoices';

const router = useRouter();
const { data: invoice, isLoading } = useInvoice(/* id from route */);
</script>

<template>
  <IonPage>
    <IonHeader>
      <IonToolbar>
        <IonTitle>Invoice</IonTitle>
      </IonToolbar>
    </IonHeader>

    <IonContent class="ion-padding">
      <p v-if="isLoading">Loading…</p>
      <article v-else-if="invoice">
        <h2>{{ invoice.number }}</h2>
        <IonButton @click="router.back()">Back</IonButton>
      </article>
    </IonContent>
  </IonPage>
</template>
```

- **Every routed page is an `IonPage`.** It's not optional — Ionic's navigation cache (`IonRouterOutlet`) keys off it for transitions and lifecycle.
- **`IonContent` is the scroll container.** Don't put your own `overflow: scroll` inside; let Ionic handle scroll, pull-to-refresh, and footer-aware sizing.

## Page lifecycle

Vue's `onMounted` / `onUnmounted` (and React's `useEffect`) fire when the component instance mounts — but Ionic caches pages in `IonRouterOutlet`, so the same instance can be navigated away from and back to without unmounting. For navigation-aware work, use Ionic's lifecycle hooks:

| Hook | Fires when |
|---|---|
| `onIonViewWillEnter` | Before the page becomes the active view |
| `onIonViewDidEnter` | After the enter transition completes |
| `onIonViewWillLeave` | Before leaving |
| `onIonViewDidLeave` | After leaving |

Use `onIonViewWillEnter` to refresh data that may have changed (e.g. invalidate a TanStack Query); use `onIonViewWillLeave` to pause subscriptions or stop active sensors.

## Capacitor plugins

- **Official plugins first.** `@capacitor/camera`, `@capacitor/geolocation`, `@capacitor/preferences`, `@capacitor/network`, `@capacitor/push-notifications`, `@capacitor/share`. Vetted, cross-platform, well-maintained.
- **Community plugins** from the Capacitor community org are fine when official doesn't cover the need.
- **Custom plugins** when you need a native API neither covers — write a thin Capacitor plugin in Kotlin / Swift rather than reaching for a deprecated Cordova plugin.

### Wrap every plugin

Don't call Capacitor plugins directly from components. Wrap each one in `src/plugins/` so:

- You have one place to add a **web fallback** for development in the browser.
- You can mock the plugin in tests by swapping the wrapper.
- You can swap the underlying plugin (official ↔ community ↔ custom) without touching every caller.

```ts
// src/plugins/camera.ts
import { Camera, CameraResultType } from '@capacitor/camera';
import { Capacitor } from '@capacitor/core';

export async function takePhoto(): Promise<string | null> {
  if (!Capacitor.isNativePlatform()) {
    // Web dev fallback — open a file picker, return data URL
    return webPhotoFallback();
  }

  const photo = await Camera.getPhoto({ quality: 80, resultType: CameraResultType.Uri });
  return photo.webPath ?? null;
}
```

## Platform-specific code

Use `Capacitor.getPlatform()` (`'ios' | 'android' | 'web'`) or `Capacitor.isNativePlatform()` (`true` for ios + android) at the wrapper layer. **Don't leak platform branching into shared components** — they should stay platform-agnostic. If a component needs different behaviour per platform, push the branching down into a plugin wrapper or composable.

## Native build / run workflow

```bash
npm run build              # Vite production build → dist/
npx cap sync               # copies dist/ + plugin native code into ios/ and android/
npx cap open ios           # opens Xcode
npx cap open android       # opens Android Studio
```

Run from device / simulator inside Xcode or Android Studio. For day-to-day iteration:

```bash
npx cap run ios --livereload --external
```

Live-reloads from the dev server into the simulator. Painful on first setup, productive after.

**Commit `ios/` and `android/`** — they're not generated artefacts in any meaningful sense; they hold signing config, Info.plist edits, AndroidManifest.xml entries, and any native code you've added. Treat them like first-class source.

## Mobile UX rules

These are easy to forget on web and break the app on phones:

- **Safe-area insets.** Notches and rounded corners eat content. `IonHeader` / `IonContent` / `IonFooter` handle this for you; if you add custom chrome, use `padding-top: env(safe-area-inset-top)` etc. (or Ionic's `--ion-safe-area-*` CSS vars).
- **Keyboard.** When the keyboard opens, content shifts. `IonContent` adapts; custom scroll containers usually don't. Test every form on a real device.
- **Hardware back button (Android).** Ionic wires the back button to navigation by default, but custom modals / overlays need to register with `App.addListener('backButton', …)` or use Ionic's `useBackButton()` to handle dismissal — otherwise the back button closes the app.
- **Tap targets.** 44×44 px minimum. Ionic components meet this; custom touch areas often don't.
- **Loading states.** Networks on cellular are slow and lossy. Every TanStack Query consumer should render a sensible loading state and a retry path — not a blank screen.

## Testing

- **Unit / component tests** — Vitest + Vue Test Utils / React Testing Library. Same as web. See `cmo-frontend/frontend-testing`.
- **Capacitor plugin wrappers** are unit-testable by mocking the wrapper — that's why we wrap.
- **E2E on the web build** — Playwright against `npm run build && npm run preview` catches the lion's share of UI regressions cheaply.
- **Smoke tests on real devices** — manual, but unavoidable. Native bugs (camera, push, deep links, file system) only surface on hardware.
- **`npx cap doctor`** — run periodically to confirm the native projects are in sync with the JS layer.

## Quick reference

| Aspect | Rule |
|---|---|
| When to use Ionic | Native mobile delivery + Vue/React skill |
| When *not* to | Web-only apps; heavy native integrations beyond Capacitor's reach |
| Default stack | Ionic + Vue + Capacitor; Ionic + React for existing React shops |
| Native folders | `ios/` and `android/` are committed source |
| Components | Ionic components for anything with a native counterpart — don't reinvent |
| Page = `IonPage` | Every routed page; `IonContent` is the scroll container |
| Lifecycle | Use `onIonView*` hooks for navigation-aware behaviour, not just `onMounted` |
| Capacitor plugins | Wrap every plugin in `src/plugins/` for web fallback + mockability |
| Platform branching | At the wrapper layer, not in shared components |
| Build / run | `npm run build && npx cap sync && npx cap open <ios\|android>` |
| Safe-area / keyboard / back button | Test on real hardware before merging |
| Tests | Vitest unit + Playwright E2E on web build; manual smoke on real devices |
