# Mouseless

Mouseless is a personal macOS 14+ menu-bar utility for controlling the pointer with the keyboard in **自由模式** (free mode). It is intentionally local-only and has no App Sandbox.

## Build

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), make sure the local certificate `Mouseless Local Development` exists in the login keychain, and run:

```sh
./Scripts/build-and-run.sh
```

The script generates the Xcode project from `project.yml`, builds with the fixed bundle identifier `com.reinerlau.mouseless`, verifies the designated requirement and Hardened Runtime, then launches the menu-bar agent. The signature/TCC smoke-test conclusion is recorded in `docs/adr/0001-use-a-fixed-local-signing-identity.md`; the interactive TCC checks are documented in the prototype branch referenced there.

Run the deterministic runtime suite with:

```sh
swift test
```

On first launch, use Request Permissions and grant Accessibility, Input Monitoring (Listen Event), and Post Event access. The menu offers Recheck Permissions, Open System Settings, Reload Configuration, diagnostics, and Quit.

The first launch creates `~/Library/Application Support/Mouseless/config.json`. Edit only the
documented JSON fields, then choose Reload Configuration from the menu. Invalid files are rejected
without replacing the last valid runtime configuration. The interactive real-app check is
`./Scripts/configuration-smoke-test.sh`.

For lock-screen, sleep, permission-loss, and event-tap recovery checks, run
`./Scripts/recovery-smoke-test.sh`. These cases require system interaction and are recorded as an
operator checklist; after each fault, free mode must remain off until explicitly re-enabled.
