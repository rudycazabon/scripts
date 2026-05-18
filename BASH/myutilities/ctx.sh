#!/usr/bin/env bash
set -euo pipefail

# ── cleanup stack (LIFO, signal-safe) ────────────────────────────────────────
declare -a _CLEANUP_STACK=()
declare -i _CLEANUP_RUNNING=0

push_cleanup() {
    _CLEANUP_STACK+=("$*")
}

_run_cleanups() {
    [[ $_CLEANUP_RUNNING -eq 1 ]] && return
    _CLEANUP_RUNNING=1
    local i
    for (( i=${#_CLEANUP_STACK[@]}-1; i>=0; i-- )); do
        eval "${_CLEANUP_STACK[$i]}" || true
    done
}

trap '_run_cleanups' EXIT
trap '_run_cleanups; trap - INT;  kill -INT  $$' INT
trap '_run_cleanups; trap - TERM; kill -TERM $$' TERM
trap '_run_cleanups; trap - HUP;  kill -HUP  $$' HUP

# ── with() dispatcher ─────────────────────────────────────────────────────────
# Usage: with <ctx_fn> [-- <body_fn> [args...]]
# Contexts nest cleanly: with ctx_a -- with ctx_b -- body
with() {
    local ctx_fn="$1"; shift
    [[ "${1:-}" == "--" ]] && shift

    "$ctx_fn" __setup__

    # Register teardown on the cleanup stack so signals also trigger it
    push_cleanup "$ctx_fn __teardown__"

    if [[ $# -gt 0 ]]; then
        "$@"
        local exit_code=$?

        # Explicit teardown when body exits normally — pops logical scope.
        # _run_cleanups on EXIT will skip already-cleared entries.
        "$ctx_fn" __teardown__
        # Neutralise the stack entry so it doesn't double-fire
        _CLEANUP_STACK[${#_CLEANUP_STACK[@]}-1]="true"

        return $exit_code
    fi
    # No body supplied — caller manages scope manually
}

# ── context: managed temp directory ──────────────────────────────────────────
ctx_tempdir() {
    case "$1" in
        __setup__)
            TEMPDIR=$(mktemp -d)
            export TEMPDIR
            echo "[ctx:tempdir   ] created : $TEMPDIR" ;;
        __teardown__)
            rm -rf "$TEMPDIR"
            echo "[ctx:tempdir   ] removed : $TEMPDIR" ;;
    esac
}

# ── context: exclusive lock file ─────────────────────────────────────────────
ctx_lockfile() {
    local lock="/tmp/myapp.lock"
    case "$1" in
        __setup__)
            exec 9>"$lock"
            if ! flock -n 9; then
                echo "[ctx:lockfile  ] ERROR: failed to acquire lock — $lock" >&2
                exit 1
            fi
            echo "[ctx:lockfile  ] acquired: $lock" ;;
        __teardown__)
            flock -u 9
            rm -f "$lock"
            echo "[ctx:lockfile  ] released: $lock" ;;
    esac
}

# ── context: elapsed timer ────────────────────────────────────────────────────
ctx_timer() {
    case "$1" in
        __setup__)
            _TIMER_START=$(date +%s%N)
            echo "[ctx:timer     ] started" ;;
        __teardown__)
            local end; end=$(date +%s%N)
            local ms=$(( (end - _TIMER_START) / 1000000 ))
            echo "[ctx:timer     ] elapsed : ${ms}ms" ;;
    esac
}

# ── context: scoped ENV override ─────────────────────────────────────────────
ctx_env() {
    case "$1" in
        __setup__)
            _SAVED_ENV=$(env | sort)
            export APP_ENV="staging"
            export LOG_LEVEL="debug"
            echo "[ctx:env       ] overrides applied (APP_ENV=staging LOG_LEVEL=debug)" ;;
        __teardown__)
            unset APP_ENV LOG_LEVEL
            echo "[ctx:env       ] overrides cleared" ;;
    esac
}

# ── workload ──────────────────────────────────────────────────────────────────
do_work() {
    echo
    echo "[work] APP_ENV   = ${APP_ENV:-unset}"
    echo "[work] LOG_LEVEL = ${LOG_LEVEL:-unset}"
    echo "[work] writing to $TEMPDIR/output.txt"
    echo "context manager demo — $(date -Iseconds)" > "$TEMPDIR/output.txt"
    cat "$TEMPDIR/output.txt"
    sleep 0.15
    echo "[work] complete"
    echo
}

# ── simulate an abort to prove trap fires ────────────────────────────────────
do_work_then_abort() {
    do_work
    echo "[work] simulating unexpected failure..."
    kill -INT $$          # sends SIGINT to self — cleanups must still fire
}

# ── demo ──────────────────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════"
echo " Demo 1: normal exit — all contexts unwind"
echo "═══════════════════════════════════════════"
with ctx_timer -- \
with ctx_env   -- \
with ctx_tempdir -- \
with ctx_lockfile -- \
    do_work

echo
echo "═══════════════════════════════════════════"
echo " Demo 2: SIGINT mid-body — trap unwinds stack"
echo "═══════════════════════════════════════════"
# Reset stack between demos
_CLEANUP_STACK=()
_CLEANUP_RUNNING=0

with ctx_timer -- \
with ctx_tempdir -- \
with ctx_lockfile -- \
    do_work_then_abort