#!/usr/bin/env bats
# Tests for wtw.zsh — the zsh shell integration wrapper.
# Requires: bats-core. Tests that need zsh or pwsh skip gracefully if not installed.

SHELL_FILE="${BATS_TEST_DIRNAME}/../../shell/wtw.zsh"

@test "wtw.zsh file exists" {
    [ -f "$SHELL_FILE" ]
}

@test "wtw.zsh is valid zsh syntax" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    zsh -n "$SHELL_FILE"
}

@test "wtw.zsh defines wtw function after sourcing" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; type wtw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.zsh defines _wtw_set_terminal function" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; type _wtw_set_terminal"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.zsh defines _wtw_go function" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; type _wtw_go"
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "wtw.zsh resolves _wtw_pwsh to an executable" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; [ -x \"\$_wtw_pwsh\" ] && echo ok"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "wtw.zsh does not produce output on source" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "source '$SHELL_FILE' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "wtw with no args produces help (via pwsh)" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    command -v pwsh &>/dev/null || skip "pwsh not available"
    run zsh -c "source '$SHELL_FILE' 2>/dev/null; wtw 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree"* ]] || [[ "$output" == *"wtw"* ]]
}

@test "wtw registers native completion when compinit ran first" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -dfc "
        autoload -Uz compinit
        compinit -D
        source '$SHELL_FILE' 2>/dev/null
        print -r -- \"\${_comps[wtw]:-missing}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "_wtw_completion" ]
}

@test "wtw registers native completion when sourced before compinit" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -dfc "
        source '$SHELL_FILE' 2>/dev/null
        autoload -Uz compinit
        compinit -D
        for hook in \"\${precmd_functions[@]}\"; do
            \"\$hook\"
        done
        print -r -- \"\${_comps[wtw]:-missing}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "_wtw_completion" ]
}

@test "_wtw_set_terminal produces no visible output for unsupported terminal" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -c "
        unset TERM_PROGRAM TMUX WT_SESSION KITTY_PID KONSOLE_VERSION WEZTERM_PANE
        source '$SHELL_FILE' 2>/dev/null
        _wtw_set_terminal '#e05d44' 'test-title'
    "
    [ "$status" -eq 0 ]
    [[ ! "$output" == *"error"* ]]
    [[ ! "$output" == *"Error"* ]]
}

@test "wtw go refreshes cmux metadata after switching directories" {
    command -v zsh &>/dev/null || skip "zsh not installed"
    run zsh -dfc "
        unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID
        source '$SHELL_FILE' 2>/dev/null
        function cmux() { return 0 }
        typeset -gi mock_apply_count=0
        function mock_pwsh() {
            if [[ \"\$*\" == *'__resolve'* ]]; then
                print -r -- \"\$PWD\"\$'\\t''#e05d44'\$'\\t''demo/feature'\$'\\t\\t''feature'\$'\\t''1'
            elif [[ \"\$*\" == *'__cmux_apply_current'* ]]; then
                (( mock_apply_count++ ))
            fi
        }
        _wtw_pwsh=mock_pwsh
        export CMUX_WORKSPACE_ID='workspace:test'
        export CMUX_SURFACE_ID='surface:test'
        _wtw_go feature >/dev/null
        print -r -- \"\$mock_apply_count\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "no bare pwsh calls in wtw.zsh (uses \$_wtw_pwsh)" {
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
