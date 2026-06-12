---
paths:
  - "**/*.html"
  - "**/*.css"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.tsx"
  - "**/*.razor"
  - "**/*.cshtml"
  - "**/*.dart"
---

# Frontend / UI rules

**Universal (web AND native mobile):**
- ALWAYS invoke the `frontend-design` skill via the Skill tool BEFORE writing ANY UI code — web markup, React Native components, or Flutter widgets. "UI code" is not just HTML/CSS; a screen built from RN `<View>`s or Flutter `Widget`s is UI code and gets the same design pass.
- Follow the project `design-system/MASTER.md` (or design tokens) for every screen — no ad-hoc colors, spacing, or type. Visual drift is the same sin on a phone as on the web.
- No magic style values scattered inline — centralize (see per-stack rule below).

**Web (HTML / CSS / JS / Razor):**
- Use `const`/`let` in JavaScript — never `var`.
- Use strict equality (`===`) in JavaScript.
- Semantic HTML5 — choose the right element (nav, article, section, aside).
- Use CSS classes or CSS files — never inline `style="..."`.
- Mobile-first responsive design.

**Native mobile (React Native / Flutter):**
- The JS/HTML/CSS specifics above do not apply, but the design discipline does. React Native: centralize styles in `StyleSheet.create` / a theme — never scatter literal style objects; respect safe-area insets; use the platform type scale. Flutter: drive visuals from `ThemeData` / design tokens — never hardcode `Color(0x...)`/`EdgeInsets` per widget; use `MediaQuery`/`LayoutBuilder` for adaptivity.
- Accessibility is not optional: RN `accessibilityLabel`/`accessibilityRole`, Flutter `Semantics`. The screen must be reachable by VoiceOver/TalkBack and survive the largest system font scale.
