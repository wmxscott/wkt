#!/usr/bin/env bats

load test_helper

LIST=$'list-sessions -F #{session_name}\t#{@wkt-worktree}\t#{session_path}\t#{session_last_attached}'
CURRENT='display-message -p #{session_name}'
GH_VIEW='pr view topic --json state,headRefOid --jq [.state,.headRefOid]|@tsv'

setup() {
    common_setup
    make_origin
    make_layout
    cd "$LAYOUT/main" || return 1
    wkt new -b topic >/dev/null 2>&1
    : >"$STUB_HERDR_LOG"
    cd "$LAYOUT/topic" || return 1
}

has_branch() { git -C "$LAYOUT" show-ref --verify --quiet "refs/heads/$1"; }
no_branch() { ! git -C "$LAYOUT" show-ref --verify --quiet "refs/heads/$1"; }
commit() { git commit --quiet --allow-empty -m "${1:-work}"; }

# pr <state> <head-oid>: gh's answer for the branch's pull request.
pr() { printf '%s\t%s' "$1" "$2"; }

# gone_upstream: push topic with an upstream, then delete it on origin and
# prune it, as GitHub does after merging a pull request.
gone_upstream() {
    git push --quiet -u origin topic
    git push --quiet origin --delete topic
    git fetch --quiet --prune origin
}

@test "removes the worktree you're in, and its branch when it was never used" {
    run --separate-stderr wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    no_branch topic
    lacks "$(git -C "$LAYOUT" worktree list)" "$LAYOUT/topic"
    [ "${lines[0]}" = "✓ removed topic  $LAYOUT/topic  branch deleted" ]
    [ "$(last_line)" = "→ your folder is gone; run: cd $LAYOUT/main" ]
    [ -z "$stderr" ]
}

@test "-b removes the worktree that has the branch, and needs no cd" {
    cd "$LAYOUT/main"
    run wkt rm -b topic
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    no_branch topic
    [ "$output" = "✓ removed topic  $LAYOUT/topic  branch deleted" ]
}

@test "a branch with slashes leaves no empty folders behind" {
    wkt new -b feat/login >/dev/null 2>&1
    run wkt rm -b feat/login
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/feat" ]
    no_branch feat/login
}

@test "--no-herdr is accepted and changes nothing" {
    run wkt rm --no-herdr
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
}

# --- refusals --------------------------------------------------------------

@test "refuses the main checkout of a normal clone" {
    make_clone
    cd "$CLONE"
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "Refusing to remove the main checkout."
    run wkt rm -b main
    [ "$status" -eq 1 ]
    contains "$output" "Refusing to remove the main checkout."
    [ -d "$CLONE/.git" ]
}

@test "refuses the default branch's worktree in a .bare layout" {
    run wkt rm -b main
    [ "$status" -eq 1 ]
    contains "$output" "Refusing to remove the default branch's worktree."
    cd "$LAYOUT/main"
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "Refusing to remove the default branch's worktree."
    [ -d "$LAYOUT/main" ]
    has_branch main
}

@test "refuses the default branch's worktree in a normal clone too" {
    make_clone
    git -C "$CLONE" checkout --quiet develop
    cd "$CLONE"
    wkt new -b main >/dev/null 2>&1
    run wkt rm -b main
    [ "$status" -eq 1 ]
    contains "$output" "Refusing to remove the default branch's worktree."
    cd "$HOME/.herdr/worktrees/acme/widget/main"
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "Refusing to remove the default branch's worktree."
    [ -d "$HOME/.herdr/worktrees/acme/widget/main" ]
    git -C "$CLONE" show-ref --verify --quiet refs/heads/main
}

@test "refuses a branch with no worktree" {
    run wkt rm -b develop
    [ "$status" -eq 1 ]
    contains "$output" "No worktree has 'develop' checked out."
    has_branch develop

    run wkt rm -b nope
    [ "$status" -eq 1 ]
    contains "$output" "No worktree has 'nope' checked out."
}

@test "refuses to guess outside a worktree" {
    cd "$LAYOUT"
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "Not inside a Git worktree."
    contains "$output" "-b"
}

@test "refuses uncommitted changes, even untracked files; -f removes anyway" {
    echo draft >notes.txt
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") \
        STUB_TMUX_SESSIONS="$(sessions widget/topic "$LAYOUT/topic" "$LAYOUT/topic")" run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "'topic' has uncommitted changes or untracked files."
    contains "$output" "pass -f"
    [ -f "$LAYOUT/topic/notes.txt" ]
    [ -z "$(herdr_calls)" ]
    [ -z "$(tmux_calls)" ]

    run wkt rm -f
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
}

@test "refuses commits that were never pushed; -f removes anyway and keeps the branch" {
    commit
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "'topic' has commits that were never pushed."
    [ -d "$LAYOUT/topic" ]

    run wkt rm -f
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    has_branch topic
    contains "${lines[0]}" "branch kept: not merged into origin/main"
}

