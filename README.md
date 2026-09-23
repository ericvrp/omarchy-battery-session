# Sleep Actions

A fork of [hungmi/omarchy-battery-session](https://github.com/hungmi/omarchy-battery-session)
that keeps the battery-session measurement and adds a dropdown of actions to
run when the machine goes to sleep, plus logging that ties those settings to
the measurements.

On the bar: a battery glyph and one number (time left or time in use).
Clicking it opens the panel with the discharge details, the sleep action
toggles, and the history. Right-click still cycles the bar label.

## Sleep actions

| Toggle | What it does |
|---|---|
| Turn off Bluetooth | Blocks the Bluetooth radio before suspend, unblocks it on wake |
| Turn off Wi-Fi | Blocks the Wi-Fi radio before suspend, unblocks it on wake |

Both default to off (radios kept on). The point is to test whether a radio is
what keeps the machine drawing power while suspended: flip one on, leave the
machine asleep for a while, and compare `events.tsv` / the settings column
against the discharge numbers.

How it works:

- `sleep-watch.sh` is a long-lived user process started by the plugin service.
  It subscribes to logind's `PrepareForSleep` signal on the system bus.
- On suspend it runs `sleepctl.sh apply-pre`; on wake `sleepctl.sh apply-post`.
  The controller uses `rfkill` (no root needed: `/dev/rfkill` carries a
  logind-managed ACL for the active session).
- Radios already blocked by the user are left alone; the controller only
  touches what it blocked itself, tracked in
  `~/.local/state/omarchy/sleep-actions/applied`.
- If the watcher stops (shell restart, plugin disable, crash) it reconciles:
  anything left blocked is unblocked again. On start it does the same, so a
  machine that shut down while asleep never comes up with a radio stuck off.
- Nothing waits for a suspend. If the watcher or the controller fails, sleep
  works exactly as if the plugin were not installed; the only effect is that
  the action did not run.

## Logging

Two additions make the settings visible to the measurements:

- Every 60 s sample gains a ninth column with the policy in effect at that
  moment, e.g. `bt=off;wifi=keep`. Rows written before the fork have eight
  fields and read as "no settings recorded".
- `~/.local/share/battery-session/events.tsv` gets a line at every change and
  every action (tab separated `wall`, `event`, `detail`):

```
wall	event	detail
1788400000	settings	bluetooth=off
1788410000	pre	settings=bluetooth=off,wifi=keep bluetooth=blocked
1788413600	post	bluetooth=unblocked
1788420000	reconcile	nothing-to-restore
```

That is enough to line up a suspend window with the policy that was active
and to confirm the radio actually went off.

## What it shows

On the bar: a battery glyph and one number. Right-click to cycle between:

| Mode | Meaning |
|---|---|
| Time left (all-time avg) | Remaining charge ÷ your average awake power draw across all recorded discharges. Default. |
| Time left (session avg) | Same, using only this discharge's average. |
| Time in use | Awake time since unplugging. |

Click to open the details:

```
Battery life
  Unplugged at           09-03 16:11  100%
  Now                    09-03 23:46   71%
  Time since unplugged   7h 35m
  Suspended / off        5h 27m
  Time in use            2h 08m
  Discharging            now 5.0W · session avg 4.7W
  Time left              6h 04m (session avg 4.7W)
                         4h 10m (all-time avg 6.9W)

When sleeping
  Turn off Bluetooth     [ ]
  Turn off Wi-Fi         [ ]
```

Averages use awake power only. Suspend still draws roughly 1 W on many
laptops; that energy is reported separately as "Used while asleep" so it does
not inflate your estimate.

Languages: English, Traditional Chinese and Simplified Chinese, following the
system locale (`zh_TW` / `zh_HK` / `zh_MO` → Traditional, other `zh` → Simplified).

## Data files

- `~/.local/share/battery-session/YYYY-MM.tsv` — one file per month, last 12
  kept. The directory is shared with the original plugin on purpose: renaming
  the fork does not throw away the recorded history. Do not enable the
  original and this fork at the same time; both would append to the same
  month file.
- `~/.local/share/battery-session/events.tsv` — settings changes and sleep
  actions, appended as above.
- `~/.config/omarchy/sleep-actions.conf` — the two settings.
- `~/.local/state/omarchy/sleep-actions/applied` — what is currently blocked
  by the plugin, so it can be restored.

## Install

This is a local fork; install it from the checkout:

```bash
omarchy plugin add https://github.com/<you>/omarchy-sleep-actions.git --enable
```

or clone it straight into place and enable it:

```bash
git clone https://github.com/<you>/omarchy-sleep-actions.git \
  ~/.config/omarchy/plugins/ericvrp.sleep-actions
omarchy-shell shell rescanPlugins
omarchy plugin enable ericvrp.sleep-actions --section right
```

Settings, via the popup, or:

```bash
~/.config/omarchy/plugins/ericvrp.sleep-actions/sleepctl.sh set bluetooth off
~/.config/omarchy/plugins/ericvrp.sleep-actions/sleepctl.sh get
```

## Remove

```bash
omarchy plugin disable ericvrp.sleep-actions
omarchy plugin remove ericvrp.sleep-actions
```

Removing does not delete recorded data. To remove that too:

```bash
rm -rf ~/.local/share/battery-session ~/.local/state/omarchy/sleep-actions
rm -f ~/.config/omarchy/sleep-actions.conf
```

## Requirements

- Omarchy 4.x shell (Quickshell based)
- A laptop battery exposed under `/sys/class/power_supply/` with either
  `energy_now` or `charge_now` + `voltage_now`
- `/usr/bin/bash`, `/usr/bin/dd`, `/usr/bin/mkdir`, `/usr/bin/rm`,
  `/usr/bin/mv`, `/usr/bin/rfkill`, `/usr/bin/timeout`, `/usr/bin/sleep`,
  `/usr/bin/dbus-monitor` (all part of a base Arch install or its dependencies)
- No Python, no network, no systemd units, no sudo

## Trust boundary

Everything runs as the desktop user inside the Omarchy shell. `sample.sh`
reads `/sys/class/power_supply` and `/proc/schedstat`; `sleepctl.sh` reads and
writes the settings, state and log files and calls `rfkill`;
`sleep-watch.sh` only subscribes to the system bus and dispatches. External
programs are used by absolute path, file opens use `O_NOFOLLOW` and
`O_NONBLOCK`, settings and state are written via an exclusive temp file and
renamed into place, and every directory level is verified owned by the user
and not a symlink first.

## License

MIT. Forked from `hungmi/omarchy-battery-session`, © hungmi; see LICENSE.
