# Environment

This file describes how the development environment is configured. Update it when tooling, auth, or workflow details change.

## Local Development

- Developed on Ubuntu 24.04 with Python 3.12. If `python3-venv`/ensurepip is missing, use `uv` (the installer puts a pinned one at `/opt/musegadget/bin/uv`).
- SDK tests: `cd src/sdk && uv run --with pytest --with . pytest`, then delete the `.venv`, `uv.lock` and `build/` they leave behind.
- Validate the plugin: `claude plugin validate .` and `claude plugin validate src/plugin`.
- Installing and pairing need root, a systemd host and (for pairing) Bluetooth LE plus the Muse app in Developer mode.

## Devcontainer

This template includes devcontainer configuration under `.devcontainer/`, but it may not be in use. Confirm whether you are running inside a devcontainer before assuming its features are available.

## Skills

- Repo-managed skills live in `agents/skills/`. Each skill is a subdirectory containing a `SKILL.md`.
- `agents/scripts/symlink-skills.sh` links them into `~/.codex/skills/` and `~/.claude/skills/`.
- If expected skills are missing from your tool's skill directory, run `bash agents/scripts/symlink-skills.sh` to restore them.
