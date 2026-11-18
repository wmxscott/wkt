# Plan: wkt tmux mode

| | |
|---|---|
| **Status** | in progress · next: A2 |
| **Updated** | 2026-11-17 |
| **Tracker** | — |
| **Related** | [approved design](../superpowers/specs/2026-11-17-tmux-mode-design.md); tmux core design in `wmxscott/dotfiles`, `docs/superpowers/specs/2026-11-16-tmux-core-design.md` |

## Goal

wkt opens worktrees as tmux sessions when asked with `--tmux`, keeps them in step on rename, and removes finished ones from the keyboard, so the user's daily worktree loop works in tmux without Herdr. Herdr keeps working through `--herdr`, and nothing opens, moves the screen or deletes work unless the user asked.

**Falsifiable:** after this plan, the user can run their whole loop from a tmux pane, with nothing opening unasked: create (`wkt new -b x --tmux`), switch, rename (`wkt rename`) and remove (`wkt rm`, `Ctrl-D`, `Ctrl-X`).

### Done when

- [ ] `bats test` and CI pass on `main` with every phase of Stack A merged.
- [ ] wkt 2.0.0 is tagged and released, and `brew upgrade wkt` installs it from the tap.
- [ ] In the user's real tmux, in Ghostty:
  - `wkt new -b x --tmux` lands them in a session named `<repo>/x`.
  - `wkt rename -b y` renames that session to `<repo>/y`.
  - `wkt rm`, run from inside it, removes the worktree and leaves them in another session.
- [ ] `prefix W` opens the picker in a popup, and `Enter`, `Ctrl-N`, `Ctrl-D` and `Ctrl-X` all work from there.
- [ ] Launchpad's wkt entry in Herdr still opens worktrees as workspaces.
- [ ] wkt 2.1.0 rejects `--no-herdr` as an unknown option, and nothing the user runs still passes it (S18).
- [ ] An agent following the updated ai-toolkit skills runs plain `wkt new`, and the user's tmux client doesn't move.

## Settled: do not re-derive

