# sane.ksh — KEYBD trap dispatcher + keybinding API
#
# Three dispatch tables (one per editing mode) plus a mode-independent
# fallback. The KEYBD trap fires every keystroke when viraw is enabled;
# we look up the current char (or accumulated sequence) and call the
# bound handler function if one exists.
#
# Handlers that need to inject multi-char strings must use the inject
# buffer (_SANE_INJECT_BUF) since .sh.edchar only processes one byte
# per KEYBD invocation. Use _sane_inject to enqueue text.

# -- Dispatch tables ----------------------------------------------------------
typeset -A _SANE_KEYS_INSERT     # vi insert / emacs mode
typeset -A _SANE_KEYS_COMMAND    # vi command mode
typeset -A _SANE_KEYS_ANY        # mode-independent

# -- Inject buffer ------------------------------------------------------------
# Handlers push here; the dispatcher drains one char per keystroke.
typeset _SANE_INJECT_BUF=''

# -- Prefix cache -------------------------------------------------------------
# Precomputed set of all strict prefixes of bound keys. Rebuilt at bind/unbind
# time so the hot path is a single O(1) hash lookup instead of an O(N) scan.
typeset -A _SANE_KEY_PREFIXES

# -- Sequence accumulator -----------------------------------------------------
typeset    _SANE_KEY_SEQ=''
typeset -F _SANE_KEY_SEQ_TIME=0
typeset -F _SANE_KEY_SEQ_TIMEOUT=0.2

# -- Previous vi mode (for change detection) ----------------------------------
typeset    _SANE_KEY_PREV_MODE=''

# -- Inject API ---------------------------------------------------------------
# Enqueue a string for injection into the editor one char at a time.
# The first char is delivered immediately via .sh.edchar; the rest is
# buffered for subsequent KEYBD invocations.
function _sane_inject {
    typeset str="$1"
    if [[ -n "$str" ]]; then
        .sh.edchar="${str:0:1}"
        _SANE_INJECT_BUF="${str:1}"
    fi
}

# -- Prefix cache rebuild -----------------------------------------------------
function _sane_rebuild_prefixes {
    _SANE_KEY_PREFIXES=()
    typeset k
    typeset -i i len
    for k in "${!_SANE_KEYS_INSERT[@]}" "${!_SANE_KEYS_COMMAND[@]}" "${!_SANE_KEYS_ANY[@]}"; do
        len=${#k}
        for (( i = 1; i < len; i++ )); do
            _SANE_KEY_PREFIXES[${k:0:i}]=1
        done
    done
}

# -- Public API ---------------------------------------------------------------
# Usage: sane_bind <key> <handler> [insert|command|any]
function sane_bind {
    typeset key="$1" handler="$2" mode="${3:-insert}"

    case "$mode" in
    insert)  _SANE_KEYS_INSERT[$key]="$handler" ;;
    command) _SANE_KEYS_COMMAND[$key]="$handler" ;;
    any)     _SANE_KEYS_ANY[$key]="$handler" ;;
    *)       print -u2 "sane: bind: unknown mode: $mode"; return 1 ;;
    esac

    _sane_rebuild_prefixes
}

# Usage: sane_unbind <key> [insert|command|any]
function sane_unbind {
    typeset key="$1" mode="${2:-insert}"

    case "$mode" in
    insert)  unset "_SANE_KEYS_INSERT[$key]" ;;
    command) unset "_SANE_KEYS_COMMAND[$key]" ;;
    any)     unset "_SANE_KEYS_ANY[$key]" ;;
    *)       print -u2 "sane: unbind: unknown mode: $mode"; return 1 ;;
    esac

    _sane_rebuild_prefixes
}

# -- KEYBD trap handler -------------------------------------------------------
# Called on every keystroke. Drains inject buffer, determines mode,
# accumulates multi-char sequences, dispatches to the right handler.
function _sane_keybd_dispatch {
    # -- Drain inject buffer (highest priority) -------------------------------
    if [[ -n "$_SANE_INJECT_BUF" ]]; then
        .sh.edchar="${_SANE_INJECT_BUF:0:1}"
        _SANE_INJECT_BUF="${_SANE_INJECT_BUF:1}"
        return
    fi

    typeset char="${.sh.edchar}"
    typeset mode

    # Detect vi mode: .sh.edmode == ESC means command mode
    if [[ "${.sh.edmode}" == $'\E' ]]; then
        mode=command
    else
        mode=insert
    fi

    # Fire vi-mode-change on transitions
    if [[ "$mode" != "$_SANE_KEY_PREV_MODE" ]]; then
        _SANE_KEY_PREV_MODE="$mode"
        _SANE_VI_MODE="$mode"
        _sane_fire vi-mode-change "$mode"
    fi

    # -- Multi-char sequence handling -----------------------------------------
    typeset -F now=$SECONDS

    # Check for timeout on pending sequence
    if [[ -n "$_SANE_KEY_SEQ" ]]; then
        if (( now - _SANE_KEY_SEQ_TIME > _SANE_KEY_SEQ_TIMEOUT )); then
            # Timed out: replay first char now, drain rest + current via inject
            typeset flush="${_SANE_KEY_SEQ:1}${char}"
            .sh.edchar="${_SANE_KEY_SEQ:0:1}"
            _SANE_KEY_SEQ=''
            _SANE_INJECT_BUF="${flush}${_SANE_INJECT_BUF}"
            return
        fi
    fi

    # Build candidate: accumulated + current
    typeset seq="${_SANE_KEY_SEQ}${char}"

    # Look up handler: mode-specific table first, then any-mode
    typeset handler="${_SANE_KEYS_ANY[$seq]:-}"
    if [[ "$mode" == insert ]]; then
        handler="${_SANE_KEYS_INSERT[$seq]:-$handler}"
    else
        handler="${_SANE_KEYS_COMMAND[$seq]:-$handler}"
    fi

    if [[ -n "$handler" ]]; then
        _SANE_KEY_SEQ=''
        .sh.edchar=''    # suppress trigger; handler overrides via _sane_inject
        "$handler"
        return
    fi

    # Check prefix cache: is this sequence worth accumulating?
    if [[ -n "${_SANE_KEY_PREFIXES[$seq]+set}" ]]; then
        _SANE_KEY_SEQ="$seq"
        _SANE_KEY_SEQ_TIME=$now
        .sh.edchar=''
        return
    fi

    # No match — replay first char now, drain rest + current via inject buffer
    if [[ -n "$_SANE_KEY_SEQ" ]]; then
        typeset flush="${_SANE_KEY_SEQ:1}${char}"
        .sh.edchar="${_SANE_KEY_SEQ:0:1}"
        _SANE_KEY_SEQ=''
        _SANE_INJECT_BUF="${flush}${_SANE_INJECT_BUF}"
        return
    fi
    # If no sequence was pending, .sh.edchar is untouched — pass through
}

# -- Install KEYBD trap -------------------------------------------------------
function _sane_install_keybd {
    trap '_sane_keybd_dispatch' KEYBD
}
