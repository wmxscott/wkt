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
    wkt new -b topic >/dev/null
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
    wkt new -b aaa >/dev/null
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

@test "enter: prints the worktree path and nothing else, even inside Herdr" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\ttopic\t'"$LAYOUT/topic"
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    lacks "$(herdr_calls)" "worktree open"
}

@test "--no-herdr is accepted and changes nothing" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" "" $'x\tmain\t\t'"$LAYOUT/main"
    run --separate-stderr wkt --no-herdr
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/main" ]
    lacks "$(herdr_calls)" "worktree open"
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
    contains "$args" $'--expect\nctrl-n,ctrl-d,ctrl-x'
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
        wkt new -b "$wt" >/dev/null
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
    contains "$(fzf_args 1)" $'\xe2\x86\xb5 open \xc2\xb7 ^n new \xc2\xb7 ^d remove \xc2\xb7 ^x remove merged \xc2\xb7 esc quit'
}

@test "long paths are cut from the left" {
    make_clone
    local long
    long="$HOME/$(printf 'very-long-folder-name-%s/' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
    long=${long%/}
    cd "$CLONE"
    WKT_ROOT=$long wkt new -b topic >/dev/null
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

@test "--herdr: enter opens the workspace and prints nothing" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\t\t'"$LAYOUT/topic"
    run --separate-stderr wkt --herdr
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    contains "$(herdr_calls)" "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus"
}

@test "--herdr outside Herdr: enter opens the workspace" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\t\t'"$LAYOUT/topic"
    run --separate-stderr wkt --herdr
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    contains "$(herdr_calls)" "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus"
}

@test "--herdr: Herdr fails, the path is printed" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" $'x\ttopic\t\t'"$LAYOUT/topic"
    STUB_HERDR_FAIL=1 run --separate-stderr wkt --herdr
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    contains "$stderr" "warning:"
}

@test "open workspaces get the blue circle" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") run picker_input
    contains "$(row_for "$LAYOUT/topic")" "$ICO_OPEN"
    contains "$(row_for "$LAYOUT/topic")" "$MACCHIATO_BLUE"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"
    contains "$(herdr_calls)" "workspace list"
}

@test "outside Herdr: open workspaces still get the circle" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/topic") run picker_input
    contains "$(herdr_calls)" "workspace list"
    contains "$(row_for "$LAYOUT/topic")" "$ICO_OPEN"
}

@test "Herdr not answering: rows show no Herdr status, and no warning" {
    make_layout
    STUB_HERDR_FAIL=1 STUB_HERDR_WORKSPACES=$(workspaces "$LAYOUT/main") run picker_input
    contains "$(row_for "$LAYOUT/main")" "$ICO_HOME"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"

    cd "$LAYOUT"
    rm -f "$STUB_FZF_DIR"/*
    fzf_reply 1 130
    STUB_HERDR_FAIL=1 run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$stderr" ]

    rm "$STUB_BIN/herdr"
    rm -f "$STUB_FZF_DIR"/*
    fzf_reply 1 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$stderr" ]
}

@test "current beats open-in-Herdr" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
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
    wkt new -b topic >/dev/null
    run --separate-stderr wkt __preview "$LAYOUT/topic"
    [ "$status" -eq 0 ]
    starts_with "$output" $'\n\e[1;'"${MACCHIATO_TEXT}mtopic"
    contains "$output" "$LAYOUT/topic"
    [ -z "$stderr" ]
}

@test "preview: changed files, coloured by kind" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
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
    wkt new -b topic >/dev/null
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
    [ "$(fzf_calls)" -eq 3 ]
    lacks "$(herdr_calls)" "worktree open"
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

@test "--herdr: label step, then opened with the label" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    fzf_reply 4 1 Login ""
    run --separate-stderr wkt --herdr
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    contains "$(fzf_args 4)" $'--prompt\nLabel: '
    contains "$(fzf_args 4)" "^o don't open in Herdr"
    contains "$(herdr_calls)" "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --label Login --focus"
}

@test "--herdr outside Herdr: label step, then opened" {
    unset HERDR_TAB_ID
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    fzf_reply 4 1 "" ""
    run --separate-stderr wkt --herdr
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    contains "$(fzf_args 4)" $'--prompt\nLabel: '
    contains "$(herdr_calls)" "worktree open --cwd $LAYOUT/.bare --path $LAYOUT/topic --focus"
}

@test "--herdr: ctrl-o skips Herdr" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    fzf_reply 4 0 "" ctrl-o
    run --separate-stderr wkt --herdr
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

# --- tmux ------------------------------------------------------------------

LIST=$'list-sessions -F #{session_name}\t#{@wkt-worktree}\t#{session_path}\t#{session_last_attached}'
WHO=$'display-message -p #{client_name}\t#{session_name}'
CLIENT=/dev/ttys001
CURRENT="display-message -t$CLIENT -p #{session_name}"

# picked <path>: a row as fzf prints it when picked; only the path counts.
picked() { printf 'x\t%s\t\t%s' "${1##*/}" "$1"; }

