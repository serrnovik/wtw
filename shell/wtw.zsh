# wtw — zsh integration
# Source this from .zshrc:  source ~/.wtw/shell/wtw.zsh
# Delegates all logic to pwsh. Only cd and terminal escapes run natively.

_wtw_module="${HOME}/.wtw/module/wtw.psm1"

# Resolve pwsh path at source time — handles cases where pwsh is in a PATH
# segment that's set up before this file is sourced (e.g. Homebrew paths)
_wtw_pwsh=$(command -v pwsh 2>/dev/null || echo "pwsh")
if [ ! -x "$_wtw_pwsh" ] && [ "$_wtw_pwsh" = "pwsh" ]; then
    # Try common Homebrew/system locations
    for _p in /usr/local/bin/pwsh /opt/homebrew/bin/pwsh /usr/bin/pwsh /snap/bin/pwsh; do
        [ -x "$_p" ] && _wtw_pwsh="$_p" && break
    done
fi

# Terminal color: set tab color + title via escape sequences
_wtw_set_terminal() {
    local color="$1" title="$2"
    # Title — OSC 0, works nearly everywhere
    [ -n "$title" ] && printf '\e]0;%s\a' "$title"
    # Tab color
    [ -z "$color" ] && return
    local hex="${color#\#}"
    local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
    if [ -n "$TMUX" ]; then
        tmux select-pane -P "bg=default" 2>/dev/null
        tmux set-option -p pane-active-border-style "fg=#${hex}" 2>/dev/null
        tmux set-option -p pane-border-style "fg=#${hex}" 2>/dev/null
    elif [ "$TERM_PROGRAM" = "iTerm.app" ]; then
        printf '\e]6;1;bg;red;brightness;%d\a' "$r"
        printf '\e]6;1;bg;green;brightness;%d\a' "$g"
        printf '\e]6;1;bg;blue;brightness;%d\a' "$b"
    elif [ -n "$WT_SESSION" ]; then
        printf '\e]9;9;rgb:%s/%s/%s\e\\' "${hex:0:2}" "${hex:2:2}" "${hex:4:2}"
    elif [ -n "$KITTY_PID" ] || [ "$TERM_PROGRAM" = "kitty" ]; then
        printf '\e]30;#%s\a' "$hex"
    elif [ -n "$KONSOLE_VERSION" ]; then
        printf '\e]30;#%s\a' "$hex"
    fi
    # Unsupported terminals: title is already set above
}

# Go to a worktree: resolve via pwsh, cd natively, set terminal color
_wtw_go() {
    local name="$1"
    [ -z "$name" ] && echo "Usage: wtw go <name>" && return 1
    local safe_name="${name//\'/\'\\\'\'}"
    local result
    result=$("$_wtw_pwsh" -NoLogo -NoProfile -Command "
        Import-Module '${_wtw_module}' -DisableNameChecking
        Invoke-Wtw __resolve '${safe_name}'
    " 2>&1)
    [ $? -ne 0 ] && echo "$result" && return 1
    local path color title startup_script
    IFS=$'\t' read -r path color title startup_script <<< "$result"
    [ -z "$path" ] && echo "Could not resolve '$name'" && return 1
    cd "$path" || return 1
    # Always set terminal color/title natively from zsh.
    # Startup scripts are pwsh-specific (they expect a full pwsh profile environment)
    # and should not be launched from a zsh subprocess.
    _wtw_set_terminal "$color" "$title"
}

# Main wtw function — dispatches commands
wtw() {
    case "$1" in
        go)
            shift; _wtw_go "$@" ;;
        "")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw" ;;
        # Commands that modify registry — delegate fully to pwsh
        init|add|create|remove|rm|workspace|ws|copy|sync|color|clean|install|update)
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw @args" -args "$@"
            # Regenerate aliases after commands that change the registry
            case "$1" in
                init|add|create|remove|rm) _wtw_register_aliases ;;
            esac
            ;;
        # List — delegate to pwsh (ANSI output passes through)
        list|ls)
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw @args" -args "$@" ;;
        # Open — delegate to pwsh
        open)
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw @args" -args "$@" ;;
        # Help
        help|-h|--help)
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw @args" -args "$@" ;;
        # Unknown: try as implicit "go" (same as pwsh behavior)
        *)
            _wtw_go "$1" ;;
    esac
}

# Register aliases from the registry — called on shell startup and after create/remove
_wtw_register_aliases() {
    [ ! -f "$_wtw_module" ] && return
    local _wtw_output
    _wtw_output=$("$_wtw_pwsh" -NoLogo -NoProfile -Command "
        Import-Module '${_wtw_module}' -DisableNameChecking
        Invoke-Wtw __aliases
    " 2>/dev/null) || return
    [ -z "$_wtw_output" ] && return

    # Generate a block of function definitions and eval it in the current shell
    local _wtw_defs=""
    local _wtw_a _wtw_p _wtw_c _wtw_t _wtw_s
    while IFS=$'\t' read -r _wtw_a _wtw_p _wtw_c _wtw_t _wtw_s; do
        [ -z "$_wtw_a" ] && continue
        # Skip aliases with unsafe characters (only allow alphanumeric, dash, underscore)
        [[ "$_wtw_a" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
        _wtw_p="${_wtw_p//\'/\'\\\'\'}"
        _wtw_c="${_wtw_c//\'/\'\\\'\'}"
        _wtw_t="${_wtw_t//\'/\'\\\'\'}"
        _wtw_defs+="function ${_wtw_a}() {"$'\n'
        _wtw_defs+="  cd '${_wtw_p}' || return 1"$'\n'
        _wtw_defs+="  _wtw_set_terminal '${_wtw_c}' '${_wtw_t}'"$'\n'
        _wtw_defs+="}"$'\n'
    done <<< "$_wtw_output"

    eval "$_wtw_defs"
}

# Register aliases on load (silently)
_wtw_register_aliases 2>/dev/null
