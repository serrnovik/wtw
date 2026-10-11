#!/usr/bin/env bats
# Tests for wtw.bash — the bash shell integration wrapper.
# Requires: bats-core, bash, pwsh

SHELL_FILE="${BATS_TEST_DIRNAME}/../../shell/wtw.bash"

@test "wtw.bash file exists" {
    [ -f "$SHELL_FILE" ]
}

@test "wtw.bash is valid bash syntax" {
    bash -n "$SHELL_FILE"
}

@test "wtw.bash has unix line endings" {
    ! grep -q $'\r' "$SHELL_FILE"
}

@test "wtw.bash defines wtw function after sourcing" {
    run bash -c "source '$SHELL_FILE' 2>/dev/null; type wtw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.bash defines _wtw_set_terminal function" {
    run bash -c "source '$SHELL_FILE' 2>/dev/null; type _wtw_set_terminal"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.bash defines _wtw_go function" {
    run bash -c "source '$SHELL_FILE' 2>/dev/null; type _wtw_go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.bash resolves _wtw_pwsh" {
    run bash -c "source '$SHELL_FILE' 2>/dev/null; echo \$_wtw_pwsh"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "wtw.bash does not produce output on source" {
    run bash -c "source '$SHELL_FILE' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_wtw_set_terminal produces no errors" {
    run bash -c "
        unset TERM_PROGRAM TMUX WT_SESSION KITTY_PID KONSOLE_VERSION WEZTERM_PANE
        source '$SHELL_FILE' 2>/dev/null
        _wtw_set_terminal '#e05d44' 'test-title'
    "
    [ "$status" -eq 0 ]
    [[ ! "$output" == *"error"* ]]
}

@test "wtw internal hooks and --on reach pwsh instead of implicit go" {
    run bash -c "
        unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID
        source '$SHELL_FILE' 2>/dev/null
        mock_pwsh() { printf '%s\n' \"\$*\"; }
        _wtw_pwsh=mock_pwsh
        wtw __cmux_init_current
        wtw __cmux_apply_current
        wtw __cmux_remote_shell
        wtw --on at go auth
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Invoke-Wtw '__cmux_init_current'"* ]]
    [[ "$output" == *"Invoke-Wtw '__cmux_apply_current'"* ]]
    [[ "$output" == *"Invoke-Wtw '__cmux_remote_shell'"* ]]
    [[ "$output" == *"Invoke-Wtw '--on' 'at' 'go' 'auth'"* ]]
    [[ "$output" != *"__resolve"* ]]
}

@test "wtw CLI commands and host-first shorthand reach pwsh instead of implicit go" {
    run bash -c "
        unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID
        source '$SHELL_FILE' 2>/dev/null
        mock_pwsh() {
            printf '%s\n' \"\$*\"
            [[ \"\$*\" == *'__resolve'* ]] && return 1
            return 0
        }
        _wtw_pwsh=mock_pwsh
        wtw info x
        wtw show x
        wtw host list
        wtw chatgpt
        wtw sbx demo
        wtw run list
        wtw ss
        _wtw_known_hosts=(at)
        wtw at cmux auth
        wtw zzz-not-a-command || true
        wtw go zzz-not-a-command || true
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Invoke-Wtw 'info' 'x'"* ]]
    [[ "$output" == *"Invoke-Wtw 'show' 'x'"* ]]
    [[ "$output" == *"Invoke-Wtw 'host' 'list'"* ]]
    [[ "$output" == *"Invoke-Wtw 'chatgpt'"* ]]
    [[ "$output" == *"Invoke-Wtw 'sbx' 'demo'"* ]]
    [[ "$output" == *"Invoke-Wtw 'run' 'list'"* ]]
    [[ "$output" == *"Invoke-Wtw 'ss'"* ]]
    [[ "$output" == *"Invoke-Wtw 'at' 'cmux' 'auth'"* ]]
    [[ "$output" == *"__resolve 'zzz-not-a-command'"* ]]
    [[ "$output" != *"Invoke-Wtw 'zzz-not-a-command'"* ]]
    [[ "$output" != *"Invoke-Wtw 'go'"* ]]
}

_wtw_bare_pwsh_lines() {
    # Remove only quoted completion descriptions, not whole lines: a bare call
    # on the same line must still fail. Token boundaries exclude the --pwsh flag.
    sed -E "s/'--pwsh:[^']*'//g" "$@" \
        | grep -nE '(^|[^[:alnum:]_-])pwsh([^[:alnum:]_-]|$)' \
        | grep -Ev '^[0-9]+:[[:space:]]*#' \
        | grep -v '_wtw_pwsh=' \
        | grep -v 'command -v pwsh' \
        | grep -v '/pwsh' \
        | grep -v 'echo.*pwsh' \
        | grep -v '\$_wtw_pwsh' \
        || true
}

@test "no bare pwsh calls in wtw.bash (uses \$_wtw_pwsh)" {
    local bad_lines
    bad_lines=$(_wtw_bare_pwsh_lines "$SHELL_FILE")
    [ -z "$bad_lines" ]
}

@test "bash bare-pwsh detection ignores comments and completion text" {
    local bad_lines
    bad_lines=$(printf '%s\n' \
        '    # Pass the current shell PATH so pwsh subprocess can find tools' \
        $'\t# must reach pwsh. Implicit go would treat them as worktree names.' \
        'host|self) flags="--wtw --pwsh --yes" ;;' \
        "    '--pwsh:remote pwsh path'" \
        | _wtw_bare_pwsh_lines)
    [ -z "$bad_lines" ]
}

@test "bash bare-pwsh detection still rejects executable calls" {
    local sample bad_lines
    for sample in \
        'pwsh' \
        '    pwsh -NoProfile -Command true' \
        'result=$(pwsh -NoProfile -Command true)' \
        'PATH="$PATH" pwsh -NoProfile' \
        'true && pwsh -NoProfile' \
        'pwsh --pwsh' \
        'flags="--pwsh"; pwsh -NoProfile' \
        "options=('--pwsh:remote pwsh path'); pwsh -NoProfile"
    do
        bad_lines=$(_wtw_bare_pwsh_lines <<< "$sample")
        [ -n "$bad_lines" ]
    done
}
