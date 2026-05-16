---
name: ionic-capacitor
description: Use when working on Ionic + Capacitor mobile apps in C-Mo repos. Covers Ionic components, Capacitor plugins, platform-specific code, mobile lifecycle, and the native build/run workflow.
---

# Ionic + Capacitor

TODO — fill in C-Mo Ionic + Capacitor rules. Topics to cover:

- When this skill applies: `@ionic/*` and/or `@capacitor/*` in `package.json`.
- Ionic component usage and routing (`IonRouterOutlet`, page lifecycle hooks).
- Capacitor plugin patterns — official plugins, custom plugins, web fallbacks.
- Platform-specific code (`Capacitor.getPlatform()`, `isNativePlatform()`); avoid leaking native concerns into shared components.
- Native build / run workflow: `npx cap sync`, iOS vs Android, signing.
- Mobile-specific UX rules (safe-area insets, keyboard handling, hardware back button).