@test "refuses commits that aren't on the upstream" {
    commit
    git push --quiet -u origin topic
    commit "more"
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "'topic' has commits that were never pushed."
    [ -d "$LAYOUT/topic" ]
}

@test "a branch the default branch already has passes, even ahead of its upstream" {
    commit
    git push --quiet -u origin topic
    commit "more"
    git push --quiet origin HEAD:main
    git fetch --quiet origin
    run wkt rm
    [ "$status" -eq 0 ]
    no_branch topic
}

@test "squash-merged with its upstream gone: removed and deleted without -f" {
    commit
    gone_upstream
    STUB_GH_PR=$(pr MERGED "$(rev . HEAD)") run wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    no_branch topic
    contains "${lines[0]}" "branch deleted"
    [ "$(cat "$STUB_GH_LOG")" = "$GH_VIEW" ]
}

@test "squash-merged, then a commit made after the PR's head: refused" {
    local head
    commit
    gone_upstream
    head=$(rev . HEAD)
    commit "after"
    STUB_GH_PR=$(pr MERGED "$head") run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "'topic' has commits that were never pushed."
    [ -d "$LAYOUT/topic" ]
    has_branch topic
    [ "$(cat "$STUB_GH_LOG")" = "$GH_VIEW" ]
}

@test "merged, with a PR head that isn't here and isn't HEAD: refused" {
    commit
    gone_upstream
    STUB_GH_PR=$(pr MERGED 0123456789abcdef0123456789abcdef01234567) run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "'topic' has commits that were never pushed."
    [ -d "$LAYOUT/topic" ]
}

@test "merged, with a PR head that has HEAD in it: removed" {
    local later
    commit
    gone_upstream
    later=$(git commit-tree -p HEAD -m later 'HEAD^{tree}')
    STUB_GH_PR=$(pr MERGED "$later") run wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    no_branch topic
}

# --- the branch ------------------------------------------------------------

@test "pushed but not merged: removes the worktree and keeps the branch" {
    commit
    git push --quiet -u origin topic
    run wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    has_branch topic
    contains "${lines[0]}" "✓ removed topic  $LAYOUT/topic  branch kept: not merged into origin/main"
    [ "$(cat "$STUB_GH_LOG")" = "$GH_VIEW" ]
}

@test "an open pull request keeps the branch" {
    commit
    git push --quiet -u origin topic
    STUB_GH_PR=$(pr OPEN "$(rev . HEAD)") run wkt rm
    [ "$status" -eq 0 ]
    has_branch topic
    contains "$output" "branch kept"
}

@test "a merged pull request deletes the local branch, and never origin's" {
    commit
    git push --quiet -u origin topic
    STUB_GH_PR=$(pr MERGED "$(rev . HEAD)") run wkt rm
    [ "$status" -eq 0 ]
    no_branch topic
    contains "${lines[0]}" "branch deleted"
    git -C "$ORIGIN" show-ref --verify --quiet refs/heads/topic
}

@test "a branch already in origin's default branch is deleted without asking GitHub" {
    commit
    git push --quiet origin HEAD:main
    git fetch --quiet origin
    run wkt rm
    [ "$status" -eq 0 ]
    no_branch topic
    contains "${lines[0]}" "branch deleted"
    [ ! -e "$STUB_GH_LOG" ]
}

@test "a detached worktree goes, and the branch it left stays" {
    git checkout --quiet --detach
    run wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    has_branch topic
    [ "${lines[0]}" = "✓ removed topic  $LAYOUT/topic" ]
}

@test "no origin: the local default branch stands in for it" {
    local solo="$TMP/solo" wt="$HOME/.herdr/worktrees/local/solo/topic"
    git init --quiet "$solo"
    git -C "$solo" commit --quiet --allow-empty -m initial
    cd "$solo"
    wkt new -b topic >/dev/null 2>&1
    cd "$wt"
    commit
    run wkt rm
    [ "$status" -eq 1 ]
    contains "$output" "'topic' has commits that were never pushed."

    git -C "$solo" merge --quiet --ff-only topic
    rm -f "$STUB_GH_LOG"
    run wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$wt" ]
    run ! git -C "$solo" show-ref --verify --quiet refs/heads/topic
    [ ! -e "$STUB_GH_LOG" ]
}

# --- Herdr -----------------------------------------------------------------

@test "closes the worktree's Herdr workspace" {
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/main" "$LAYOUT/topic") run wkt rm
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = $'workspace list\nworkspace close w2' ]
    [ "${lines[0]}" = "✓ removed topic  $LAYOUT/topic  branch deleted  Herdr workspace closed" ]
}

