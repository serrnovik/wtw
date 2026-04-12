#!/usr/bin/env bash
# wtw installer — macOS and Linux
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/serrnovik/wtw/main/install.sh | bash
#   wget -qO- https://raw.githubusercontent.com/serrnovik/wtw/main/install.sh | bash
set -euo pipefail

WTW_REPO="https://github.com/serrnovik/wtw.git"
WTW_DIR="${HOME}/.wtw/source"

echo ""
echo "  wtw — Git Worktree + Workspace Manager"
echo "  ───────────────────────────────────────"
echo ""

# --- Check / install git ---
if ! command -v git &>/dev/null; then
    echo "  Git is required but not found."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  Installing via Xcode Command Line Tools..."
        xcode-select --install 2>/dev/null || true
        echo ""
        echo "  After Xcode tools finish installing, re-run this script."
    elif command -v apt-get &>/dev/null; then
        echo "  Install with: sudo apt-get install git"
    elif command -v dnf &>/dev/null; then
        echo "  Install with: sudo dnf install git"
    elif command -v pacman &>/dev/null; then
        echo "  Install with: sudo pacman -S git"
    else
        echo "  Install git from: https://git-scm.com"
    fi
    echo ""
    exit 1
fi

# --- Check / install pwsh ---
if ! command -v pwsh &>/dev/null; then
    echo "  PowerShell 7+ is required but not found."
    echo ""

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &>/dev/null; then
            read -rp "  Install PowerShell via Homebrew? [Y/n]: " yn
            yn="${yn:-y}"
            if [[ "$yn" =~ ^[Yy] ]]; then
                echo "  Installing PowerShell..."
                brew install --cask powershell
            else
                echo "  Skipped. Install manually: brew install --cask powershell"
                exit 1
            fi
        else
            echo "  Install Homebrew first: https://brew.sh"
            echo "  Then run: brew install --cask powershell"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux"* ]]; then
        if command -v apt-get &>/dev/null; then
            echo "  Attempting to install PowerShell via Microsoft repository..."
            read -rp "  Install PowerShell via apt? [Y/n]: " yn
            yn="${yn:-y}"
            if [[ "$yn" =~ ^[Yy] ]]; then
                # Detect distro
                source /etc/os-release 2>/dev/null || true
                if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]]; then
                    sudo apt-get update && sudo apt-get install -y wget apt-transport-https software-properties-common
                    source /etc/os-release
                    wget -q "https://packages.microsoft.com/config/${ID}/${VERSION_ID}/packages-microsoft-prod.deb"
                    sudo dpkg -i packages-microsoft-prod.deb
                    rm packages-microsoft-prod.deb
                    sudo apt-get update
                    sudo apt-get install -y powershell
                else
                    echo "  Auto-install not supported for ${ID:-unknown}."
                    echo "  See: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
                    exit 1
                fi
            else
                echo "  Skipped."
                exit 1
            fi
        elif command -v snap &>/dev/null; then
            read -rp "  Install PowerShell via snap? [Y/n]: " yn
            yn="${yn:-y}"
            if [[ "$yn" =~ ^[Yy] ]]; then
                sudo snap install powershell --classic
            else
                echo "  Skipped."
                exit 1
            fi
        else
            echo "  See: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
            exit 1
        fi
    fi

    # Verify
    if ! command -v pwsh &>/dev/null; then
        echo ""
        echo "  PowerShell still not found. Check your PATH and try again."
        exit 1
    fi
fi

echo "  git:  $(git --version)"
echo "  pwsh: $(pwsh --version)"
echo ""

# --- Clone or update wtw ---
if [ -d "$WTW_DIR/.git" ]; then
    echo "  Updating wtw source..."
    git -C "$WTW_DIR" pull --ff-only --quiet
else
    echo "  Cloning wtw..."
    rm -rf "$WTW_DIR"
    git clone --depth 1 --quiet "$WTW_REPO" "$WTW_DIR"
fi

# --- Run wtw install via pwsh ---
echo "  Running wtw install..."
echo ""
pwsh -NoLogo -NoProfile -Command "
    Import-Module '${WTW_DIR}/wtw.psm1' -Force -DisableNameChecking
    Install-Wtw
"

echo ""
echo "  Restart your shell to activate wtw."
echo ""
