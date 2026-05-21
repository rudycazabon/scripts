#!/usr/bin/env bash
# =============================================================================
# logger.sh — robust structured logger with stdout/stderr capture
# =============================================================================
set -euo pipefail

# ── configuration (override before sourcing) ──────────────────────────────────
: "${LOG_LEVEL:=INFO}"           # TRACE|DEBUG|INFO|WARN|ERROR|FATAL
: "${LOG_FILE:=/tmp/run.log}"    # set to "" to disable file logging
: "${LOG_COLOR:=true}"           # false to strip ANSI in terminal output
: "${LOG_SHOW_CALLER:=true}"     # annotate with filename:lineno
: "${LOG_CAPTURE_TRIM:=5}"       # max captured lines shown inline (0=unlimited)

# ── internal state ────────────────────────────────────────────────────────────
declare -i _LOG_SCOPE=0          # indentation depth from ctx_logger
declare -A _LOG_LEVELS=([TRACE]=0 [DEBUG]=1 [INFO]=2 [WARN]=3 [ERROR]=4 [FATAL]=5)

# ── ANSI palette ──────────────────────────────────────────────────────────────
_C_RESET='\033[0m'
_C_BOLD='\033[1m'
_C_DIM='\033[2m'
_C_TRACE='\033[0;37m'      # grey
_C_DEBUG='\033[0;36m'      # cyan
_C_INFO='\033[0;32m'       # green
_C_WARN='\033[0;33m'       # yellow
_C_ERROR='\033[0;31m'      # red
_C_FATAL='\033[1;35m'      # bold magenta
_C_LABEL='\033[0;34m'      # blue  — for stdout label
_C_ELABEL='\033[0;31m'     # red   — for stderr label
_C_META='\033[2;37m'       # dim grey — timestamps, caller

# ── initialise log file ───────────────────────────────────────────────────────
_log_init() {
    [[ -z "$LOG_FILE" ]] && return
    mkdir -p "$(dirname "$LOG_FILE")"
    # Write a session header so tailed files are easy to navigate
    printf '# %-72s\n' "────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE"
    printf '# session started : %s  pid=%s\n' "$(date -Iseconds)" "$$"                           >> "$LOG_FILE"
    printf '# %-72s\n' "────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE"
}

# ── core emit ─────────────────────────────────────────────────────────────────
# _log_emit LEVEL message [prefix_for_extra_lines]
_log_emit() {
    local level="$1"; shift
    local msg="$1";   shift
    local continuation="${1:-}"; shift || true

    # level gate
    local lvl_num="${_LOG_LEVELS[$level]:-2}"
    local cfg_num="${_LOG_LEVELS[$LOG_LEVEL]:-2}"
    (( lvl_num < cfg_num )) && return 0

    # timestamp
    local ts; ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"

    # caller — walk the stack past _log_emit and log()
    local caller_info=""
    if [[ "$LOG_SHOW_CALLER" == "true" ]]; then
        local frame=1
        while [[ "${FUNCNAME[$frame]:-}" =~ ^(_log|log_|run_|ctx_logger|with)$ ]]; do
            (( ++frame ))
        done
        caller_info=" ${BASH_SOURCE[$frame]##*/}:${BASH_LINENO[$((frame-1))]}"
    fi

    # scope indent
    local indent; indent="$(printf '%*s' $(( _LOG_SCOPE * 2 )) '')"

    # pick colour
    local color_var="_C_${level}"
    local color="${!color_var:-}"

    # terminal line (with colour)
    local term_color="$(_ansi "$color")${_C_BOLD}[${level:0:5}]${_C_RESET}"
    [[ "$LOG_COLOR" != "true" ]] && term_color="[${level:0:5}]"
    local meta_open meta_close
    meta_open="$(_ansi "$_C_META")"; meta_close="${_C_RESET}"
    [[ "$LOG_COLOR" != "true" ]] && { meta_open=""; meta_close=""; }

    local term_line
    term_line="${meta_open}${ts}${meta_close} ${term_color} ${indent}${msg}${_C_RESET}"
    [[ -n "$caller_info" ]] && term_line+="${meta_open}${caller_info}${meta_close}"

    # plain line (no colour, for file)
    local plain_line="[${ts}] [${level:0:5}] ${indent}${msg}${caller_info}"

    # emit to stderr (terminal)
    echo -e "${term_line}" >&2

    # emit to file
    if [[ -n "$LOG_FILE" ]]; then
        echo "$plain_line" >> "$LOG_FILE"
    fi
}

