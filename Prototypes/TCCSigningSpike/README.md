# TCC Signing Spike — PROTOTYPE, THROW AWAY

This native macOS spike answers one question:

> Can a locally self-signed app keep its TCC identity across rebuilds while using an active `CGEventTap` and posting a mouse event?

It is not the Mouseless application. It deliberately contains no movement engine, configuration system, production architecture, or reusable implementation.

## Run

```bash
./Prototypes/TCCSigningSpike/build-and-run.sh
```

The script builds an agent-style menu bar app with bundle ID `com.reinerlau.mouseless.tcc-spike`, signs it with `Mouseless Local Development`, verifies the signature, and launches it.

## First pass

1. Grant the permissions macOS requests.
2. If the menu bar item shows `TCC!`, quit the spike, relaunch it with the build script, and choose **Recheck Permissions**.
3. Wait for the menu bar item to show `TCC✓`.
4. Press `Control–Option–Command–M`.
5. Pass condition: the M keystroke is swallowed and the pointer moves 40 points to the right.
6. Choose **Cycle Event Tap**, then repeat the chord. It must still work.

## Rebuild identity pass

1. Quit the spike from its menu.
2. Run the build script again. The bundle build number changes, forcing a new code signature over changed bundle contents.
3. Pass condition: the spike reaches `TCC✓` without adding a new Accessibility/Input Monitoring entry, and the test chord still moves the pointer.

## Verdict

- **Pass**: the self-signed designated requirement is stable enough for this Mac. The real app may use the same local signing identity.
- **Fail**: stop. Do not build the real input engine on this identity. Revisit Apple Development signing or another permission strategy.

## Observed result — PASS

Verified on 2026-08-26 with macOS 26, Xcode 26.6, and Swift 6.3.3:

- Build `20260826050655` received the required TCC permissions, swallowed the test chord, and moved the pointer.
- Build `20260826051419` changed the signed bundle contents while retaining the same designated requirement: bundle identifier `com.reinerlau.mouseless.tcc-spike` plus certificate leaf `B81920E0AE7821E1162447B174A80421AFE9ABBC`.
- The rebuilt app retained its Accessibility/Input Monitoring authorization without being added again.
- The rebuilt app swallowed the test chord and posted pointer movement successfully.

The design question is settled for this Mac: a fixed local self-signed identity is viable for Mouseless development and personal use.

## Cleanup

Quit the menu bar spike. Its generated app lives only under `Prototypes/TCCSigningSpike/.build/`. TCC entries are intentionally left untouched until the verdict is captured, so cleanup cannot accidentally erase evidence.
