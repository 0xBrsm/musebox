# Outstanding

## Backlog

- Test `install.sh` and `pair.sh` on a fresh host. The generic flow has been proven on one install, and parts of it ran by hand.
- Test pairing from both iOS and Android, and `pair.sh --install` on a host that has Bluetooth.
- Propose an optional files-only / allowlist mode upstream to facebookincubator/muse-gadget-sdk, so the fork can shrink.
- Run ShellCheck on the scripts.

## Open Questions

- How does Muse handle large inputs (hundreds of KiB) at 64 KiB per read? Untested.
- Whether Meta keeps the task side chats, and for how long.
