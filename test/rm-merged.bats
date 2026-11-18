#!/usr/bin/env bats

load test_helper

LIST=$'list-sessions -F #{session_name}\t#{@wkt-worktree}\t#{session_path}\t#{session_last_attached}'
CURRENT='display-message -p #{session_name}'
DIRTY='uncommitted changes or untracked files'

# A .bare layout with worktrees fresh, never used, and squashed, whose pull
# request was squash-merged: both merged. open has an open pull request,
# dirty is merged but has an untracked file, and loose is detached.
setup() {
    common_setup
    make_origin
    make_layout

    # gh answers pr view <branch> from $STUB_GH_DIR/<branch>.
    export STUB_GH_DIR="$TMP/gh"
    mkdir -p "$STUB_GH_DIR"
    cat >"$STUB_BIN/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_GH_LOG"
[[ $1 == pr && -f $STUB_GH_DIR/$3 ]] || exit 1
cat "$STUB_GH_DIR/$3"
EOF

    cd "$LAYOUT/main" || return 1
    local b
    for b in fresh squashed open dirty; do
        wkt new -b "$b" >/dev/null 2>&1
    done
    git -C "$LAYOUT/squashed" commit --quiet --allow-empty -m squashed
    git -C "$LAYOUT/squashed" push --quiet -u origin squashed
    git -C "$LAYOUT/squashed" push --quiet origin --delete squashed
    git -C "$LAYOUT/squashed" fetch --quiet --prune origin
    printf 'MERGED\t%s' "$(rev "$LAYOUT/squashed" HEAD)" >"$STUB_GH_DIR/squashed"
    git -C "$LAYOUT/open" commit --quiet --allow-empty -m open
    git -C "$LAYOUT/open" push --quiet -u origin open
    printf 'OPEN\t%s' "$(rev "$LAYOUT/open" HEAD)" >"$STUB_GH_DIR/open"
    echo draft >"$LAYOUT/dirty/notes.txt"
    git worktree add --quiet --detach "$LAYOUT/loose"
    : >"$STUB_HERDR_LOG"
}

has_branch() { git -C "$LAYOUT" show-ref --verify --quiet "refs/heads/$1"; }
no_branch() { ! git -C "$LAYOUT" show-ref --verify --quiet "refs/heads/$1"; }

# untouched: every worktree and branch from setup is still there.
untouched() {
    local b
    for b in main fresh squashed open dirty loose; do
        [ -d "$LAYOUT/$b" ] || return 1
    done
    for b in main fresh squashed open dirty; do
        has_branch "$b" || return 1
    done
}

# listed: what's printed before anything goes.
listed() {
    printf '%s\n' "Merged worktrees to remove:" \
        "  fresh  $LAYOUT/fresh" \
        "  squashed  $LAYOUT/squashed" \
        "Skipping:" \
        "  dirty  $LAYOUT/dirty  ($DIRTY)"
}

@test "lists what goes and what's skipped, asks, and anything but y changes nothing" {
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/fresh") \
        STUB_TMUX_SESSIONS="$(sessions widget/fresh "$LAYOUT/fresh" "$LAYOUT/fresh")" \
        TMUX=stub run --separate-stderr wkt rm --merged <<<n
    [ "$status" -eq 1 ]
    [ "$output" = "$(listed)" ]
    contains "$stderr" "Remove 2 merged worktrees? [y/N]"
    contains "$stderr" "Aborted. Nothing was changed."
    untouched
    [ -z "$(herdr_calls)" ]
    [ -z "$(tmux_calls)" ]

    run wkt rm --merged </dev/null
    [ "$status" -eq 1 ]
    contains "$output" "Aborted. Nothing was changed."
    untouched
}

@test "y removes every merged worktree and its branch, and nothing else" {
    run --separate-stderr wkt rm --merged <<<y
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/fresh" ]
    [ ! -e "$LAYOUT/squashed" ]
    no_branch fresh
    no_branch squashed
    [ -d "$LAYOUT/open" ]
    has_branch open
    [ -d "$LAYOUT/loose" ]
    [ -d "$LAYOUT/main" ]
    has_branch main
    [ "$(last_line)" = "✓ removed 2, skipped 1" ]
}

