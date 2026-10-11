#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    make_origin
}

# --- .bare layout -----------------------------------------------------------

@test "bare layout: new branch goes next to .bare, from the default branch" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    [ "$(git -C "$LAYOUT/topic" branch --show-current)" = topic ]
    [ "$(rev "$LAYOUT/topic" HEAD)" = "$(rev "$LAYOUT" origin/main)" ]
    [ "$(last_line)" = "✓ topic  ../topic  opened in Herdr" ]
}

@test "bare layout: works from the layout root" {
    make_layout
    cd "$LAYOUT"
    run wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    [ "$(last_line)" = "✓ topic  topic  opened in Herdr" ]
}

@test "bare layout: new branch doesn't track its source" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic
    [ "$status" -eq 0 ]
    run git -C "$LAYOUT/topic" rev-parse --abbrev-ref '@{upstream}'
    [ "$status" -ne 0 ]
}

@test "bare layout: branch names with slashes nest" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b feat/login
    [ "$status" -eq 0 ]
    [ "$(git -C "$LAYOUT/feat/login" branch --show-current)" = feat/login ]
}

@test "herdr is told the repo and the worktree path" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus" ]
}

@test "-n passes a label to herdr" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic -n "Login page"
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label Login page --focus" ]
    [ "$(last_line)" = "✓ topic (Login page)  ../topic  opened in Herdr" ]
}

@test "inside a Herdr popup: opened from HERDR_ENV alone" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT/main"
    HERDR_ENV=1 run wkt new -b topic
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus" ]
    [ "$(last_line)" = "✓ topic  ../topic  opened in Herdr" ]
}

# --- source branches ----------------------------------------------------------

@test "-s branches from a custom source" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic -s develop
    [ "$status" -eq 0 ]
    contains "$output" "branching from origin/develop"
    [ "$(rev "$LAYOUT/topic" HEAD)" = "$(rev "$LAYOUT" origin/develop)" ]
}

@test "-s picks up commits pushed to origin since the last fetch" {
    make_layout
    git -C "$TMP/src" checkout --quiet develop
    git -C "$TMP/src" commit --quiet --allow-empty -m "newer"
    git -C "$TMP/src" push --quiet "$ORIGIN" develop
    cd "$LAYOUT/main"
    run wkt new -b topic -s develop
    [ "$status" -eq 0 ]
    [ "$(rev "$LAYOUT/topic" HEAD)" = "$(rev "$TMP/src" develop)" ]
}

@test "-s accepts a local-only branch" {
    make_clone
    cd "$CLONE"
    git checkout --quiet -b local-base origin/develop
    git commit --quiet --allow-empty -m "local only"
    git checkout --quiet main
    run wkt new -b topic -s local-base
    [ "$status" -eq 0 ]
    wt="$HOME/.herdr/worktrees/acme/widget/topic"
    [ "$(rev "$wt" HEAD)" = "$(rev "$CLONE" local-base)" ]
}

@test "unknown source branch fails without creating anything" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic -s nope
    [ "$status" -eq 1 ]
    contains "$output" "Source branch 'nope' not found"
    [ ! -e "$LAYOUT/topic" ]
    run git show-ref --verify --quiet refs/heads/topic
    [ "$status" -ne 0 ]
}

@test "invalid branch name" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b "../escape"
    [ "$status" -eq 1 ]
    contains "$output" "not a valid branch name"
    [ ! -e "$TMP/escape" ]
}

# --- existing branches ----------------------------------------------------

@test "existing local branch is checked out, not recreated" {
    make_clone
    git -C "$CLONE" branch mine origin/develop
    cd "$CLONE"
    run wkt new -b mine -s feature-x
    [ "$status" -eq 0 ]
    wt="$HOME/.herdr/worktrees/acme/widget/mine"
    [ "$(git -C "$wt" branch --show-current)" = mine ]
    [ "$(rev "$wt" HEAD)" = "$(rev "$CLONE" origin/develop)" ]
}

@test "branch that only exists on origin is checked out tracking it" {
    make_clone
    cd "$CLONE"
    run wkt new -b feature-x
    [ "$status" -eq 0 ]
    wt="$HOME/.herdr/worktrees/acme/widget/feature-x"
    [ "$(rev "$wt" HEAD)" = "$(rev "$CLONE" origin/feature-x)" ]
    [ "$(git -C "$wt" rev-parse --abbrev-ref '@{upstream}')" = origin/feature-x ]
}

@test "existing worktree is reopened, not recreated" {
    make_layout
    cd "$LAYOUT/main"
    wkt new -b topic >/dev/null 2>&1
    head_before="$(rev "$LAYOUT/topic" HEAD)"
    : >"$STUB_HERDR_LOG"
    run wkt new -b topic -n again
    [ "$status" -eq 0 ]
    [ "$(rev "$LAYOUT/topic" HEAD)" = "$head_before" ]
    lacks "$output" "branching from"
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label again --focus" ]
}

@test "branch checked out elsewhere reuses that worktree" {
    make_clone
    cd "$CLONE"
    run wkt new -b main
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.herdr/worktrees/acme/widget/main" ]
    [ "$(herdr_calls)" = "worktree open --cwd $CLONE/.git --path $CLONE --focus" ]
}

@test "a directory in the way that isn't a worktree is left alone" {
    make_layout
    mkdir "$LAYOUT/topic"
    touch "$LAYOUT/topic/keep"
    cd "$LAYOUT/main"
    run wkt new -b topic
    [ "$status" -eq 1 ]
    contains "$output" "exists and isn't a worktree of this repo"
    [ -e "$LAYOUT/topic/keep" ]
}

