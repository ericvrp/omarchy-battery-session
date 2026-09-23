# Sleep Actions

A fork of [hungmi/omarchy-battery-session](https://github.com/hungmi/omarchy-battery-session)
that keeps the battery-session measurement and adds a dropdown of actions to
run when the machine goes to sleep, plus logging that ties those settings to
the measurements.

On the bar: a battery glyph, the current charge in percent, and one number
(time left or time in use). Clicking it opens the sleep panel with the action
toggles and the measured sleep periods. Right-click still cycles the bar
label.

## Sleep actions

| Option | What it does |
|---|---|
| Nothing turned off | Default: radios behave exactly as they do today |
| Bluetooth off | Blocks the Bluetooth radio before suspend, unblocks it on wake |
| Wi-Fi off | Blocks the Wi-Fi radio before suspend, unblocks it on wake |
| Bluetooth + Wi-Fi off | Both of the above |

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
- `~/.local/share/sleep-actions/events.tsv` gets a line at every change and
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

On the bar: a battery glyph, the current charge (percent) and one number.
Right-click cycles the number between time left (all-time average), time left
(this discharge's average) and time in use. Clicking opens the panel:

```
Turn off while sleeping
  Bluetooth [ ]   Wi-Fi [ ]

Sleep periods
  Nothing turned off   2.8 W  (4)
    09-23 20:11 → 20:43   2.1 W · 1.2 Wh
  Bluetooth off   1.8 W  (2)
    09-24 08:12 → 08:50   1.8 W · 1.1 Wh
```

Two checkboxes on one line pick what is turned off before suspend. The list is
grouped by that setting, and each group carries its own average, so the groups
can be compared directly. Up to four recent sleeps are listed per group, one
line each: when it started and ended, the average power and the energy used.
Sleeps on the charger stay visible in an "On charger" group without a power
figure, which is why a short test sleep still shows up.

Each sleep period is measured between the samples around it: duration from the
awake tick counter (jiffies only advance while awake), energy from the battery
gauge, and average power derived from those. The energy is taken from the
first settled sample after wake, so the fuel gauge's post-resume lag does not
understate a sleep.

Power (W) and energy (Wh) are absolute, so they can be compared across
machines and battery sizes; a percentage-per-hour figure is deliberately not
shown because it would depend on the battery capacity. The recorded sleep
action settings are also kept in the sample column and in `events.tsv` (see
Logging above), so the group of any period can be checked against the raw
data.

Group averages cover every measured period in the retained history (the last
12 monthly files), not only the listed ones. Time-left estimates and the bar
label still use awake power only; suspend energy is never mixed into them.
Languages: English, Traditional Chinese and Simplified Chinese, following the
system locale (`zh_TW` / `zh_HK` / `zh_MO` → Traditional, other `zh` → Simplified).

## Data files

- `~/.local/share/sleep-actions/YYYY-MM.tsv` — one file per month, last 12
  kept. This fork's own database; the original plugin's
  `~/.local/share/battery-session` directory is not read or written. It starts
  empty: statistics recorded before the settings column existed are not
  imported, so every listed sleep belongs to one of the four settings groups.
- `~/.local/share/sleep-actions/events.tsv` — settings changes and sleep
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
rm -rf ~/.local/share/sleep-actions ~/.local/state/omarchy/sleep-actions
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
