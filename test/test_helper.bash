# shellcheck shell=bash
# Shared setup: every test runs in its own temp dir with a scrubbed
# environment, a throwaway HOME and git config, and stub herdr, gh, fzf and
# defaults commands, so nothing touches a real Herdr session, GitHub,
# terminal, macOS setting or your repos.
# HERDR_TAB_ID is set to a dummy value so wkt behaves as if inside Herdr;
# tests of the outside-Herdr path unset it.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)/bin/wkt"

common_setup() {
    local name
    for name in $(compgen -e); do
        case $name in
            HERDR_* | GIT_* | GH_* | GITHUB_TOKEN | ZDOTDIR | XDG_* | WKT_* | DEV_DIR | NO_COLOR)
                unset "$name" ;;
        esac
    done

    TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    export GIT_CONFIG_NOSYSTEM=1
    cat >"$HOME/.gitconfig" <<'EOF'
[user]
    name = Test
    email = test@example.com
[init]
    defaultBranch = main
[commit]
    gpgsign = false
[advice]
    detachedHead = false
EOF

    STUB_BIN="$TMP/bin"
    mkdir -p "$STUB_BIN"
    ln -s "$SCRIPT" "$STUB_BIN/wkt"
    export HERDR_TAB_ID=stub-tab

    export STUB_HERDR_LOG="$TMP/herdr.log"
    cat >"$STUB_BIN/herdr" <<'EOF'
#!/bin/bash
if env | grep '^HERDR_' | grep -qvx 'HERDR_TAB_ID=stub-tab'; then
    echo "stub herdr: HERDR_* leaked into the environment" >&2
    exit 99
fi
printf '%s\n' "$*" >>"$STUB_HERDR_LOG"
if [[ -n ${STUB_HERDR_FAIL:-} ]]; then
    echo '{"error":"server not running"}' >&2
    exit 1
fi
EOF

    export STUB_GH_LOG="$TMP/gh.log"
    cat >"$STUB_BIN/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_GH_LOG"
if [[ $1 == pr && -n ${STUB_GH_PR:-} ]]; then
    printf '%s\n' "$STUB_GH_PR"
    exit 0
fi
exit 1
EOF

    # fzf replays $STUB_FZF_DIR/reply.<n> for call n: an exit code on the
    # first line, then fzf's stdout. See fzf_reply.
    export STUB_FZF_DIR="$TMP/fzf"
    mkdir -p "$STUB_FZF_DIR"
    cat >"$STUB_BIN/fzf" <<'EOF'
#!/bin/bash
if [[ ${1-} == --version ]]; then
    printf '%s\n' "${STUB_FZF_VERSION:-0.74.4 (stub)}"
    exit 0
fi
n=$(( $(cat "$STUB_FZF_DIR/count" 2>/dev/null || echo 0) + 1 ))
printf '%s\n' "$n" >"$STUB_FZF_DIR/count"
printf '%s\0' "$@" >"$STUB_FZF_DIR/$n.args"
if [[ -t 0 ]]; then
    : >"$STUB_FZF_DIR/$n.in"
else
    cat >"$STUB_FZF_DIR/$n.in"
fi
reply="$STUB_FZF_DIR/reply.$n"
if [[ ! -f $reply ]]; then
    echo "stub fzf: no reply for call $n" >&2
    exit 98
fi
tail -n +2 "$reply"
exit "$(head -n 1 "$reply")"
EOF
    # macOS appearance, for the picker's theme: Dark, or unset for light.
    export STUB_DEFAULTS_LOG="$TMP/defaults.log"
    cat >"$STUB_BIN/defaults" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_DEFAULTS_LOG"
[[ -n ${STUB_DEFAULTS_STYLE:-} ]] || exit 1
printf '%s\n' "$STUB_DEFAULTS_STYLE"
EOF
    chmod +x "$STUB_BIN/herdr" "$STUB_BIN/gh" "$STUB_BIN/fzf" "$STUB_BIN/defaults"
    export WKT_ASSUME_TTY=1 WKT_THEME=dark

    export PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
    local tool
    for tool in herdr gh fzf defaults; do
        if [[ "$(command -v "$tool")" != "$STUB_BIN/$tool" ]]; then
            echo "refusing to run: $tool doesn't resolve to the stub" >&2
            return 1
        fi
    done

    cd "$TMP" || return 1
}

# make_origin [<default-branch>]: a bare "remote" at $ORIGIN, named
# acme/widget, with the default branch plus 'develop' and 'feature-x'.
make_origin() {
    local default=${1:-main} src="$TMP/src"
    ORIGIN="$TMP/remotes/acme/widget.git"
    git init --quiet -b "$default" "$src"
    git -C "$src" commit --quiet --allow-empty -m "initial"
    git -C "$src" branch develop
    git -C "$src" branch feature-x
    git -C "$src" checkout --quiet develop
    git -C "$src" commit --quiet --allow-empty -m "develop work"
    git -C "$src" checkout --quiet feature-x
    git -C "$src" commit --quiet --allow-empty -m "feature work"
    git -C "$src" checkout --quiet "$default"
    mkdir -p "${ORIGIN%/*}"
    git clone --quiet --bare "$src" "$ORIGIN"
}

# make_layout: a .bare layout of $ORIGIN at $LAYOUT, made by 'setup'.
make_layout() {
    LAYOUT="$TMP/layout"
    mkdir -p "$LAYOUT"
    (cd "$LAYOUT" && wkt setup "$ORIGIN") >/dev/null 2>&1
}

# make_clone: a normal clone of $ORIGIN at $CLONE.
make_clone() {
    CLONE="$TMP/widget"
    git clone --quiet "$ORIGIN" "$CLONE"
}

rev() { git -C "$1" rev-parse "$2"; }

herdr_calls() { cat "$STUB_HERDR_LOG" 2>/dev/null || true; }

# fzf_reply <n> <code> [<line>...]: what the stub fzf does on call n.
fzf_reply() {
    local n=$1
    shift
    printf '%s\n' "$@" >"$STUB_FZF_DIR/reply.$n"
}

# fzf_args <n>: call n's arguments, one per line.
fzf_args() { tr '\0' '\n' <"$STUB_FZF_DIR/$1.args"; }

# fzf_input <n>: what call n read on stdin.
fzf_input() { cat "$STUB_FZF_DIR/$1.in"; }

fzf_calls() { cat "$STUB_FZF_DIR/count" 2>/dev/null || echo 0; }

# The last line of $output; macOS's bash 3.2 has no ${lines[-1]}.
# shellcheck disable=SC2154 # bats sets $lines
last_line() { printf '%s\n' "${lines[${#lines[@]}-1]}"; }

# Assertions. Bash 3.2 (macOS) doesn't stop a test on a failing [[ ]] that
# isn't the last command, so string checks go through functions instead.
contains() {
    [[ $1 == *"$2"* ]] && return 0
    printf 'expected to contain: %s\nactual: %s\n' "$2" "$1" >&2
    return 1
}
lacks() {
    [[ $1 != *"$2"* ]] && return 0
    printf 'expected not to contain: %s\nactual: %s\n' "$2" "$1" >&2
    return 1
}
starts_with() {
    [[ $1 == "$2"* ]] && return 0
    printf 'expected to start with: %s\nactual: %s\n' "$2" "$1" >&2
    return 1
}
