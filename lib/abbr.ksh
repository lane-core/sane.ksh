# sane.ksh — Fish-style abbreviation expansion
#
# Type an abbreviation, press space or enter → the abbreviation is
# replaced with its expansion inline. Uses the "kill and retype"
# approach: Ctrl-U clears the line, then the rebuilt line with the
# expansion is injected via _sane_inject.

typeset -A _SANE_ABBR
typeset _SANE_ABBR_POSITION=command   # cached from SANE.abbr_position at init

# -- Load abbreviations from SANE compound ------------------------------------
function _sane_abbr_load {
    [[ "${SANE.abbr_enabled:-true}" == false ]] && return 0

    # Copy user-defined abbreviations into runtime table
    typeset k
    for k in "${!SANE.abbr[@]}"; do
        _SANE_ABBR[$k]="${SANE.abbr[$k]}"
    done
}

# -- Expansion logic ----------------------------------------------------------
# Called by KEYBD handlers for space and newline. Checks the word before
# the cursor and replaces it with the expansion if found.
function _sane_abbr_expand {
    typeset trigger="${.sh.edchar}"
    typeset line="${.sh.edtext}"
    typeset -i col=${.sh.edcol}

    # Only expand when cursor is at end of a word (at EOL or before whitespace)
    if (( col < ${#line} )); then
        [[ "${line:col:1}" != ' ' ]] && { _sane_inject "$trigger"; return; }
    fi

    # Extract the word before the cursor
    typeset before="${line:0:col}"
    typeset after="${line:col}"
    typeset word="${before##* }"

    # If no word, pass through
    if [[ -z "$word" ]]; then
        _sane_inject "$trigger"
        return
    fi

    # Compute prefix (everything before the word)
    typeset prefix="${before%"$word"}"

    # Position check: if command mode, only expand the first token
    if [[ "$_SANE_ABBR_POSITION" == command ]]; then
        if [[ "$prefix" == *[! ]* ]]; then
            _sane_inject "$trigger"
            return
        fi
    fi

    # Look up the abbreviation
    if [[ -z "${_SANE_ABBR[$word]+set}" ]]; then
        _sane_inject "$trigger"
        return
    fi

    typeset expansion="${_SANE_ABBR[$word]}"

    # Rebuild the line: prefix + expansion + after
    typeset newline="${prefix}${expansion}${after}"

    # Kill line (Ctrl-U) + retype rebuilt line + trigger char
    _sane_inject $'\025'"${newline}${trigger}"
}

# -- Wire up KEYBD handlers ---------------------------------------------------
function _sane_abbr_init {
    [[ "${SANE.abbr_enabled:-true}" == false ]] && return 0

    _SANE_ABBR_POSITION="${SANE.abbr_position:-command}"
    _sane_abbr_load
    sane_bind $' ' _sane_abbr_expand insert
    sane_bind $'\n' _sane_abbr_expand insert
}

# -- Runtime add/remove -------------------------------------------------------
function _sane_abbr_add {
    typeset name="$1"; shift
    typeset expansion="$*"

    # Newlines in expansions break the inject buffer (editor submits mid-inject)
    expansion="${expansion//$'\n'/ }"

    _SANE_ABBR[$name]="$expansion"

    # Remove existing entry first to avoid duplicates in persistence file
    _sane_abbr_remove "$name"

    # Persist to user abbreviation file
    typeset abbr_file="${XDG_CONFIG_HOME:-$HOME/.config}/ksh/sane/abbr.ksh"
    [[ -d "${abbr_file%/*}" ]] || mkdir -p "${abbr_file%/*}"
    print -r -- "_SANE_ABBR[${name}]=$(printf '%q' "$expansion")" >> "$abbr_file"

    # Restore runtime entry (remove cleared it)
    _SANE_ABBR[$name]="$expansion"
}

function _sane_abbr_remove {
    typeset name="$1"
    unset "_SANE_ABBR[$name]"

    # Rewrite persistence file without this entry
    typeset abbr_file="${XDG_CONFIG_HOME:-$HOME/.config}/ksh/sane/abbr.ksh"
    [[ -f "$abbr_file" ]] || return 0
    typeset tmp="${abbr_file}.tmp"
    typeset line
    while IFS= read -r line; do
        [[ "$line" == "_SANE_ABBR\[${name}\]="* ]] && continue
        print -r -- "$line"
    done < "$abbr_file" > "$tmp"
    command mv -f "$tmp" "$abbr_file"
}

function _sane_abbr_list {
    typeset k
    for k in "${!_SANE_ABBR[@]}"; do
        printf '%-15s → %s\n' "$k" "${_SANE_ABBR[$k]}"
    done
}
