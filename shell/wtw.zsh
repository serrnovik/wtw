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

# Run a session script, detecting interpreter from file extension
_wtw_run_script() {
    local script_path="$1"
    [ -z "$script_path" ] && return
    [ ! -f "$script_path" ] && return
    case "$script_path" in
        *.ps1)
            # Pass the current shell's PATH so pwsh subprocess can find
            # tools like vault, kubectl, id, etc.
            PATH="$PATH" "$_wtw_pwsh" -NoLogo -File "$script_path"
            ;;
        *.zsh) source "$script_path" ;;
        *.sh)  source "$script_path" ;;
        *.bash) source "$script_path" ;;
        *)     source "$script_path" ;;  # default: try sourcing
    esac
}

# Set worktree environment variables for dev tooling integration
_wtw_export_env() {
    local wt_id="$1" wt_index="${2:-0}"
    local port_offset=$((wt_index * 100))
    # WTW-specific
    export WTW_WORKTREE_ID="$wt_id"
    export WTW_WORKTREE_INDEX="$wt_index"
    # Generic (tool-agnostic) — usable by jax, deploy scripts, any CI/build tool
    export DEV_WORKTREE_ID="$wt_id"
    export DEV_WORKTREE_INDEX="$wt_index"
    export DEV_WORKTREE_PORT_OFFSET="$port_offset"
    if [ -n "$wt_id" ]; then
        export DEV_WORKTREE_DASHED_POSTFIX="-${wt_id}"
    else
        export DEV_WORKTREE_DASHED_POSTFIX=""
    fi
}

# Go to a worktree: resolve via pwsh, cd natively, run session script + set terminal color
_wtw_go() {
    local name="$1"
    [ -z "$name" ] && echo "Usage: wtw go <name>" && return 1
    local safe_name="${name//\'/\'\\\'\'}"
    local result
    result=$("$_wtw_pwsh" -NoLogo -NoProfile -Command "
        Import-Module '${_wtw_module}' -DisableNameChecking
        Invoke-Wtw __resolve '${safe_name}' --shell zsh
    " 2>&1)
    [ $? -ne 0 ] && echo "$result" && return 1
    local path color title startup_script wt_id wt_index
    IFS=$'\t' read -r path color title startup_script wt_id wt_index <<< "$result"
    [ -z "$path" ] && echo "Could not resolve '$name'" && return 1
    cd "$path" || return 1
    # Set worktree env vars (generic + wtw-specific)
    _wtw_export_env "$wt_id" "$wt_index"
    # Set terminal color/title
    _wtw_set_terminal "$color" "$title"
    # Run session script if configured (interpreter detected from extension)
    if [ -n "$startup_script" ]; then
        _wtw_run_script "${path}/${startup_script}"
    fi
}

# Helper: build a safe pwsh argument string by quoting each arg
_wtw_quote_args() {
    local result=""
    for arg in "$@"; do
        # Escape single quotes for PowerShell
        local safe="${arg//\'/\'\'}"
        result+=" '${safe}'"
    done
    echo "$result"
}

# Main wtw function — dispatches commands
wtw() {
    case "$1" in
        go)
            shift; _wtw_go "$@" ;;
        "")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw" ;;
        # Commands that modify registry — delegate fully to pwsh
        init|add|create|remove|rm|workspace|ws|copy|sync|color|clean|install|update|skill)
            local cmd_args=$(_wtw_quote_args "$@")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw${cmd_args}"
            # Regenerate aliases after commands that change the registry
            case "$1" in
                init|add|create|remove|rm) _wtw_register_aliases ;;
            esac
            ;;
        # List — delegate to pwsh (ANSI output passes through)
        list|ls)
            local cmd_args=$(_wtw_quote_args "$@")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw${cmd_args}" ;;
        # Open — delegate to pwsh
        open)
            local cmd_args=$(_wtw_quote_args "$@")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw${cmd_args}" ;;
        # Help
        help|-h|--help)
            local cmd_args=$(_wtw_quote_args "$@")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw${cmd_args}" ;;
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
        Invoke-Wtw __aliases --shell zsh
    " 2>/dev/null) || return
    [ -z "$_wtw_output" ] && return

    # Generate a block of function definitions and eval it in the current shell
    local _wtw_defs=""
    local _wtw_a _wtw_p _wtw_c _wtw_t _wtw_s _wtw_wid _wtw_widx
    while IFS=$'\t' read -r _wtw_a _wtw_p _wtw_c _wtw_t _wtw_s _wtw_wid _wtw_widx; do
        [ -z "$_wtw_a" ] && continue
        [[ "$_wtw_a" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
        _wtw_p="${_wtw_p//\'/\'\\\'\'}"
        _wtw_c="${_wtw_c//\'/\'\\\'\'}"
        _wtw_t="${_wtw_t//\'/\'\\\'\'}"
        _wtw_s="${_wtw_s//\'/\'\\\'\'}"
        _wtw_defs+="function ${_wtw_a}() {"$'\n'
        _wtw_defs+="  cd '${_wtw_p}' || return 1"$'\n'
        _wtw_defs+="  _wtw_export_env '${_wtw_wid}' '${_wtw_widx}'"$'\n'
        _wtw_defs+="  _wtw_set_terminal '${_wtw_c}' '${_wtw_t}'"$'\n'
        if [ -n "$_wtw_s" ]; then
            _wtw_defs+="  _wtw_run_script '${_wtw_p}/${_wtw_s}'"$'\n'
        fi
        _wtw_defs+="}"$'\n'
    done <<< "$_wtw_output"

    eval "$_wtw_defs"
}

# Register aliases on load (silently)
_wtw_register_aliases 2>/dev/null
