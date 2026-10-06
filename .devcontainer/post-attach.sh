#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if ! git config --global --get-all safe.directory | grep -Fx -- "${ROOT}" >/dev/null 2>&1; then
  git config --global --add safe.directory "${ROOT}"
fi

# Docker creates missing bind-mount parents as root, which would break CLI auth writes and the skills symlink.
sudo -n chown vscode:vscode /home/vscode/.claude /home/vscode/.codex 2>/dev/null || true

bash "${ROOT}/agents/scripts/symlink-skills.sh"
bash "${ROOT}/agents/scripts/symlink-extension-bins.sh"

if command -v gh >/dev/null 2>&1 && gh auth status -h github.com >/dev/null 2>&1; then
  gh auth setup-git >/dev/null 2>&1 || true
fi
