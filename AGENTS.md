# Agent Working Notes

musebox: a files-only drop box between a Linux machine and the user's Muse (Meta's AI assistant), plus a Claude Code skill for dispatching work to it.

This file is the entry point for agent context. It stays short and points to focused sub-documents under `agents/`. As the project grows, add detail to those files rather than expanding this one.

## About This Project

- **musebox**: Meta's Muse gadget SDK patched into a files-only drop box, with a CLI, a sandboxed systemd install, BLE pairing that works from another host, and a Claude Code plugin whose skill dispatches tasks to Muse.
- Product code is in `src/` (see `README.md`). `src/sdk/` is Meta's code: keep our changes minimal and regenerate `src/deploy/musebox-fork.patch` when you touch it.
- Run the SDK tests from `src/sdk`: `uv run --with pytest --with . pytest`.
- Anything placed in a box goes to Meta's servers. Never put secrets in test tasks.
- For library or API questions, consult up-to-date documentation tools rather than relying on training data.

## Repo Structure

| Path | Purpose |
|---|---|
| `AGENTS.md` | Agent context entry point (this file) |
| `agents/overview.md` | Project goal, scope, and key paths |
| `agents/environment.md` | Dev environment setup, auth, and tooling |
| `agents/conventions.md` | Project-level code and documentation norms |
| `agents/status.md` | Current project state and blockers |
| `agents/outstanding.md` | Backlog and open questions |
| `agents/skills/` | Repo-managed agent skills |
| `agents/scripts/` | Shared automation scripts |
| `src/` | Production application code |
| `.devcontainer/` | Optional containerized dev environment |
| `.claude-plugin/` | Claude Code marketplace manifest (plugin lives in `src/plugin/`) |

## Skills Setup

Repo-managed skills in `agents/skills/` need to be symlinked into each tool's home directory. The devcontainer does this automatically on attach. For local development, run:

```bash
bash agents/scripts/symlink-skills.sh
```
