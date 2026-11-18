#!/usr/bin/env bats

load test_helper

setup() { common_setup; }

@test "--version prints the version" {
    run wkt --version
    [ "$status" -eq 0 ]
    [ "$output" = "wkt 2.1.0" ]

    run wkt -V
    [ "$status" -eq 0 ]
    [ "$output" = "wkt 2.1.0" ]
}

@test "--help names the command it was run as" {
    ln -s wkt "$STUB_BIN/tree"
    run tree --help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Usage: tree <command> [options]" ]
    contains "$output" "WKT_ROOT"

    run wkt -h
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Usage: wkt <command> [options]" ]

    run wkt help
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Usage: wkt <command> [options]" ]
}

@test "--help mentions the picker and its theme" {
    run wkt --help
    [ "$status" -eq 0 ]
    contains "$output" "Pick, make or remove worktrees (needs fzf)"
    contains "$output" "WKT_THEME"
}

@test "command help exits 0" {
    for cmd in setup adopt new rename rm; do
        run wkt "$cmd" --help
        [ "$status" -eq 0 ]
        starts_with "${lines[0]}" "Usage: wkt $cmd"
    done
    run wkt new -h
    [ "$status" -eq 0 ]
    starts_with "${lines[0]}" "Usage: wkt new"
}

@test "errors point at help" {
    run wkt new
    [ "$status" -eq 2 ]
    contains "$output" "Branch name (-b) is required."
    contains "$output" "Run 'wkt new --help' for usage."

    run wkt bogus
    [ "$status" -eq 2 ]
    contains "$output" "Unknown command: bogus"
    contains "$output" "Run 'wkt --help' for usage."
}

@test "no arguments prints usage to stderr and exits 2" {
    unset WKT_ASSUME_TTY
    run --separate-stderr wkt
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    starts_with "$stderr" "Usage: wkt"
}

@test "unknown top-level option" {
    run wkt --frobnicate
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: --frobnicate"

    run wkt --herdr --frobnicate
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: --frobnicate"

    run wkt --herdr extra
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: extra"
}

@test "the picker: --tmux and --herdr together" {
    run wkt --tmux --herdr
    [ "$status" -eq 2 ]
    contains "$output" "--tmux and --herdr can't be used together."
    contains "$output" "Run 'wkt --help' for usage."
}

@test "--tmux and --herdr together" {
    run wkt new -b topic --tmux --herdr
    [ "$status" -eq 2 ]
    contains "$output" "--tmux and --herdr can't be used together."
    contains "$output" "Run 'wkt new --help' for usage."
}

@test "help offers --herdr, not --no-herdr" {
    local cmd
    for cmd in "" new rename rm; do
        run wkt ${cmd:+"$cmd"} --help
        [ "$status" -eq 0 ]
        lacks "$output" "--no-herdr"
    done
    contains "$(wkt --help)" "--herdr"
    contains "$(wkt --help)" "(no command) [--tmux | --herdr]"
    contains "$(wkt new --help)" "--herdr"
    contains "$(wkt new --help)" "--tmux"
    lacks "$(wkt rename --help)" "--herdr"
    lacks "$(wkt rename --help)" "--tmux"
    lacks "$(wkt rm --help)" "--herdr"
    lacks "$(wkt rm --help)" "--tmux"
    run wkt --herdr --help
    [ "$status" -eq 0 ]
    starts_with "${lines[0]}" "Usage: wkt"
}

@test "new: argument errors" {
    run wkt new -x
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: -x"

    run wkt new -b
    [ "$status" -eq 2 ]
    contains "$output" "Option -b needs a value."

    run wkt new -b topic extra
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: extra"

    run wkt new -s main
    [ "$status" -eq 2 ]
    contains "$output" "Branch name (-b) is required."
}

@test "rename: argument errors" {
    run wkt rename
    [ "$status" -eq 2 ]
    contains "$output" "New branch name (-b) is required."

    run wkt rename -q
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: -q"

    run wkt rename -b a b
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: b"

    run wkt rename -b a --herdr
    [ "$status" -eq 2 ]
    contains "$output" "rename doesn't take --herdr"

    run wkt rename -b a --tmux
    [ "$status" -eq 2 ]
    contains "$output" "rename doesn't take --tmux"
    contains "$output" "tmux session"
}

@test "rm: argument errors" {
    run wkt rm -q
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: -q"
    contains "$output" "Run 'wkt rm --help' for usage."

    run wkt rm -b
    [ "$status" -eq 2 ]
    contains "$output" "Option -b needs a value."

    run wkt rm -b a b
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: b"

    run wkt rm --herdr
    [ "$status" -eq 2 ]
    contains "$output" "rm doesn't take --herdr"

    run wkt rm -b a --tmux
    [ "$status" -eq 2 ]
    contains "$output" "rm doesn't take --tmux"

    run wkt rm --merged -f
    [ "$status" -eq 2 ]
    contains "$output" "--merged can't be used with -b or -f."

    run wkt rm -b a --merged
    [ "$status" -eq 2 ]
    contains "$output" "--merged can't be used with -b or -f."

    run wkt rm -y
    [ "$status" -eq 2 ]
    contains "$output" "-y only goes with --merged."

    run wkt rm --merged extra
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: extra"
}

@test "setup: argument errors" {
    run wkt setup
    [ "$status" -eq 2 ]
    contains "$output" "Repo URL is required."

    run wkt setup a b
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: b"

    run wkt setup -x
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: -x"
}

@test "adopt: argument errors" {
    run wkt adopt -x
    [ "$status" -eq 2 ]
    contains "$output" "Unknown option: -x"

    run wkt adopt extra
    [ "$status" -eq 2 ]
    contains "$output" "Unexpected argument: extra"
}

@test "adopt outside a repository" {
    mkdir empty && cd empty
    run wkt adopt
    [ "$status" -eq 1 ]
    contains "$output" "Not inside a Git worktree."
}

@test "new outside a repository" {
    mkdir empty && cd empty
    run wkt new -b topic
    [ "$status" -eq 1 ]
    contains "$output" "Not inside a Git repository."
}

@test "rename outside a repository" {
    mkdir empty && cd empty
    run wkt rename -b topic
    [ "$status" -eq 1 ]
    contains "$output" "Not inside a Git worktree."
}

@test "rm outside a repository" {
    mkdir empty && cd empty
    run wkt rm -b topic
    [ "$status" -eq 1 ]
    contains "$output" "Not inside a Git repository."
}

@test "output has no colour when not a terminal" {
    run wkt new
    lacks "$output" $'\e['
}

@test "the script parses" {
    run zsh -n "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "the assertion helpers fail when they should" {
    run contains "abc" "x"
    [ "$status" -ne 0 ]
    run lacks "abc" "b"
    [ "$status" -ne 0 ]
    run starts_with "abc" "b"
    [ "$status" -ne 0 ]
}
