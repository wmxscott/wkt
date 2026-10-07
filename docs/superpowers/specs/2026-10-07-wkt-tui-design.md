# wkt picker (TUI) — design

**Date:** 2026-10-07 · **Status:** draft for review

## Goal

Running `wkt` with no arguments opens a full-screen picker over the current repo's worktrees. You can open one, or create a new one with every `wkt new` option. Every `wkt <command>` keeps working exactly as it does today.

It looks and behaves like the pickers in `wmxscott/pr-tracker` and `wmxscott/herdr-projects`: built on fzf, using Catppuccin Latte or Macchiato, nerd-font icons, and a dim line of key hints.

## Decisions

| Topic | Decision |
|---|---|
| Entry point | Plain `wkt`. No `ui` subcommand |
| Engine | fzf, called from zsh inside `bin/wkt`. fzf is optional: only the picker needs it |
| Scope | The current repo only |
| "Open", outside Herdr | Print the path on stdout. A shell function runs `cd` to it |
| "Open", inside Herdr | `herdr worktree open … --focus`, the same as `wkt new`. Nothing goes to stdout |
| Theme | Chosen once at launch: `WKT_THEME`, else theme-monitor's trigger file, else macOS's own setting |

## 1. Starting the picker

The `""` branch of the command dispatch changes:

- **At a terminal** (stdin and stderr are TTYs, or the test-only override `WKT_ASSUME_TTY=1` is set): run `cmd_ui`. stdout doesn't need to be a terminal, so `$(wkt)` works.
- **Not at a terminal:** today's behaviour stays. It prints usage to stderr and exits 2.

`cmd_ui` checks these, in order, and calls `die` if one fails:

1. In a git repo, else `Not inside a Git repository.`
2. `fzf` is on `PATH`, else `the picker needs fzf: brew install fzf`.
3. `fzf --version` is at least **0.36**, the first version with the `load` event. Otherwise it says which version it found and which it needs.

The top-level `--help` gets a line: `(no command)  Pick or create a worktree (needs fzf)`.

## 2. Theme

The theme is read the same way as in the sibling pickers, once at launch:

1. `WKT_THEME` set to `light` or `dark`. Any other value counts as `auto`.
2. The theme-monitor trigger file, `$XDG_DATA_HOME/theme-monitor/theme-change.trigger`, else `~/.local/share/theme-monitor/theme-change.trigger`. It holds `light` or `dark`.
3. On macOS, `defaults read -g AppleInterfaceStyle`: `Dark` means dark.
4. Otherwise light.

`light` uses **Catppuccin Latte** and `dark` uses **Catppuccin Macchiato**. The RGB values are copied from `herdr-projects/lib/herdr_projects/theme.py`: base, surface0–2, overlay0–1, subtext0, text, green, red, yellow, peach, mauve and blue.

Colour rules, as in the sibling pickers:

- Rows are painted with 24-bit colour codes (`38;2;r;g;b`). fzf gets no `--color`, so it keeps the terminal's own theme.
- The frame (hints, paths, spines) uses only the neutral colours (overlay, subtext, text). Strong colours mean status and nothing else.
- With `NO_COLOR` set, rows are plain text and still have their icons.

## 3. Shared fzf look

Every fzf screen, the list and each step of "new", uses these settings:

```
--ansi --layout=reverse --height=100% --border=none --margin=0 --padding=0 --no-info --prompt '> '
```

**Header.** It has three rows, like `theme.header()` in herdr-projects:

1. A blank row.
2. An optional bold title in `text`, then ` · <hints>` dim in `overlay0`.
3. A notice, or a blank row. Problems are red and successes are green.

Hints use `↵` for Enter and `^x` for ctrl-x, joined with ` · `.

**Icons** are written as `$'\uXXXX'` escapes in the script, never as literal characters. Codepoints are from nerd-fonts 3.5.1, checked against herdr-projects' `glyphs.tsv`:

| Name | Codepoint | Used for | Colour |
|---|---|---|---|
| `nf-oct-git_branch` | U+F418 | worktree on a branch | overlay1 |
| `nf-oct-home` | U+F46D | worktree on the default branch | overlay1 |
| `nf-oct-git_commit` | U+F417 | detached `HEAD` | overlay1 |
| `nf-fa-circle` | U+F111 | the worktree you're in | green, bold |
| `nf-oct-circle` | U+F4AA | has an open Herdr workspace | blue |
| `nf-md-link_off` | U+F0338 | folder missing (prunable) | red |
| `nf-oct-lock` | U+F456 | locked worktree | yellow |
| `nf-oct-alert` | U+F421 | error notice | red |

