# herdr-jj-status

A [herdr](https://herdr.dev) plugin that shows the **Jujutsu (`jj`) bookmark and
status** for `jj` workspaces in the spaces sidebar — the useful equivalent of the
built-in `branch` / `git_status` row for repos you manage with `jj`.

For plain-git workspaces it does nothing: the built-in git row is left untouched.

## How it works

herdr lets a plugin report custom sidebar values as workspace **metadata tokens**
(`$name` tokens in `ui.sidebar.spaces.rows`). This plugin populates two tokens:

| token          | analogous to     | contents |
| -------------- | ---------------- | -------- |
| `$jj_bookmark` | git `branch`     | where `@` is: the bookmark name(s) when you're on one; otherwise `<nearest>:: @<change-id>`; or just `@<change-id>` with no bookmark |
| `$jj_status`   | git `git_status` | `! ↑A↓D *N` — conflict, remote ahead/behind, dirty file count |

**`$jj_bookmark` examples:** `main` (on it) · `main:: @xyz` (on a descendant of
`main`, currently at change `xyz`) · `@xyz` (no bookmark) · `feat wip` (two
bookmarks) · `main??` (conflicted bookmark).

`::` is jj's DAG-range operator (`foo::` = descendants of foo), so `foo:: @xyz`
reads "in foo's descendants, at change `xyz`.

**`$jj_status` glyphs:**

| glyph | meaning |
| ----- | ------- |
| `!`    | working-copy commit `@` is conflicted |
| `↑A` `↓D` | the bookmark is A ahead / D behind its remote (default `origin`) |
| `*N`   | `@` is non-empty; N = changed files |

Examples: `↑2` · `↓1 *3` · `!*2` · `↑2↓1`. Set `JJ_STATUS_REMOTE` to compare
against a remote other than `origin`.

**No background process.** herdr invokes a short-lived `bin/refresh.sh` on
workspace/worktree events (and on demand via the `jj status: refresh all`
action); each run reports the tokens and exits. Nothing is daemonized, there is
no pidfile, and there are no orphan processes. Every `jj` call is a pure read
(`--ignore-working-copy --no-pager`), so the plugin never snapshots or mutates
your working copy.

All rows are swept once at server **startup and after a live handoff** (a
`[[startup]]` hook), so they're populated immediately. After that, because herdr
emits no event for commands typed inside a pane, a row refreshes when you **switch
into** its space (`workspace.focused`), when a space or worktree is
**created/opened**, or when you run the **refresh action**. Bind the action to a
key for an instant manual refresh (see below).

## Requirements

- herdr ≥ 0.7.5
- `jj` and `jq` on `PATH`

## Install

```sh
# From GitHub:
herdr plugin install mroth/herdr-jj-status

# …or from a local checkout (for development):
herdr plugin link /path/to/herdr-jj-status
```

Confirm it linked:

```sh
herdr plugin list
```

## Configure the sidebar

Add a jj row to `ui.sidebar.spaces.rows` in `~/.config/herdr/config.toml`. The
default is:

```toml
[ui.sidebar.spaces]
rows = [["state_icon", "workspace"], ["branch", "git_status"]]
```

Add the jj tokens as their own row:

```toml
[ui.sidebar.spaces]
rows = [["state_icon", "workspace"], ["branch", "git_status"], ["$jj_bookmark", "$jj_status"]]
```

Then reload:

```sh
herdr server reload-config
```

The jj row is empty for non-jj workspaces and collapses automatically, so it only
takes up space where it applies.

### Optional: bind a refresh key

To refresh all rows on demand, invoke the action:

```sh
herdr plugin action invoke refresh --plugin mroth.jj-status
```

Bind that to a key via your herdr keybinding config if you want instant refresh
after running `jj` commands without switching spaces.

## Development

```sh
bash test/compute_test.sh   # dependency-free tests for the token computation
bash bin/refresh.sh         # sweep all workspaces once (against a running herdr)
```

- `lib/compute.sh <dir>` — pure: prints `<jj_bookmark>\t<jj_status>` for a repo
  dir, exit 3 if not a jj repo.
- `bin/refresh.sh` — reports tokens for the event's workspace
  (`HERDR_PLUGIN_CONTEXT_JSON`) or, with no context, sweeps all workspaces.

## Uninstall

```sh
herdr plugin unlink mroth.jj-status   # linked local plugin
# herdr plugin uninstall mroth.jj-status
```

Remove the `$jj_bookmark` / `$jj_status` tokens from `ui.sidebar.spaces.rows` and
`herdr server reload-config`.
