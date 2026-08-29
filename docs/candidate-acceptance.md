# Keyveer daily-use candidate acceptance

This document is the operator record for Issue #11. It is intentionally a
manual record: TCC, display topology, lock/sleep behavior, Instruments, and
long-running stability cannot be honestly certified by a unit test. Do not
mark the seven-day period complete until seven calendar days have actually
elapsed.

## Candidate identity

Create the candidate and keep the generated manifest with the acceptance notes:

```sh
./Scripts/candidate-build.sh
cat build/candidate/candidate-manifest.txt
```

Record the following before the first run:

| Field | Value |
| --- | --- |
| Candidate manifest | |
| Git revision | |
| Source state / working-tree fingerprint | |
| Version / build number | |
| Designated requirement | `identifier "com.reinerlau.keyveer"` |
| Signing identity | `Keyveer Local Development` |
| macOS version | |
| Displays and refresh rates | |
| Starting TCC state | Accessibility / Listen Event / Post Event |
| Acceptance start date and time | |

Rebuild the candidate once after permissions have been granted. Run
`./Scripts/tcc-smoke-test.sh build/candidate/Build/Products/Release/Keyveer.app`
and confirm in System Settings that the same application still has its three
permissions. A changed bundle identifier or signing identity is a failure,
not a new candidate identity to silently accept.

## First-run and feature smoke checklist

Run the existing focused smoke scripts after the candidate build. Each script
must be run with the candidate app path where it accepts an argument:

```sh
APP=build/candidate/Build/Products/Release/Keyveer.app
./Scripts/configuration-smoke-test.sh "$APP"
./Scripts/motion-smoke-test.sh "$APP"
./Scripts/button-smoke-test.sh "$APP"
./Scripts/scroll-smoke-test.sh "$APP"
./Scripts/recovery-smoke-test.sh "$APP"
```

Record a check only after observing the result in the real app:

- [ ] First launch creates the default configuration and the permission menu clearly reports each missing capability.
- [ ] Accessibility, Listen Event, and Post Event can be granted from the requested flow; incomplete permissions pass keys through and cannot enter free mode.
- [ ] Rebuilding with the fixed identity preserves the existing TCC grant.
- [ ] Left Option enters and exits free mode as the fixed safety exit; Escape's down, repeat, and up events pass through; ordinary application switching leaves free mode unchanged.
- [ ] In free mode, every ANSI letter, number, punctuation key, Space, keypad number/operator/decimal key, and available ISO/JIS character key is consumed without text leakage when unmapped; mapped keys still perform their Keyveer action.
- [ ] Return, keypad Enter, Delete, Forward Delete, Tab, Escape, arrows, Home, End, Page Up/Down, function keys, and media keys pass through; Shift, Caps Lock, right Option, and Fn do not bypass character protection.
- [ ] Command/Control shortcuts pass through completely, and a key's down/repeat/up decision remains paired across entry, Left Option exit, Left Option release, permission loss, lock, sleep, and event-tap recovery.
- [ ] Immediately after entering free mode, the blue indicator is at the current pointer location within one display refresh; I/J/K/L move up/left/down/right, including diagonals and opposing directions.
- [ ] A precision key, each fast key, and stacked fast keys produce the expected ordered speeds; at both 60 Hz and 120 Hz, equal movement and scroll hold times produce approximately equal distances.
- [ ] Movement crosses a reachable multi-display boundary and respects non-standard/negative display coordinates and display gaps.
- [ ] Space/R/E/Q/W produce paired left/right/middle/back/forward button events; holding each while moving produces drag events; all buttons release on Left Option and every safety exit.
- [ ] M/comma/period/slash produce the four scroll directions, including diagonal scrolling, low-speed scrolling, and precision/fast multipliers.
- [ ] Physical mouse and trackpad movement still works in free mode, and keyboard movement resumes from the physical pointer location.
- [ ] Valid configuration reload applies atomically; malformed, unknown-field, or out-of-range configuration keeps the previous valid behavior and reports the error.
- [ ] Lock, unlock, sleep, wake, session inactive/active, and each permission revocation leave free mode off and release all virtual buttons.
- [ ] Event-tap timeout/user-input disable either recovers or reports a distinct failure; after failure the menu remains usable, free mode stays off, and keyboard input is passed through.
- [ ] Diagnostic summary contains only capability/configuration/event-tap state and aggregate counters; it contains no raw keys, input text, app/window names, or pointer history.

## Performance evidence

The Release candidate's process budget is measured with:

```sh
./Scripts/performance-smoke-test.sh build/candidate/Build/Products/Release/Keyveer.app
```

The script records a ten-second idle window and a ten-second continuous
movement window. The default limits are idle CPU below 0.5%, active CPU below
3%, and peak resident memory below 50 MB. Save its terminal output with the
acceptance record. If a machine is unusually busy, repeat the same fixed
window and record the reason; do not silently change limits.

Quit any existing process from the candidate path before starting this test;
the script refuses to measure a reused process. It moves the pointer to the
main display center, drives a timed rightward movement, verifies that movement
occurred, and leaves free mode off. The script reports peak *sampled* RSS;
transient peaks and long-term growth still require the Instruments check below.

For callback latency, build/run a Debug configuration, exercise movement, use
Copy Diagnostic Summary, save the text to a file, and run:

```sh
./Scripts/diagnostic-budget-check.sh /path/to/debug-diagnostic-summary.txt
```

This requires at least one latency sample and checks the maximum callback
latency is below 1 ms. Also verify by source review or Instruments that the
event-tap callback does not perform logging, configuration parsing, UI work,
or synthesized mouse-event generation. Run Instruments or an equivalent
sampling tool once to look for main-thread blocking, listener-thread timeout,
or sustained memory growth, and record the result here:

| Evidence | Tool / duration | Result or artifact path |
| --- | --- | --- |
| Callback path | Source review / Instruments | |
| Main-thread responsiveness | Instruments Time Profiler | |
| Listener timeout | Instruments / Console | |
| Memory growth | Instruments Allocations or equivalent | |

## Seven-day record

At the end of each day, record the candidate identity and the observed failure
modes. A blank day is not evidence of a pass.

| Day / date | Build identity | Hours used | Features exercised | Failures / recovery observations | Initials |
| --- | --- | ---: | --- | --- | --- |
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |
| 6 | | | | | |
| 7 | | | | | |

Final sign-off requires all feature checks above, saved performance evidence,
no unexplained input-state residue, no permanent event-tap failure, and seven
actual calendar days of use. The parent specification in Issue #1 remains the
authoritative target for the final personal replacement decision.