@test "--tmux inside tmux: enter opens the worktree's session, switching the picker's client" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_CLIENT=$CLIENT TMUX=stub run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" \
        "new-session -d -s widget/topic -c $LAYOUT/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -c$CLIENT -t =widget/topic")" ]
}

@test "--tmux outside tmux: enter makes the session and says how to attach" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" "$LIST" \
        "new-session -d -s widget/topic -c $LAYOUT/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic")" ]
    contains "$stderr" "→ attach with: tmux attach -t widget/topic"
}

@test "--tmux: enter on a worktree with a misnamed session renames and re-tags it, then switches to it" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_SESSIONS="$(sessions restored "" "$LAYOUT/topic")" STUB_TMUX_CLIENT=$CLIENT TMUX=stub \
        run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" \
        "rename-session -t =restored widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -c$CLIENT -t =widget/topic")" ]
}

@test "--tmux outside tmux: enter on a misnamed session renames it and says how to attach" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_SESSIONS="$(sessions 0 "$LAYOUT/topic" "$LAYOUT/topic")" run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$LIST" "$LIST" \
        "rename-session -t =0 widget/topic" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic")" ]
    contains "$stderr" "→ attach with: tmux attach -t widget/topic"
}

@test "--tmux: enter on a correctly named session re-tags it without renaming" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_SESSIONS="$(sessions widget/topic "" "$LAYOUT/topic")" STUB_TMUX_CLIENT=$CLIENT TMUX=stub \
        run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" \
        "set-option -t =widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -c$CLIENT -t =widget/topic")" ]
}

@test "--tmux: enter renames to <org>/<repo>/<branch> when another session has the name" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_SESSIONS="$(sessions \
        widget/topic "$TMP/other" "$TMP/other" \
        0 "$LAYOUT/topic" "$LAYOUT/topic")" STUB_TMUX_CLIENT=$CLIENT TMUX=stub \
        run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" \
        "rename-session -t =0 acme/widget/topic" \
        "set-option -t =acme/widget/topic: @wkt-worktree $LAYOUT/topic" \
        "switch-client -c$CLIENT -t =acme/widget/topic")" ]
}

@test "--tmux: enter when renaming fails warns and still switches, by the old name" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_SESSIONS="$(sessions 0 "" "$LAYOUT/topic")" STUB_TMUX_FAIL=rename-session \
        STUB_TMUX_CLIENT=$CLIENT TMUX=stub run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" \
        "rename-session -t =0 widget/topic" \
        "set-option -t =0: @wkt-worktree $LAYOUT/topic" \
        "switch-client -c$CLIENT -t =0")" ]
    contains "$stderr" "tmux didn't rename session 0 to widget/topic"
}

