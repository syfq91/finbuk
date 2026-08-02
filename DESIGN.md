---
name: Finbuk Design System
version: alpha
colors:
  primary: "#673AB7" # Material 3 Deep Purple seed
  on-primary: "#FFFFFF"
  primary-container: "#EADDFF"
  on-primary-container: "#21005D"
  secondary: "#625B71"
  tertiary: "#7D5260"
  surface: "#FFFBFE"
  on-surface: "#1C1B1F"
  error: "#B3261E"
  warning: "#FF9800" # Reserved for Offline Mode banner
  background: "#FFFBFE"

typography:
  headline:
    fontFamily: Roboto
    fontSize: 28px
    fontWeight: 400
    lineHeight: 36px
  title:
    fontFamily: Roboto
    fontSize: 22px
    fontWeight: 400
    lineHeight: 28px
  body:
    fontFamily: Roboto
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
  label:
    fontFamily: Roboto
    fontSize: 12px
    fontWeight: 500
    lineHeight: 16px

rounded:
  sm: 4px
  md: 8px
  lg: 16px
  full: 100px

spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px

components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  input-field:
    rounded: "{rounded.sm}"
    padding: "{spacing.md}"
  offline-banner:
    backgroundColor: "{colors.warning}"
    textColor: "#FFFFFF"
    padding: "{spacing.xs}"
    typography: "{typography.label}"
  app-bar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.on-surface}"
    height: 64px
---

## Overview

Finbuk (a portmanteau of "Fin" from Jellyfin and "Buk" for books) follows the **Material 3 (M3)** design system. It prioritizes immersive reading experiences, accessibility, and a clean, modern aesthetic.

## Colors

The palette is anchored by a **Deep Purple** seed color, which generates a harmonious Material 3 color scheme.

- **Primary (#673AB7)**: The brand identifier, used for major actions, active states, and key highlights.
- **Surface**: Screens use a near-white surface in light mode and a deep charcoal in dark mode to minimize eye strain.
- **Warning (#FF9800)**: A high-visibility orange used exclusively for the **Offline Mode** banner, ensuring users are aware when they are browsing cached content.

## Typography

Finbuk uses **Roboto** as its primary typeface, ensuring readability across various Android device resolutions.

- **Headlines**: Used for main screen titles in the AppBar.
- **Titles**: Used for book titles and section headers in the dashboard.
- **Body**: Optimized for book metadata and settings descriptions.
- **Labels**: Used for micro-copy, such as the text in navigation bars and status indicators.

## Layout & Spacing

The layout is built on a responsive 8dp grid system.

- **Responsive Navigation**: Finbuk adapts to the device width.
  - **Phone (<600dp)**: Uses a `NavigationBar` at the bottom for easy thumb access.
  - **Tablet/Large Screen (>600dp)**: Transitions to a `NavigationRail` on the left to maximize vertical screen space for content.
- **Content Grids**: Library items are presented in a responsive grid with a standard 16dp gutter (`spacing.md`).

## Components

- **Book Cards**: Feature high-quality cover art with a subtle 8dp rounded corner (`rounded.md`).
- **Action Buttons**: Primary actions (like Login or Download) use `FilledButton` styling with 16dp vertical padding.
- **Search Bar**: A floating or integrated search field that provides quick access to the library.
- **Reader Interface**: The comic reader enters an **Immersive Mode**, hiding system UI elements and using the full screen to showcase the artwork.
- **Media Player Interface**:
  - **Video**: Full-screen immersive UI with a black scaffold and transparent AppBar for distraction-free viewing.
  - **Music**: Prominent, large, rounded album art (`rounded.lg`), centered metadata, and standard play/pause/skip controls using Material icons.
  - **Audiobook**: Tailored controls emphasizing pacing with `Rewind 10s`, `Fast-Forward 30s` buttons, and an active playback speed selector in the AppBar.