@test "a worktree whose path is a prefix of the target doesn't count" {
    make_layout
    cd "$LAYOUT/main"
    wkt new -b topic-long >/dev/null 2>&1
    mkdir "$LAYOUT/topic"
    run wkt new -b topic
    [ "$status" -eq 1 ]
    contains "$output" "exists and isn't a worktree of this repo"
}

# --- normal repos ---------------------------------------------------------

@test "normal repo: worktree goes under ~/.herdr/worktrees/<org>/<repo> by default" {
    make_clone
    cd "$CLONE"
    run wkt new -b topic
    [ "$status" -eq 0 ]
    wt="$HOME/.herdr/worktrees/acme/widget/topic"
    [ "$(git -C "$wt" branch --show-current)" = topic ]
    [ "$(rev "$wt" HEAD)" = "$(rev "$CLONE" origin/main)" ]
    [ "$(last_line)" = "✓ topic  ~/.herdr/worktrees/acme/widget/topic  opened in Herdr" ]
    [ "$(herdr_calls)" = "worktree open --cwd $CLONE/.git --path $wt --focus" ]
}

@test "normal repo: WKT_ROOT moves the root" {
    make_clone
    cd "$CLONE"
    WKT_ROOT="$TMP/wt/" run wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$TMP/wt/acme/widget/topic" ]
    [ ! -e "$HOME/.herdr" ]
}

@test "normal repo: WKT_ROOT expands a leading ~" {
    make_clone
    cd "$CLONE"
    # shellcheck disable=SC2088 # the literal ~ is the point
    WKT_ROOT="~/trees" run wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$HOME/trees/acme/widget/topic" ]
}

@test "normal repo: a relative WKT_ROOT is refused" {
    make_clone
    cd "$CLONE"
    WKT_ROOT="trees" run wkt new -b topic
    [ "$status" -eq 1 ]
    contains "$output" "WKT_ROOT must be an absolute path"
    [ ! -e "$CLONE/trees" ]
}


@test "normal repo: works from inside an existing worktree" {
    make_clone
    cd "$CLONE"
    wkt new -b first >/dev/null 2>&1
    cd "$HOME/.herdr/worktrees/acme/widget/first"
    run wkt new -b second
    [ "$status" -eq 0 ]
    [ -d "$HOME/.herdr/worktrees/acme/widget/second" ]
}

@test "normal repo: org and repo come from scp-style and https URLs" {
    make_clone
    cd "$CLONE"
    git remote set-url origin git@example.com:someorg/thing.git
    run wkt new -b topic -s main
    [ "$status" -eq 0 ]
    [ -d "$HOME/.herdr/worktrees/someorg/thing/topic" ]

    git remote set-url origin https://example.com/other/project
    run wkt new -b topic2 -s main
    [ "$status" -eq 0 ]
    [ -d "$HOME/.herdr/worktrees/other/project/topic2" ]
}

@test "normal repo without a remote: local/<repo>, even from a worktree" {
    git init --quiet solo
    git -C solo commit --quiet --allow-empty -m init
    cd solo
    run wkt new -b one
    [ "$status" -eq 0 ]
    [ -d "$HOME/.herdr/worktrees/local/solo/one" ]
    lacks "$output" "updating"

    cd "$HOME/.herdr/worktrees/local/solo/one"
    run wkt new -b two
    [ "$status" -eq 0 ]
    [ -d "$HOME/.herdr/worktrees/local/solo/two" ]
}

@test "symlinked paths resolve to the same worktree" {
    make_layout
    ln -s "$LAYOUT" "$TMP/link"
    cd "$TMP/link/main"
    wkt new -b topic >/dev/null 2>&1
    run wkt new -b topic
    [ "$status" -eq 0 ]
    [ "$(git -C "$LAYOUT" worktree list --porcelain | grep -c '^worktree ')" -eq 3 ]
}

# --- without Herdr --------------------------------------------------------

@test "outside Herdr: worktree is made, herdr isn't called, no warning" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT/main"
    run --separate-stderr wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    lacks "$stderr" "warning"
    [ -z "$(herdr_calls)" ]
    [ "$(last_line)" = "✓ topic  ../topic" ]
}

@test "--no-herdr: worktree is made, herdr isn't called" {
    make_layout
    cd "$LAYOUT/main"
    run --separate-stderr wkt new --no-herdr -b topic -n "Label"
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    lacks "$stderr" "warning"
    [ -z "$(herdr_calls)" ]
    [ "$(last_line)" = "✓ topic (Label)  ../topic" ]

    run wkt new -b other --no-herdr
    [ "$status" -eq 0 ]
    [ -z "$(herdr_calls)" ]
}

@test "without herdr on PATH: worktree is made, warning, exit 0" {
    rm "$STUB_BIN/herdr"
    run command -v herdr
    [ "$status" -ne 0 ]
    make_layout
    cd "$LAYOUT/main"
    run --separate-stderr wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    contains "$stderr" "herdr not found on PATH"
    [ "$(last_line)" = "✓ topic  ../topic" ]
}

@test "when herdr fails: worktree is made, warning, exit 0" {
    make_layout
    cd "$LAYOUT/main"
    STUB_HERDR_FAIL=1 run --separate-stderr wkt new -b topic -n "My label"
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    contains "$stderr" "Herdr didn't open the worktree: {\"error\":\"server not running\"}"
    contains "$stderr" "herdr worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label 'My label' --focus"
    [ "$(last_line)" = "✓ topic (My label)  ../topic" ]
}
