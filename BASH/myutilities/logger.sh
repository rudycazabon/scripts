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
    local cfg_num="${_LOG_LEVELS[$LOG_LEVEL:-INFO]:-2}"
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
# ── capture block renderer — fixed for set -e ─────────────────────────────────
_log_block() {
    local level="$1"; shift
    local stream_label="$1"; shift
    local content="$1";      shift

    [[ -z "$content" ]] && return 0

    local lvl_num="${_LOG_LEVELS[$level]:-2}"
    local cfg_num="${_LOG_LEVELS[$LOG_LEVEL:-INFO]:-2}"
    (( lvl_num < cfg_num )) && return 0

    local ts; ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    local indent; indent="$(printf '%*s' $(( (_LOG_SCOPE + 1) * 2 )) '')"

    local label_color
    [[ "$stream_label" == "STDOUT" ]] && label_color="$_C_LABEL" || label_color="$_C_ELABEL"

    local line_no=0    # plain integer — avoids -i arithmetic pitfalls
    local total; total="$(echo "$content" | wc -l)"

    while IFS= read -r line; do
        (( ++line_no ))   # <-- pre-increment: evaluates to ≥1, always exit status 0

        # trim guard: (( expr )) is safe here because it's in an && list
        (( LOG_CAPTURE_TRIM > 0 && line_no > LOG_CAPTURE_TRIM )) && break

        local tag; tag="${stream_label}[$(printf '%3d' "$line_no")]"

        if [[ "$LOG_COLOR" == "true" ]]; then
            echo -e "$(_ansi "$_C_META")${ts}${_C_RESET} $(_ansi "$label_color")${_C_BOLD}[${tag}]${_C_RESET} ${indent}${line}" >&2
        else
            echo "${ts} [${tag}] ${indent}${line}" >&2
        fi

        [[ -n "$LOG_FILE" ]] && echo "[${ts}] [${tag}] ${indent}${line}" >> "$LOG_FILE"

    done <<< "$content"

    # omission notice — guard omitted-count arithmetic the same way
    if (( LOG_CAPTURE_TRIM > 0 && total > LOG_CAPTURE_TRIM )); then
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
# ── reset stack between ctx runs ──────────────
# Reset stack between 
cleanup() {
    _CLEANUP_STACK=()
    _CLEANUP_RUNNING=0
}

# ── ctx_logger — scoped logging context (integrates with with()) ──────────────
ctx_logger() {
    case "$1" in
        __setup__)
            log_info "┌─ entering scope (depth=$((_LOG_SCOPE+1)))"
            (( _LOG_SCOPE++ )) || true ;;
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

# ── cleanup stack + with() (from contextmanager.sh) ──────────────────────────
declare -a _CLEANUP_STACK=()
declare -i _CLEANUP_RUNNING=0
declare     _CLEANUP_SOURCE="NORMAL"   # ← tracks what triggered cleanup


_push_cleanup() { _CLEANUP_STACK+=("$*"); }

_run_cleanups() {
    [[ $_CLEANUP_RUNNING -eq 1 ]] && return
    _CLEANUP_RUNNING=1

    # Only announce when a signal or unexpected EXIT actually fires live entries
    local live=0
    local i
    for (( i=0; i<${#_CLEANUP_STACK[@]}; i++ )); do
        [[ "${_CLEANUP_STACK[$i]}" != "true" ]] && (( ++live ))
    done

    if (( live > 0 )); then
        _log_emit "ERROR" "⚡ cleanup triggered by ${_CLEANUP_SOURCE} — ${live} live context(s) to unwind"
    fi

    for (( i=${#_CLEANUP_STACK[@]}-1; i>=0; i-- )); do
        if [[ "${_CLEANUP_STACK[$i]}" != "true" ]]; then
            _log_emit "WARN" "  ↳ [trap] unwinding: ${_CLEANUP_STACK[$i]}"
        fi
        eval "${_CLEANUP_STACK[$i]}" || true
    done
}

trap '_CLEANUP_SOURCE="EXIT"   _run_cleanups'                                   EXIT
trap '_CLEANUP_SOURCE="SIGINT" _run_cleanups; trap - INT;  kill -INT  $$'       INT
trap '_CLEANUP_SOURCE="SIGTERM" _run_cleanups; trap - TERM; kill -TERM $$'      TERM
trap '_CLEANUP_SOURCE="SIGHUP"  _run_cleanups; trap - HUP;  kill -HUP  $$'     HUP

# ── with() dispatcher ─────────────────────────────────────────────────────────
# Usage: with <ctx_fn> [-- <body_fn> [args...]]
# Contexts nest cleanly: with ctx_a -- with ctx_b -- body
with() {
    local ctx_fn="$1"; shift
    [[ "${1:-}" == "--" ]] && shift

    "$ctx_fn" __setup__
    _push_cleanup "$ctx_fn __teardown__"
    local my_idx=$(( ${#_CLEANUP_STACK[@]} - 1 ))  # capture MY index before nested calls shift it

    if [[ $# -gt 0 ]]; then
        "$@"
        local rc=$?
        "$ctx_fn" __teardown__
        _CLEANUP_STACK[$my_idx]="true"              # neutralise MY slot, not whatever is last
        return $rc
    fi
}
# ── context: managed temp directory ──────────────────────────────────────────
ctx_tempdir() {
    case "$1" in
        __setup__)
            TEMPDIR=$(mktemp -d)
            export TEMPDIR
            log_info "[ctx:tempdir   ] created : $TEMPDIR" ;;
        __teardown__)
            rm -rf "$TEMPDIR"
            log_info "[ctx:tempdir   ] removed : $TEMPDIR" ;;
    esac
}
# ── ctx_cwd — change into a specified directory, return on teardown ───────────
# Requires: CTX_CWD_DIR set before calling with ctx_cwd
ctx_cwd() {
    case "$1" in
        __setup__)
            # Validate
            if [[ -z "${CTX_CWD_DIR:-}" ]]; then
                log_fatal "ctx_cwd: CTX_CWD_DIR is not set"
            fi
            if [[ ! -d "$CTX_CWD_DIR" ]]; then
                log_fatal "ctx_cwd: directory does not exist: $CTX_CWD_DIR"
            fi

            # Capture origin before moving
            _CTX_CWD_ORIGIN="$(pwd)"
            export _CTX_CWD_ORIGIN

            cd "$CTX_CWD_DIR"
            log_debug "ctx_cwd: cd $CTX_CWD_DIR (was $_CTX_CWD_ORIGIN)" ;;

        __teardown__)
            cd "$_CTX_CWD_ORIGIN"
            log_debug "ctx_cwd: returned to $_CTX_CWD_ORIGIN"
            unset _CTX_CWD_ORIGIN CTX_CWD_DIR ;;
    esac
}
# ── make_ctx_cwd — returns a uniquely named context function ─────────────────
# Usage: make_ctx_cwd <directory>
# Sets: CWD_CTX (name of the generated function, pass to with())
make_ctx_cwd() {
    local target_dir="$1"
    local fn_name="_ctx_cwd_$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"

    eval "
${fn_name}() {
    local target=\"${target_dir}\"
    local origin_var=\"_CWDCTX_ORIGIN_${fn_name}\"

    case \"\$1\" in
        __setup__)
            if [[ ! -d \"\$target\" ]]; then
                log_fatal \"ctx_cwd: directory does not exist: \$target\"
            fi
            printf -v \"\$origin_var\" '%s' \"\$(pwd)\"
            export \"\$origin_var\"
            cd \"\$target\"
            log_debug \"ctx_cwd [\${fn_name}]: cd \$target (was \${!origin_var})\" ;;

        __teardown__)
            local origin=\"\${!origin_var}\"
            cd \"\$origin\"
            log_debug \"ctx_cwd [${fn_name}]: returned to \$origin\"
            unset \"\$origin_var\" ;;
    esac
}
"
    # Export name so caller can pass it to with()
    CWD_CTX="$fn_name"
    export CWD_CTX
}

# ── context: exclusive lock file ─────────────────────────────────────────────
ctx_lockfile() {
    local lock="/tmp/myapp.lock"
    case "$1" in
        __setup__)
            exec 9>"$lock"
            if ! flock -n 9; then
                log_error "[ctx:lockfile  ] ERROR: failed to acquire lock — $lock" >&2
                exit 1
            fi
            log_info "[ctx:lockfile  ] acquired: $lock" ;;
        __teardown__)
            flock -u 9
            rm -f "$lock"
            log_info "[ctx:lockfile  ] released: $lock" ;;
    esac
}

# ── context: elapsed timer ────────────────────────────────────────────────────
ctx_timer() {
    case "$1" in
        __setup__)
            _TIMER_START=$(date +%s%N)
            log_info "[ctx:timer     ] started" ;;
        __teardown__)
            local end; end=$(date +%s%N)
            local ms=$(( (end - _TIMER_START) / 1000000 ))
            log_info "[ctx:timer     ] elapsed : ${ms}ms" ;;
    esac
}

# ── context: scoped ENV override ─────────────────────────────────────────────
ctx_env() {
    case "$1" in
        __setup__)
            # Save only vars we will override — never touch logger internals
            _SAVED_APP_ENV="${APP_ENV:-}"
            _SAVED_LOG_LEVEL_ENV="${LOG_LEVEL:-}"   # save but DO NOT restore LOG_LEVEL
                                                     # — it belongs to the logger
            export APP_ENV="staging"
            # Use a separate app-level var, not LOG_LEVEL
            export APP_LOG_LEVEL="debug"
            log_info "[ctx:env       ] overrides applied (APP_ENV=staging APP_LOG_LEVEL=debug)" ;;
        __teardown__)
            [[ -n "$_SAVED_APP_ENV" ]] && export APP_ENV="$_SAVED_APP_ENV" || unset APP_ENV
            unset APP_LOG_LEVEL
            log_info "[ctx:env       ] overrides cleared" ;;
    esac
}
