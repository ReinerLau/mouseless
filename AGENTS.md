## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues using the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The default five-label triage vocabulary is used. See `docs/agents/triage-labels.md`.

### Domain docs

This repository uses the single-context layout. See `docs/agents/domain.md`.

## App verification

When a change affects the runtime or macOS app behavior, completion requires
running `./Scripts/build-and-run.sh` after tests. The script must stop the
running Mouseless process, build the Release app, launch that built app, and
leave the process-path and launch-time verification in the completion report.
`swift build` and `swift test` verify source behavior but do not replace this
app verification step.
