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

Rows refresh when you switch into a space or run the refresh action (and once at
herdr startup). herdr has no event for commands run inside a pane, so a row won't
update live while you stay put — switch away and back, or trigger the action.

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

## Uninstall

```sh
herdr plugin uninstall mroth.jj-status   # installed from GitHub
# …or, if you linked a local checkout:
herdr plugin unlink mroth.jj-status
```

Remove the `$jj_bookmark` / `$jj_status` tokens from `ui.sidebar.spaces.rows` and
`herdr server reload-config`.
