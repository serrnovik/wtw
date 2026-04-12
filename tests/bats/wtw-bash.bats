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

@test "no bare pwsh calls in wtw.bash (uses \$_wtw_pwsh)" {
    local bad_lines
    bad_lines=$(grep -n 'pwsh' "$SHELL_FILE" \
        | grep -Ev '^[0-9]+:[[:space:]]*#' \
        | grep -v '_wtw_pwsh=' \
        | grep -v 'command -v pwsh' \
        | grep -v '/pwsh' \
        | grep -v 'echo.*pwsh' \
        | grep -v '\$_wtw_pwsh' \
        || true)
    [ -z "$bad_lines" ]
}
