# wkt

[![CI](https://github.com/wmxscott/wkt/actions/workflows/ci.yml/badge.svg)](https://github.com/wmxscott/wkt/actions/workflows/ci.yml)

Git worktrees in a predictable place, one command each. wkt prints the worktree's path, or when you ask, opens it as a tmux session or a Herdr workspace. Renaming or removing the worktree keeps its session and workspace in step.

Give each piece of work its own git worktree and parallel tasks, or coding agents, can't trip over each other's checkouts. wkt makes that one command: it puts the worktree in a predictable place and starts the branch from a freshly fetched default branch. When the branch earns a better name, one more command renames the branch, its directory and the branch on origin together. When the work is merged, `wkt rm` removes the worktree and its branch, and `wkt rm --merged` clears out every merged one at once.

`wkt new` gives you the worktree one of three ways:

- **On its own**, it prints the path and opens nothing.
- **With `--tmux`**, it opens the worktree's own [tmux session](#tmux) and switches you to it, or outside tmux, says how to attach.
- **With `--herdr`**, it opens the worktree as a workspace in [Herdr](https://herdr.dev), which runs coding agents in persistent terminal workspaces.

```console
$ wkt new -b fix-login
→ updating main from origin
→ branching from origin/main
✓ fix-login  ~/.herdr/worktrees/acme/widget/fix-login
$ wkt new -b fix-login --tmux
✓ fix-login  ~/.herdr/worktrees/acme/widget/fix-login  opened in tmux
$ wkt new -b fix-login --herdr
✓ fix-login  ~/.herdr/worktrees/acme/widget/fix-login  opened in Herdr
```

`wkt rename` and `wkt rm` find the worktree's session and workspace on their own, so they need neither flag.

## Why not `herdr worktree create`?

Herdr can create worktrees itself, and `wkt new --herdr` uses Herdr's `worktree open` to show them. But Herdr is optional: `--tmux` opens the worktree in tmux instead, and without either, wkt opens nothing. Wherever you open it, the difference is what happens around the checkout:

- **Remote branches.** A branch that only exists on origin is checked out tracking it. Herdr creates a new branch of that name from `--base` or `HEAD` instead.
- **Fresh starting point.** A new branch starts from the default branch, or `-s <source>`, after fetching it from origin, so it isn't based on a stale local copy.
- **Reopening.** Asking again for a branch that already has a worktree, wherever it is, gives you that worktree, and `--tmux` switches to its session if it already has one.
- **Renaming.** Herdr has no rename for worktrees. `wkt rename` renames the branch locally and on origin, moves the directory, points the worktree's Herdr workspace at the new path and renames its tmux session, if it has them.
- **Removing.** `wkt rm` removes the folder, closes the worktree's Herdr workspace and tmux session, and deletes the branch once its pull request is merged, refusing when that would lose work.
- **`.bare` layouts.** `wkt setup` clones a repository into a layout where every branch is a sibling folder, `wkt adopt` converts a clone you already have, and `wkt new` keeps to it.

## Install

### Homebrew

```sh
brew install wmxscott/tap/wkt
```

### From source

Needs zsh and git, which macOS already has.

```sh
git clone https://github.com/wmxscott/wkt.git
install -d ~/.local/bin
install wkt/bin/wkt ~/.local/bin/
```

### Optional dependencies

Herdr is optional, and wkt never opens anything in it unless you pass `--herdr`. Then, if `herdr` isn't on your `PATH` or can't reach the server, wkt still does the git work, prints a warning with the `herdr` command to run later, and exits successfully. The picker, `wkt rename` and `wkt rm` also ask Herdr which worktrees have a workspace, and say nothing when it isn't there to answer.

tmux is optional too, and wkt only opens a session when you pass `--tmux`. Then, if `tmux` isn't on your `PATH`, or a tmux command fails, wkt still does the git work, warns, and exits successfully. The picker, `wkt rename` and `wkt rm` also ask tmux which session has the worktree, and say nothing when there's no tmux to answer.

The [picker](#the-picker) needs a little more:

- **fzf** 0.36 or newer: `brew install fzf`. Only the picker uses it; every `wkt <command>` works without it.
- **[wmxscott/theme-monitor](https://github.com/wmxscott/theme-monitor)** lets the picker follow macOS's light and dark mode through its trigger file. Without it, the picker asks macOS when it starts, or you can set `WKT_THEME`.
- **A [Nerd Font](https://www.nerdfonts.com)** in your terminal, for the picker's icons.

## Usage

```
wkt [--tmux | --herdr]
wkt new -b <branch> [-s <source>] [-n <name>] [--tmux | --herdr]
wkt rename -b <new-branch> [-n <name>] [-y]
wkt rm [-b <branch>] [-f]
wkt rm --merged [-y]
wkt setup <repo-url>
wkt adopt
wkt --help | --version
```

Every command also takes `--help`.

### The picker

Run `wkt` on its own, anywhere in a repository, to pick one of its worktrees, make a new one, or remove them. It needs [fzf](#optional-dependencies).

Each row shows a worktree's branch and folder. An icon at the end marks the worktree you're in, one that has a [tmux session](#finding-a-worktrees-session) or is open in Herdr, one whose folder is gone, or one that's locked. The pane on the right shows the highlighted worktree's upstream, changed files and recent commits. Typing searches branch names.

| Key | |
|---|---|
| `Enter` | Choose the highlighted worktree |
| `Ctrl-N` | Make a new worktree, with what you typed as its branch name |
| `Enter` with no matches | The same as `Ctrl-N` |
| `Ctrl-D` | Remove the highlighted worktree, as `wkt rm -b <branch>` does, after asking |
| `Ctrl-X` | Remove every merged worktree, as `wkt rm --merged` does, after showing which and asking |
| `Esc` | Quit |

A new worktree takes up to three steps:

1. **Branch.** The name for the branch and its folder. It's checked before moving on.
2. **Source.** The branch to start from. Skipped when the branch already exists locally or on origin.
3. **Label.** With `--herdr` only: the workspace's label. Leave it blank to let Herdr pick one, or press `Ctrl-O` to not open the worktree in Herdr. `--tmux` adds no step.

`Esc` at any step goes back to the list. After the last step, it runs [`wkt new`](#wkt-new) with your answers.

The picker prints the chosen worktree's path and nothing else. `wkt --tmux` opens its [tmux session](#tmux) instead, as `wkt new --tmux` does: inside tmux, it switches you to it, and outside, it says how to attach. `wkt --herdr` opens it as a Herdr workspace. Either way it prints no path, unless the worktree couldn't be opened; then it warns and prints the path. A new worktree opens the same way.

`Ctrl-D` and `Ctrl-X` ask `y/N` on an input line before removing anything. `Ctrl-D` names the branch. `Ctrl-X` lists what it would remove and what it would skip, or says there's nothing to remove and doesn't ask. Both follow [`wkt rm`](#wkt-rm)'s rules, without `-f`: a worktree it refuses, such as one with uncommitted changes, stays, and why shows above the list. Otherwise the list comes back without what went, and what `wkt rm` said shows above it. If what you removed had the tmux session you're in, wkt switches you to another session, closes that one, and quits.

In tmux, the picker works well in a popup, like `display-popup -E -d '#{pane_current_path}' 'wkt --tmux'` in a key binding. A popup has no pane of its own, so tmux would act on whichever client was used last; wkt notes the popup's client when it starts, and switches that one.

A program can't change its shell's folder, so to have plain `wkt` move you into the worktree you pick, add this function to `~/.zshrc` or `~/.bashrc`:

```zsh
wkt() {
  (( $# )) && { command wkt "$@"; return; }
  local dir; dir=$(command wkt) || return
  [[ -n $dir ]] && cd -- "$dir"
}
```

`wkt --tmux`, `wkt --herdr` and `wkt <command>` still run as usual.

The picker's colours are Catppuccin Latte in light mode and Macchiato in dark mode. It chooses once when it starts: `WKT_THEME` if it's `light` or `dark`, else theme-monitor's trigger file, else macOS's own setting.

### `wkt new`

Run it anywhere in a repository: the main checkout, any worktree, or the top of a `.bare` layout. It picks the first of these that applies:

1. `<branch>` is already checked out in a worktree: use that worktree.
2. The worktree folder for `<branch>` already exists: use it.
3. `<branch>` exists locally: add a worktree for it.
4. `<branch>` exists on origin: create it locally, tracking origin's.
5. Otherwise, fetch `<source>` from origin and create `<branch>` from it. The new branch doesn't track `<source>`, so the first push needs `git push -u origin HEAD`, or set `push.autoSetupRemote`.

It then prints the worktree's path. With `--tmux`, it also opens the worktree's [tmux session](#tmux), making it if there's none. With `--herdr`, it opens the worktree with `herdr worktree open` and focuses it. Passing both is an error.

| Option | |
|---|---|
| `-b <branch>` | Branch to create or open. Also the worktree's folder name. Required |
| `-s <source>` | Branch to start a new branch from. Defaults to the repository's default branch: origin's `HEAD`, else `main` or `master` |
| `-n <name>` | With `--tmux`, the session's name, instead of `<repo>/<branch>`. With `--herdr`, the workspace's label; without it, Herdr picks one |
| `--tmux` | Open the worktree's tmux session and switch to it. Outside tmux, print how to attach to it instead |
| `--herdr` | Open the worktree as a Herdr workspace and focus it |

### `wkt rename`

Run it from inside a worktree to give its branch a new name. It:

1. Renames the branch on origin, if it was pushed. When origin is on GitHub and [`gh`](https://cli.github.com) is installed, it uses GitHub's branch-rename API. Otherwise, or if that fails, it pushes the new name and deletes the old one.
2. Renames the local branch and moves the worktree folder to match.
3. If a Herdr workspace has the worktree open, points it at the new folder, labelled with the new branch name.
4. If the worktree has a [tmux session](#finding-a-worktrees-session), renames it to `<repo>/<new-branch>`, following the same [naming rules](#session-names) as `wkt new`, and tags it with the new folder. Its starting folder, `session_path`, stays the old one, since tmux only changes that when a client attaches; the tag is what ties the session to the worktree.

It never opens a workspace or session that wasn't there, and it needs no flag for either.

Your shell stays in the old folder, which no longer exists, so `cd` to the path it prints.

If the branch has an open pull request, it stops and asks first. GitHub closes an open PR when its branch is renamed through git or the API; only the rename button in GitHub's web UI keeps it open. To keep the PR, rename the branch on GitHub, then run `wkt rename` to bring the local branch, folder, Herdr workspace and tmux session in line. Without a terminal to ask on, it stops unless you pass `-y`.

| Option | |
|---|---|
| `-b <new-branch>` | New branch name. Also the new folder name. Required |
| `-n <name>` | The Herdr workspace's label, instead of the new branch name, and the tmux session's name, instead of `<repo>/<new-branch>` |
| `-y` | Rename even when an open pull request would be closed |

It won't rename the main checkout of a normal clone, a detached `HEAD`, or onto a branch or folder that already exists.

### `wkt rm`

Run it from inside a worktree to remove that worktree, or pass `-b <branch>`, anywhere in the repository, to remove the one that has `<branch>` checked out. It:

1. Checks nothing would be lost. It stops if `git status` shows anything, untracked files included, or if the branch has commits that were never pushed: commits that aren't on its upstream, or without one, on none of origin's branches. In a repository without an origin, that means commits that aren't on the local default branch. Nothing counts as never pushed when the default branch already has it, or when it's in a pull request that was merged, even after a squash merge deleted the branch on origin. A commit you made after the pull request's last one still counts. `-f` removes the worktree anyway.
2. Removes the folder with `git worktree remove`, along with any folders a branch name with slashes left empty. If git can't remove it, wkt stops there, leaving the branch, the Herdr workspace and the tmux session alone, and exits with git's status.
3. Deletes the local branch only when nothing on it would be lost: its pull request was merged and has all of its commits, or origin's default branch already has the branch's last commit, as it does for a branch that was never used. Without an origin, the local default branch stands in for origin's. Otherwise it keeps the branch and says why, so after `-f`, commits made after a merged pull request's last one stay on the branch. It never touches the branch on origin, and a detached worktree has no branch to delete.
4. Closes the worktree's Herdr workspace, if it has one. If Herdr can't, wkt warns with the command to run later and carries on.
5. Closes the worktree's [tmux session](#finding-a-worktrees-session), if it has one, as its very last step. If you're in that session, it first switches your client to the session you attached to most recently. If there's no other session, it opens one for the default branch's worktree, or a normal clone's main checkout, and switches to that, so you're never thrown out of tmux.

It asks [`gh`](https://cli.github.com) about the branch's pull request once, before removing anything, since a squash merge leaves no trace git can see. It closes whatever workspace or session the worktree has, and needs no flag for either.

```console
$ wkt rm -b fix-login
✓ removed fix-login  ~/.herdr/worktrees/acme/widget/fix-login  branch deleted  Herdr workspace closed
```

When you remove the worktree you're in, your shell is left in a folder that no longer exists, so `cd` to the path it prints. There's no need when wkt has switched you to another tmux session, since the one you were in is closed.

| Option | |
|---|---|
| `-b <branch>` | Remove the worktree that has `<branch>` checked out, instead of the one you're in |
| `-f` | Remove it even with uncommitted changes, untracked files or commits that were never pushed |
| `--merged` | Remove every merged worktree in the repository, as below |
| `-y` | With `--merged`, don't ask first |

It won't remove the main checkout of a normal clone or the worktree that has the default branch checked out, in any layout, and with `-b`, the branch must have a worktree.

`wkt rm --merged` cleans up a whole repository at once. It finds every worktree whose branch has nothing that would be lost, by the test in step 3: the default branch already has it, or its pull request was merged with all of its commits. A detached worktree, the main checkout and the default branch's worktree are never among them. Any with uncommitted changes or untracked files are skipped.

It lists what it will remove and what it's skipping and why, then asks `Remove 2 merged worktrees? [y/N]`. Anything but `y` stops it with nothing changed, and so does having no terminal to ask on, unless you pass `-y`, which skips the question. With nothing to remove, it says so and doesn't ask.

```console
$ wkt rm --merged
Merged worktrees to remove:
  fix-login  ~/.herdr/worktrees/acme/widget/fix-login
  new-icons  ~/.herdr/worktrees/acme/widget/new-icons
Skipping:
  try-cache  ~/.herdr/worktrees/acme/widget/try-cache  (uncommitted changes or untracked files)
Remove 2 merged worktrees? [y/N] y
✓ removed fix-login  ~/.herdr/worktrees/acme/widget/fix-login  branch deleted  Herdr workspace closed
✓ removed new-icons  ~/.herdr/worktrees/acme/widget/new-icons  branch deleted  tmux session widget/new-icons closed
✓ removed 2, skipped 1
```

Each one goes exactly as `wkt rm` would remove it. If you're in one of their tmux sessions, that worktree goes last, so wkt switches you away and closes the session once, after everything else. If git can't remove one, wkt reports it, carries on with the rest, and exits 1.

### `wkt setup`

Run it in a new, empty folder to clone a repository into a `.bare` layout:

```console
$ mkdir widget && cd widget
$ wkt setup git@github.com:acme/widget.git
```

```
widget/
├── .bare/     the repository, cloned with --bare
├── .git       a file containing "gitdir: ./.bare"
└── main/      a worktree for the default branch
```

It configures origin to fetch every branch and sets the default branch's worktree to track origin's.

### `wkt adopt`

Run it at the top of a clone you already have to turn it into the same `.bare` layout, in place:

```console
$ cd widget
$ wkt adopt
→ moving the working tree aside
→ moving .git to .bare
→ adding worktree for main
✓ .bare worktree layout ready  main
```

`.git` becomes `.bare`, a `.git` file points at it, and the working tree moves into a folder named after the branch you're on. The files are moved, not checked out again, so uncommitted changes, staged changes, untracked files and ignored files like `node_modules` or `.env` all come along, and `git status` in the new folder matches what it showed before. Linked worktrees you'd already made are repaired to point at `.bare`.

Every path in the working tree changes, from `widget/src` to `widget/main/src`, so editors, `direnv allow`, `mise trust` and anything else that remembers absolute paths needs pointing at the new folder.

It refuses a detached `HEAD`, a repository with submodules, a merge, rebase, cherry-pick, revert or bisect in progress, and anything that isn't the main checkout of a normal clone. If a step fails partway, it stops without deleting anything and says where your files and the repository are.

## Where worktrees go

Worktrees are named after their branch. A branch with slashes, like `feat/login`, nests: `feat/login/`.

**`.bare` layouts.** When the repository's git directory is called `.bare`, worktrees go next to it, so everything for one repository stays in one folder:

```
widget/
├── .bare/
├── main/
└── fix-login/
```

**Normal clones.** Worktrees go outside the checkout, under

```
$WKT_ROOT/<org>/<repo>/<branch>
```

`<org>` and `<repo>` come from origin's URL, so `git@github.com:acme/widget.git` gives `acme/widget`. A repository without an origin uses `local/<folder name>`.

`WKT_ROOT` defaults to `~/.herdr/worktrees`, the folder Herdr's own `worktrees.directory` setting uses by default, so worktrees you make from Herdr's sidebar and from wkt end up side by side. If you've changed Herdr's setting, or don't use Herdr, set `WKT_ROOT` to wherever you want them.

## tmux

`wkt new --tmux`, and the [picker](#the-picker)'s `wkt --tmux`, give the worktree its own tmux session. If the worktree already has one, wkt uses it, first giving it the [name](#session-names) it should have and tagging it with the worktree's path again. Otherwise it makes one, detached, starting in the worktree's folder, and tags it with the worktree's path. If no tmux server is running, making the session starts one.

- **Inside tmux**, when `$TMUX` is set, wkt switches your client to the session.
- **Outside tmux**, it switches nothing and prints how to attach:

```console
$ wkt new -b fix-login --tmux
→ updating main from origin
→ branching from origin/main
✓ fix-login  ~/.herdr/worktrees/acme/widget/fix-login  opened in tmux
→ attach with: tmux attach -t widget/fix-login
```

### Session names

A session is named `<repo>/<branch>`, like `widget/fix-login`, so tmux's status bar says which repository you're in. `<repo>` is the name from origin's URL that normal clones' [paths](#where-worktrees-go) use, and `.bare` layouts use it too. Without an origin, it's the repository's folder: the clone, or the folder that holds `.bare`. tmux reads `.` and `:` in a target as separators, so they become `-`: branch `v1.2` gives `widget/v1-2`.

If a session that isn't this worktree's already has the name, wkt uses `<org>/<repo>/<branch>`, like `acme/widget/fix-login`. If that's taken too, it adds `-2`, `-3` and so on. `-n <name>` chooses the name yourself, with the same `-2` rule.

Switching to a session that already exists, from `wkt new --tmux` or the picker, corrects its name, so one you made or renamed yourself gets the name above. `wkt new`'s `✓` line says so: `switched to widget/fix-login (renamed from 0)`. The session's own name never counts as taken. A name chosen with `-n` lasts only until the next switch without `-n`, which puts the usual name back; tmux-resurrect doesn't save `@` options, so there's nowhere for wkt to remember it. If tmux won't rename the session, wkt warns and switches to it by the name it has.

### Finding a worktree's session

Every session wkt makes has the session option `@wkt-worktree` set to the worktree's absolute path, with symlinks resolved. A worktree's session is, in order:

1. The session whose `@wkt-worktree` is the worktree's path.
2. Otherwise, a session whose `session_path`, with symlinks resolved, is the worktree's folder or a folder inside it.

The second rule is for sessions restored by [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect), which doesn't save `@` options and recreates each session with its first pane's folder as `session_path`.

Other tools, such as a session switcher, can match sessions to worktrees with the same rule. One query gets all it needs:

```sh
tmux list-sessions -F $'#{session_name}\t#{@wkt-worktree}\t#{session_path}'
```

Target a session by its exact name, as in `tmux switch-client -t '=widget/fix-login'`. Without the `=`, tmux falls back to a prefix match, so `widget/fix-login` could reach `widget/fix-login-2`. Commands that take a pane, like `set-option`, need a `:` after it: `-t '=widget/fix-login:'`.

## Configuration

wkt has no config file. It reads these environment variables:

| Variable | Default | |
|---|---|---|
| `WKT_ROOT` | `~/.herdr/worktrees` | Where worktrees of normal clones go. Must be absolute; a leading `~` is expanded. |
| `WKT_THEME` | `auto` | The picker's colours: `light`, `dark` or `auto`. `auto` follows theme-monitor's trigger file, else macOS's setting |
| `XDG_DATA_HOME` | `~/.local/share` | Where the picker looks for theme-monitor's `theme-monitor/theme-change.trigger` |
| `NO_COLOR` | *(unset)* | Set to anything to turn off coloured output. The picker keeps its icons. Output is plain whenever it isn't going to a terminal |
| `TMUX` | *(set by tmux)* | Tells wkt it's inside tmux, so `--tmux` switches your client instead of printing how to attach, and `wkt rm` moves you off a session before closing it. Without `--tmux`, `wkt new` and the picker open nothing, set or not |

For example, in `~/.zshenv`:

```sh
export WKT_ROOT=~/src/worktrees
```

## Exit status

| Status | |
|---|---|
| `0` | Done. This includes when opening, switching to or closing a tmux session or Herdr workspace didn't work, which only warns |
| `1` | wkt refused or something went wrong, such as not being in a repository, a folder in the way, or work that would be lost. Also when `wkt rename` or `wkt rm --merged` asks first and you answer anything but `y`, or there's no terminal to ask on and no `-y`, and when `wkt rm --merged` couldn't remove one of the worktrees |
| `2` | Bad arguments, including flags that clash: `--tmux` with `--herdr`, either of them with `rename` or `rm`, and `rm --merged` with `-b` or `-f`. Also plain `wkt` without a terminal |
| `130` | The picker was closed with `Esc` |

A git command that fails passes on its own status instead of `1`.

## Coding agents

An agent skill that teaches coding agents to start work with `wkt new` and rename it with `wkt rename` ships as the `wkt` plugin in [wmxscott/ai-toolkit](https://github.com/wmxscott/ai-toolkit).

## Development

```sh
brew install bats-core
bats test
zsh -n bin/wkt
```

The tests use [bats](https://github.com/bats-core/bats-core). Each one runs in a temporary folder against a local bare repository standing in for origin, with a throwaway `HOME`, `TMUX` and `TMUX_PANE` removed, and stub `herdr`, `tmux`, `gh`, `fzf` and `defaults` commands first on `PATH`. Every `HERDR_*` variable is removed too, except a dummy `HERDR_TAB_ID`, which wkt 1.x took to mean it was inside Herdr, so every test also shows wkt opens nothing in Herdr unasked. They never touch a running Herdr or tmux server, GitHub, your terminal or your own repositories. The stub `herdr` and `tmux` record their arguments, so the tests check exactly what wkt asks of them. The stub `fzf` records what it was given and plays back answers each test scripts, and fails loudly when a test didn't expect a call.

`contrib/wkt.rb` is the Homebrew formula.

## License

[MIT](LICENSE)
