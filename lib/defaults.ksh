# sane.ksh — Sane shell options, history, and editing defaults
#
# Applied when SANE.defaults != false. These are the "batteries included"
# settings that make ksh93u+m feel modern without being opinionated about
# the user's workflow.

function _sane_apply_defaults {
    [[ "${SANE.defaults:-true}" == false ]] && return 0

    # -- Shell options --------------------------------------------------------
    set -o globstar          # ** recursive glob
    set -o trackall          # hash all commands on first use
    set -o viraw             # raw keystroke delivery (KEYBD trap needs this)
    set --nobackslashctrl    # prevent backslash eating arrow keys

    # macOS: case-insensitive globbing on HFS+/APFS
    [[ "$(uname -s 2>/dev/null)" == Darwin ]] && set -o globcasedetect 2>/dev/null

    # -- History --------------------------------------------------------------
    HISTSIZE=${SANE.history_size:-50000}
    # Preserve HISTFILE if already set; default to XDG location
    if [[ -z "${HISTFILE:-}" ]]; then
        HISTFILE="${XDG_DATA_HOME:-$HOME/.local/share}/ksh/history"
        [[ -d "${HISTFILE%/*}" ]] || mkdir -p "${HISTFILE%/*}"
    fi

    # -- Convenience aliases --------------------------------------------------
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
}
