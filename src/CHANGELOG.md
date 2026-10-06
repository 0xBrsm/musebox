# Changelog

Semantic versioning. Newest first.

## 0.1.0 (2026-10-05)

- Files-only SDK patch on muse-gadget-sdk `1d2cb5a`: no `system.run`, file operations confined to the box (`MUSEBOX_ROOT`), writes only to `tasks/<id>/out/`. Command descriptions tell Muse the files are on the device.
- `musebox` CLI: `run`, `new`, `send`, `wait`, `cat`, `pull`, `ls`, `rm`. Each task gets its own side chat (UUID).
- `install.sh` with `--box`, `--members`, `--start`, `--uninstall`, `--purge`; systemd sandbox drop-in.
- `pair.sh`: Bluetooth pairing on any Linux box, either local or exported to a host without Bluetooth.
- Claude Code plugin with the `musebox` dispatch skill and a marketplace manifest.