## 4. List screen

**Rows** come from `git worktree list --porcelain`. The `.bare` entry is skipped, and so is any other bare entry. Each row looks like this:

```
<icon>  <branch>   <path>                        <status>
```

- **Branch** is shown in `text`. A detached worktree shows its short SHA.
- **Path** is dim `overlay0`. In a `.bare` layout it's relative to the layout's folder, otherwise it's shortened with `~`. When space runs out, it's cut from the left with `…`.
- **Status** is a single icon at the right edge. Priority order: current, then missing, then locked, then open in Herdr. Rows without a status leave it blank.
- **Width** is measured once at launch with `stty size </dev/tty`, less the preview pane and fzf's 3 columns for pointer, marker and scrollbar. Display width is counted with zsh's `${(m)#…}`.
- **Order:** the default branch first, then the rest in git's order.
- **Herdr open state:** inside Herdr only, one `herdr workspace list` call. Worktree paths are read from its `checkout_path` fields. If that fails, rows show no Herdr status. Outside Herdr it isn't called.
- **Searching:** each row is `head⇥branch⇥tail⇥path`, shown with `--delimiter '\t' --with-nth 1..3 --nth 2 --tabstop 1`, so searching matches the branch only. The hidden 4th field is the path, which is what Enter acts on.
- **Start position:** the cursor starts on the worktree you're in.

**Preview** is on the right, 40% wide with `border-left`, the same as pr-tracker. It shows the highlighted worktree's details, and starts one line down because fzf draws its scroll position over the first line:

```

<branch>                     bold text
<path>                       subtext
<upstream> → ahead/behind    blue, arrow dim overlay0   (when tracking)

<git status -s, first 10>    paths in text, status letters green/red/yellow
<git log --oneline -8>       SHA dim overlay0, subject text
```

The preview calls `wkt` itself through a hidden internal command, `wkt __preview <path>`, so its colours follow the same theme. The command isn't listed in `--help`.

**Keys and header:** `↵ open · ^n new · esc quit`, read through `--expect=ctrl-n --print-query`.

| Input | Result |
|---|---|
| Enter on a row | Open that worktree. See §6 |
| ctrl-n | Start "new worktree", with the search text as the branch name |
| Enter with no matching rows | Same as ctrl-n |
| Esc or ctrl-c | Print nothing and exit 130 |

## 5. New-worktree steps

These are chained fzf screens, like `flow.py` in herdr-projects. Each has the header title `New worktree` and the hints `↵ accept · esc discards`. Esc at any step discards everything and returns to the list.

1. **Branch:** an input line, pre-filled with the search text. It uses `--print-query --disabled --query <default>` and `--prompt 'Branch: '`. A blank answer asks again. The name is checked with `git check-ref-format --branch`. A bad name asks again, with a red notice: `'<name>' is not a valid branch name`.
2. **Source:** `--prompt 'Source: '`. It's a list of local branches and origin's branches, with duplicates removed and the default branch first, each with the branch icon. Enter only accepts a row from the list (`enter:accept-non-empty`). **This step is skipped** when the branch already exists locally or on origin, because `wkt new` ignores `-s` then.
3. **Label:** inside Herdr only, and only when `--no-herdr` wasn't chosen. It's an input line with the prompt `Label: `, and blank lets Herdr pick. Its hints add `^o don't open in Herdr`. ctrl-o accepts with `NO_HERDR=1`.

After the last step, it calls `cmd_new -b <branch> [-s <source>] [-n <label>] [--no-herdr]` in the same shell, with stdout sent to stderr. If `cmd_new` fails, it calls `die`, so the picker closes with its usual error message.

## 6. Output contract

- **stdout** carries **one line, the chosen path, or nothing**. Every other message (steps, `✓`, warnings) goes to stderr, so it still shows when stdout is captured.
- **Opening an existing row:** inside Herdr, call `herdr_open "$common_dir" "$path"`. If Herdr opened it, print nothing. Otherwise print the path. Outside Herdr, print the path.
- **After creating:** print `WKT_PATH`, unless `WKT_HERDR_OPENED=1`.
- **Exit status:** 0 when done, 130 on Esc, 1 or git's own status on failure. This matches today's `wkt`.

