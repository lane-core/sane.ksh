# sane.ksh — fzf integration widgets
#
# Three widgets bound to standard keys: Ctrl-R (history), Ctrl-T (files),
# Alt-C (cd to directory). All gated on fzf being available.
#
# Terminal handoff: fzf runs inside $() command substitution within the
# KEYBD trap. ksh93's editor suspends, fzf takes over, result is captured
# and injected via _sane_inject. Ctrl-L suffix forces a redraw.

# -- Configuration -----------------------------------------------------------
typeset _SANE_FZF_CMD=''
typeset _SANE_FZF_FILE_CMD=''
typeset _SANE_FZF_DIR_CMD=''

function _sane_fzf_load_config {
    _SANE_FZF_CMD="${SANE.fzf_cmd:-fzf --height=40% --layout=reverse}"
    _SANE_FZF_FILE_CMD="${SANE.fzf_file_cmd:-}"
    _SANE_FZF_DIR_CMD="${SANE.fzf_dir_cmd:-}"

    typeset has_fd=false
    command -v fd >/dev/null 2>&1 && has_fd=true

    # Default file finder: fd if available, else find
    if [[ -z "$_SANE_FZF_FILE_CMD" ]]; then
        if [[ "$has_fd" == true ]]; then
            _SANE_FZF_FILE_CMD="fd --type f --hidden --exclude .git"
        else
            _SANE_FZF_FILE_CMD="find . -type f -not -path '*/.git/*'"
        fi
    fi

    # Default directory finder
    if [[ -z "$_SANE_FZF_DIR_CMD" ]]; then
        if [[ "$has_fd" == true ]]; then
            _SANE_FZF_DIR_CMD="fd --type d --hidden --exclude .git"
        else
            _SANE_FZF_DIR_CMD="find . -type d -not -path '*/.git/*'"
        fi
    fi
}

# -- Ctrl-R: history search --------------------------------------------------
function _sane_fzf_history {
    typeset result
    result=$(fc -lnr 1 | ${_SANE_FZF_CMD} --query="${.sh.edtext}" +m) || {
        # User cancelled — redraw
        _sane_inject $'\014'
        return
    }
    # Kill current line, inject selected command, redraw
    _sane_inject $'\025'"${result}"$'\014'
}

# -- Ctrl-T: file finder -----------------------------------------------------
function _sane_fzf_file {
    typeset result
    result=$(eval "$_SANE_FZF_FILE_CMD" | ${_SANE_FZF_CMD} -m) || {
        _sane_inject $'\014'
        return
    }
    # Quote each selected path separately (multi-select returns newline-separated)
    typeset qresult='' f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        qresult+="$(printf '%q' "$f") "
    done <<< "$result"
    qresult="${qresult% }"
    _sane_inject "${qresult}"$'\014'
}

# -- Alt-C: cd to directory ---------------------------------------------------
function _sane_fzf_cd {
    typeset result
    result=$(eval "$_SANE_FZF_DIR_CMD" | ${_SANE_FZF_CMD} +m) || {
        _sane_inject $'\014'
        return
    }
    # Kill line, inject cd command (shell-quoted for spaces), execute, redraw
    typeset qresult
    printf -v qresult '%q' "$result"
    _sane_inject $'\025'"cd ${qresult}"$'\n'
}

# -- Wire up bindings ---------------------------------------------------------
function _sane_fzf_init {
    [[ "${SANE.fzf:-true}" == false ]] && return 0
    command -v fzf >/dev/null 2>&1 || return 0

    _sane_fzf_load_config

    # Ctrl-R = \x12, Ctrl-T = \x14, Alt-C = \eC (ESC + c)
    sane_bind $'\x12' _sane_fzf_history any
    sane_bind $'\x14' _sane_fzf_file    insert
    sane_bind $'\ec'  _sane_fzf_cd      insert
}
