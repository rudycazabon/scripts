#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "$SCRIPT_DIR/logger.sh"

do_work() {
    echo
    log_info "[work] APP_ENV   = ${APP_ENV:-unset}"
    log_info "[work] LOG_LEVEL = ${LOG_LEVEL:-unset}"
    log_info "[work] writing to $TEMPDIR/output.txt"
    log_info "context manager demo — $(date -Iseconds)" > "$TEMPDIR/output.txt"
    cat "$TEMPDIR/output.txt"
    sleep 0.15
    log_info "[work] complete"
    echo
}

# ── simulate an abort to prove trap fires ────────────────────────────────────
do_work_then_abort_with_kill() {
    # do_work
    log_info "[work] simulating unexpected failure..."
    kill -INT $$          # sends SIGINT to self — cleanups must still fire
}

do_work_then_abort_with_run() {
    # do_work
    log_info "[work] simulating unexpected failure..."
    run --level WARN --label "intentional failure" -- bash -c 'echo "before fail"; ls /nonexistent 2>&1; exit 42' || true
}

#
#echo "═══════════════════════════════════════════"
#echo " Demo 1: normal exit — all contexts unwind"
#echo "═══════════════════════════════════════════"
#with ctx_logger -- \
#with ctx_timer -- \
#with ctx_env   -- \
#with ctx_tempdir -- \
#with ctx_lockfile -- \
#    do_work

echo
echo "========== do_work_then_abort_with_run"
# Reset stack between demos
_CLEANUP_STACK=()
_CLEANUP_RUNNING=0

with ctx_logger -- \
with ctx_env -- \
with ctx_timer -- \
    do_work_then_abort_with_run

# Reset stack between demos
_CLEANUP_STACK=()
_CLEANUP_RUNNING=0

echo '========== do_work_then_abort_with_kill'
with ctx_logger -- \
with ctx_env -- \
with ctx_timer -- \
    do_work_then_abort_with_kill