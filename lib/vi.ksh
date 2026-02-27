# sane.ksh — Vi mode indicator + enhancements
#
# Exposes _SANE_VI_MODE (insert/command) for prompt consumers.
# Mode tracking is done in the KEYBD dispatcher (keys.ksh); this file
# provides the vi-specific helper functions and opt-in enhancements.

# Current vi mode — updated by _sane_keybd_dispatch on transitions
typeset _SANE_VI_MODE=insert

# -- jk/jj escape handler ----------------------------------------------------
# Opt-in: user registers via sane_bind "jk" _sane_vi_escape insert
# Switches to command mode by injecting ESC into the editor.
function _sane_vi_escape {
    sane_inject $'\E'
}

# -- Mode query ---------------------------------------------------------------
# Returns current mode as a string. Useful for prompt integration.
function _sane_vi_mode {
    print -r -- "$_SANE_VI_MODE"
}
