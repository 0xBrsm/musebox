# musebox

A drop box between a Linux machine and your Muse, Meta's AI assistant. You put
a task and some input files in a directory, Muse reads them and writes its
results back as files. Muse can read the box and write to one folder in it.
It gets no shell and sees nothing else on the machine.

```sh
id=$(musebox run q3-summary -t task.md notes.md)
musebox wait "$id"              # prints Muse's summary when it's done
musebox pull "$id" ./results    # copies the result files
```

There is also a Claude Code plugin, so a coding agent can hand work to Muse and
pick up the results the same way.

Anything you put in the box is sent to Meta. Don't use it for credentials or
for anything you wouldn't paste into the Muse app.

## Why

Meta's [Muse gadget SDK](https://github.com/facebookincubator/muse-gadget-sdk)
turns a Linux box into a gadget that Muse can control from its app. By default
that means Muse can run any shell command on the machine, with no
allowlist or approval step. It also has no way to get Muse's answer back to
the machine: replies only show up in the app.

musebox narrows the SDK to reading and writing files in one directory, and
uses files as the return channel. A script or agent can leave a task, wait,
and read the result without anyone touching a phone.

## How it works

```
/srv/musebox/
  README.md          instructions for Muse
  tasks/<id>/
    TASK.md          what to do
    MANIFEST.txt     the input files and their sizes
    in/              inputs
    out/             results, ending with DONE.md
```

`musebox send` posts a short message from the gadget into a new Muse side chat
for the task. Muse reads `TASK.md` and the inputs with the gadget's
`file.read` command, writes its results with `file.write`, and writes
`out/DONE.md` last. A simple task takes under a minute.

Muse has to type everything it writes through `file.write`, so that only works
well for small files. For anything over about 8 KiB, Muse builds the file on
its own cloud VM, uploads it to muse.ai file sharing, and lists it in
`out/LINKS.tsv`:

```
target         url                          bytes    sha256
snapshots.csv  https://muse.ai/files/...    682406   d8f99690...
```

`musebox wait` (or `musebox fetch`) downloads each link into `out/` and checks
the size and SHA-256. It only accepts `https://muse.ai/files/` links and plain
file names. The download runs on your side; the gadget itself still has no
network access. Shared links are reachable by anyone who has the URL until
they expire, about two days after upload.

## What Muse can and can't do

The SDK is patched and sandboxed in three layers:

1. The `system.run` command is removed. Muse gets `file.read`, `file.write`
   and `device.health`.
2. File operations resolve symlinks and refuse anything outside the box. Writes
   are only allowed under `tasks/<id>/out/`.
3. File operations run as a dedicated `muse` account with no sudo and no home,
   inside a systemd sandbox. `/home`, `/root`, `/mnt`, `/media` and the rest of
   `/opt` and `/srv` are hidden, and everything except the box is read-only.
   Inside the box, only `out/` folders are writable by that account.

The service itself runs as root because it holds the device keys, which is how
the upstream SDK works.

## Requirements

- Linux with systemd and Python 3.9 or later. Tested with the gadget on
  Ubuntu 24.04, paired from a Raspberry Pi 4 on Debian 12.
- The Muse app on iOS or Android, with Developer mode turned on (Settings >
  Devices).