- **S1 Opening is explicit (user's decision).**
  - `wkt new -b <branch>` does the git work and prints the path, and nothing else.
  - `--tmux` opens or switches to the worktree's tmux session.
  - `--herdr` opens it as a Herdr workspace.
  - *Rejected:* detecting tmux or Herdr from the environment, which is today's behaviour for Herdr. The user wants nothing opened unasked, and an agent running wkt inside tmux must never switch the user's client.
- **S2 `--no-herdr` is accepted and does nothing**, on every command. Callers that still pass it:
  - ai-toolkit's `landing-changes` skill and `wkt` plugin
  - docket's `AGENTS.md`
  - *Rejected:* removing the flag, which breaks those callers, and keeping its old meaning, since nothing opens by default now. It's removed from the help text and the README.
- **S3** Passing `--tmux` and `--herdr` together is a usage error, exit 2.
- **S4 Session name is `<repo>/<branch>` (user's decision).**
  - `<repo>` is the name wkt already puts in normal-clone paths: the last component of origin's URL without `.git` (`cmd_new`, `bin/wkt` ~L439–455), or the folder name when there's no origin. For a `.bare` layout, it's the same URL rule, falling back to the layout folder's name.
  - `.` and `:` in the name become `-`.
  - `-n <name>` overrides the name.
  - If the name is taken by another worktree's session, use `<org>/<repo>/<branch>`. If that's taken too, append `-2`, `-3` and so on. *(collision fallback decided here; the design left it to the builder)*
  - *Rejected:* the plain branch name with the repo added only on a clash, because the status bar has to say which repo you're in.
- **S5 How to find a worktree's session.**
  - First, a session whose user option `@wkt-worktree` equals the worktree's absolute path, resolved with `:A`.
  - Otherwise, a session whose `session_path` is the worktree or a folder inside it.
  - **Why the fallback:** tmux-resurrect doesn't save `@` options, and it recreates each session with its first pane's folder as `session_path`.
  - wkt always sets the option when it opens or renames a session.
  - The README documents this rule, because project 3's switcher uses the same one.
- **S6 Herdr no longer requires running inside Herdr.**
  - `in_herdr` stops gating Herdr calls.
  - `--herdr` calls `herdr worktree open … --focus` wherever wkt runs.
  - `rename` and `rm` look up the worktree's workspace with `herdr workspace list`. The lookup is silent when `herdr` is missing or fails.
  - `rename` re-points an existing workspace with `herdr worktree open --path <new> --label …`, without `--focus`. It never creates a workspace where none existed.
  - The README promise "wkt only talks to it when run inside Herdr" goes, and so does `rename.bats`'s "outside Herdr: renames without calling herdr".
  - *Rejected:* keeping the limit. The user runs wkt from tmux during the migration, and the limit would leave workspaces pointing at deleted folders.
- **S7 `wkt rm` safety.** It refuses, unless `-f` is given, when:
  - `git status --porcelain` shows anything, including untracked files, or
  - the branch has commits that aren't on origin. With an upstream, that's `git rev-list @{u}..HEAD`. Without one, it's `git rev-list HEAD --not --remotes=origin`.
- **S8 When `rm` deletes the local branch.** It runs `git branch -D` only if either:
  - `gh pr view <branch> --json state` says `MERGED`. The user squash-merges, so git alone can't tell, or
  - the branch tip is an ancestor of `origin/<default>`, or of the local default branch when there's no origin. This covers branches that were never used.

  Otherwise it keeps the branch and says so. It never touches the branch on origin.
- **S9 `wkt rm` refuses:**
  - the main checkout of a normal clone
  - the default branch's worktree in a `.bare` layout
  - a `-b <branch>` that has no worktree

  A detached worktree can be removed; there's just no branch to delete.
- **S10 Leaving the session `rm` kills.**
  - When `$TMUX` is set and the current session is the one being removed, wkt first runs `switch-client` to the most recently used other session, the highest `session_last_attached`.
  - If there's no other session, it opens the repo's default-branch worktree (or the main checkout) as a session through the normal open path, then switches to it.
  - Killing the session is the very last step, after all output.
  - *Rejected:* letting tmux detach when it was the only session, which would throw the user out of tmux.
- **S11 `wkt rm --merged`.**
  - It covers the repository it's run in only.
  - The set is every worktree whose branch passes S8, minus those S9 protects.
  - Each one is checked against S7. Unsafe ones are skipped and listed.
  - It shows the list and asks `[y/N]`. `-y` skips the question. With no terminal and no `-y`, it stops without changing anything.
  - Combining `-f` with `--merged` is a usage error.
  - *Deferred:* a cross-repo cleanup, which belongs to project 3.
- **S12 The picker.**
  - Plain `wkt` prints the path, as now.
  - `wkt --tmux` or `wkt --herdr` makes `Enter` and making a new worktree open there.
  - The Herdr label step, with `^o`, runs only under `--herdr`. `--tmux` adds no extra step.
  - `Ctrl-D` removes the highlighted worktree, and `Ctrl-X` runs `rm --merged`. Each asks first. *(user's decision: these keys, not `prefix W c`)*
  - The "open" icon shows when the worktree has a tmux session or a Herdr workspace. Both are looked up silently.
- **S13 It ships as version 2.0.0**, because Herdr users lose auto-open.
  - `contrib/wkt.rb` points at the `v2.0.0` tag.
  - Releases are a tag plus a GitHub release named `wkt X.Y.Z`. For precedent, see `v1.1.1` and PR #7.
- **S14 Facts about the code.**
  - `bin/wkt` is one zsh script, with `err_exit` and `pipe_fail` set.
  - Relevant functions: `take_no_herdr` (L144), `in_herdr` (L249), `herdr_open` (L257), `cmd_new` (L404), `cmd_rename` (L515, which calls `herdr_open` at L642), `ui_herdr_paths` (L800), `ui_rows` (L817), `ui_new` (L1020, Herdr label step at L1046) and `cmd_ui` (L1060).
  - `ui_new` must not run on the left of `||` or `&&`, which would turn off `err_exit` inside `cmd_new`.
  - Test stubs: `test/test_helper.bash` exports `HERDR_TAB_ID=stub-tab` by default and stubs `herdr`, `gh`, `fzf` and `defaults`, refusing to run if any of them doesn't resolve to its stub. The stub `herdr` logs its arguments and answers `workspace list` from `STUB_HERDR_WORKSPACES`.
- **S15 Facts about tmux on the user's machine.**
  - tmux 3.8, with `detach-on-destroy off`.
  - `display-popup` does **not** expand `#{…}` in its command. This was found in dotfiles PR #42.
  - From inside a popup, `$TMUX` is set but `$TMUX_PANE` isn't.
  - Whether `tmux switch-client -t <s>` run from a popup moves the popup's client must be checked on a real throwaway server (`tmux -L <name>`) in A6. Don't assume it.
- **S16 The tests never touch a real tmux.**
  - `common_setup` unsets `TMUX` and `TMUX_PANE` and adds a stub `tmux` that logs its arguments and answers queries the test sets up.
  - The guard loop refuses to run if `tmux` doesn't resolve to the stub.
- **S17 Where this plan lives.** It's in `docs/plans/` with a base36 name, as in herdr-projects. The approved design remains the record of the user's own words. This plan is the working artifact.
- **S18 `--no-herdr` is removed in wkt 2.1.0 (user's decision, added 2026-11-17).** S2's "accepted and ignored" lasts only until no caller passes the flag.
  - **Order:** ai-toolkit's skills drop it first (R4), and so does docket. Then wkt removes it, and it becomes an unknown option (exit 2).
  - **Version:** 2.1.0 rather than 3.0.0, because the user asked for it within 2.x.
  - **Before C2 lands,** the user's machines must have the updated ai-toolkit plugins. Otherwise an agent still following the old `landing-changes` skill would get a usage error.

## Command contracts

### `wkt new`
`-b <branch> [-s <source>] [-n <name>] [--tmux | --herdr] [--no-herdr]`

- The git work is unchanged.
- **With neither flag:** print the `✓` line with the path. No `herdr` or `tmux` call at all.
- **`--herdr`:** as today's in-Herdr path, minus the `in_herdr` gate (S6).
- **`--tmux`:** see Session contract. The `✓` line ends `opened in tmux`, or `switched to <name>` when the session already existed.

### `wkt rename`
`-b <new-branch> [-n <name>] [-y] [--no-herdr]`

- The branch, origin and folder work is unchanged.
- **Before the move,** record the worktree's tmux session (S5) and Herdr workspace (S6).
- **After the move:**
  - rename the session to `<repo>/<new-branch>`, or to `-n`, and update `@wkt-worktree` and its starting folder (Session contract, Renaming)
  - re-point the Herdr workspace, labelled with `-n` or the new branch name
- **No flag needed.** `--tmux` and `--herdr` are usage errors on rename.

### `wkt rm`
`[-b <branch>] [-f] | --merged [-y]`

- **Order:**
  1. Resolve the target worktree.
  2. Apply the S9 refusals.
  3. Apply the S7 checks, unless `-f`.
  4. Close the Herdr workspace.
  5. `git worktree remove`, with `--force` only under `-f`.
  6. Apply the S8 branch rule.
  7. Leave and kill the tmux session (S10).
- **Output:** a `✓` line naming what went: the folder, the branch or the kept branch, the session and the workspace.
- **Without `-b`,** the target is the worktree the shell is in. Outside tmux, the last line tells the user to `cd` to the main worktree, since their folder is gone.

### `wkt rm --merged`
- Collect the candidates (S11), print them, ask, then remove each one as `rm` would.
- The session you're in goes last, so S10 runs once.
- **Summary:** a count of removed and skipped worktrees, with each skipped one and its reason.

### Picker
`wkt [--tmux | --herdr]`

- The rows are unchanged, apart from the icon rule in S12.
- **Header:** `Enter` open, `^n` new, `^d` remove, `^x` remove merged, `esc` quit.
- **Confirming:** `Ctrl-D` and `Ctrl-X` confirm with a `ui_ask`-style y/N line, then run `cmd_rm` and return to the list. If you removed the session you're in, the picker exits, since its client has moved.

## Session contract

### Naming
Follow S4. A single function returns the name for a worktree path. `new`, `rename` and the default-branch fallback in `rm` all use it.

### Tagging and finding
- **Tag:** `set-option -t <s> @wkt-worktree <abs-path>` whenever wkt creates or renames a session.
- **Find:** a single query, `list-sessions -F '#{session_name}\t#{@wkt-worktree}\t#{session_path}'`, then apply the S5 rule in zsh.

### Opening
- **No session yet:**
  - `new-session -d -s <name> -c <path>`, then tag it.
  - If `$TMUX` is set, `switch-client -t <name>`.
  - Otherwise, print `→ attach with: tmux attach -t <name>`. If no tmux server is running, `new-session -d` starts one, which is fine.
- **A session already exists:** just switch, or print the attach hint.

### Renaming
- `rename-session -t <old> <new>`, then re-tag it.
- For the starting folder, the builder decides whether tmux 3.8 can change `session_path` directly. If not, the tag alone is enough for S5. Don't add a hack to move it.

### Closing and leaving
Follow S10. Run the kill as the last command, via `tmux kill-session -t <name>`, after all output is flushed.

## Herdr contract

- **Open:** `herdr worktree open --cwd <common-dir> --path <wt> [--label] --focus`, as today.
- **Find:** `herdr workspace list` JSON, matching `checkout_path` resolved with `:A`. That's today's parsing in `ui_herdr_paths`. Extend it to capture each workspace's id for closing.
- **Re-point on rename:** the open command above, without `--focus`, and only when the find step matched.
- **Close on rm:** `herdr workspace close <id>`. The builder checks whether `herdr worktree remove` is the better fit, but wkt must stay the one deleting the folder and branch.
- **Failure:** a lookup failure is silent. An open, re-point or close failure warns with the `herdr` command to run by hand, and the exit status stays 0, as today.

## Failure semantics

- **Git work succeeded, opening or switching failed:** a warning and exit 0, for both Herdr and tmux.
- **`rm` order:** it's arranged so that a failure leaves things recoverable. If the Herdr close fails, it warns and continues. If `git worktree remove` fails, wkt stops before touching the branch or the session, and exits with git's status.
- **`--merged`:** a failure on one worktree is reported, the rest continue, and the exit is 1 if any failed.
- **Exit codes:** usage errors exit 2, runtime errors 1, and `Esc` in the picker 130, all unchanged.

## Test seams

- **The stub `tmux`:**
  - It appends `$*` to `$STUB_TMUX_LOG`.
  - For `list-sessions`, it prints `$STUB_TMUX_SESSIONS`, which has the same tab-separated rows wkt asks for.
  - For `display-message -p`, it prints `$STUB_TMUX_CURRENT`.
  - It exits 1 when `$STUB_TMUX_FAIL` is set.
- **Helpers:** `tmux_calls`, mirroring `herdr_calls`.
- **Inside tmux:** a test sets `TMUX=stub` itself. `common_setup` always unsets it.
- **The stub `gh`** already answers `pr view` from `$STUB_GH_PR`. The `rm` tests use it for the `MERGED` state.

## Stacks and phases

### Stack A: wkt

- **Base:** `main`
- **Owns:** `bin/wkt`, `test/**`, `README.md`, `contrib/wkt.rb`, `docs/**`
- **Independent of:** —
- **Depends on:** —

| Phase | Lands | Depends on |
|---|---|---|
| A1 | Explicit `--herdr`. `--no-herdr` becomes a no-op. Herdr works from anywhere. Rename re-points existing workspaces only | — |
| A2 | Stub `tmux`, the repo-name helper, and `wkt new --tmux` with naming, tagging and opening | A1 |
| A3 | `wkt rename` keeps the tmux session in step | A2 |
| A4 | `wkt rm` | A3 |
| A5 | `wkt rm --merged` | A4 |
| A6 | Picker: `--tmux` and `--herdr`, the session icon, `Ctrl-D` and `Ctrl-X`, and working inside a tmux popup | A5 |
| A7 | Release 2.0.0: version, formula, README final pass | A6 |

- [ ] A1: explicit `--herdr`
- [ ] A2: `wkt new --tmux`
- [ ] A3: rename keeps the session in step
- [ ] A4: `wkt rm`
- [ ] A5: `wkt rm --merged`
- [ ] A6: picker modes and remove keys
- [ ] A7: release 2.0.0

**A1: explicit `--herdr`**
- **What changes:**
  - `take_no_herdr` becomes a general flag parser for `--herdr`, `--tmux` and `--no-herdr`. `--tmux` gives "not supported yet", exit 2, until A2.
  - `herdr_open` runs only under `--herdr` and drops the `in_herdr` gate.
  - `rename` uses the find-then-re-point logic in the Herdr contract.
  - `ui_herdr_paths` drops its gate.
  - The picker accepts `--herdr`, and the label step is gated on it.
  - The help text and README sections for `new`, `rename`, the picker and the Herdr notes.
- **Tests:** go through the existing tests that assumed auto-open (new, rename, ui) and add `--herdr` where opening is expected. Add tests showing that plain `new` makes no `herdr` call even with `HERDR_TAB_ID` set, and that `--no-herdr` is a no-op.
- **Cites:** S1, S2, S6, S12, S14, and Herdr contract.
- *Shippable when:* bats, `zsh -n` and ShellCheck pass, and a plain `wkt new` inside the stub Herdr leaves `herdr.log` empty.
- *Split seam:* the picker part (`cmd_ui`, `ui_new`, `ui_herdr_paths`) as A1b.

**A2: `wkt new --tmux`**
- **What changes:**
  - The stub `tmux` and the env scrub in `test_helper.bash`.
  - Pull the org and repo parsing out of `cmd_new` into a function that both the path and the session name use.
  - The session-name function, tagging and finding, and opening inside and outside tmux.
  - S3's usage error.
  - The `✓` line wording.
  - README: a "tmux" section, including S5's rule for other tools.
- **Cites:** S3, S4, S5, S15, S16, Session contract, and Test seams.
- *Shippable when:* the tests cover a new session, reuse by tag, reuse by `session_path` (the post-restore case), a name collision going to `<org>/<repo>/<branch>` and then `-2`, `-n`, and outside tmux printing the attach hint with no `switch-client`.
- *Split seam:* the helper extraction and the stub `tmux`, with no behaviour change, as A2a.

**A3: rename keeps the tmux session in step**
- **What changes:** the session lookup before the move, then rename, re-tag and starting folder after it, per Session contract, Renaming. Also `--tmux` and `--herdr` as usage errors on rename.
- **Cites:** S4, S5, and `wkt rename` contract.
- *Shippable when:* the tests show the session renamed and re-tagged, no tmux call when there's no session, and the Herdr and tmux cases both handled in a single rename.
- *Split seam:* none expected. It's small.

**A4: `wkt rm`**
- **What changes:**
  - `cmd_rm`, its usage text and dispatch.
  - The S9 refusals and S7 checks with `-f`.
  - The S8 branch rule through the stub `gh`.
  - The Herdr close.
  - S10's leave-then-kill, including the only-session fallback.
  - README.
- **Cites:** S7–S10, `wkt rm` contract, and Failure semantics.
- *Shippable when:* the tests cover each refusal, dirty and unpushed with and without `-f`, `MERGED` deleting the branch, an ancestor deleting it, unmerged keeping it, switching to the most recent session, the only-session fallback, the kill coming last in `tmux.log`, and a `git worktree remove` failure leaving the branch and session untouched.
- *Split seam:* the tmux leave and kill (S10) as A4b, with A4a removing the folder, branch and workspace only.

**A5: `wkt rm --merged`**
- **What changes:** collecting the candidates, the list, the `[y/N]` question, `-y`, the no-terminal stop, skipping unsafe worktrees, the current session last, the summary and exit status, and S11's usage error.
- **Cites:** S11 and `wkt rm --merged` contract.
- *Shippable when:* the tests cover the question being declined, `-y`, no terminal, a dirty merged worktree skipped and listed, the default branch never listed, and the current session removed last.

**A6: picker modes and remove keys**
- **What changes:**
  - `wkt --tmux`: `Enter` and `Ctrl-N` open through the Session contract.
  - The icon rule from S12.
  - `Ctrl-D` and `Ctrl-X` with confirmation.
  - The header text.
  - Check on a real throwaway tmux server that `switch-client` from inside `display-popup` moves the popup's client (S15). If it doesn't, pass the client explicitly: `wkt` reads `#{client_name}` through `tmux display-message -p` before fzf starts.
- **Cites:** S12, S15, and Picker contract.
- *Shippable when:* the stub-fzf tests cover each key, and the manual popup check has been recorded in the PR body.
- *Split seam:* `Ctrl-D` and `Ctrl-X` as A6b.

**A7: release 2.0.0**
- **What changes:** `VERSION=2.0.0`, `test/cli.bats`'s version check, `contrib/wkt.rb` pointing at `v2.0.0`, and a final README pass covering the "Why not `herdr worktree create`?" section, the configuration table and the exit codes. Once it merges, tag `v2.0.0` and create the GitHub release `wkt 2.0.0`, with notes that lead with the breaking change (S1, S2).
- *Shippable when:* CI is green, `bin/wkt --version` prints `wkt 2.0.0`, and the release exists.

### Stack R: rollout in the user's other repos

- **Base:** `main`
- **Owns:** —
- **Independent of:** —
- **Depends on:** A (each phase needs wkt 2.0.0 released)

Each phase is a PR in a different repository, so nothing here touches this repo, and none of them is stacked on another. They're ordered because R2 needs R1's `brew upgrade`. Do R1 and R2 in one sitting: between them, Launchpad's picker prints a path instead of opening a workspace.

| Phase | Lands | Depends on |
|---|---|---|
| R1 | `wmxscott/homebrew-tap`: `Formula/wkt.rb` at `v2.0.0`; its test uses `wkt new -b topic --herdr` | A7 |
| R2 | The user's private dotfiles: Launchpad's wkt entry becomes `command = ["wkt", "--herdr"]` | R1 |
| R3 | `wmxscott/dotfiles`: tmux `prefix W` opens `wkt --tmux` in a popup at the pane's folder; the core design's `prefix shift+g` note is corrected to say lazygit, from project 4 | R1 |
| R4 | `wmxscott/ai-toolkit`: the `wkt` plugin's skill, README, tests and marketplace descriptions, and stacked-planning's `landing-changes` skill, say plain `wkt new` for agents, drop `--no-herdr`, and document `wkt rm` | R1 |

- [ ] R1: tap formula 2.0.0
- [ ] R2: Launchpad passes `--herdr`
- [ ] R3: tmux `prefix W`
- [ ] R4: agent skills

**R3 note:** set the popup's folder with `-d '#{pane_current_path}'`, which *is* format-expanded. Its command is plain `wkt --tmux`, with no `#{}` in it, per S15. The existing `bind W` (rename session) goes, and tmux's default `prefix $` stays. Restow `tmux` after merging.

**R4 note:** `--no-herdr` must stay in the skills until the user's machines have 2.0.0. R4 is gated on R1 for that reason.

### Stack C: drop `--no-herdr`

- **Base:** `main`
- **Owns:** `bin/wkt`, `test/**`, `README.md`, `contrib/wkt.rb`
- **Independent of:** —
- **Depends on:** A (2.0.0 released), R (R4's skills no longer pass the flag)

This stack runs after A and R, so it changes the same files as A without overlapping it in time. C1 and C3 are in other repositories.

| Phase | Lands | Depends on |
|---|---|---|
| C1 | `wmxscott/docket`: `AGENTS.md` and `CLAUDE.md` say plain `wkt new -b <branch>` | R4 |
| C2 | wkt: `--no-herdr` removed from every command, tests flipped to expect exit 2, release 2.1.0 | C1 |
| C3 | `wmxscott/homebrew-tap`: `Formula/wkt.rb` at `v2.1.0` | C2 |

- [ ] C1: docket stops passing `--no-herdr`
- [ ] C2: wkt 2.1.0 drops `--no-herdr`
- [ ] C3: tap formula 2.1.0

**C1: docket stops passing `--no-herdr`**
- **What changes:** the one line in each of docket's `AGENTS.md` and `CLAUDE.md`.
- *Shippable when:* docket's own checks pass.

**C2: wkt 2.1.0 drops `--no-herdr`**
- **What changes:**
  - The parser stops accepting `--no-herdr`, so it reports an unknown option, exit 2, on `new`, `rename`, `rm` and the picker.
  - The tests that pinned the no-op now pin the error.
  - `VERSION=2.1.0`, `test/cli.bats` and `contrib/wkt.rb` follow.
  - Once it merges, tag `v2.1.0` and create the GitHub release `wkt 2.1.0`, with a note naming the removal.
- **Before dispatching,** confirm on this machine that the installed ai-toolkit `landing-changes` and `wkt` skills no longer mention `--no-herdr`. A search of `~/.claude/plugins/cache/ai-toolkit/` is enough. If they still do, ask the user to update the plugins first.
- *Shippable when:* CI is green, `wkt new -b x --no-herdr` exits 2, and the release exists.

**C3: tap formula 2.1.0**
- **What changes:** the usual URL and checksum bump.
- *Shippable when:* the tap's CI passes and `brew upgrade wkt` installs 2.1.0.

## Forest from the trees

### Challenge

The advisor tool isn't available in this session, so here is the strongest case that the sequence is wrong, argued myself.

1. **The daily path arrives late.** The user lives in `prefix W` and the picker, but A6 and R3 come last. If work stopped after A3, they'd have only the CLI.
   *Response:* kept. `wkt new -b x --tmux` is the user's stated usual path ("most of the time, I use `wkt new`"), so A2 delivers the core value first. The picker depends on `rm` existing for `Ctrl-D` and `Ctrl-X`.
2. **A1 flips the Herdr default before tmux works.** If the stack stalled after A1, Herdr users would lose auto-open for nothing.
   *Response:* nothing is released until A7, and the tap still serves 1.1.1, so the flip is invisible until the whole stack lands. Kept.
3. **The S5 session rule is shared with project 3, but is only tested with stubs.** A rule that's wrong against a real resurrect restore would mislead the switcher.
   *Response:* added the reuse-by-`session_path` test to A2's gate. The user's Ghostty check after a real restart is part of Done when, through the `rename` and `rm` checks on restored sessions.
4. **The rollout window.** Between `brew upgrade` and R2, Launchpad stops opening workspaces.
   *Response:* added the "R1 and R2 in one sitting" instruction.

### Drift test

Ask of every PR:

1. If every phase after this one were cancelled, could the user do more of the loop (create, switch, rename, remove) in tmux than before, or is this PR a seam that a later phase in this plan visibly needs?
2. Does any path in this PR open a session or workspace, move a tmux client, or delete a folder or branch without the user asking for it through a flag, a key or a confirmation? It must be no.

## Not doing

- **Detecting tmux or Herdr from the environment:** rejected (S1).
- **Starting Claude, layouts or extra windows in new sessions:** out of scope. The user starts Claude themselves.
- **Deleting branches on origin:** out of scope. GitHub deletes merged PR branches.
- **Cleanup across repos:** deferred to project 3's switcher.
- **A name step for tmux in the picker:** rejected. It's an extra keystroke on the user's usual path, and `-n` covers renaming.
- **`prefix W c` as a tmux key table:** rejected by the user in favour of `Ctrl-X` in the picker.
- ~~**docket's `--no-herdr` mentions:** deferred. They're harmless under S2.~~ Now phase C1, since S18 removes the flag.
- **Removing Herdr support:** out of scope until project 5, and only on the user's say-so.

## Blocked on

- **The user's check in Ghostty** blocks only the last Done-when items, not any phase. The user owns it.

## Log

- 2026-11-17: plan written from the approved design.
- 2026-11-17: plan amended. Added S18 and Stack C, to remove `--no-herdr` in 2.1.0 once the skills and docket stop passing it, as the user asked.
- 2026-11-17: phase A1 landed as #10.
