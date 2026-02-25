# sane.ksh

Modern interactive UX for ksh93u+m. No external dependencies — built entirely on ksh93 primitives (KEYBD trap, discipline functions, DEBUG trap, compound variables).

ksh93u+m is the most capable Bourne-derived shell, but its stock interactive experience hasn't kept up. sane.ksh fills the gap: keybindings, abbreviations, fzf integration, vi mode awareness, and smart cd — all in ~900 lines of pure ksh.

## Install

### Via [pack.ksh](https://github.com/lane-core/pack.ksh)

```ksh
pack "lane-core/sane.ksh" load=now
```

### Standalone

```ksh
git clone https://github.com/lane-core/sane.ksh ~/.local/share/ksh/sane.ksh
echo '. ~/.local/share/ksh/sane.ksh/init.ksh' >> ~/.kshrc
```

Requires ksh93u+m. No dependency on func.ksh or any other package.

## Features

### Sane Defaults

Enabled by default (`SANE.defaults=true`):

- `set -o globstar` — `**` recursive glob
- `set -o viraw` — raw keystroke delivery (required for KEYBD trap)
- `set -o trackall` — hash all commands
- `set --nobackslashctrl` — prevent backslash eating arrow keys
- `set -o globcasedetect` — case-insensitive glob on macOS (HFS+/APFS)
- `HISTSIZE=50000`
- Aliases: `..`, `...`, `....`

### Keybinding Framework

Three dispatch tables (insert, command, any-mode) with multi-char sequence support:

```ksh
# Bind a key to a handler function
sane_bind $'\x01' my_handler insert     # Ctrl-A in insert mode

# Multi-char sequences (e.g., jk → ESC for vi users)
sane_bind "jk" _sane_vi_escape insert

# Unbind
sane_unbind $'\x01' insert
```

The KEYBD trap dispatcher uses a precomputed prefix hash for O(1) lookups on every keystroke. Multi-char sequences accumulate with a configurable timeout (default 200ms).