- An SDK token from [gadgets.muse.ai](https://gadgets.muse.ai/settings/sdk-tokens).
  Meta's [Gadget SDK Terms](https://gadgets.muse.ai/sdk-terms) limit tokens to
  personal, non-commercial use with your own Muse account.
- Bluetooth LE for the one-time pairing. The machine running musebox doesn't
  need it: you can pair on any Linux box near your phone, such as a Raspberry
  Pi, and copy the result over.

## Install

```sh
git clone https://github.com/0xBrsm/musebox && cd musebox
sudo bash src/deploy/install.sh --members "$USER"
```

This creates the `muse` account and `musebox` group, the box at
`/srv/musebox` (change it with `--box DIR`), a Python venv in
`/opt/musegadget`, the `musebox` command and the systemd service. Accounts
listed in `--members` can create tasks. Rerun the same command to update.

### Pair on the same machine

If the machine has Bluetooth:

```sh
sudo bash src/deploy/pair.sh --install < token.txt
sudo bash src/deploy/install.sh --start
```

While `pair.sh` runs, open the Muse app, add a device and pick the one named
`MuseGadget…`. The window stays open for 10 minutes.

### Pair on another machine

If it doesn't, pair on a box that does (here a Pi reachable as `pi`) and move
the device state over:

```sh
d=$(ssh pi mktemp -d)
scp -rq src/sdk src/deploy/pair.sh pi:$d/
ssh pi "sudo bash $d/pair.sh --out -" < token.txt > state.tgz
ssh pi "sudo rm -r $d"
sudo tar -C /var/lib/musegadget -xzf state.tgz && shred -u state.tgz
sudo bash src/deploy/install.sh --start
```

`state.tgz` holds the device keys, so treat it like a password.

Either way, `pair.sh` builds a temporary venv and turns Bluetooth on with the
settings the Muse app needs. Afterwards it puts Bluetooth back the way it was.
When the service starts properly, `sudo journalctl -u musegadget` shows
`registered with the Muse`.

## Usage

Write the task as a short Markdown file. Muse sees nothing but this file and
the inputs, so say what each input is and which files you want back:

```markdown
# Task

in/q3-notes.md is raw meeting notes. Write out/summary.md: five bullet
points of decisions, then the action items with owners.
```

Then:

| Command | |
|---|---|
| `musebox run <name> -t TASK.md [FILE...]` | create a task and send it; prints the task id |
| `musebox new <name> [-t TASK.md] [FILE...]` | create a task without sending it |
| `musebox send <id>` | send a task created with `new` |
| `musebox wait <id> [SECONDS]` | wait for `out/DONE.md`, print it and download linked files (default timeout 30 min) |
| `musebox fetch <id>` | download the files listed in `out/LINKS.tsv` |
| `musebox cat <id> [FILE]` | list the result files, or print one |
| `musebox pull <id> DEST` | copy the result files to DEST |
| `musebox ls` | list tasks as draft, sent or done |
| `musebox rm <id>` | delete a task |

Muse writes `out/DONE.md` even when it can't finish, with the reason. Each task
gets its own side chat in the Muse app, where you can watch Muse work.

## Claude Code plugin

The plugin adds a `musebox` skill that tells a Claude Code agent when to hand
work to Muse, what it must never send, how to write a task Muse can act on, and
how to collect the results.

```
/plugin marketplace add 0xBrsm/musebox
/plugin install musebox@musebox
```

Or link the skill by hand:
`ln -s "$PWD/src/plugin/skills/musebox" ~/.claude/skills/musebox`.

## Notes

- Side-chat ids must be UUIDs. The Muse API rejects anything else with
  `invalid session_id`.
- Muse also has its own cloud VM with a shell. If a message doesn't say the
  files are on the gadget and to use its file commands, Muse searches its VM
  instead and reports the box missing. `musebox send` says so explicitly.
- The device state (`identity.json`, `pairing.json`, `sdk_token` in
  `/var/lib/musegadget`) isn't tied to the hardware, so a gadget paired on one
  machine runs fine on another.
- The Muse app sometimes drops the Bluetooth connection right after you
  confirm, then reconnects by itself.
- Muse reads files 64 KiB at a time, so very large inputs are slow. Large
  outputs come back as links instead.

## Uninstall

```sh
sudo bash src/deploy/install.sh --uninstall           # keeps the box and the pairing
sudo bash src/deploy/install.sh --uninstall --purge   # removes everything
```

Then remove the device in the Muse app.

## Repository layout

| Path | |
|---|---|
| `src/sdk/` | Meta's `muse-gadget-sdk/linux` at commit `1d2cb5a`, with the musebox patch |
| `src/deploy/musebox-fork.patch` | the patch on its own, for applying to newer SDK versions |
| `src/bin/musebox` | the command-line tool |
| `src/deploy/install.sh` | install, update and uninstall |
| `src/deploy/musebox.conf.in` | the systemd sandbox |
| `src/deploy/pair.sh` | Bluetooth pairing |
| `src/box/README.md.in` | the instructions Muse reads in the box |
| `src/plugin/` | the Claude Code plugin |
| `AGENTS.md`, `agents/` | notes for coding agents working on this repo |

To update the SDK, apply the patch to a newer checkout of its `linux/`
directory, run the tests with `uv run --with pytest --with . pytest` in
`src/sdk`, and rerun `install.sh`.

## License

Apache-2.0. `src/sdk/` is Meta's code under the same license
(`src/sdk/LICENSE`); the changed files are `executor.py`, `fileops.py` and
`tests/test_executor.py`. The license covers the code only. SDK tokens are
governed by Meta's Gadget SDK Terms.
