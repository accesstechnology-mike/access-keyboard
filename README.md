# access: keyboard

An assistive custom keyboard for **iPhone and iPad** (iOS / iPadOS 18). It pairs
a literacy font, optional colour themes, a prediction bar that learns on the
device, and an optional "Fix" that can correct the current text field through a
hosted proxy. The keyboard still types with Full Access off and with no network.
Fix sends text only when the user taps Fix, and only after they allow it when
consent is required.

## Feature flags

The switch is a compile-time constant in
`Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/FeatureFlags.swift`.
Change the constant and ship a new build. It is not a Settings toggle.

| Constant | Default | Effect |
| --- | --- | --- |
| `FeatureFlags.fixConsentRequired` | `true` | The first Fix call shows Allow / Not now before any text is sent to OpenAI. Allow is remembered in the App Group and can be turned off under Settings → Allow Fix to send text. `false` sends on Fix without that step. |

Beth mode stays in the Settings colour list under the name Beth. The colours are `BethColorMap`.

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
