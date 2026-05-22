#!/usr/bin/env bash

source "./logger.sh"

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


echo "═══════════════════════════════════════════"
echo " Demo 1: normal exit — all contexts unwind"
echo "═══════════════════════════════════════════"
with ctx_logger -- \
with ctx_timer -- \
with ctx_env   -- \
with ctx_tempdir -- \
with ctx_lockfile -- \
    do_work