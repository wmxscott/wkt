#!/usr/bin/env bats

load test_helper

LIST=$'list-sessions -F #{session_name}\t#{@wkt-worktree}\t#{session_path}\t#{session_last_attached}'

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
    [ "$(last_line)" = "✓ topic  ../topic" ]
}

@test "bare layout: works from the layout root" {
    make_layout
    cd "$LAYOUT"
    run wkt new -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    [ "$(last_line)" = "✓ topic  topic" ]
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

@test "--herdr: herdr is told the repo and the worktree path" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new --herdr -b topic
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus" ]
    [ "$(last_line)" = "✓ topic  ../topic  opened in Herdr" ]
}

@test "--herdr: -n passes a label to herdr" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic -n "Login page" --herdr
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label Login page --focus" ]
    [ "$(last_line)" = "✓ topic (Login page)  ../topic  opened in Herdr" ]
}

@test "--herdr outside Herdr: opened all the same" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT/main"
    run wkt new --herdr -b topic
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
    run wkt new --herdr -b topic -n again
    [ "$status" -eq 0 ]
    [ "$(rev "$LAYOUT/topic" HEAD)" = "$head_before" ]
    lacks "$output" "branching from"
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label again --focus" ]
}

@test "branch checked out elsewhere reuses that worktree" {
    make_clone
    cd "$CLONE"
    run wkt new --herdr -b main
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
    run wkt new --herdr -b topic
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

# --- opening ---------------------------------------------------------------

@test "without --herdr or --tmux: neither is called, even inside them" {
    make_layout
    cd "$LAYOUT/main"
    TMUX=stub run --separate-stderr wkt new -b topic -n "Label"
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    lacks "$stderr" "warning"
    [ -z "$(herdr_calls)" ]
    [ -z "$(tmux_calls)" ]
    [ "$(last_line)" = "✓ topic (Label)  ../topic" ]

    unset HERDR_TAB_ID
    HERDR_ENV=1 run wkt new -b other
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/other" ]
    [ -z "$(herdr_calls)" ]
}

@test "--no-herdr is accepted and changes nothing" {
    make_layout
    cd "$LAYOUT/main"
    run --separate-stderr wkt new --no-herdr -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    [ -z "$(herdr_calls)" ]
    [ "$(last_line)" = "✓ topic  ../topic" ]

    run wkt new --herdr -b other --no-herdr
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/other --focus" ]
}

@test "--tmux and --herdr together: usage error, nothing made" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic --tmux --herdr
    [ "$status" -eq 2 ]
    contains "$output" "--tmux and --herdr can't be used together."
    [ ! -e "$LAYOUT/topic" ]
    [ -z "$(herdr_calls)" ]
    [ -z "$(tmux_calls)" ]
}

@test "without herdr on PATH: worktree is made, warning, exit 0" {
    rm "$STUB_BIN/herdr"
    run command -v herdr
    [ "$status" -ne 0 ]
    make_layout
    cd "$LAYOUT/main"
    run --separate-stderr wkt new --herdr -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    contains "$stderr" "herdr not found on PATH"
    [ "$(last_line)" = "✓ topic  ../topic" ]
}

@test "when herdr fails: worktree is made, warning, exit 0" {
    make_layout
    cd "$LAYOUT/main"
    STUB_HERDR_FAIL=1 run --separate-stderr wkt new --herdr -b topic -n "My label"
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    contains "$stderr" "Herdr didn't open the worktree: {\"error\":\"server not running\"}"
    contains "$stderr" "herdr worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label 'My label' --focus"
    [ "$(last_line)" = "✓ topic (My label)  ../topic" ]
}

# --- tmux ------------------------------------------------------------------

@test "--tmux outside tmux: makes a tagged session and says how to attach" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "new-session -d -s widget/topic -c $LAYOUT/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic")" ]
    contains "$output" "✓ topic  ../topic  opened in tmux"
    [ "$(last_line)" = "→ attach with: tmux attach -t widget/topic" ]
}

@test "--tmux inside tmux: makes a tagged session and switches to it" {
    make_layout
    cd "$LAYOUT/main"
    TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "new-session -d -s widget/topic -c $LAYOUT/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =widget/topic")" ]
    [ "$(last_line)" = "✓ topic  ../topic  opened in tmux" ]
}

@test "--tmux: the session tagged with the worktree comes first" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions \
        widget/topic "" "$LAYOUT/topic" \
        mine "$LAYOUT/topic" "$TMP")"
    export STUB_TMUX_SESSIONS
    TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =mine acme/widget/topic" \
        "set-option -t =acme/widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =acme/widget/topic")" ]
    [ "$(last_line)" = "✓ topic  ../topic  switched to acme/widget/topic (renamed from mine)" ]
}

