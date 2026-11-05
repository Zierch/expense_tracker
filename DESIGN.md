---
version: alpha
name: Expense Tracker
description: Friendly, calm expense tracking with emerald accents and playful illustrations.
colors:
  primary: "#0E5A44"
  accent: "#10B981"
  accent-light: "#A7F3D0"
  light-background: "#F4F6F8"
  light-surface: "#FFFFFF"
  light-text: "#111827"
  light-muted: "#6B7280"
  light-border: "#E5E7EB"
  light-activity: "#E8F5E9"
  light-grocery: "#E4F1E9"
  light-income: "#D1FAE5"
  light-entertainment: "#EEF0F5"
  dark-background: "#101916"
  dark-surface: "#1B2924"
  dark-elevated: "#263A30"
  dark-tinted: "#244239"
  dark-text: "#EDF7F1"
  dark-muted: "#A8BDB3"
  dark-border: "#31443A"
  dark-accent: "#83DFB7"
  dark-on-accent: "#10291F"
  dark-grocery: "#29483B"
  dark-income: "#24473B"
  dark-entertainment: "#353E4C"
  dark-error: "#FF8A8A"
  dark-validation: "#FF9393"
  white: "#FFFFFF"
typography:
  title:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: 700
  section:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: 700
  body:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: 400
  caption:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: 400
  balance:
    fontFamily: Inter
    fontSize: 34px
    fontWeight: 700
rounded:
  icon: 12px
  button: 14px
  card: 16px
  panel: 20px
  hero: 24px
spacing:
  small: 8px
  medium: 16px
  screen: 20px
  large: 24px
components:
  primary-button:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.white}"
    rounded: "{rounded.button}"
  dark-secondary-button:
    backgroundColor: "{colors.dark-tinted}"
    textColor: "{colors.dark-accent}"
    rounded: "{rounded.button}"
  dark-surface:
    backgroundColor: "{colors.dark-surface}"
    textColor: "{colors.dark-text}"
    rounded: "{rounded.panel}"
  light-surface:
    backgroundColor: "{colors.light-surface}"
    textColor: "{colors.light-text}"
    rounded: "{rounded.card}"
---

## Overview

An expense and income tracker, not a wallet or banking app. Keep the interface calm, approachable and legible; use emerald for primary actions and small friendly mascots as supporting illustrations. This document describes the target design, not necessarily the current implementation.

## Colors

Use semantic light/dark pairs rather than applying one color across both themes. Background, cards, text, muted copy, borders and interactive accents are listed in the front matter. Balance cards use `primary` with white text and `accent-light` for the label. The activity card uses `light-activity` in light mode and `dark-tinted` in dark mode. Grocery, income and entertainment colors are subtle icon backgrounds, not transaction text colors.

Use `dark-error` for destructive actions and `dark-validation` for errors on dark surfaces. Verify contrast for every actual foreground/background pair; normal text requires 4.5:1 and large text 3:1 (WCAG AA). The mockup uses white text on `#10B981` and pale inactive text on white in places; do not copy those pairs blindly because they can fail contrast. For a mint badge use dark text instead. Never convey errors or income/expense solely by color.

## Typography

The target design uses Inter, with regular, semibold and bold weights. It is not currently bundled in the app: verify font licensing and packaging before adding a dependency or font files; use an appropriate platform fallback until then. Sizes above are reference logical pixels, not fixed constraints. Respect system text scaling, wrapping and accessible labels.

## Layout

The reference artboard is 390 × 844 logical pixels. Home uses 20px side margins, 16–24px section spacing, a 350 × 160 balance card, a 350 × 72 activity card and 64px transaction rows. These are proportions, not fixed sizes: use responsive widths, scrollable content, safe areas and enough room for larger text. Keep the three-tab bottom navigation persistent across Home, Statistics and Settings; Add/Edit are separate routes. Statistics report content scrolls without obscuring navigation.

## Elevation & Depth

Use background/surface contrast and restrained dividers rather than strong shadows. Dark dialogs and dropdowns use the elevated dark surface over a dimmed scrim.

## Shapes

Use rounded 16px transaction cards, approximately 20px settings panels and 24px balance card corners; buttons use 14px and icon tiles 12px. The activity card reference uses 18px. Preserve sufficient padding and touch targets rather than forcing artwork dimensions.

## Components

- Splash: in dark system mode use the `dark-background` canvas and the existing centered splash icon; Android controls the native launch layout. The native launch theme follows the system setting before Flutter loads the saved in-app theme.
- Home: balance card with `assets/images/piggy_bank.png`; activity card with `assets/images/receipt_mascot.png` and one Add action; recent transactions follow below.
- Transaction rows: category icon tile at left, name and time in the middle, right-aligned amount. Grocery and entertainment use their respective muted backgrounds in each theme.
- Statistics: Expense/Income and Week/Month/Year filters, charts, and an independently ranged PDF/CSV report. Empty and error states remain readable in both themes.
- Settings: Appearance, Google Drive account, backup/sync and updates. Show cached account status as historical; entering Settings must not start sign-in. Refer to `docs/plans/design-to-code-redesign.md` for system behavior and migration decisions.
- Navigation: use a consistent accessible icon set, not the mixed emoji placeholders in mockups. Do not show a back action on root tabs; keep it for pushed subpages.

## Do's and Don'ts

- Do reuse theme tokens and component patterns for states without separate dark frames.
- Do preserve transparent artwork and its aspect ratio. The images are bundled in `pubspec.yaml` but not yet used by the UI.
- Do verify layouts at small widths, large text sizes and in both themes; screenshots alone do not establish accessibility compliance.
- Don't add transfer, payment or other e-wallet features. Don't mistake placeholder colors, sample values or design frames for live functionality.
