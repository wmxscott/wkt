# wkt

[![CI](https://github.com/wmxscott/wkt/actions/workflows/ci.yml/badge.svg)](https://github.com/wmxscott/wkt/actions/workflows/ci.yml)

Git worktrees in a predictable place, one command each. Inside [Herdr](https://herdr.dev), they open as Herdr workspaces and stay in sync with them when you rename a branch.

Give each piece of work its own git worktree and parallel tasks, or coding agents, can't trip over each other's checkouts. wkt makes that one command: it puts the worktree in a predictable place and starts the branch from a freshly fetched default branch. When the branch earns a better name, one more command renames the branch, its directory and the branch on origin together.

Herdr runs coding agents in persistent terminal workspaces. When you run wkt inside Herdr, it also opens each new worktree as a Herdr workspace, and a rename moves the workspace with it. Pass `--no-herdr` to skip that for one command.

```console
$ wkt new -b fix-login
→ updating main from origin
→ branching from origin/main
✓ fix-login  ~/.herdr/worktrees/acme/widget/fix-login  opened in Herdr
```

## Why not `herdr worktree create`?

Herdr can create worktrees itself, and wkt uses Herdr's `worktree open` to show them. The difference is what happens around the checkout:

- **Remote branches.** A branch that only exists on origin is checked out tracking it. Herdr creates a new branch of that name from `--base` or `HEAD` instead.
- **Fresh starting point.** A new branch starts from the default branch, or `-s <source>`, after fetching it from origin, so it isn't based on a stale local copy.
- **Reopening.** Asking again for a branch that already has a worktree, wherever it is, opens that worktree.
- **Renaming.** Herdr has no rename for worktrees. `wkt rename` renames the branch locally and on origin, moves the directory and points the Herdr workspace at the new path.
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

Herdr is optional. wkt only talks to it when run inside a Herdr pane, which it detects from `HERDR_TAB_ID`. There, if `herdr` isn't on your `PATH` or can't reach the server, wkt still does the git work, prints a warning with the `herdr` command to run later, and exits successfully.

The [picker](#the-picker) needs a little more:

- **fzf** 0.36 or newer: `brew install fzf`. Only the picker uses it; every `wkt <command>` works without it.
- **[wmxscott/theme-monitor](https://github.com/wmxscott/theme-monitor)** lets the picker follow macOS's light and dark mode through its trigger file. Without it, the picker asks macOS when it starts, or you can set `WKT_THEME`.
- **A [Nerd Font](https://www.nerdfonts.com)** in your terminal, for the picker's icons.

## Usage

```
wkt
wkt new -b <branch> [-s <source>] [-n <label>] [--no-herdr]
wkt rename -b <new-branch> [-n <label>] [-y] [--no-herdr]
wkt setup <repo-url>
wkt adopt
wkt --help | --version
```

Every command also takes `--help`.

### The picker

Run `wkt` on its own, anywhere in a repository, to pick one of its worktrees or make a new one. It needs [fzf](#optional-dependencies).

Each row shows a worktree's branch and folder. An icon at the end marks the worktree you're in, one that's open in Herdr, one whose folder is gone, or one that's locked. The pane on the right shows the highlighted worktree's upstream, changed files and recent commits. Typing searches branch names.

| Key | |
|---|---|
| `Enter` | Open the highlighted worktree |
| `Ctrl-N` | Make a new worktree, with what you typed as its branch name |
| `Enter` with no matches | The same as `Ctrl-N` |
| `Esc` | Quit |

A new worktree takes up to three steps:

1. **Branch.** The name for the branch and its folder. It's checked before moving on.
2. **Source.** The branch to start from. Skipped when the branch already exists locally or on origin.
3. **Label.** Inside Herdr only: the workspace's label. Leave it blank to let Herdr pick one, or press `Ctrl-O` to not open the worktree in Herdr.

`Esc` at any step goes back to the list. After the last step, it runs [`wkt new`](#wkt-new) with your answers.

Outside Herdr, the picker prints the chosen worktree's path and nothing else. Inside Herdr, it opens the worktree as a workspace and prints nothing, unless Herdr can't be reached; then it warns and prints the path.

A program can't change its shell's folder, so to have plain `wkt` move you into the worktree you pick, add this function to `~/.zshrc` or `~/.bashrc`:

```zsh
wkt() {
  (( $# )) && { command wkt "$@"; return; }
  local dir; dir=$(command wkt) || return
  [[ -n $dir ]] && cd -- "$dir"
}
```

`wkt <command>` still runs the command as usual.

The picker's colours are Catppuccin Latte in light mode and Macchiato in dark mode. It chooses once when it starts: `WKT_THEME` if it's `light` or `dark`, else theme-monitor's trigger file, else macOS's own setting.

### `wkt new`

Run it anywhere in a repository: the main checkout, any worktree, or the top of a `.bare` layout. It picks the first of these that applies:

1. `<branch>` is already checked out in a worktree: use that worktree.
2. The worktree folder for `<branch>` already exists: use it.
3. `<branch>` exists locally: add a worktree for it.
4. `<branch>` exists on origin: create it locally, tracking origin's.
5. Otherwise, fetch `<source>` from origin and create `<branch>` from it. The new branch doesn't track `<source>`, so the first push needs `git push -u origin HEAD`, or set `push.autoSetupRemote`.

Inside Herdr, it then opens the worktree with `herdr worktree open` and focuses it.

| Option | |
|---|---|
| `-b <branch>` | Branch to create or open. Also the worktree's folder name. Required |
| `-s <source>` | Branch to start a new branch from. Defaults to the repository's default branch: origin's `HEAD`, else `main` or `master` |
| `-n <label>` | Label for the Herdr workspace. Without it, Herdr picks one |
| `--no-herdr` | Don't open the worktree in Herdr, for when you want the worktree but not another workspace |

### `wkt rename`

Run it from inside a worktree to give its branch a new name. It:

1. Renames the branch on origin, if it was pushed. When origin is on GitHub and [`gh`](https://cli.github.com) is installed, it uses GitHub's branch-rename API. Otherwise, or if that fails, it pushes the new name and deletes the old one.
2. Renames the local branch and moves the worktree folder to match.
3. Inside Herdr, points the Herdr workspace at the new folder, labelled with the new branch name. Run it from outside Herdr, or with `--no-herdr`, and an open workspace keeps the old path until you reopen it.

Your shell stays in the old folder, which no longer exists, so `cd` to the path it prints.

If the branch has an open pull request, it stops and asks first. GitHub closes an open PR when its branch is renamed through git or the API; only the rename button in GitHub's web UI keeps it open. To keep the PR, rename the branch on GitHub, then run `wkt rename` to bring the local branch, folder and Herdr workspace in line. Without a terminal to ask on, it stops unless you pass `-y`.

| Option | |
|---|---|
| `-b <new-branch>` | New branch name. Also the new folder name. Required |
| `-n <label>` | Label for the Herdr workspace. Defaults to the new branch name |
| `-y` | Rename even when an open pull request would be closed |
| `--no-herdr` | Leave the Herdr workspace alone |

It won't rename the main checkout of a normal clone, a detached `HEAD`, or onto a branch or folder that already exists.

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

It configures origin to fetch every branch and sets the default branch's worktree to track origin's. It doesn't open anything in Herdr.

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

## Configuration

wkt has no config file. It reads these environment variables:

| Variable | Default | |
|---|---|---|
| `WKT_ROOT` | `~/.herdr/worktrees` | Where worktrees of normal clones go. Must be absolute; a leading `~` is expanded. |
| `HERDR_TAB_ID` | *(set by Herdr)* | Its presence means wkt is running inside Herdr, so it opens worktrees there |
| `WKT_THEME` | `auto` | The picker's colours: `light`, `dark` or `auto`. `auto` follows theme-monitor's trigger file, else macOS's setting |
| `XDG_DATA_HOME` | `~/.local/share` | Where the picker looks for theme-monitor's `theme-monitor/theme-change.trigger` |
| `NO_COLOR` | *(unset)* | Set to anything to turn off coloured output. The picker keeps its icons. Output is plain whenever it isn't going to a terminal |

For example, in `~/.zshenv`:

```sh
export WKT_ROOT=~/src/worktrees
```

## Exit status

| Status | |
|---|---|
| `0` | Done. This includes when Herdr couldn't be reached, which only warns |
| `2` | Bad arguments, or plain `wkt` without a terminal |
| `130` | The picker was closed with `Esc` |
| Anything else | Something went wrong, such as not being in a repository or a folder in the way. A failing git command passes on its own status |

## Coding agents

An agent skill that teaches coding agents to start work with `wkt new` and rename it with `wkt rename` ships as the `herdr` plugin in [wmxscott/ai-toolkit](https://github.com/wmxscott/ai-toolkit).

## Development

```sh
brew install bats-core
bats test
zsh -n bin/wkt
```

The tests use [bats](https://github.com/bats-core/bats-core). Each one runs in a temporary folder against a local bare repository standing in for origin, with a throwaway `HOME`, every `HERDR_*` variable removed except a dummy `HERDR_TAB_ID`, and stub `herdr`, `gh`, `fzf` and `defaults` commands first on `PATH`. They never touch a running Herdr, GitHub, your terminal or your own repositories. The stub `herdr` records its arguments, so the tests check exactly what wkt asks Herdr to do. The stub `fzf` records what it was given and plays back answers each test scripts, and fails loudly when a test didn't expect a call.

`contrib/wkt.rb` is the Homebrew formula.

## License

[MIT](LICENSE)
