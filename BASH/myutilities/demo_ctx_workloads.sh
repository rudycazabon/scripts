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

do_check_what_dir_this_is() {
    log_info "[work------] this directory is: $(pwd)"
}


# echo "═══════════════════════════════════════════"
# echo " Demo 1: normal exit — all contexts unwind"
# echo "═══════════════════════════════════════════"
# with ctx_logger -- \
# with ctx_timer -- \
# with ctx_env   -- \
# with ctx_tempdir -- \
# with ctx_lockfile -- \
#     do_work
# # Reset stack between demos
# _CLEANUP_STACK=()
# _CLEANUP_RUNNING=0

# with ctx_logger -- \
# with ctx_env -- \
# with ctx_timer -- \
#     do_work_then_abort_with_run
# # Reset stack between demos
# _CLEANUP_STACK=()
# _CLEANUP_RUNNING=0

# echo '========== do_work_then_abort_with_kill'
# with ctx_logger -- \
# with ctx_env -- \
# with ctx_timer -- \
#     do_work_then_abort_with_kill
# # Reset stack between demos
# _CLEANUP_STACK=()
# _CLEANUP_RUNNING=0

echo '========== testing ctx_tempdir'
with ctx_logger -- \
with ctx_tempdir -- \
    do_check_what_dir_this_is
cleanup

echo '========= testing ctx_cwd'
CTX_CWD_DIR="$HOME"
with ctx_logger -- \
with ctx_cwd -- \
    do_check_what_dir_this_is

CTX_CWD_DIR="$HOME/projects" \
with ctx_logger -- \
with ctx_cwd -- \
    do_check_what_dir_this_is
cleanup

echo '========== Usage — single directory:'
make_ctx_cwd "/var/log"

with ctx_logger -- \
with ctx_timer  -- \
"$CWD_CTX"      -- \
    do_work


echo '========== Usage — nested directories (each context independent):'
inspect_dir() {
    log_info "cwd = $(pwd)"
    run --level INFO --label "listing" -- ls -1
}

make_ctx_cwd "/var/log";  LOG_CTX="$CWD_CTX"
make_ctx_cwd "/tmp";      TMP_CTX="$CWD_CTX"

with ctx_logger -- \
"$LOG_CTX"      -- bash -c '
    log_info "inside /var/log"
    inspect_dir
'

with ctx_logger -- \
"$TMP_CTX"      -- bash -c '
    log_info "inside /tmp"
    inspect_dir
'

echo '========= Full working demo'
do_work() {
    log_info "[work] cwd     = $(pwd)"
    log_info "[work] origin  = ${_CTX_CWD_ORIGIN:-via factory}"
    run --level INFO --label "list cwd" -- ls -1
}

echo "═══════════════════════════════════════════"
echo " Variable-based ctx_cwd"
echo "═══════════════════════════════════════════"
CTX_CWD_DIR="$HOME" \
with ctx_logger  -- \
with ctx_timer   -- \
with ctx_cwd     -- \
    do_work

echo
echo "═══════════════════════════════════════════"
echo " Factory ctx_cwd — two dirs, same script"
echo "═══════════════════════════════════════════"
make_ctx_cwd "/var/log"; VAR_LOG_CTX="$CWD_CTX"
make_ctx_cwd "/tmp";     TMP_CTX="$CWD_CTX"

with ctx_logger    -- \
with ctx_timer     -- \
"$VAR_LOG_CTX"     -- \
    do_work

echo
with ctx_logger    -- \
with ctx_timer     -- \
"$TMP_CTX"         -- \
    do_work