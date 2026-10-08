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

@test "glyphs are written as escapes in the script" {
    run perl -CSD -ne 'print "$.\n" if /[\x{e000}-\x{f8ff}\x{f0000}-\x{10ffff}\x{2026}\x{21b5}]/' "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a non-UTF-8 LANG only changes the character set" {
    make_layout
    unset LC_ALL LC_CTYPE
    LANG=C run picker_input
    contains "$output" "$ICO_HOME"
}

# The visible text of a row: fields 1-3, escapes removed.
plain_row() { row_for "$1" | cut -f 1-3 | sed $'s/\e\\[[0-9;]*m//g'; }

@test "a path that only repeats the branch name is left out" {
    make_layout
    run picker_input
    local text
    text=$(plain_row "$LAYOUT/main")
    contains "$text" "main"
    lacks "${text#*main}" "main"

    make_clone
    cd "$CLONE"
    rm -f "$STUB_FZF_DIR"/*
    fzf_reply 1 130
    run wkt
    contains "$(plain_row "$CLONE")" "/widget"
}

ICO_OPEN=$'\xef\x92\xaa'
MACCHIATO_BLUE="38;2;138;173;244"

# workspaces <path>...: herdr's 'workspace list' reply, with a workspace per
# path and one without a worktree.
workspaces() {
    local path list=""
    for path in "$@"; do
        list+='{"id":"w:'"$path"'","label":"x","worktree":{"checkout_path":"'"$path"'","is_linked_worktree":true}},'
    done
    printf '{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[%s{"id":"w:none","label":"y"}]}}' "$list"
}

@test "inside Herdr: enter opens the workspace and prints nothing" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\t\t'"$LAYOUT/topic"
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    contains "$(herdr_calls)" "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus"
}

@test "inside Herdr: Herdr fails, the path is printed" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\t\t'"$LAYOUT/topic"
    STUB_HERDR_FAIL=1 run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    contains "$stderr" "warning:"
}

@test "open workspaces get the blue circle" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") run picker_input
    contains "$(row_for "$LAYOUT/topic")" "$ICO_OPEN"
    contains "$(row_for "$LAYOUT/topic")" "$MACCHIATO_BLUE"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"
    contains "$(herdr_calls)" "workspace list"
}

@test "outside Herdr: workspace list is never called" {
    unset HERDR_TAB_ID
    make_layout
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/main") run picker_input
    lacks "$(herdr_calls)" "workspace list"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"
}

@test "Herdr not answering: rows show no Herdr status" {
    make_layout
    STUB_HERDR_FAIL=1 STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/main") run picker_input
    contains "$(row_for "$LAYOUT/main")" "$ICO_HOME"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"
}

@test "current beats open-in-Herdr" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    fzf_reply 1 130
    cd "$LAYOUT/topic"
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") run wkt
    contains "$(row_for "$LAYOUT/topic")" "$ICO_CURRENT"
    lacks "$(row_for "$LAYOUT/topic")" "$ICO_OPEN"
}

MACCHIATO_GREEN="38;2;166;218;149"
MACCHIATO_YELLOW="38;2;238;212;159"

@test "preview: a blank line, then the bold branch and the path" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    run --separate-stderr wkt __preview "$LAYOUT/topic"
    [ "$status" -eq 0 ]
    starts_with "$output" $'\n\e[1;'"${MACCHIATO_TEXT}mtopic"
    contains "$output" "$LAYOUT/topic"
    [ -z "$stderr" ]
}

@test "preview: changed files, coloured by kind" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    echo new >"$LAYOUT/topic/loose.txt"
    echo staged >"$LAYOUT/topic/staged.txt"
    git -C "$LAYOUT/topic" add staged.txt
    run wkt __preview "$LAYOUT/topic"
    contains "$output" "loose.txt"
    contains "$output" "${MACCHIATO_YELLOW}m??"
    contains "$output" "staged.txt"
    contains "$output" "${MACCHIATO_GREEN}mA"
}

@test "preview: recent commits" {
    make_layout
    run wkt __preview "$LAYOUT/main"
    contains "$output" "initial"
    contains "$output" "$(git -C "$LAYOUT/main" rev-parse --short HEAD)"
}

@test "preview: the upstream and how far ahead and behind" {
    make_layout
    git -C "$LAYOUT/main" commit --quiet --allow-empty -m "local work"
    run wkt __preview "$LAYOUT/main"
    contains "$output" "origin/main"
    contains "$output" "1 ahead"
    contains "$output" "0 behind"
}

@test "preview: a missing folder says so" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic --no-herdr >/dev/null
    rm -rf "$LAYOUT/topic"
    run --separate-stderr wkt __preview "$LAYOUT/topic"
    [ "$status" -eq 0 ]
    contains "$output" "folder missing"
    [ -z "$stderr" ]
}

@test "preview: not in --help" {
    run wkt --help
    lacks "$output" "__preview"
}

@test "the list shows the preview on the right" {
    make_layout
    run picker_input
    local args
    args=$(fzf_args 1)
    contains "$args" $'--preview\n'
    contains "$args" "bin/wkt __preview {4}"
    contains "$args" $'--preview-window\nright,40%,border-left'
}

@test "ctrl-n: branch, source, then created and printed" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 develop
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    [ "$(rev "$LAYOUT/topic" HEAD)" = "$(rev "$LAYOUT" origin/develop)" ]
    contains "$stderr" "topic"
    contains "$(fzf_args 2)" $'--prompt\nBranch: '
    contains "$(fzf_args 2)" "New worktree"
    contains "$(fzf_args 3)" $'--prompt\nSource: '
}

@test "ctrl-n: the search text is the default branch name" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 fix ctrl-n ""
    fzf_reply 2 130
    fzf_reply 3 130
    run wkt
    contains "$(fzf_args 2)" $'--query\nfix'
}

@test "enter with no match starts new, prefilled" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 1 fix-login ""
    fzf_reply 2 130
    fzf_reply 3 130
    run wkt
    [ "$status" -eq 130 ]
    contains "$(fzf_args 2)" $'--query\nfix-login'
}

@test "a blank branch name asks again" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 ""
    fzf_reply 3 130
    fzf_reply 4 130
    run wkt
    [ "$status" -eq 130 ]
    contains "$(fzf_args 3)" $'--prompt\nBranch: '
}

@test "bad branch name asks again with a notice" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 "a..b"
    fzf_reply 3 130
    fzf_reply 4 130
    run wkt
    [ "$status" -eq 130 ]
    contains "$(fzf_args 3)" "'a..b' is not a valid branch name"
    contains "$(fzf_args 3)" $'--query\na..b'
}

@test "source list: default first, origin branches merged in" {
    make_layout
    cd "$LAYOUT"
    git branch --quiet local-only main
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 130
    fzf_reply 4 130
    run wkt
    local sources
    sources=$(fzf_input 3 | awk -F '\t' '{ print $NF }')
    [ "$(printf '%s\n' "$sources" | head -n 1)" = main ]
    [ "$(printf '%s\n' "$sources" | grep -cx develop)" -eq 1 ]
    [ "$(printf '%s\n' "$sources" | grep -cx feature-x)" -eq 1 ]
    [ "$(printf '%s\n' "$sources" | grep -cx local-only)" -eq 1 ]
    lacks "$sources" "origin"
    lacks "$sources" "HEAD"
    contains "$(fzf_input 3 | head -n 1)" "$ICO_HOME"
    contains "$(fzf_args 3)" "enter:accept-non-empty"
}

@test "existing branch skips the source step" {
    unset HERDR_TAB_ID
    make_clone
    cd "$CLONE"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 feature-x
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$(fzf_calls)" -eq 2 ]
    [ "$output" = "$HOME/.herdr/worktrees/acme/widget/feature-x" ]
    [ "$(git -C "$output" rev-parse --abbrev-ref '@{upstream}')" = origin/feature-x ]
}

@test "inside Herdr: label step, then opened with the label" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    fzf_reply 4 1 Login ""
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    contains "$(fzf_args 4)" $'--prompt\nLabel: '
    contains "$(fzf_args 4)" "^o don't open in Herdr"
    contains "$(herdr_calls)" "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label Login --focus"
}

@test "inside Herdr: ctrl-o skips Herdr" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    fzf_reply 4 0 "" ctrl-o
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    lacks "$(herdr_calls)" "worktree open"
}

@test "esc during new goes back to the list" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 130
    fzf_reply 4 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$output" ]
    [ "$(fzf_calls)" -eq 4 ]
    [ ! -e "$LAYOUT/topic" ]
    contains "$(fzf_args 4)" "--expect"
}

@test "a failing new worktree ends the picker with its error" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    mkdir "$LAYOUT/topic"
    : >"$LAYOUT/topic/stray"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    run --separate-stderr wkt
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    contains "$stderr" "isn't a worktree of this repo"
}

@test "a git failure while creating stops the picker" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    : >"$LAYOUT/fix"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 fix/login
    fzf_reply 3 0 main
    run --separate-stderr wkt
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    lacks "$stderr" "✓"
}
