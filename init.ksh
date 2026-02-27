# sane.ksh — modern interactive UX for ksh93u+m
#
# A pack.ksh package that provides sane defaults, a keybinding framework,
# fish-style abbreviations, fzf integration, vi mode enhancements, and
# smart cd with zoxide support.
#
# Usage (via pack.ksh):
#   pack "lane-core/sane.ksh" load=now
#
# Usage (standalone):
#   . /path/to/sane.ksh/init.ksh
#
# No func.ksh dependency. Uses only ksh93u+m builtins.

# -- Source guard -------------------------------------------------------------
[[ -n "${_SANE_KSH_INIT:-}" ]] && return 0

# -- Version check ------------------------------------------------------------
if [[ "${.sh.version}" != *93u+m* ]]; then
    print -u2 "sane.ksh: requires ksh93u+m (found: ${.sh.version})"
    return 1
fi

# -- Resolve root -------------------------------------------------------------
_SANE_ROOT=${.sh.file%/*}

# -- Read user config ---------------------------------------------------------
# Default compound — populated before user config so user can override fields
if [[ -z "${SANE+set}" ]]; then
    typeset -C SANE=(
        defaults=true
        fzf=true
        abbr_enabled=true
        vi_indicator=true
        smart_cd=true
        history_size=50000
        abbr_position=command
        fzf_cmd="fzf --height=40% --layout=reverse"
        typeset -A abbr=()
        typeset -A marks=()
    )
fi

typeset _sane_config="${XDG_CONFIG_HOME:-$HOME/.config}/ksh/sane.ksh"
[[ -f "$_sane_config" ]] && . "$_sane_config"

# Load persisted abbreviations (from sane abbr add)
typeset _sane_abbr_file="${XDG_CONFIG_HOME:-$HOME/.config}/ksh/sane/abbr.ksh"
[[ -f "$_sane_abbr_file" ]] && . "$_sane_abbr_file"
unset _sane_config _sane_abbr_file

# -- Source libraries (order matters) -----------------------------------------
for _sane_lib in hooks keys defaults vi abbr fzf cd; do
    . "${_SANE_ROOT}/lib/${_sane_lib}.ksh"
done
unset _sane_lib

# -- Apply defaults -----------------------------------------------------------
_sane_apply_defaults

# -- Initialize features ------------------------------------------------------
_sane_abbr_init
_sane_fzf_init
_sane_cd_init

# -- Wire precmd via PS1 discipline -------------------------------------------
# The .get discipline fires in the parent shell every time PS1 is expanded.
# It captures $? (the previous command's exit code) before any hook machinery
# clobbers it, then passes it through to precmd handlers as $1.
typeset -i _SANE_LAST_EXIT=0
typeset _sane_ps1_hook
function _sane_ps1_hook.get {
    _SANE_LAST_EXIT=$?
    sane_fire precmd "$_SANE_LAST_EXIT"
    .sh.value=""
}
PS1="${_sane_ps1_hook}${PS1:-\$ }"

# -- Chain DEBUG trap (preexec) -----------------------------------------------
# Capture existing trap (e.g. pure.ksh's _pure_preexec), compose with ours.
#
# Strategy: extract the action string from `trap -p DEBUG` output, then
# eval it into a wrapper function body. ksh93u+m's trap -p output is
# formatted as `trap -- 'action' DEBUG` and is designed to be eval-safe.
function _sane_preexec_handler {
    sane_fire preexec "${.sh.command:-}"
}

typeset _sane_prev_debug _sane_prev_action
_sane_prev_debug=$(trap -p DEBUG 2>/dev/null)
_sane_prev_action=''

if [[ -n "$_sane_prev_debug" && "$_sane_prev_debug" != "trap -- '' DEBUG" ]]; then
    # Extract action: strip "trap -- '" prefix and "' DEBUG" suffix.
    # The suffix strip includes the closing single quote so that an
    # embedded " DEBUG" substring in the action body cannot be matched.
    _sane_prev_action="${_sane_prev_debug#"trap -- '"}"
    _sane_prev_action="${_sane_prev_action%"' DEBUG"}"
fi

if [[ -n "$_sane_prev_action" ]]; then
    # Compose: our handler runs first, then the original action.
    # eval is safe here — the action came from trap -p which quotes properly.
    eval "function _sane_debug_composite { _sane_preexec_handler; ${_sane_prev_action}; }"
    trap '_sane_debug_composite' DEBUG
else
    trap '_sane_preexec_handler' DEBUG
fi
unset _sane_prev_debug _sane_prev_action

# -- Install KEYBD trap -------------------------------------------------------
_sane_install_keybd

# -- pack.ksh ready hook (defensive reinstall) --------------------------------
# set -o vi after plugin load can reset the KEYBD trap. If pack.ksh is
# present, reinstall on the ready event (fires after all .kshrc processing).
if typeset -f pack_hook >/dev/null 2>&1; then
    pack_hook ready _sane_install_keybd
fi

# -- FPATH + autoload ---------------------------------------------------------
FPATH="${_SANE_ROOT}/functions${FPATH:+:${FPATH}}"
autoload sane

_SANE_KSH_INIT=1
