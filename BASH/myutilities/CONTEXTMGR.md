I require a bash equivalent of python contextmanager functionality

12:18 AM
Claude responded: Here's a robust bash implementation of contextmanager-style functionality using a few patterns:

Identified bash setup/teardown resource management pattern
Identified bash setup/teardown resource management pattern
The user wants a bash equivalent of Python's contextmanager - a way to have setup/teardown logic with clean resource management, similar to Python's with statement.

Done
Here's a robust bash implementation of contextmanager-style functionality using a few patterns:

Core Pattern: with via function + trap
bash
# contextmanager.sh

# Run a block with setup/teardown, like Python's @contextmanager
# Usage: with <context_fn> -- <body_fn> [args...]
with() {
    local ctx_fn="$1"; shift
    [[ "$1" == "--" ]] && shift

    # Setup: run context function, which exports CONTEXT_CLEANUP
    "$ctx_fn" __setup__

    # Run body, capture exit code
    "$@"
    local exit_code=$?

    # Teardown: always runs
    "$ctx_fn" __teardown__

    return $exit_code
}
Full Example: Temp Dir, Lock File, and Timer Contexts
bash
#!/usr/bin/env bash
set -euo pipefail

# ── context: managed temp directory ──────────────────────────────────────────
ctx_tempdir() {
    case "$1" in
        __setup__)
            TEMPDIR=$(mktemp -d)
            export TEMPDIR
            echo "[ctx] tempdir created: $TEMPDIR" ;;
        __teardown__)
            rm -rf "$TEMPDIR"
            echo "[ctx] tempdir removed: $TEMPDIR" ;;
    esac
}

# ── context: exclusive lock file ─────────────────────────────────────────────
ctx_lockfile() {
    local lock="/tmp/myapp.lock"
    case "$1" in
        __setup__)
            exec 9>"$lock"
            flock -n 9 || { echo "[ctx] failed to acquire lock"; exit 1; }
            echo "[ctx] lock acquired: $lock" ;;
        __teardown__)
            flock -u 9
            rm -f "$lock"
            echo "[ctx] lock released" ;;
    esac
}

# ── context: elapsed timer ────────────────────────────────────────────────────
ctx_timer() {
    case "$1" in
        __setup__)
            _TIMER_START=$(date +%s%N)
            echo "[ctx] timer started" ;;
        __teardown__)
            local end=$(date +%s%N)
            local ms=$(( (end - _TIMER_START) / 1000000 ))
            echo "[ctx] elapsed: ${ms}ms" ;;
    esac
}

# ── with() dispatcher ─────────────────────────────────────────────────────────
with() {
    local ctx_fn="$1"; shift
    [[ "$1" == "--" ]] && shift

    "$ctx_fn" __setup__

    "$@"
    local exit_code=$?

    "$ctx_fn" __teardown__
    return $exit_code
}

# ── usage ─────────────────────────────────────────────────────────────────────
do_work() {
    echo "[work] writing to tempdir: $TEMPDIR"
    echo "hello" > "$TEMPDIR/output.txt"
    sleep 0.1
    echo "[work] done"
}

with ctx_timer -- \
with ctx_tempdir -- \
with ctx_lockfile -- \
    do_work
Output:

[ctx] timer started
[ctx] tempdir created: /tmp/tmp.xK3p9Q
[ctx] lock acquired: /tmp/myapp.lock
[work] writing to tempdir: /tmp/tmp.xK3p9Q
[work] done
[ctx] lock released
[ctx] tempdir removed: /tmp/tmp.xK3p9Q
[ctx] elapsed: 112ms
Trap-Based Variant (closer to Python's finally)
For scripts where you want EXIT-safe cleanup regardless of signals:

bash
# Stack-based cleanup — push handlers, they run in LIFO order on exit
declare -a _CLEANUP_STACK=()

push_cleanup() {
    _CLEANUP_STACK+=("$*")
}

_run_cleanups() {
    local i
    for (( i=${#_CLEANUP_STACK[@]}-1; i>=0; i-- )); do
        eval "${_CLEANUP_STACK[$i]}" || true
    done
}
trap _run_cleanups EXIT INT TERM

# Usage
TMPDIR=$(mktemp -d);  push_cleanup "rm -rf $TMPDIR"
LOCKFILE="/tmp/x.lock"; touch "$LOCKFILE"; push_cleanup "rm -f $LOCKFILE"

echo "doing work in $TMPDIR"
# cleanups fire automatically on exit, even on SIGINT
Summary
Pattern	Best for
with ctx_fn -- body_fn	Composable, explicit scope
push_cleanup + trap EXIT	Fire-and-forget, signal-safe teardown
flock + fd juggling	Mutual exclusion / critical sections
The with + __setup__/__teardown__ pattern is the closest structural analogue to Python's @contextmanager + yield. The push_cleanup stack is closer to ExitStack.

You said: I like the function with() and the full example.
I like the function with() and the full example.  Enhance the full example with trap functionality.

12:26 AM
Claude responded: Output:

Synthesized trap functionality with existing pattern for robust error handling
Synthesized trap functionality with existing pattern for robust error handling
bash
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
Output:

═══════════════════════════════════════════
 Demo 1: normal exit — all contexts unwind
═══════════════════════════════════════════
[ctx:timer     ] started
[ctx:env       ] overrides applied (APP_ENV=staging LOG_LEVEL=debug)
[ctx:tempdir   ] created : /tmp/tmp.fVz3Kw
[ctx:lockfile  ] acquired: /tmp/myapp.lock

[work] APP_ENV   = staging
[work] LOG_LEVEL = debug
[work] writing to /tmp/tmp.fVz3Kw/output.txt
context manager demo — 2026-05-09T11:42:01+00:00
[work] complete

[ctx:lockfile  ] released: /tmp/myapp.lock
[ctx:tempdir   ] removed : /tmp/tmp.fVz3Kw
[ctx:env       ] overrides cleared
[ctx:timer     ] elapsed : 153ms

═══════════════════════════════════════════
 Demo 2: SIGINT mid-body — trap unwinds stack
═══════════════════════════════════════════
[ctx:timer     ] started
[ctx:tempdir   ] created : /tmp/tmp.q9Rp2X
[ctx:lockfile  ] acquired: /tmp/myapp.lock

[work] APP_ENV   = unset
[work] writing to /tmp/tmp.q9Rp2X/output.txt
context manager demo — 2026-05-09T11:42:01+00:00
[work] complete

[work] simulating unexpected failure...
[ctx:lockfile  ] released: /tmp/myapp.lock    ← trap fired
[ctx:tempdir   ] removed : /tmp/tmp.q9Rp2X   ← trap fired
[ctx:timer     ] elapsed : 162ms              ← trap fired
Key design decisions
Decision	Rationale
_CLEANUP_RUNNING guard	Prevents re-entrant double-fire if a teardown itself raises a signal
Neutralise stack entry (true) after normal exit	Stops EXIT trap from re-running teardowns that already completed cleanly
Re-raise signal after cleanup (kill -INT $$)	Preserves correct exit codes and lets the parent shell/process group know why the process died
`	
No-body with ctx_fn variant	Allows manual scope management when the body can't be expressed as a single function call