# emit a continuation block (captured output lines)
_log_block() {
    local level="$1"; shift
    local stream_label="$1"; shift   # STDOUT / STDERR
    local content="$1";      shift

    [[ -z "$content" ]] && return

    local lvl_num="${_LOG_LEVELS[$level]:-2}"
    local cfg_num="${_LOG_LEVELS[$LOG_LEVEL]:-2}"
    (( lvl_num < cfg_num )) && return 0

    local ts; ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    local indent; indent="$(printf '%*s' $(( (_LOG_SCOPE+1) * 2 )) '')"

    local label_color
    [[ "$stream_label" == "STDOUT" ]] && label_color="$_C_LABEL" || label_color="$_C_ELABEL"

    local -i line_no=0 total
    total=$(echo "$content" | wc -l)
    local trimmed=false
    (( LOG_CAPTURE_TRIM > 0 && total > LOG_CAPTURE_TRIM )) && trimmed=true

    while IFS= read -r line; do
        (( ++line_no ))
        (( LOG_CAPTURE_TRIM > 0 && line_no > LOG_CAPTURE_TRIM )) && break

        local tag="${stream_label}[$(printf '%3d' $line_no)]"

        if [[ "$LOG_COLOR" == "true" ]]; then
            echo -e "$(_ansi "$_C_META")${ts}$_C_RESET $(_ansi "$label_color")${_C_BOLD}[${tag}]$_C_RESET ${indent}${line}" >&2
        else
            echo "${ts} [${tag}] ${indent}${line}" >&2
        fi
        [[ -n "$LOG_FILE" ]] && echo "[${ts}] [${tag}] ${indent}${line}" >> "$LOG_FILE"
    done <<< "$content"

    if [[ "$trimmed" == "true" ]]; then
        local omitted=$(( total - LOG_CAPTURE_TRIM ))
        _log_emit "$level" "↳ … ${omitted} more lines omitted (LOG_CAPTURE_TRIM=${LOG_CAPTURE_TRIM})"
    fi
}

# helper: conditionally emit ANSI escape
_ansi() { [[ "$LOG_COLOR" == "true" ]] && printf '%s' "$1" || true; }

# ── public log functions ──────────────────────────────────────────────────────
log_trace() { _log_emit TRACE "$*"; }
log_debug() { _log_emit DEBUG "$*"; }
log_info()  { _log_emit INFO  "$*"; }
log_warn()  { _log_emit WARN  "$*"; }
log_error() { _log_emit ERROR "$*"; }
log_fatal() { _log_emit FATAL "$*"; exit 1; }

# ── run — capture stdout+stderr, log both ─────────────────────────────────────
# Usage: run [--level LEVEL] [--label "description"] -- cmd [args...]
#        run cmd [args...]     (shorthand, level=DEBUG)
run() {
    local level="DEBUG"
    local label=""

    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --level) level="${2^^}"; shift 2 ;;
            --label) label="$2";    shift 2 ;;
            --)      shift; break  ;;
            *)       break ;;
        esac
    done

    local cmd=("$@")
    local display="${label:-${cmd[*]}}"

    _log_emit "$level" "▶ ${display}"

    # capture stdout and stderr separately, preserve exit code
    local stdout_file stderr_file
    stdout_file=$(mktemp); stderr_file=$(mktemp)

    local rc=0
    "${cmd[@]}" >"$stdout_file" 2>"$stderr_file" || rc=$?

    local stdout_content stderr_content
    stdout_content=$(cat "$stdout_file"); rm -f "$stdout_file"
    stderr_content=$(cat "$stderr_file"); rm -f "$stderr_file"

    _log_block "$level" "STDOUT" "$stdout_content"
    _log_block "$level" "STDERR" "$stderr_content"

    if (( rc == 0 )); then
        _log_emit "$level" "✔ ${display} [exit=0]"
    else
        _log_emit "ERROR" "✘ ${display} [exit=${rc}]"
    fi

    return $rc
}

# ── run_pipe — log a pipeline, capture combined output ───────────────────────
# Usage: run_pipe --label "desc" -- cmd1 \| cmd2 \| cmd3
# (pass the pipeline as a single string after --)
run_pipe() {
    local label=""
    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --label) label="$2"; shift 2 ;;
            --)      shift; break ;;
            *)       break ;;
        esac
    done
    local pipeline="$*"
    local display="${label:-${pipeline}}"

    _log_emit "DEBUG" "▶ pipeline: ${display}"

    local out err rc=0
    out=$(eval "$pipeline" 2>/tmp/_pipe_stderr.$$) || rc=$?
    err=$(cat /tmp/_pipe_stderr.$$ 2>/dev/null); rm -f /tmp/_pipe_stderr.$$

    _log_block "DEBUG" "STDOUT" "$out"
    _log_block "DEBUG" "STDERR" "$err"

    (( rc == 0 )) \
        && _log_emit "DEBUG" "✔ pipeline done [exit=0]" \
        || _log_emit "ERROR" "✘ pipeline failed [exit=${rc}]"

    return $rc
}

# ── ctx_logger — scoped logging context (integrates with with()) ──────────────
ctx_logger() {
    case "$1" in
        __setup__)
            log_info "┌─ entering scope (depth=$((_LOG_SCOPE+1)))"
            (( ++_LOG_SCOPE )) || true ;;
        __teardown__)
            (( _LOG_SCOPE-- )) || true
            log_info "└─ exiting scope (depth=${_LOG_SCOPE})" ;;
    esac
}

# ── initialise on source/run ──────────────────────────────────────────────────
_log_init

# =============================================================================
# demo — requires contextmanager.sh patterns above to be defined
# =============================================================================

# ── cleanup stack (LIFO, signal-safe) ────────────────────────────────────────
declare -a _CLEANUP_STACK=()
declare -i _CLEANUP_RUNNING=0

_push_cleanup() {
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
    _push_cleanup "$ctx_fn __teardown__"

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


# ── demo workloads ────────────────────────────────────────────────────────────
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

with ctx_logger -- task_normal; echo
with ctx_logger -- task_mixed_streams; echo
with ctx_logger -- task_failing; echo
with ctx_logger -- task_pipeline; echo

log_info "nested scopes:"
with ctx_logger -- with ctx_logger -- _inner_task

log_info "all demos complete — log written to: $LOG_FILE"