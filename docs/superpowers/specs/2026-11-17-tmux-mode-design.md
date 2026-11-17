# wkt tmux mode: design

**Status:** the builder check is done and its questions are answered. Waiting on the user's approval.

## Why

The user is moving their daily terminal setup from Herdr to tmux. They want a stable environment they own, not one that changes with every new tool. The plan has five projects. The tmux core is done; its design is in `wmxscott/dotfiles`, `docs/superpowers/specs/2026-11-16-tmux-core-design.md`. This is project 2. The switcher, agent state and status-bar alerts are project 3.

Herdr stays installed and in use until the user says otherwise, so wkt must keep working with it.

In the new setup, a worktree is a tmux session and a Herdr tab is a tmux window. wkt is how the user makes worktrees. Almost always they run `wkt new -b <branch>`, then start Claude Code themselves in the new worktree's pane.

The user asked for two changes to how wkt behaves:

1. **Opening is explicit.** Today wkt opens every new worktree in Herdr whenever it runs inside Herdr. From now on, nothing opens unless you ask with `--tmux` or `--herdr`.
2. **Removing a worktree from the keyboard.** Today the user right-clicks the worktree in Herdr's sidebar and picks "close and delete". They don't like needing the mouse.

## Goals

- `wkt new --tmux` creates or reuses the worktree and puts you in its tmux session.
- `wkt rename` keeps an existing tmux session or Herdr workspace in step, with no flag.
- `wkt rm` removes a finished worktree together with its session or workspace, without losing work.
- The picker can open worktrees in tmux or Herdr, and can remove them.
- Herdr keeps working through `--herdr` while the user still uses it.

## Non-goals

- Deciding from the environment whether to open anything. The user chose explicit flags.
- Starting anything in a new session, such as Claude, a layout or extra windows.
- Deleting branches on origin. GitHub already deletes a merged PR's branch.
- The switcher, agent state and status-bar alerts, which are project 3. Its delete key will call `wkt rm`.
- Dropping Herdr support.

## Anti-goals

Any of these counts as a failure, even if everything else works:

- Something opens, or the user's screen moves, without being asked. Above all, an agent running `wkt new` inside tmux must never switch the user's tmux client to another session.
- `wkt rm` loses work: uncommitted changes, untracked files, commits never pushed, or a branch whose work was never merged.
- The user's Herdr setup breaks partway through the migration. Launchpad's wkt entry and the agent skills both depend on wkt.
- The tests touch a real tmux server, Herdr or GitHub.

## Decided

Items marked *(my call)* weren't discussed with the user. They're mine to settle, and the user can overrule them when reviewing.

### Opening is explicit

- **`wkt new -b <branch>`** does the git work and prints the path, and nothing else, wherever it runs. This is what agents run.
- **`--tmux`** also opens the worktree's tmux session and switches to it. If the worktree already has a session, it switches to that one instead.
- **`--herdr`** opens the worktree as a Herdr workspace, as wkt does inside Herdr today.
- Passing `--tmux` and `--herdr` together is a usage error. *(my call)*
- `--no-herdr` is still accepted and does nothing, so the agent skills and scripts that pass it keep working. It disappears from the help text and the README. *(my call)*
- **`--tmux` run outside tmux** creates the session in the background and prints how to attach (`tmux attach -t <name>`). *(my call)*
- **wkt no longer has to run inside Herdr to talk to it.** *(my call)* During the migration, the user mostly runs wkt from tmux.
  - `--herdr` opens the worktree in the running Herdr, wherever wkt runs, and warns if Herdr can't be reached.
  - `rename` and `rm` ask Herdr whether the worktree has a workspace and update or close it. They skip that step silently if Herdr isn't running.
  - `rename` never creates a workspace where none existed, and never moves Herdr's focus.
  - The README's "only talks to Herdr when run inside it" goes, and so does the test that pins it.
- **Picker:** `wkt --tmux` and `wkt --herdr` make Enter, and making a new worktree, open it there. Plain `wkt` still prints the path, for the `cd` wrapper. *(my call)*
- As with Herdr today, once the git work has succeeded, failing to open only warns, and the exit status is 0.

### A new session

- **Contents:** one window running a shell, in the worktree folder. Nothing is started for you.
- **Name:** always `<repo>/<branch>`, such as `widget/fix-login`. That's the user's choice. The status bar's left side shows the session name, so it always says which repo you're in, as the tmux core design promised.
  - `<repo>` is the same name wkt already uses in worktree paths: the repository's name from origin's URL, or the folder name when there's no origin.
  - `.` and `:` become `-`, because tmux doesn't allow them in session names.
  - If the name is still taken by another worktree's session, for example two orgs with a repo of the same name, the builder picks a fallback.
  - `-n <name>` sets the name, as `-n` sets the Herdr label today.

### `wkt rename` keeps things in step

- Branch, origin and folder are handled as today.
- **If the worktree has a tmux session,** it's renamed to `<repo>/<new-branch>`, or to `-n`, and points at the new folder.
- **If the worktree has a Herdr workspace,** it's updated as `wkt rename` does inside Herdr today.
- No flag is needed, and `--no-herdr` is accepted and ignored.

### `wkt rm`

- **`wkt rm [-b <branch>] [-f]`.** Without `-b` it removes the worktree you're in.
- **What it removes:**
  - the worktree folder
  - the worktree's tmux session
  - the worktree's Herdr workspace
