#!/usr/bin/env bash

source "./logger.sh"

# ── demo workloads ────────────────────────────────────────────────────────────
task_normal() {
    log_info "running normal commands"
    run --level INFO --label "list /etc/hosts" -- cat /etc/hosts
    run --level DEBUG                           -- echo "simple echo"
    run --level WARN  --label "disk usage"      -- df -h /
}

task_mixed_streams() {
    log_info "command that writes to both stdout and stderr"
    # writes a mix intentionally
    run --level INFO --label "mixed output script" -- bash -c '
        echo "line 1 to stdout"
        echo "warning to stderr" >&2
        echo "line 2 to stdout"
        echo "another stderr msg" >&2
        echo "final stdout line"
    '
}

task_failing() {
    log_warn "running a command expected to fail — error is captured, not fatal"
    run --level WARN --label "intentional failure" -- bash -c 'echo "before fail"; ls /nonexistent 2>&1; exit 42' || true
}

task_pipeline() {
    log_info "pipeline capture demo"
    run_pipe --label "find + count bash files" -- \
        "find /etc -maxdepth 1 -name '*.conf' 2>/dev/null | head -5 | wc -l"
}

task_nested_scope() {
    log_info "outer task begins"
    with ctx_logger -- bash -c '
        source "'"$0"'" 2>/dev/null || true   # re-source not needed — functions inherited
    ' || true
    # call inner directly since we are in-process
    _inner_task
}

_inner_task() {
    log_debug "inner task — inside nested logger scope"
    run --level DEBUG --label "hostname" -- hostname
    log_debug "inner task done"
}

# ── main demo ─────────────────────────────────────────────────────────────────
log_info "═══════════════════════════════════════════════════"
log_info " logger.sh demo"
log_info "═══════════════════════════════════════════════════"

with ctx_logger -- task_normal
echo
with ctx_logger -- task_mixed_streams
echo
with ctx_logger -- task_failing
echo
with ctx_logger -- task_pipeline
echo

log_info "nested scopes:"
with ctx_logger -- with ctx_logger -- _inner_task

log_info "all demos complete — log written to: $LOG_FILE"