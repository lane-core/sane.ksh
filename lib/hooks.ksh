# sane.ksh — Event hook system (pub/sub)
#
# Adapted from pack.ksh's lib/hooks.ksh. Provides the pub/sub backbone
# for precmd, preexec, chpwd, and vi-mode-change events.
#
# Hook points: precmd preexec chpwd vi-mode-change

typeset -C -A _SANE_HOOKS

# Pre-initialize all event slots so compound-associative subscript
# access never hits a missing key (triggers nounset in trap context)
for _sane_ev in precmd preexec chpwd vi-mode-change; do
    _SANE_HOOKS[$_sane_ev]=(typeset -a handlers=())
done
unset _sane_ev

# -- Register ----------------------------------------------------------------
# Usage: sane_hook <event> <func>
function sane_hook {
    typeset event="$1" func="$2"

    if [[ -z "${_SANE_HOOKS[$event]+set}" ]]; then
        _SANE_HOOKS[$event]=(typeset -a handlers=())
    fi

    # Deduplicate
    typeset -i i n
    n=${#_SANE_HOOKS[$event].handlers[@]}
    for (( i = 0; i < n; i++ )); do
        [[ "${_SANE_HOOKS[$event].handlers[i]}" == "$func" ]] && return 0
    done

    # Full reassignment (not +=) for compound-array sub-field safety
    typeset -a _cur=()
    for (( i = 0; i < n; i++ )); do
        _cur+=("${_SANE_HOOKS[$event].handlers[i]}")
    done
    _cur+=("$func")
    _SANE_HOOKS[$event]=(typeset -a handlers=("${_cur[@]}"))
}

# -- Unregister ---------------------------------------------------------------
# Usage: sane_unhook <event> <func>
function sane_unhook {
    typeset event="$1" func="$2"

    [[ -z "${_SANE_HOOKS[$event]+set}" ]] && return 0
    typeset -i n
    n=${#_SANE_HOOKS[$event].handlers[@]}
    (( n == 0 )) && return 0

    typeset -a new=()
    typeset -i i
    for (( i = 0; i < n; i++ )); do
        [[ "${_SANE_HOOKS[$event].handlers[i]}" != "$func" ]] && \
            new+=("${_SANE_HOOKS[$event].handlers[i]}")
    done

    _SANE_HOOKS[$event]=(typeset -a handlers=("${new[@]}"))
}

# -- Fire ---------------------------------------------------------------------
# Usage: sane_fire <event> [args...]
# Errors from handlers go to stderr but don't halt iteration.
function sane_fire {
    (( $# )) || return 0
    [[ -z "${_SANE_HOOKS[$1]+set}" ]] && return 0

    # Avoid typeset -i and ${#...[@]} — both trigger ksh93u+m bugs when
    # called from a DEBUG trap during compound variable assignment context.
    # The for-in pattern iterates the array directly (empty → no iterations).
    typeset _sf_h
    for _sf_h in "${_SANE_HOOKS[$1].handlers[@]}"; do
        [[ -n "$_sf_h" ]] && "$_sf_h" "${@:2}" || true
    done
}
