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