Handlers inject text via `_sane_inject`, which buffers multi-character strings and drains them one byte per KEYBD invocation (ksh93's `.sh.edchar` only processes one character at a time).

### Fish-Style Abbreviations

Type an abbreviation, press space or enter — the abbreviation expands inline:

```
gst<space>  →  git status
```

```ksh
# Add at runtime (persisted to ~/.config/ksh/sane/abbr.ksh)
sane abbr add gst "git status"
sane abbr add gco "git checkout"
sane abbr add gp  "git push"

# Remove
sane abbr rm gst

# List all
sane abbr list
```

By default, abbreviations only expand in command position (first word on the line). Set `SANE.abbr_position=anywhere` to expand at any position.

### fzf Integration

Three widgets, gated on `fzf` being installed:

| Binding | Widget | Behavior |
|---------|--------|----------|
| Ctrl-R | History search | Pipe history to fzf, replace line with selection |
| Ctrl-T | File finder | Pipe fd/find to fzf, insert path(s) at cursor |
| Alt-C | Directory cd | Pipe fd/find dirs to fzf, cd to selection |

Uses `fd` if available, falls back to `find`. All paths are shell-quoted for safety.

### Smart cd

Unified `cd` that replaces zoxide's shell integration:

```ksh
cd @work        # bookmark lookup
cd -2           # directory stack (2 back)
cd -            # OLDPWD (standard)
cd project      # zoxide query (frecency, if zoxide installed)
cd ./foo        # plain cd (starts with . / / or ~)
cd              # home
```

Resolution order: bookmarks → stack index → plain path → zoxide → error.

```ksh
# Manage bookmarks
sane mark add work ~/src
sane mark add dots ~/.config
sane mark rm work
sane mark list

# View directory stack
sane stack
```

Fires a `chpwd` hook on every directory change. If zoxide is installed, `zoxide add` runs in the parent shell on each cd (zero-fork — no `$()` subshell).

### Vi Mode Indicator

Tracks vi insert/command mode transitions and exposes `_SANE_VI_MODE` for prompt consumers. Fires a `vi-mode-change` hook on every transition.

```ksh
# In your prompt:
sane_hook vi-mode-change my_update_prompt

# Opt-in jk → ESC escape sequence:
sane_bind "jk" _sane_vi_escape insert
```

### Hook System

Pub/sub events for shell lifecycle:

```ksh
sane_hook precmd my_precmd_fn         # before each prompt
sane_hook preexec my_preexec_fn       # before each command
sane_hook chpwd my_chpwd_fn           # after directory change
sane_hook vi-mode-change my_mode_fn   # on vi mode transition

sane_unhook precmd my_precmd_fn       # unregister

sane hook list                        # show all registered handlers
sane hook list precmd                 # show handlers for one event
```

Chains with existing DEBUG traps (e.g., pure.ksh's preexec) rather than replacing them.

## Configuration

User config at `~/.config/ksh/sane.ksh`, sourced at init:

```ksh
SANE=(
    # Feature toggles (all default true)
    defaults=true
    fzf=true
    abbr_enabled=true
    vi_indicator=true
    smart_cd=true

    # Abbreviations
    typeset -A abbr=(
        [gst]="git status"
        [gco]="git checkout"
        [gp]="git push"
        [gl]="git log --oneline --graph"
    )

    # Directory bookmarks
    typeset -A marks=(
        [work]="$HOME/src"
        [dots]="$HOME/.config"
    )

    # Tuning
    history_size=50000
    abbr_position=command       # "command" or "anywhere"
    fzf_cmd="fzf --height=40% --layout=reverse"
    fzf_file_cmd="fd --type f --hidden --exclude .git"
    fzf_dir_cmd="fd --type d --hidden --exclude .git"
)
```

## File Layout

```
sane.ksh/
  init.ksh             Entry point: config, lib sourcing, trap wiring
  lib/
    hooks.ksh          Event hook system (precmd, preexec, chpwd, vi-mode-change)
    keys.ksh           KEYBD trap dispatcher, inject buffer, prefix cache
    defaults.ksh       Shell options, history, aliases
    vi.ksh             Vi mode indicator + jk escape
    abbr.ksh           Fish-style abbreviation expansion
    fzf.ksh            Ctrl-R/Ctrl-T/Alt-C fzf widgets
    cd.ksh             Smart cd: bookmarks, dirstack, zoxide
  functions/
    sane               CLI dispatcher (autoloaded via FPATH)
```

## Architecture

sane.ksh is built on four ksh93u+m primitives:

- **KEYBD trap** — fires every keystroke. `.sh.edchar` (mutable), `.sh.edtext`, `.sh.edcol`, `.sh.edmode`. This is the keybinding engine.
- **Discipline functions** — `.get`/`.set` on variables. A PS1 discipline gives us zero-fork precmd hooks.
- **DEBUG trap** — fires before each command. `.sh.command` available. This is the preexec hook.
- **Compound-associative arrays** — `typeset -C -A` for structured dispatch tables and hook registries.

Key design decisions:

- **Inject buffer**: `.sh.edchar` only processes one byte per KEYBD invocation. Multi-char injections (abbreviation expansion, fzf results) go through `_SANE_INJECT_BUF`, drained one byte per subsequent keystroke.
- **Prefix cache**: The KEYBD handler fires on every character. Instead of scanning all bound keys for prefix matches (O(N) per keystroke), we precompute a `_SANE_KEY_PREFIXES` hash at bind-time for O(1) lookups.
- **DEBUG trap chaining**: sane.ksh composes with existing DEBUG traps rather than replacing them, so pure.ksh's preexec timing continues to work.
- **Zero-fork zoxide**: The chpwd hook calls `command zoxide add` directly in the parent shell rather than using zoxide's standard `$(__zoxide_hook)` which forks a subshell every prompt.

## What's NOT Possible (requires C patches)

- Inline autosuggestions (ghost text rendering)
- Real-time syntax highlighting (editor has no color buffer)
- Programmable tab completion (no `complete`/`compgen` builtins)
- Completion menus/pagers (editor can't render multi-line overlays)
- Native autocd (no `command_not_found` hook)

## CLI Reference

```
sane bind <key> <handler> [mode]   Bind a key to a handler function
sane unbind <key> [mode]           Remove a keybinding
sane abbr add <name> <expansion>   Add an abbreviation
sane abbr rm <name>                Remove an abbreviation
sane abbr list                     List all abbreviations
sane mark add <name> [dir]         Bookmark a directory (default: $PWD)
sane mark rm <name>                Remove a bookmark
sane mark list                     List all bookmarks
sane stack                         Show directory stack
sane hook list [event]             Show registered hook handlers
sane help                          Show help
```

## License

MIT
