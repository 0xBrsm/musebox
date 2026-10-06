# Overview

## Goal

Give people (and their coding agents) a safe way to hand work to their Muse
and get results back as files, without giving Muse a shell on their machine.

## Scope

- A minimal, auditable patch on Meta's Linux gadget SDK: files only, confined to one box.
- Defense in depth: path checks in code plus a systemd sandbox and a dedicated account.
- Works on any systemd Linux host. Bluetooth is only needed once for pairing, and that can happen on another machine.
- A Claude Code plugin/skill so agents know how and when to dispatch tasks, and what never to send.
- Out of scope: giving Muse a shell, network access or anything outside the box.

## Key Paths

- `src/sdk/`: Meta's `muse-gadget-sdk/linux` at `1d2cb5a`; only `executor.py`, `fileops.py` and `tests/test_executor.py` differ.
- `src/deploy/musebox-fork.patch`: that diff, for re-applying on upstream updates.
- `src/bin/musebox`: the CLI agents and people use.
- `src/deploy/install.sh`, `pair.sh`, `musebox.conf.in`: install, pairing, sandbox.
- `src/plugin/`: Claude Code plugin; `skills/musebox/SKILL.md` is the dispatch skill.
- `src/box/README.md.in`: what Muse reads first in the box.
