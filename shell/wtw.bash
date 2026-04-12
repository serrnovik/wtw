# wtw — bash integration
# Source this from .bashrc:  source ~/.wtw/shell/wtw.bash
# Delegates all logic to pwsh. Only cd and terminal escapes run natively.

_wtw_module="${HOME}/.wtw/module/wtw.psm1"

# Resolve pwsh path at source time
_wtw_pwsh=$(command -v pwsh 2>/dev/null || echo "pwsh")
if [ ! -x "$_wtw_pwsh" ] && [ "$_wtw_pwsh" = "pwsh" ]; then
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
    local r g b
    r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
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
        *.bash) source "$script_path" ;;
        *.sh)  source "$script_path" ;;
        *)     source "$script_path" ;;
    esac
}

# Set worktree environment variables for dev tooling integration
_wtw_export_env() {
    local wt_id="$1" wt_index="${2:-0}"
    local port_offset=$((wt_index * 100))
    export WTW_WORKTREE_ID="$wt_id"
    export WTW_WORKTREE_INDEX="$wt_index"
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
        Invoke-Wtw __resolve '${safe_name}' --shell bash
    " 2>&1)
    [ $? -ne 0 ] && echo "$result" && return 1
    local path color title startup_script wt_id wt_index
    IFS=$'\t' read -r path color title startup_script wt_id wt_index <<< "$result"
    [ -z "$path" ] && echo "Could not resolve '$name'" && return 1
    cd "$path" || return 1
    _wtw_export_env "$wt_id" "$wt_index"
    _wtw_set_terminal "$color" "$title"
    if [ -n "$startup_script" ]; then
        _wtw_run_script "${path}/${startup_script}"
    fi
}

# Helper: build a safe pwsh argument string by quoting each arg
_wtw_quote_args() {
    local result=""
    for arg in "$@"; do
        local safe="${arg//\'/\'\'}"
        result+=" '${safe}'"
    done
    echo "$result"
}

# Main wtw function
wtw() {
    case "$1" in
        go)
            shift; _wtw_go "$@" ;;
        "")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw" ;;
        init|add|create|remove|rm|workspace|ws|copy|sync|color|clean|install|update|skill)
            local cmd_args=$(_wtw_quote_args "$@")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw${cmd_args}"
            case "$1" in
                init|add|create|remove|rm) _wtw_register_aliases ;;
            esac
            ;;
        list|ls|open|help|-h|--help)
            local cmd_args=$(_wtw_quote_args "$@")
            "$_wtw_pwsh" -NoLogo -NoProfile -Command "Import-Module '${_wtw_module}' -DisableNameChecking; Invoke-Wtw${cmd_args}" ;;
        *)
            _wtw_go "$1" ;;
    esac
}

# Register aliases from the registry
_wtw_registered_aliases=()

_wtw_register_aliases() {
    [ ! -f "$_wtw_module" ] && return
    local _wtw_output
    _wtw_output=$("$_wtw_pwsh" -NoLogo -NoProfile -Command "
        Import-Module '${_wtw_module}' -DisableNameChecking
        Invoke-Wtw __aliases --shell bash
    " 2>/dev/null) || return
    [ -z "$_wtw_output" ] && return

    # Remove stale aliases
    local _wtw_new_names=()
    while IFS=$'\t' read -r _n _rest; do
        [ -n "$_n" ] && _wtw_new_names+=("$_n")
    done <<< "$_wtw_output"
    for _old in "${_wtw_registered_aliases[@]}"; do
        local _found=false
        for _new in "${_wtw_new_names[@]}"; do
            [ "$_old" = "$_new" ] && _found=true && break
        done
        $_found || unset -f "$_old" 2>/dev/null
    done
    _wtw_registered_aliases=()

    local _wtw_defs=""
    local _wtw_a _wtw_p _wtw_c _wtw_t _wtw_s _wtw_wid _wtw_widx
    while IFS=$'\t' read -r _wtw_a _wtw_p _wtw_c _wtw_t _wtw_s _wtw_wid _wtw_widx; do
        [ -z "$_wtw_a" ] && continue
        [[ "$_wtw_a" =~ ^[a-zA-Z0-9_-]+$ ]] || continue
        _wtw_p="${_wtw_p//\'/\'\\\'\'}"
        _wtw_c="${_wtw_c//\'/\'\\\'\'}"
        _wtw_t="${_wtw_t//\'/\'\\\'\'}"
        _wtw_s="${_wtw_s//\'/\'\\\'\'}"
        _wtw_defs+="${_wtw_a}() {"$'\n'
        _wtw_defs+="  cd '${_wtw_p}' || return 1"$'\n'
        _wtw_defs+="  _wtw_export_env '${_wtw_wid}' '${_wtw_widx}'"$'\n'
        _wtw_defs+="  _wtw_set_terminal '${_wtw_c}' '${_wtw_t}'"$'\n'
        if [ -n "$_wtw_s" ]; then
            _wtw_defs+="  _wtw_run_script '${_wtw_p}/${_wtw_s}'"$'\n'
        fi
        _wtw_defs+="}"$'\n'
        _wtw_registered_aliases+=("${_wtw_a}")
    done <<< "$_wtw_output"

    eval "$_wtw_defs"
}

_wtw_register_aliases 2>/dev/null