- **Leaving a session:** if you're inside the session being removed, it switches you to another session first, so you're never left on a dead one. *(my call)*
  - You land where tmux would put you anyway: the most recently used other session.
  - If there's no other session, wkt first opens a session for the repo's default-branch worktree (or the main checkout), so running `wkt rm` never throws you out of tmux.
- **Safety:** it refuses when the worktree has uncommitted changes, untracked files, or commits that were never pushed. `-f` removes it anyway.
- **The local branch** is deleted only if:
  - `gh` reports its PR as merged (squash merges make a merged branch look unmerged to git), or
  - git itself sees it as merged into the default branch. *(my call: this covers a branch that was never used)*

  Otherwise the branch is kept, and wkt says so.
- **It refuses** the main checkout of a normal clone, and the default branch's worktree in a `.bare` layout. *(my call)*
- **Picker:** `Ctrl-D` removes the highlighted worktree after asking to confirm.

### The tmux key, in the dotfiles repo

- **`prefix W`** opens the picker as `wkt --tmux` in a tmux popup. That's the user's choice. Typing a new branch name and pressing Enter makes the worktree and switches to it.
- **Renaming a session** keeps tmux's built-in `prefix $`. `prefix W` did that until now, but wkt names the sessions, so it's rarely needed by hand.
- **`prefix G` stays free.** It's lazygit in the user's Herdr setup and comes back with the Launchpad port in project 4. The tmux core design wrongly reserved it for "new worktree", so correct that note.
- The picker, including `Ctrl-D` on the session you're in, has to work inside a tmux popup.

## Constraints

- **wkt itself:** one zsh script, `bin/wkt`. It has no config file, only environment variables.
- **Tests:** bats, with stub `herdr`, `gh`, `fzf` and `defaults` commands first on `PATH`. Add a stub `tmux` that works the same way: it records its arguments and returns whatever answers each test scripts.
- **CI:** must stay green. That's bats on macOS, `zsh -n`, ShellCheck on the tests, the formula's syntax check, and gitleaks.
- **Public repo:** no personal paths, names or machine details in code, tests or docs.
- **Output:** keep wkt's existing style. That's `→` steps, `warning:` lines and a `✓` summary, plain output when not writing to a terminal, and `NO_COLOR` respected.
- **The user's tmux:**
  - tmux 3.8.
  - `detach-on-destroy off`, so a client whose session is killed moves to another session.
  - tmux-resurrect restores sessions when the server starts. Resurrect doesn't save `@` user options, and it recreates each session with its first pane's folder as the session's starting folder.
- **Finding a worktree's session must still work after `wkt rename` and after a resurrect restore.** One way: tag the session with a user option holding the worktree path, and fall back to a session whose starting folder is the worktree or a folder inside it. Project 3's switcher will use the same rule to match sessions to worktrees, so the README documents it.

## Release and follow-ups

- **Version 2.0.0.** *(my call)* Inside Herdr, `wkt new` no longer opens a workspace unless asked, which breaks anyone relying on the old default.
- **The tap** (`wmxscott/homebrew-tap`, `Formula/wkt.rb`) needs the usual URL and checksum bump. Its test currently expects `opened in Herdr` from a plain `wkt new`, so it needs `--herdr`.
- **After the release, in other repos:**
  - **Launchpad's wkt entry** in the user's private dotfiles (`.config/herdr/plugins/config/launchpad/config.toml`, `command = ["wkt"]`) becomes `["wkt", "--herdr"]`. Without it, the picker in Launchpad stops opening workspaces.
  - **ai-toolkit:**
    - The `wkt` plugin's skill, README, tests and marketplace descriptions, and stacked-planning's `landing-changes` skill, say that agents run plain `wkt new` and never `--tmux` or `--herdr` unless the user asks.
    - They drop `--no-herdr`.
    - They document `wkt rm`.
  - **docket's `AGENTS.md` and `CLAUDE.md`** pass `--no-herdr`. That's harmless now, so update them when convenient.

## Left to the builder

- How to point a tmux session at a new folder on rename, or whether the session tag makes that unnecessary.
- How `wkt rm` finishes cleanly when it's running inside the session it kills.
- How to find a worktree's Herdr workspace and close it. `herdr workspace list`, `herdr workspace close` and `herdr worktree remove` all exist.
- The exact "never pushed" check: commits ahead of the upstream, or, for a branch never pushed, commits that aren't on origin's default branch.
- The picker's icon for a worktree that has a tmux session, and how `Ctrl-D` confirms.
- Messages, help text and README wording.

## Done when

- **Tests cover:**
  - `new` with and without each flag; `--tmux` inside and outside tmux; reusing an existing session; the `<repo>/<branch>` name and a collision
  - `rename` updating a tmux session and a Herdr workspace
  - `rm`:
    - a clean removal and each refusal
    - `-f`, and both branch-deletion rules
    - leaving the session you're in
  - the picker's flags and `Ctrl-D`
  - `--no-herdr` doing nothing
- **Shipped:** CI is green, 2.0.0 is released through the tap, Launchpad's entry is updated, and the agent skills are updated.
- **The user has checked in Ghostty:**
  - `wkt new -b x --tmux` lands them in the new session.
  - `wkt rename` renames it.
  - `wkt rm`, run from inside the session, removes it and lands them in another session.
