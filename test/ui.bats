#!/usr/bin/env bats

load test_helper

setup() { common_setup; make_origin; }

@test "no terminal: usage on stderr, exit 2" {
    unset WKT_ASSUME_TTY
    run --separate-stderr wkt
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    starts_with "$stderr" "Usage: wkt"
}

@test "no fzf: says how to install it" {
    make_clone
    cd "$CLONE"
    rm "$STUB_BIN/fzf"
    run --separate-stderr wkt
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    contains "$stderr" "brew install fzf"
}

@test "old fzf: names both versions" {
    make_clone
    cd "$CLONE"
    STUB_FZF_VERSION="0.30.0 (brew)" run --separate-stderr wkt
    [ "$status" -eq 1 ]
    contains "$stderr" "0.30"
    contains "$stderr" "0.36"
}

@test "fzf version is compared as numbers" {
    make_clone
    cd "$CLONE"
    STUB_FZF_VERSION=0.4.0 run --separate-stderr wkt
    [ "$status" -eq 1 ]
    contains "$stderr" "0.36"

    fzf_reply 1 130
    STUB_FZF_VERSION=1.2.0 run --separate-stderr wkt
    [ "$status" -ne 1 ]
    lacks "$stderr" "error:"
}

@test "outside a repo: same error as wkt new" {
    mkdir empty && cd empty
    run --separate-stderr wkt
    [ "$status" -eq 1 ]
    contains "$stderr" "Not inside a Git repository."
}

# The path field (the 4th, hidden one) of row n of fzf call 1.
row_path() { fzf_input 1 | sed -n "${1}p" | cut -f 4; }

@test "rows: one per worktree, .bare left out" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    fzf_reply 1 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ "$(fzf_input 1 | wc -l | tr -d ' ')" -eq 2 ]
    [ "$(row_path 1)" = "$LAYOUT/main" ]
    [ "$(row_path 2)" = "$LAYOUT/topic" ]
    lacks "$(fzf_input 1)" ".bare"
}

@test "rows: default branch first, cursor on the current worktree" {
    make_layout
    cd "$LAYOUT"
    git worktree remove main
    wkt new -b aaa --no-herdr >/dev/null
    git worktree add --quiet main main
    [ "$(git worktree list --porcelain | grep '^worktree ' | sed -n 2p)" = "worktree $LAYOUT/aaa" ]

    fzf_reply 1 130
    cd "$LAYOUT/aaa"
    run wkt
    [ "$(row_path 1)" = "$LAYOUT/main" ]
    [ "$(row_path 2)" = "$LAYOUT/aaa" ]
    contains "$(fzf_args 1)" "load:pos(2)"
}

@test "rows: no cursor move on the first row or at the layout root" {
    make_layout
    cd "$LAYOUT/main"
    fzf_reply 1 130
    run wkt
    lacks "$(fzf_args 1)" "load:pos"

    rm -r "$STUB_FZF_DIR" && mkdir "$STUB_FZF_DIR"
    cd "$LAYOUT"
    fzf_reply 1 130
    run wkt
    [ "$status" -eq 130 ]
    lacks "$(fzf_args 1)" "load:pos"
}

@test "enter: prints the worktree path and nothing else" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\ttopic\t'"$LAYOUT/topic"
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
}

@test "esc: prints nothing, exit 130" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$output" ]
}

@test "fzf gets the shared look, and search matches the branch only" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 130
    run wkt
    local args
    args=$(fzf_args 1)
    contains "$args" $'--with-nth\n1..3'
    contains "$args" $'--nth\n2'
    contains "$args" $'--delimiter\n\t'
    contains "$args" $'--tabstop\n1'
    contains "$args" $'--expect\nctrl-n'
    contains "$args" "--print-query"
    contains "$args" $'--ansi\n--layout=reverse\n--height=100%\n--border=none\n--margin=0\n--padding=0\n--no-info'
    contains "$args" $'--prompt\n> '
}

@test "fzf failing for another reason is an error" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 2
    run --separate-stderr wkt
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    contains "$stderr" "fzf"
}
