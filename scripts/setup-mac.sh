#!/bin/bash
# DigitalShift: set up a partner's Mac for Claude Code with one line in Terminal.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/digitalshift-srl/.github/main/scripts/setup-mac.sh)"
#
# Public on purpose and holds no secrets: it installs Homebrew and the GitHub CLI, logs you in to GitHub,
# then downloads the private digitalshift-srl/claude-setup repo and runs its bootstrap.sh, which does the rest.
# Safe to run again. Needs an invite to the digitalshift-srl organisation on GitHub (ask Andrea).
set -euo pipefail

ORG=digitalshift-srl
DIR="$HOME/Developer/$ORG/claude-setup"
say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

[[ "$(uname)" == Darwin ]] || { echo "This is for macOS." >&2; exit 1; }
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew: it asks for your Mac password and to press Return (a few minutes)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x $b ]] && eval "$($b shellenv)" && break; done
  command -v brew >/dev/null 2>&1 || { echo "Homebrew didn't install. See https://brew.sh, then run this line again." >&2; exit 1; }
  line="eval \"\$($(command -v brew) shellenv)\""
  grep -qsF "$line" "$HOME/.zprofile" || printf '\n%s\n' "$line" >> "$HOME/.zprofile"
fi

command -v gh >/dev/null 2>&1 || { say "Installing the GitHub CLI"; brew install gh; }

if ! gh auth status >/dev/null 2>&1; then
  say "GitHub login: copy the code it shows, press Return, paste it in the browser and click Authorize."
  gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git >/dev/null 2>&1 || true

if ! gh repo view "$ORG/claude-setup" >/dev/null 2>&1; then
  echo "Your GitHub account ($(gh api user --jq .login)) can't see $ORG/claude-setup yet." >&2
  echo "Ask Andrea for an invite to $ORG, accept it (github.com/$ORG), then run this line again." >&2
  exit 1
fi

if [[ -d "$DIR/.git" ]]; then
  git -C "$DIR" pull -q --ff-only || true
else
  mkdir -p "$(dirname "$DIR")"
  gh repo clone "$ORG/claude-setup" "$DIR" -- -q
fi

say "Running the DigitalShift setup"
exec /bin/bash "$DIR/bootstrap.sh" "$@"