@test "the workspace closes after the folder and branch go, before the session" {
    export STUB_TMUX_LOG="$STUB_HERDR_LOG" PROBE_DIR="$LAYOUT/topic" PROBE_GIT="$LAYOUT/.bare"
    cat >"$STUB_BIN/herdr" <<'EOF'
#!/bin/bash
note=""
if [[ $2 == close ]]; then
    [[ ! -e $PROBE_DIR ]] || note+=" (folder still there)"
    ! git --git-dir="$PROBE_GIT" show-ref --verify --quiet refs/heads/topic || note+=" (branch still there)"
fi
printf '%s%s\n' "$*" "$note" >>"$STUB_HERDR_LOG"
[[ $2 != list ]] || printf '%s\n' "$STUB_HERDR_WORKSPACES"
EOF
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_CURRENT=widget/topic TMUX=stub run wkt rm
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "$(printf '%s\n' "workspace list" "$LIST" "workspace close w1" "$CURRENT" \
        "switch-client -t =widget/main" "kill-session -t =widget/topic")" ]
}

@test "closing the workspace fails: warns with the command, removes anyway" {
    STUB_HERDR_FAIL="workspace close" STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") \
        run --separate-stderr wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    contains "$stderr" "Herdr didn't close the workspace"
    contains "$stderr" "herdr workspace close w1"
    lacks "$output" "Herdr workspace closed"
}

@test "no workspace, or no herdr: closes nothing and says nothing" {
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/main") run --separate-stderr wkt rm
    [ "$status" -eq 0 ]
    [ "$(herdr_calls)" = "workspace list" ]
    [ -z "$stderr" ]
    lacks "$output" "Herdr"

    cd "$LAYOUT/main"
    wkt new -b other >/dev/null 2>&1
    rm "$STUB_BIN/herdr"
    run --separate-stderr wkt rm -b other
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

# --- tmux ------------------------------------------------------------------

@test "outside tmux: kills the worktree's session, last" {
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 200)" run wkt rm
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" "kill-session -t =widget/topic")" ]
    [ "${lines[0]}" = "✓ removed topic  $LAYOUT/topic  branch deleted  tmux session widget/topic closed" ]
    [ "$(last_line)" = "→ your folder is gone; run: cd $LAYOUT/main" ]
}

@test "in the session being removed: switches to the most recently attached other one, then kills it" {
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        notes "" "$HOME" 200 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300 \
        scratch "" "$HOME" "")" STUB_TMUX_CURRENT=widget/topic TMUX=stub run wkt rm
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" "$CURRENT" \
        "switch-client -t =notes" "kill-session -t =widget/topic")" ]
    [ "$output" = "✓ removed topic  $LAYOUT/topic  branch deleted  tmux session widget/topic closed" ]
}

@test "the only session: opens the default branch's worktree, switches to it, then kills" {
    STUB_TMUX_SESSIONS="$(sessions_attached widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_CURRENT=widget/topic TMUX=stub run wkt rm
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" "$CURRENT" "$LIST" \
        "new-session -d -s widget/main -c $LAYOUT/main" \
        "set-option -t =widget/main: @wkt-worktree $LAYOUT/main" \
        "switch-client -t =widget/main" \
        "kill-session -t =widget/topic")" ]
    [ "$output" = "✓ removed topic  $LAYOUT/topic  branch deleted  tmux session widget/topic closed" ]
}

@test "normal clone, the only session: opens the main checkout" {
    make_clone
    cd "$CLONE"
    wkt new -b topic >/dev/null 2>&1
    cd "$HOME/.herdr/worktrees/acme/widget/topic"
    STUB_TMUX_SESSIONS="$(sessions widget/topic "$PWD" "$PWD")" STUB_TMUX_CURRENT=widget/topic TMUX=stub run wkt rm
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s widget/main -c $CLONE"
    contains "$(tmux_calls)" "switch-client -t =widget/main"
    [ "$(tmux_calls | tail -n 1)" = "kill-session -t =widget/topic" ]
}

@test "inside tmux, in another session: kills the worktree's without switching" {
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_CURRENT=widget/main TMUX=stub run wkt rm -b topic
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" "$CURRENT" "kill-session -t =widget/topic")" ]
}

@test "switching away fails: warns and leaves the session open" {
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_FAIL=switch-client STUB_TMUX_CURRENT=widget/topic TMUX=stub run --separate-stderr wkt rm
    [ "$status" -eq 0 ]
    [ ! -e "$LAYOUT/topic" ]
    contains "$stderr" "tmux didn't switch to widget/main"
    contains "$stderr" "tmux kill-session -t '=widget/topic'"
    lacks "$(tmux_calls)" "kill-session"
    lacks "$output" "tmux session"
}

@test "no session: only looks" {
    STUB_TMUX_SESSIONS="$(sessions_attached widget/main "$LAYOUT/main" "$LAYOUT/main" 100)" \
        TMUX=stub run wkt rm
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$LIST" ]
    lacks "$output" "tmux"
}

# --- failure ---------------------------------------------------------------

@test "git worktree remove fails: the branch, workspace and session stay, with git's status" {
    git worktree lock "$LAYOUT/topic"
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_CURRENT=widget/topic TMUX=stub run wkt rm
    [ "$status" -eq 128 ]
    contains "$output" "locked"
    [ -d "$LAYOUT/topic" ]
    has_branch topic
    [ "$(herdr_calls)" = "workspace list" ]
    [ "$(tmux_calls)" = "$LIST" ]
    lacks "$output" "✓"
}
