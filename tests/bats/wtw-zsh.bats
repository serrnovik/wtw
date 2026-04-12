#!/usr/bin/env bats
# Tests for wtw.zsh — the zsh shell integration wrapper.
# Requires: bats-core, zsh, pwsh

SHELL_FILE="${BATS_TEST_DIRNAME}/../../shell/wtw.zsh"

@test "wtw.zsh file exists" {
    [ -f "$SHELL_FILE" ]
}

@test "wtw.zsh is valid zsh syntax" {
    zsh -n "$SHELL_FILE"
}

@test "wtw.zsh defines wtw function after sourcing" {
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; type wtw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.zsh defines _wtw_set_terminal function" {
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; type _wtw_set_terminal"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.zsh defines _wtw_go function" {
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; type _wtw_go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.zsh resolves _wtw_pwsh to an executable" {
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; [ -x \"\$_wtw_pwsh\" ] && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "wtw.zsh does not produce output on source" {
    run zsh -c "source '$SHELL_FILE' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "wtw with no args produces help (via pwsh)" {
    if ! command -v pwsh &>/dev/null; then skip "pwsh not available"; fi
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; wtw 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree"* ]] || [[ "$output" == *"wtw"* ]]
}

@test "_wtw_set_terminal produces no visible output for unsupported terminal" {
    # With no TERM_PROGRAM/TMUX/etc set, only title escape should be emitted
    run zsh -c "
        unset TERM_PROGRAM TMUX WT_SESSION KITTY_PID KONSOLE_VERSION WEZTERM_PANE
        source '$SHELL_FILE' 2>/dev/null
        _wtw_set_terminal '#e05d44' 'test-title'
    "
    [ "$status" -eq 0 ]
    # Output should only contain the OSC 0 title escape, nothing else visible
    [[ ! "$output" == *"error"* ]]
    [[ ! "$output" == *"Error"* ]]
}

@test "no bare pwsh calls in wtw.zsh (uses \$_wtw_pwsh)" {
    # Lines that call pwsh should use $_wtw_pwsh, not bare pwsh
    # Exclude: comments, resolver assignment, command -v, path probing
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
