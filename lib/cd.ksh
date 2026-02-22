# sane.ksh — Smart cd: bookmarks, directory stack, zoxide integration
#
# Unified cd function that handles:
#   cd @mark     → bookmark lookup
#   cd -N        → directory stack (N back)
#   cd -         → OLDPWD (standard)
#   cd ./foo     → plain cd (starts with . / / or ~)
#   cd project   → zoxide query (frecency, if installed)
#   cd           → home
#
# Resolution: bookmarks → stack → plain path → zoxide → error

typeset -a _SANE_DIRSTACK=()
typeset -A _SANE_MARKS
typeset -i _SANE_DIRSTACK_MAX=20
typeset    _SANE_HAS_ZOXIDE=false

# -- Load bookmarks from config -----------------------------------------------
function _sane_cd_load {
    typeset k
    for k in "${!SANE.marks[@]}"; do
        _SANE_MARKS[$k]="${SANE.marks[$k]}"
    done
}

# -- Push to directory stack ---------------------------------------------------
function _sane_dirstack_push {
    typeset dir="$1"
    # Don't push duplicates of the top
    (( ${#_SANE_DIRSTACK[@]} > 0 )) && \
        [[ "${_SANE_DIRSTACK[0]}" == "$dir" ]] && return

    # Prepend and cap the stack
    typeset -a new=("$dir")
    typeset -i i n=${#_SANE_DIRSTACK[@]}
    for (( i = 0; i < n && i < _SANE_DIRSTACK_MAX - 1; i++ )); do
        new+=("${_SANE_DIRSTACK[i]}")
    done
    _SANE_DIRSTACK=("${new[@]}")
}

# -- chpwd handler (registered as hook) ---------------------------------------
function _sane_chpwd_handler {
    typeset old="$1" new="$2"
    _sane_dirstack_push "$old"

    # Zero-fork zoxide add: run in parent shell, no $() subshell
    if [[ "$_SANE_HAS_ZOXIDE" == true ]]; then
        command zoxide add "$new"
    fi
}

# -- The cd replacement -------------------------------------------------------
function cd {
    typeset target="$1"
    typeset old="$PWD"

    # cd with no args → home
    if [[ -z "$target" ]]; then
        builtin cd || return
        _sane_fire chpwd "$old" "$PWD"
        return
    fi

    # cd - → OLDPWD (standard behavior)
    if [[ "$target" == - ]]; then
        builtin cd - || return
        _sane_fire chpwd "$old" "$PWD"
        return
    fi

    # cd @mark → bookmark lookup
    if [[ "$target" == @* ]]; then
        typeset mark="${target#@}"
        if [[ -n "${_SANE_MARKS[$mark]+set}" ]]; then
            builtin cd "${_SANE_MARKS[$mark]}" || return
            _sane_fire chpwd "$old" "$PWD"
            return
        fi
        print -u2 "sane: cd: unknown bookmark: @${mark}"
        return 1
    fi

    # cd -N → directory stack
    if [[ "$target" == -+([0-9]) ]]; then
        typeset -i idx="${target#-}"
        if (( idx > 0 && idx <= ${#_SANE_DIRSTACK[@]} )); then
            builtin cd "${_SANE_DIRSTACK[idx-1]}" || return
            _sane_fire chpwd "$old" "$PWD"
            return
        fi
        print -u2 "sane: cd: stack index out of range: ${target}"
        return 1
    fi

    # cd ./path, /path, ~/path → plain cd (path starts with . / / or ~)
    if [[ "$target" == .* || "$target" == /* || "$target" == '~'* ]]; then
        builtin cd "$target" || return
        _sane_fire chpwd "$old" "$PWD"
        return
    fi

    # Plain path that exists as a directory → use it directly
    if [[ -d "$target" ]]; then
        builtin cd "$target" || return
        _sane_fire chpwd "$old" "$PWD"
        return
    fi

    # Zoxide fallback: query frecency database
    if [[ "$_SANE_HAS_ZOXIDE" == true ]]; then
        typeset zdir
        zdir=$(command zoxide query -- "$target" 2>/dev/null) || {
            print -u2 "sane: cd: no match for: ${target}"
            return 1
        }
        builtin cd "$zdir" || return
        _sane_fire chpwd "$old" "$PWD"
        return
    fi

    # Nothing worked — plain cd as last resort (will produce its own error)
    builtin cd "$target" || return
    _sane_fire chpwd "$old" "$PWD"
}

# -- Bookmark management ------------------------------------------------------
function _sane_mark_add {
    typeset name="$1" dir="${2:-$PWD}"
    _SANE_MARKS[$name]="$dir"
    print "sane: bookmark @${name} → ${dir}"
}

function _sane_mark_remove {
    typeset name="$1"
    if [[ -z "${_SANE_MARKS[$name]+set}" ]]; then
        print -u2 "sane: unknown bookmark: @${name}"
        return 1
    fi
    unset "_SANE_MARKS[$name]"
    print "sane: removed bookmark @${name}"
}

function _sane_mark_list {
    typeset k
    for k in "${!_SANE_MARKS[@]}"; do
        printf '@%-12s → %s\n' "$k" "${_SANE_MARKS[$k]}"
    done
}

function _sane_dirstack_list {
    typeset -i i n=${#_SANE_DIRSTACK[@]}
    for (( i = 0; i < n; i++ )); do
        printf '  -%d  %s\n' $(( i + 1 )) "${_SANE_DIRSTACK[i]}"
    done
}

# -- Initialize ---------------------------------------------------------------
function _sane_cd_init {
    [[ "${SANE.smart_cd:-true}" == false ]] && return 0

    _sane_cd_load
    command -v zoxide >/dev/null 2>&1 && _SANE_HAS_ZOXIDE=true
    sane_hook chpwd _sane_chpwd_handler
}