@test "--tmux: a restored session, untagged, is found by its folder and tagged" {
    make_layout
    ln -s "$LAYOUT" "$TMP/link"
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions \
        widget/topic-long "" "$LAYOUT/topic-long" \
        widget/topic "" "$TMP/link/topic/src")"
    export STUB_TMUX_SESSIONS
    TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =widget/topic")" ]
    [ "$(last_line)" = "✓ topic  ../topic  switched to widget/topic" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions restored "" "$LAYOUT/topic")" TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =restored widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =widget/topic")" ]
}

@test "--tmux outside tmux: an existing session is re-tagged, not renamed, with how to attach" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions widget/topic "$LAYOUT/topic" "$LAYOUT/topic")"
    export STUB_TMUX_SESSIONS
    run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic")" ]
    contains "$output" "✓ topic  ../topic  already open in tmux"
    lacks "$output" "renamed"
    [ "$(last_line)" = "→ attach with: tmux attach -t widget/topic" ]
}

@test "--tmux inside tmux: a misnamed session is renamed, re-tagged and switched to" {
    make_layout
    cd "$LAYOUT/main"
    wkt new -b topic >/dev/null
    STUB_TMUX_SESSIONS="$(sessions 0 "" "$LAYOUT/topic")" TMUX=stub run --separate-stderr wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =0 widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =widget/topic")" ]
    [ -z "$stderr" ]
    [ "$(last_line)" = "✓ topic  ../topic  switched to widget/topic (renamed from 0)" ]
}

@test "--tmux outside tmux: a misnamed session is renamed, with how to attach" {
    make_layout
    cd "$LAYOUT/main"
    wkt new -b topic >/dev/null
    STUB_TMUX_SESSIONS="$(sessions 0 "$LAYOUT/topic" "$HOME")" run --separate-stderr wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =0 widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic")" ]
    contains "$output" "✓ topic  ../topic  already open in tmux (renamed from 0)"
    [ "$(last_line)" = "→ attach with: tmux attach -t widget/topic" ]
}

@test "--tmux: an existing session's name falls back to <org>/<repo>/<branch> on a clash" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions \
        widget/topic "$TMP/other" "$TMP/other" \
        0 "$LAYOUT/topic" "$LAYOUT/topic")"
    export STUB_TMUX_SESSIONS
    TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =0 acme/widget/topic" \
        "set-option -t =acme/widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =acme/widget/topic")" ]
    [ "$(last_line)" = "✓ topic  ../topic  switched to acme/widget/topic (renamed from 0)" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions \
        widget/topic "$TMP/other" "$TMP/other" \
        acme/widget/topic "$LAYOUT/topic" "$LAYOUT/topic")"
    TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "set-option -t =acme/widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =acme/widget/topic")" ]
}

@test "--tmux -n renames an existing session, until a switch without -n" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions widget/topic "$LAYOUT/topic" "$LAYOUT/topic")" \
        TMUX=stub run wkt new -b topic -n "Login page.v2" --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =widget/topic Login page-v2" \
        "set-option -t =Login page-v2: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =Login page-v2")" ]
    [ "$(last_line)" = "✓ topic (Login page.v2)  ../topic  switched to Login page-v2 (renamed from widget/topic)" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions "Login page-v2" "$LAYOUT/topic" "$LAYOUT/topic")" \
        TMUX=stub run wkt new -b topic -n "Login page.v2" --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "set-option -t =Login page-v2: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =Login page-v2")" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions "Login page-v2" "$LAYOUT/topic" "$LAYOUT/topic")" \
        TMUX=stub run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =Login page-v2 widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =widget/topic")" ]
}

@test "--tmux when renaming fails: warning, still tagged and switched to by its old name, exit 0" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions 0 "" "$LAYOUT/topic")"
    export STUB_TMUX_SESSIONS
    TMUX=stub STUB_TMUX_FAIL=rename-session run --separate-stderr wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =0 widget/topic" \
        "set-option -t =0: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =0")" ]
    contains "$stderr" "tmux didn't rename session 0 to widget/topic: stub tmux: rename-session failed"
    [ "$(last_line)" = "✓ topic  ../topic  switched to 0" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_FAIL=rename-session run --separate-stderr wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    contains "$output" "✓ topic  ../topic  already open in tmux"
    lacks "$output" "renamed"
    [ "$(last_line)" = "→ attach with: tmux attach -t 0" ]
}

