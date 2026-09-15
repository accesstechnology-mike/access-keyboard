# access: keyboard

An assistive custom keyboard for **iPhone and iPad** (iOS / iPadOS 18). It pairs
a literacy font, an accessible colour scheme (including Beth Moulam's colours), a
prediction bar, and an optional "Fix" that cleans up the current text field with
a hosted proxy when Full Access is enabled.

## Device support

Universal (`TARGETED_DEVICE_FAMILY = "1,2"`). The keyboard adapts to the device
by size class:

- **iPhone** — a compact, single-column board sized to the phone width (portrait
  and landscape). QWERTY, ABC, and the Frequency (Grid) board all fit without
  overflowing or leaving broken empty bands.
- **iPad / iPad Pro** — the larger multi-column boards, unchanged.

Layout resolution lives in `LayoutClassResolver`; the pure width math is in
`KeyboardGeometry` (unit-tested in `LayoutStabilityTests`). `scripts/render_iphone_layout.py`
renders the iPhone boards and verifies that no key overflows across the real
iPhone widths on a machine with no iOS renderer.

## Targets

- **AccessKeyboard** — the host app (onboarding, settings, a Type screen).
- **AccessKeyboardExtension** — the keyboard extension embedded in the app.
- **AccessKeyboardCore** (`Packages/`) — the shared layout, engine, and prediction
  code, with the test suite.

## TestFlight

See [`TESTFLIGHT.md`](TESTFLIGHT.md) for the full build-and-distribute workflow
and [`AGENTS.md`](AGENTS.md) for the automated tag-driven CI notes. Both device
families (iPhone + iPad) are offered the build once App Store Connect advertises
iPhone availability.
