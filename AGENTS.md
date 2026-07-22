# AGENTS.md

A [herdr](https://herdr.dev) plugin (id `mroth.jj-status`) that shows the current
Jujutsu (`jj`) bookmark/status in herdr's spaces sidebar, for `jj` workspaces.

## Layout

- `herdr-plugin.toml` — manifest: the startup hook, the on-demand action, and the
  herdr event hooks that trigger a refresh.
- `bin/refresh.sh` — short-lived hook herdr invokes; computes tokens for a
  workspace (or sweeps all) and reports them via `herdr workspace
  report-metadata`, then exits.
- `lib/compute.sh <dir>` — **pure**; prints `<jj_bookmark>\t<jj_status>` for a
  repo dir (exit 3 if not a jj repo). The source of truth for the display grammar.
- `test/compute_test.sh` — tests for `compute.sh` (no deps beyond `jj`/`jq`).
- `plans/` — gitignored scratch space for storing and sharing plans/design notes
  locally; safe to create and write here.

## Invariants — do not break

- **Stateless.** No daemon or background process: herdr spawns short-lived hooks
  and reaps them. Refresh happens only on the herdr events in the manifest and the
  on-demand action — herdr emits no "command finished in a pane" event, so don't
  attempt live-on-edit updates.
- **jj reads must be pure.** Every `jj` call uses `--no-pager
  --ignore-working-copy`, so reading status never snapshots or mutates the working
  copy. Keep it that way.

## Working here

- Requires `jj` and `jq` on `PATH`.
- After changing `compute.sh`, run `bash test/compute_test.sh`.
- Verify any changed shell script with `shellcheck <file>` and fix its findings before considering the work done.
- Version control: if a `.jj/` directory is present this is a Jujutsu repo
  (colocated with git) — use `jj` commands only, not `git`. If `.jj/` is absent,
  use `git`. Either way, commit/push only when asked.
- To verify against a running herdr: `herdr plugin link "$PWD"`, then
  `bash bin/refresh.sh` and inspect `herdr api snapshot`.

## References

- herdr plugins: https://herdr.dev/docs/plugins/
- herdr configuration: https://herdr.dev/docs/configuration/
- herdr config reference: https://herdr.dev/docs/config-reference/
- jj revsets: https://docs.jj-vcs.dev/latest/revsets/