@test "--tmux when tagging an existing session fails: warning, still switched to, exit 0" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions 0 "" "$LAYOUT/topic")"
    export STUB_TMUX_SESSIONS
    TMUX=stub STUB_TMUX_FAIL=set-option run --separate-stderr wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" \
        "rename-session -t =0 widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -t =widget/topic")" ]
    contains "$stderr" "tmux didn't tag session widget/topic: stub tmux: set-option failed"
    [ "$(last_line)" = "✓ topic  ../topic  switched to widget/topic (renamed from 0)" ]
}

@test "--tmux: a name another session has falls back to <org>/<repo>/<branch>, then -2" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_SESSIONS="$(sessions widget/topic "$TMP/other" "$TMP/other")" run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s acme/widget/topic -c $LAYOUT/topic"
    contains "$(tmux_calls)" "set-option -t =acme/widget/topic: @wkt-worktree $LAYOUT/topic"
    [ "$(last_line)" = "→ attach with: tmux attach -t acme/widget/topic" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions \
        widget/topic "" "$TMP" \
        acme/widget/topic "$TMP/other" "$TMP/other")"
    export STUB_TMUX_SESSIONS
    run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s acme/widget/topic-2 -c $LAYOUT/topic"

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS+=$'\n'"$(sessions acme/widget/topic-2 "" "$HOME")"
    run wkt new -b topic --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s acme/widget/topic-3 -c $LAYOUT/topic"
}

@test "--tmux -n names the session" {
    make_layout
    cd "$LAYOUT/main"
    run wkt new -b topic -n "Login page.v2" --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s Login page-v2 -c $LAYOUT/topic"
    contains "$output" "✓ topic (Login page.v2)  ../topic  opened in tmux"
    [ "$(last_line)" = "→ attach with: tmux attach -t 'Login page-v2'" ]

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions mine "$TMP" "$TMP")" run wkt new -b other -n mine --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s mine-2 -c $LAYOUT/other"
}

@test "--tmux in a normal clone: <repo> and <org> come from origin's URL, . becomes -" {
    make_clone
    mkdir -p "$TMP/remotes/some.org"
    cp -R "$ORIGIN" "$TMP/remotes/some.org/my.site.git"
    cd "$CLONE"
    git remote set-url origin "$TMP/remotes/some.org/my.site.git"
    run wkt new -b v1.2 -s main --tmux
    [ "$status" -eq 0 ]
    wt="$HOME/.herdr/worktrees/some.org/my.site/v1.2"
    contains "$(tmux_calls)" "new-session -d -s my-site/v1-2 -c $wt"

    : >"$STUB_TMUX_LOG"
    STUB_TMUX_SESSIONS="$(sessions my-site/v1-2 "" "$TMP")" run wkt new -b v1.2 --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s some-org/my-site/v1-2 -c $wt"
}

@test "--tmux in a .bare layout without origin: <repo> is the layout's folder" {
    make_layout
    git -C "$LAYOUT" remote remove origin
    cd "$LAYOUT/main"
    run wkt new -b topic -s main --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s layout/topic -c $LAYOUT/topic"
}

@test "--tmux without tmux on PATH: worktree is made, warning, exit 0" {
    rm "$STUB_BIN/tmux"
    run command -v tmux
    [ "$status" -ne 0 ]
    make_layout
    cd "$LAYOUT/main"
    TMUX=stub run --separate-stderr wkt new --tmux -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    contains "$stderr" "tmux not found on PATH"
    [ "$(last_line)" = "✓ topic  ../topic" ]
}

@test "--tmux when tmux fails: worktree is made, warning, exit 0" {
    make_layout
    cd "$LAYOUT/main"
    STUB_TMUX_FAIL=1 run --separate-stderr wkt new --tmux -b topic
    [ "$status" -eq 0 ]
    [ -d "$LAYOUT/topic" ]
    contains "$stderr" "tmux didn't open the worktree: stub tmux: new-session failed"
    [ "$(last_line)" = "✓ topic  ../topic" ]
    lacks "$(tmux_calls)" "set-option"
}

@test "--tmux when switching fails: warning, exit 0" {
    make_layout
    cd "$LAYOUT/main"
    TMUX=stub STUB_TMUX_FAIL=switch-client run --separate-stderr wkt new --tmux -b topic
    [ "$status" -eq 0 ]
    contains "$stderr" "tmux didn't switch to widget/topic: stub tmux: switch-client failed"
    [ "$(last_line)" = "✓ topic  ../topic" ]
}
