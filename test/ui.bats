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

    rm -f "$STUB_FZF_DIR"/*
    fzf_reply 1 130
    STUB_FZF_VERSION=0.74.4 run --separate-stderr wkt
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

    rm -f "$STUB_FZF_DIR"/*
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

# Glyphs as UTF-8 bytes; bash 3.2 has no \u escapes.
ICO_HOME=$'\xef\x91\xad'
ICO_BRANCH=$'\xef\x90\x98'
ICO_COMMIT=$'\xef\x90\x97'
ICO_CURRENT=$'\xef\x84\x91'
ICO_MISSING=$'\xf3\xb0\x8c\xb8'
ICO_LOCKED=$'\xef\x91\x96'
ELLIPSIS=$'\xe2\x80\xa6'
MACCHIATO_TEXT="38;2;202;211;245"
LATTE_TEXT="38;2;76;79;105"

# The row of fzf call 1 whose path field is $1.
row_for() { fzf_input 1 | awk -F '\t' -v p="$1" '$4 == p'; }

# picker_input: run the picker in $LAYOUT, Esc at once, print the rows.
picker_input() {
    rm -f "$STUB_FZF_DIR"/*
    fzf_reply 1 130
    (cd "$LAYOUT" && wkt) >/dev/null 2>&1 || true
    fzf_input 1
}

trigger() {
    mkdir -p "$1/theme-monitor"
    printf '%s\n' "$2" >"$1/theme-monitor/theme-change.trigger"
}

@test "dark theme: Macchiato colours" {
    make_layout
    run picker_input
    contains "$output" "$MACCHIATO_TEXT"
    lacks "$output" "$LATTE_TEXT"
}

@test "light from the theme-monitor trigger file" {
    unset WKT_THEME
    make_layout
    trigger "$HOME/.local/share" light
    STUB_DEFAULTS_STYLE=Dark run picker_input
    contains "$output" "$LATTE_TEXT"
    lacks "$output" "$MACCHIATO_TEXT"
    [ ! -e "$STUB_DEFAULTS_LOG" ]
}

@test "XDG_DATA_HOME moves the trigger file" {
    unset WKT_THEME
    make_layout
    trigger "$HOME/.local/share" light
    trigger "$TMP/xdg" dark
    XDG_DATA_HOME="$TMP/xdg" run picker_input
    contains "$output" "$MACCHIATO_TEXT"
}

@test "WKT_THEME beats the trigger file; other values mean auto" {
    make_layout
    trigger "$HOME/.local/share" dark
    WKT_THEME=light run picker_input
    contains "$output" "$LATTE_TEXT"

    WKT_THEME=bogus run picker_input
    contains "$output" "$MACCHIATO_TEXT"
}

@test "no usable trigger file: macOS decides, else light" {
    unset WKT_THEME
    make_layout
    trigger "$HOME/.local/share" blue
    STUB_DEFAULTS_STYLE=Dark run picker_input
    contains "$output" "$MACCHIATO_TEXT"
    contains "$(cat "$STUB_DEFAULTS_LOG")" "read -g AppleInterfaceStyle"

    rm "$HOME/.local/share/theme-monitor/theme-change.trigger"
    run picker_input
    contains "$output" "$LATTE_TEXT"
}

@test "NO_COLOR: no escapes, icons kept" {
    make_layout
    fzf_reply 1 130
    (cd "$LAYOUT" && NO_COLOR=1 wkt) >/dev/null 2>&1 || true
    lacks "$(fzf_input 1)" $'\e['
    lacks "$(fzf_args 1)" $'\e['
    contains "$(fzf_input 1)" "$ICO_HOME"
}

@test "icons" {
    make_layout
    cd "$LAYOUT"
    local wt
    for wt in topic gone held loose; do
        wkt new -b "$wt" --no-herdr >/dev/null
    done
    rm -rf "$LAYOUT/gone"
    git worktree lock "$LAYOUT/held"
    git -C "$LAYOUT/loose" checkout --quiet --detach
    fzf_reply 1 130
    cd "$LAYOUT/topic"
    run wkt

    contains "$(row_for "$LAYOUT/main" | cut -f 1)" "$ICO_HOME"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_CURRENT"
    contains "$(row_for "$LAYOUT/topic" | cut -f 1)" "$ICO_BRANCH"
    contains "$(row_for "$LAYOUT/topic")" "$ICO_CURRENT"
    contains "$(row_for "$LAYOUT/gone")" "$ICO_MISSING"
    contains "$(row_for "$LAYOUT/held")" "$ICO_LOCKED"
    contains "$(row_for "$LAYOUT/loose" | cut -f 1)" "$ICO_COMMIT"
    contains "$(row_for "$LAYOUT/loose")" "$(git -C "$LAYOUT/loose" rev-parse --short=7 HEAD)"
}

@test "header: hints row" {
    make_layout
    run picker_input
    contains "$(fzf_args 1)" $'\xe2\x86\xb5 open \xc2\xb7 ^n new \xc2\xb7 esc quit'
}

@test "long paths are cut from the left" {
    make_clone
    local long
    long="$HOME/$(printf 'very-long-folder-name-%s/' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
    long=${long%/}
    cd "$CLONE"
    WKT_ROOT=$long wkt new -b topic --no-herdr >/dev/null
    fzf_reply 1 130
    run wkt
    local shown
    shown=$(row_for "$long/acme/widget/topic" | cut -f 3)
    contains "$shown" "$ELLIPSIS"
    contains "$shown" "/widget/topic"
    lacks "$shown" "/very-long-folder-name-1/"
}

@test "works when the locale isn't UTF-8" {
    make_layout
    LC_ALL=C LANG=C run picker_input
    contains "$output" "$ICO_HOME"
}