@test "--tmux: a detached worktree's session is named after its folder" {
    make_layout
    cd "$LAYOUT"
    wkt new -b loose >/dev/null
    git -C "$LAYOUT/loose" checkout --quiet --detach
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/loose")"
    run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "new-session -d -s widget/loose -c $LAYOUT/loose"

    : >"$STUB_TMUX_LOG"
    rm -f "${STUB_FZF_DIR:?}"/*
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/loose")"
    STUB_TMUX_SESSIONS="$(sessions 0 "$LAYOUT/loose" "$LAYOUT/loose")" run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    contains "$(tmux_calls)" "rename-session -t =0 widget/loose"
    contains "$stderr" "→ attach with: tmux attach -t widget/loose"
}

@test "--tmux: tmux failing warns and prints the path" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_FAIL=new-session TMUX=stub run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    contains "$stderr" "tmux didn't open the worktree"
}

@test "--tmux: ctrl-n makes the worktree and opens its session, with no label step" {
    make_layout
    cd "$LAYOUT"
    fzf_reply 1 0 "" ctrl-n ""
    fzf_reply 2 1 topic
    fzf_reply 3 0 main
    STUB_TMUX_CLIENT=$CLIENT TMUX=stub run --separate-stderr wkt --tmux
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(fzf_calls)" -eq 3 ]
    [ -d "$LAYOUT/topic" ]
    contains "$(tmux_calls)" "new-session -d -s widget/topic -c $LAYOUT/topic"
    [ "$(tmux_calls | tail -n 1)" = "switch-client -c$CLIENT -t =widget/topic" ]
    contains "$stderr" "opened in tmux"
}

@test "plain wkt inside tmux: enter prints the path and opens nothing" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" "" "$(picked "$LAYOUT/topic")"
    STUB_TMUX_CLIENT=$CLIENT TMUX=stub run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/topic" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST")" ]
}

@test "a worktree with a tmux session gets the circle, found as rm finds it" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    wkt new -b other >/dev/null
    STUB_TMUX_SESSIONS="$(sessions mine "$LAYOUT/topic" "$HOME" restored "" "$LAYOUT/other/src")" \
        run picker_input
    contains "$(row_for "$LAYOUT/topic")" "$ICO_OPEN"
    contains "$(row_for "$LAYOUT/other")" "$ICO_OPEN"
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"
}

@test "tmux not answering or missing: no tmux status, and no warning" {
    make_layout
    STUB_TMUX_FAIL=1 STUB_TMUX_SESSIONS="$(sessions mine "$LAYOUT/main" "$LAYOUT/main")" run picker_input
    lacks "$(row_for "$LAYOUT/main")" "$ICO_OPEN"

    cd "$LAYOUT"
    rm -f "${STUB_FZF_DIR:?}"/*
    fzf_reply 1 130
    STUB_TMUX_FAIL=1 TMUX=stub run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$stderr" ]

    rm "$STUB_BIN/tmux"
    rm -f "${STUB_FZF_DIR:?}"/*
    fzf_reply 1 130
    TMUX=stub run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$stderr" ]
}

# --- removing --------------------------------------------------------------

has_branch() { git -C "$LAYOUT" show-ref --verify --quiet "refs/heads/$1"; }
no_branch() { ! git -C "$LAYOUT" show-ref --verify --quiet "refs/heads/$1"; }

@test "ctrl-d: asks, naming the branch; y removes it as rm -b does, and the list comes back with the outcome" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 2 1 y
    fzf_reply 3 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$output" ]
    [ ! -e "$LAYOUT/topic" ]
    no_branch topic
    contains "$(fzf_args 2)" $'--prompt\nRemove topic? [y/N] '
    contains "$(fzf_args 2)" "Remove worktree"
    contains "$(fzf_args 2)" "--disabled"
    [ "$(fzf_input 3 | cut -f 4)" = "$LAYOUT/main" ]
    contains "$(fzf_args 3)" "--expect"
    contains "$(fzf_args 3)" "✓ removed topic  $LAYOUT/topic  branch deleted"
}

@test "ctrl-d: anything but y, or esc, keeps it" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 2 1 n
    fzf_reply 3 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 4 130
    fzf_reply 5 130
    run wkt
    [ "$status" -eq 130 ]
    [ "$(fzf_calls)" -eq 5 ]
    [ -d "$LAYOUT/topic" ]
    has_branch topic
    lacks "$(fzf_args 3)" "removed"
    lacks "$(fzf_args 5)" "removed"
}

@test "ctrl-d: a refusal comes back as a notice, and the picker carries on" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    wkt new -b ahead >/dev/null
    echo draft >"$LAYOUT/topic/notes.txt"
    git -C "$LAYOUT/ahead" commit --quiet --allow-empty -m work
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 2 1 y
    fzf_reply 3 0 "" ctrl-d "$(picked "$LAYOUT/main")"
    fzf_reply 4 1 y
    fzf_reply 5 0 "" ctrl-d "$(picked "$LAYOUT/ahead")"
    fzf_reply 6 1 y
    fzf_reply 7 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -z "$stderr" ]
    contains "$(fzf_args 3)" "'topic' has uncommitted changes or untracked files."
    contains "$(fzf_args 5)" "Refusing to remove the default branch's worktree."
    contains "$(fzf_args 7)" "'ahead' has commits that were never pushed."
    [ -f "$LAYOUT/topic/notes.txt" ]
    [ -d "$LAYOUT/main" ]
    [ -d "$LAYOUT/ahead" ]
}

@test "ctrl-d: a detached worktree goes by its folder, and its branch stays" {
    make_layout
    cd "$LAYOUT"
    wkt new -b loose >/dev/null
    git -C "$LAYOUT/loose" checkout --quiet --detach
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/loose")"
    fzf_reply 2 1 y
    fzf_reply 3 130
    run wkt
    [ "$status" -eq 130 ]
    contains "$(fzf_args 2)" $'--prompt\nRemove loose? [y/N] '
    [ ! -e "$LAYOUT/loose" ]
    has_branch loose
    contains "$(fzf_args 3)" "✓ removed loose"
}

@test "ctrl-d on the worktree you're in: the list comes back without it, and still works" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    cd "$LAYOUT/topic"
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 2 1 y
    fzf_reply 3 0 "" "" "$(picked "$LAYOUT/main")"
    run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ "$output" = "$LAYOUT/main" ]
    [ ! -e "$LAYOUT/topic" ]
    [ "$(fzf_input 3 | cut -f 4)" = "$LAYOUT/main" ]
    [ -z "$stderr" ]
}

@test "ctrl-d on your own tmux session: switches the picker's client away, kills the session last, and exits" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 2 1 y
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_CLIENT=$CLIENT STUB_TMUX_CURRENT=widget/topic TMUX=stub run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(fzf_calls)" -eq 2 ]
    [ ! -e "$LAYOUT/topic" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" "$CURRENT" \
        "switch-client -c$CLIENT -t =widget/main" "kill-session -t =widget/topic" "$LIST")" ]
}

@test "ctrl-d on another worktree's session: kills it and stays" {
    make_layout
    cd "$LAYOUT"
    wkt new -b topic >/dev/null
    fzf_reply 1 0 "" ctrl-d "$(picked "$LAYOUT/topic")"
    fzf_reply 2 1 y
    fzf_reply 3 130
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/topic "$LAYOUT/topic" "$LAYOUT/topic" 300)" \
        STUB_TMUX_CLIENT=$CLIENT STUB_TMUX_CURRENT=widget/main TMUX=stub run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" "$CURRENT" \
        "kill-session -t =widget/topic" "$LIST")" ]
    contains "$(fzf_args 3)" "tmux session widget/topic closed"
}

# merged_setup: worktrees fresh, never used, so merged; dirty, merged but
# with an untracked file; and open, with a pushed commit that isn't merged.
merged_setup() {
    make_layout
    cd "$LAYOUT" || return 1
    local b
    for b in fresh dirty open; do
        wkt new -b "$b" >/dev/null
    done
    echo draft >"$LAYOUT/dirty/notes.txt"
    git -C "$LAYOUT/open" commit --quiet --allow-empty -m open
    git -C "$LAYOUT/open" push --quiet -u origin open
}

plain() { sed $'s/\e\\[[0-9;]*m//g'; }

@test "ctrl-x: lists what goes and what's skipped, asks, and y removes them as rm --merged -y does" {
    merged_setup
    fzf_reply 1 0 "" ctrl-x "$(picked "$LAYOUT/main")"
    fzf_reply 2 0 y fresh
    fzf_reply 3 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    contains "$(fzf_args 2)" $'--prompt\nRemove 1 merged worktree? [y/N] '
    contains "$(fzf_args 2)" "Remove merged worktrees"
    [ "$(fzf_input 2 | plain)" = "$(printf '%s\n' "fresh  $LAYOUT/fresh" \
        "dirty  $LAYOUT/dirty  (skipped: uncommitted changes or untracked files)")" ]
    [ ! -e "$LAYOUT/fresh" ]
    no_branch fresh
    [ -d "$LAYOUT/dirty" ]
    [ -d "$LAYOUT/open" ]
    contains "$(fzf_args 3)" "✓ removed 1, skipped 1"
}

@test "ctrl-x: anything but y keeps them" {
    merged_setup
    fzf_reply 1 0 "" ctrl-x ""
    fzf_reply 2 0 n fresh
    fzf_reply 3 130
    run wkt
    [ "$status" -eq 130 ]
    [ -d "$LAYOUT/fresh" ]
    has_branch fresh
    lacks "$(fzf_args 3)" "removed"
}

@test "ctrl-x with nothing merged: says so without asking" {
    merged_setup
    wkt rm -b fresh >/dev/null
    fzf_reply 1 0 "" ctrl-x ""
    fzf_reply 2 130
    run wkt
    [ "$status" -eq 130 ]
    [ "$(fzf_calls)" -eq 2 ]
    contains "$(fzf_args 2)" "--expect"
    contains "$(fzf_args 2)" "No merged worktrees to remove; 1 skipped with uncommitted changes or untracked files"
}

@test "ctrl-x: one that git can't remove comes back as an error notice" {
    merged_setup
    git worktree lock "$LAYOUT/fresh"
    fzf_reply 1 0 "" ctrl-x ""
    fzf_reply 2 0 y fresh
    fzf_reply 3 130
    run --separate-stderr wkt
    [ "$status" -eq 130 ]
    [ -d "$LAYOUT/fresh" ]
    contains "$(fzf_args 3)" "removed 0, failed 1, skipped 1"
}

@test "ctrl-x removing your own tmux session: switches the picker's client away, kills it last, and exits" {
    merged_setup
    fzf_reply 1 0 "" ctrl-x ""
    fzf_reply 2 0 y fresh
    STUB_TMUX_SESSIONS="$(sessions_attached \
        widget/main "$LAYOUT/main" "$LAYOUT/main" 100 \
        widget/fresh "$LAYOUT/fresh" "$LAYOUT/fresh" 300)" \
        STUB_TMUX_CLIENT=$CLIENT STUB_TMUX_CURRENT=widget/fresh TMUX=stub run --separate-stderr wkt
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(fzf_calls)" -eq 2 ]
    [ ! -e "$LAYOUT/fresh" ]
    [ "$(tmux_calls)" = "$(printf '%s\n' "$WHO" "$LIST" "$LIST" "$CURRENT" \
        "switch-client -c$CLIENT -t =widget/main" "kill-session -t =widget/fresh" "$LIST")" ]
}
