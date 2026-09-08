# Crash logs & long-session stability

The keyboard runs as an **app extension**, which iOS keeps under a tight memory
limit (roughly 40–60 MB depending on device). The most common way an extension
"crashes after prolonged use" is a **jetsam** (memory) kill, which does not
always produce a classic crash `.ips` report. This note covers both where to
pull real crash reports and how to read the logging this build adds.

There is **no crash data in the repository** — Apple keeps it in App Store
Connect / on the device. Pull it from one of the sources below; do not guess at
causes without a real report or a memory trace.

## Where to pull crash reports

1. **TestFlight (testers, easiest for Mike)**
   - On the iPad: after a crash, TestFlight shows a *"share crash"* / feedback
     prompt — accept it so the report is attached to the build.
   - In App Store Connect → your app → **TestFlight** → the build → **Crashes**,
     or **Xcode → Organizer → Crashes** (filter by the build). Reports here are
     already symbolicated.

2. **Xcode Organizer (developer machine)**
   - Xcode → **Window → Organizer → Crashes**. Pick the app and build. This
     aggregates TestFlight + App Store crash reports and symbolicates them.

3. **On-device logs (fastest for a reproducible crash)**
   - iPad: **Settings → Privacy & Security → Analytics & Improvements →
     Analytics Data**. Entries named `access.keyboard-…` or `JetsamEvent-…`
     (a jetsam is a memory kill, not a code crash) are the relevant ones.
     Share the file and open it in Xcode to symbolicate.
   - Or connect the iPad and use **Xcode → Devices & Simulators → View Device
     Logs**.

4. **Live console while reproducing (best for memory growth)**
   - Connect the iPad, open **Console.app** on the Mac, select the device, and
     filter on subsystem `app.access.keyboard`. Reproduce the long session and
     watch the `mem=…MB` values (see below).

## Reading this build's logging

`KeyboardViewController` logs through `os.Logger` with
`subsystem: app.access.keyboard`, `category: extension`:

- `viewDidLoad fullAccess=… mem=…MB` — one line each time the keyboard is
  brought up. A `mem` value that starts higher every time the keyboard reopens
  hints at state leaking across presentations.
- `memory warning mem=…MB — releasing transient resources` — iOS asked the
  extension to shed memory. If a crash/disappearance follows shortly after one
  of these, it is almost certainly a jetsam kill and the fix is to reduce the
  memory high-water mark, not to chase a logic bug.

Filter in Console.app with:

```
subsystem:app.access.keyboard
```

or from the terminal against a sysdiagnose / connected device:

```
log show --predicate 'subsystem == "app.access.keyboard"' --style syslog --last 30m
```

## Stability changes already made in this build

- **Key views are reused instead of rebuilt on every keystroke.** Previously
  every press tore down and recreated ~30–40 `KeyButton` views (and could
  destroy the backspace key mid-touch). That churn raised the memory
  high-water mark and risked the extension being jetsammed during long
  sessions. The board is now only rebuilt when its *shape* changes (mode,
  rotation, size class); ordinary keystrokes just refresh the existing buttons.
  See `KeyboardView.updateKeys` and `KeyboardLayout.hasSameStructure`.
- **Memory warnings release transient UI** (the accent callout) via
  `KeyboardView.releaseTransientResources()`.
- **Timers are cancelled on key reuse and on `deinit`** so held-key repeat/
  long-press timers cannot outlive the key they belong to.

If a real crash report or a clear memory-growth trace is captured, attach it to
the build in App Store Connect (or paste the symbolicated report) so the next
fix can target the actual frame rather than a hypothesis.