@test "-y doesn't ask, and each goes as rm would: folder, branch, workspace" {
    unset WKT_ASSUME_TTY
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/fresh" "$LAYOUT/squashed") \
        run --separate-stderr wkt rm --merged -y </dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "$(listed; printf '%s\n' \
        "✓ removed fresh  $LAYOUT/fresh  branch deleted  Herdr workspace closed" \
        "✓ removed squashed  $LAYOUT/squashed  branch deleted  Herdr workspace closed" \
        "✓ removed 2, skipped 1")" ]
    [ -z "$stderr" ]
    no_branch fresh
    no_branch squashed
    [ "$(herdr_calls)" = $'workspace list\nworkspace close w1\nworkspace list\nworkspace close w2' ]
}

@test "no terminal and no -y: stops and changes nothing" {
    unset WKT_ASSUME_TTY
    run wkt rm --merged </dev/null
    [ "$status" -eq 1 ]
    contains "$output" "$(listed)"
    contains "$output" "No terminal to confirm; pass -y"
    contains "$output" "Nothing was changed."
    lacks "$output" "[y/N]"
    untouched
    [ -z "$(herdr_calls)" ]
    [ -z "$(tmux_calls)" ]
}

@test "a merged worktree with changes is skipped, listed with why, and kept" {
    run wkt rm --merged -y
    [ "$status" -eq 0 ]
    contains "$output" $'Skipping:\n'"  dirty  $LAYOUT/dirty  ($DIRTY)"
    lacks "$output" "removed dirty"
    [ -f "$LAYOUT/dirty/notes.txt" ]
    has_branch dirty
    [ "$(last_line)" = "✓ removed 2, skipped 1" ]
}

@test "nothing left to remove: says so and doesn't ask" {
    wkt rm --merged -y >/dev/null
    unset WKT_ASSUME_TTY
    run wkt rm --merged </dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' "No merged worktrees to remove." "Skipping:" \
        "  dirty  $LAYOUT/dirty  ($DIRTY)")" ]
}

@test "never lists the default branch or a normal clone's main checkout" {
    make_clone
    git -C "$CLONE" checkout --quiet -b used origin/main
    cd "$CLONE"
    wkt new -b main >/dev/null 2>&1
    wkt new -b fresh >/dev/null 2>&1
    run --separate-stderr wkt rm --merged <<<n
    [ "$status" -eq 1 ]
    [ "$output" = $'Merged worktrees to remove:\n  fresh  ~/.herdr/worktrees/acme/widget/fresh' ]
    [ -d "$HOME/.herdr/worktrees/acme/widget/main" ]
}

@test "the session you're in goes last, its kill after all output" {
    # wkt's output and the tmux calls share one log, in the order they happen.
    export STUB_TMUX_LOG="$TMP/out"
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 200 \
        widget/fresh "$LAYOUT/fresh" "$LAYOUT/fresh" 300 \
        widget/squashed "$LAYOUT/squashed" "$LAYOUT/squashed" 100)" \
        STUB_TMUX_CURRENT=widget/fresh TMUX=stub wkt rm --merged -y >>"$STUB_TMUX_LOG" 2>&1
    [ "$(tmux_calls)" = "$(listed; printf '%s\n' "$CURRENT" "$LIST" \
        "$LIST" "$CURRENT" \
        "✓ removed squashed  $LAYOUT/squashed  branch deleted  tmux session widget/squashed closed" \
        "kill-session -t =widget/squashed" \
        "$LIST" "$CURRENT" "switch-client -t =widget/main" \
        "✓ removed fresh  $LAYOUT/fresh  branch deleted  tmux session widget/fresh closed" \
        "✓ removed 2, skipped 1" \
        "kill-session -t =widget/fresh")" ]
}

@test "run from a merged worktree outside tmux: says where to go" {
    cd "$LAYOUT/fresh"
    run wkt rm --merged -y
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/fresh" ]
    [ "$(last_line)" = "→ your folder is gone; run: cd $LAYOUT/main" ]
}

@test "one that git can't remove is reported, the rest go, and the exit is 1" {
    git worktree lock "$LAYOUT/fresh"
    run --separate-stderr wkt rm --merged -y
    [ "$status" -eq 1 ]
    [ -d "$LAYOUT/fresh" ]
    has_branch fresh
    [ ! -e "$LAYOUT/squashed" ]
    no_branch squashed
    contains "$stderr" "locked"
    contains "$stderr" "fresh wasn't removed"
    contains "$stderr" "removed 1, failed 1, skipped 1"
    lacks "$output" "removed fresh"
}