**`cmd_new` refactor:** at the end it sets two global variables, `WKT_PATH`, the final worktree path, and `WKT_HERDR_OPENED`, which is 1 when `herdr_open` succeeded. What it prints doesn't change.

**Shell function**, for the README. It works the same in zsh and bash:

```zsh
wkt() {
  (( $# )) && { command wkt "$@"; return; }
  local dir; dir=$(command wkt) || return
  [[ -n $dir ]] && cd -- "$dir"
}
```

## 7. Code layout

All of it lives in `bin/wkt`, roughly 250 lines added:

| Unit | Job |
|---|---|
| `ui_theme` | Picks light or dark and fills the palette variables |
| `ui_paint <colour> [bold\|dim] <text>` | Wraps text in a colour code. Plain text under `NO_COLOR` |
| `ui_header <hints> [<title>] [<notice>]` | Builds the three-row header |
| `ui_rows` | Builds the list rows from `git worktree list --porcelain` and Herdr's open state |
| `ui_preview <path>` | Prints the preview. Reached through `wkt __preview` |
| `ui_fzf <prompt> <header> [args…]` | Runs fzf with the shared settings. Returns 130 on Esc |
| `ui_new <query>` | Runs the new-worktree steps, then `cmd_new` |
| `cmd_ui` | Checks, the list loop, and the output |

## 8. Testing

There's a new file, `test/ui.bats`. It uses a **stub `fzf`** placed first on `PATH`, next to the existing stubs. The stub:

- writes each call's arguments and stdin to a log, so tests can check rows, icons, the header and flags;
- answers `--version` with a version the test chooses;
- plays back a queue of answers, one per call. Each answer is an exit code plus stdout, in fzf's order: the query, then the `--expect` key, then the selection.

Tests set `WKT_ASSUME_TTY=1` and `WKT_THEME=dark`.

| Case | Expectation |
|---|---|
| Not at a terminal | Usage on stderr, exit 2. This is the existing `cli.bats` test |
| No fzf / old fzf | `die` with the install hint or the version message |
| Not in a repo | Same error as `wkt new` |
| Enter on a row, outside Herdr | stdout is exactly that path |
| Enter on a row, inside Herdr | The stub `herdr` logs `worktree open … --focus`, and stdout is empty |
| Herdr fails | Warning on stderr, path on stdout |
| Esc | stdout is empty, exit 130 |
| Rows | `.bare` left out, current row marked with U+F111, default branch first with U+F46D, Macchiato colour codes present |
| `NO_COLOR` | Rows have no escape codes but still have icons |
| `WKT_THEME` unset, trigger file says `light` | Latte colour codes |
| ctrl-n → branch → source | A worktree is created from the source branch, and stdout is its path |
| Enter with no matches | The new-worktree steps start, pre-filled with the search text |
| Bad branch name | Asked again with the red notice |
| Branch exists on origin | Source step skipped, and the branch tracks origin |
| Inside Herdr, ctrl-o on label | No `worktree open` call, path printed |
| Esc during the new-worktree steps | Back to the list, nothing created |
| `wkt __preview <path>` | Includes the branch, status lines and log lines |

The CI smoke test stays the same. `zsh -n` and shellcheck cover the new code and the stub.

## 9. Docs

- README: a new **Picker** section covering what plain `wkt` does, its keys, the shell function, the fzf requirement and `WKT_THEME`. `WKT_THEME` also goes in the Configuration table, and the Homebrew formula mentions fzf in its caveats.
- The usage block gets a `wkt` line with no arguments.
- README **Install** section lists the optional dependencies next to the existing Herdr note:
  - **fzf** (0.36+, `brew install fzf`): needed only for the picker. Every `wkt <command>` works without it.
  - **[wmxscott/theme-monitor](https://github.com/wmxscott/theme-monitor)**: lets the picker follow macOS light/dark mode through its trigger file. Without it, the picker asks macOS directly, or uses `WKT_THEME`.
  - A Nerd Font in the terminal, for the picker's icons.

## Out of scope

- Rename, delete or prune from the picker.
- Listing worktrees across repos.
- Live theme switching while the picker is open, and redrawing rows on resize.
- Dirty markers on each row. Status is shown in the preview instead.
- Screenshots and a VHS recording script. They can follow, like the sibling repos.
