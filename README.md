# omarchy-battery-session

An Omarchy bar plugin, installed as `ericvrp.sleep-actions` (*Sleep Actions* in
the shell). **A derived work by Eric van Riet Paap**, forked from
**Battery Session** by
[hungmi](https://github.com/hungmi)
([hungmi/omarchy-battery-session](https://github.com/hungmi/omarchy-battery-session)).
The original plugin's README is kept verbatim at the bottom of this file, and
`LICENSE` retains the original copyright (© 2026 hungmi).

## Why this fork exists

On Apple Silicon Macs running Omarchy (Asahi Linux), suspend is `s2idle`, and
the machine keeps drawing meaningfully more power than macOS standby — a night
with the lid closed can cost tens of percent. Asahi documents the platform
limits, but there is little practical data about what individual radios cost
during those sleeps on this hardware. Eric needed a way to measure it on his
own machine (MacBook Pro 14", M1 Pro, `MacBookPro18,3`): sleep with Bluetooth
and/or Wi-Fi turned off before suspend, then compare the average power (W) and
energy (Wh) per setting instead of guessing.

The same numbers are useful on any battery-powered laptop, but the Apple
Silicon / `s2idle` case is why this fork exists.

## What this fork adds on top of Battery Session

- **Bar**: a state icon (level while discharging, bolt while charging, charged
  glyph when full) and the charge percentage, both live from UPower — plugging
  and unplugging shows up at once instead of at the next sample.
- **Sleep actions**: two checkboxes, *Bluetooth* and *Wi-Fi*, under
  "Turn off while sleeping". Checked means the radio is blocked with `rfkill`
  right before suspend and unblocked again on wake (no root needed; a leftover
  block is reconciled when the plugin starts or stops).
- **Sleep periods**: measured suspends grouped by which radios were off, each
  group with its own average power. One line per sleep: start → end, W · Wh.
  Only on-battery sleeps with a reading the gauge can resolve are listed.
- **Logging**: every 60 s sample carries the settings in effect
  (`bt=off;wifi=keep`), and `events.tsv` records settings changes plus each
  sleep's pre/post actions, so measurements can be traced back to the setting.
  The sampler's 60 s cadence feeds the energy (Wh) statistics only.
- **Folder / Clear** links in the panel: open the database folder, or delete
  the recorded samples (two-step confirmation).
- **Own database**: samples and the event log live in
  `~/.local/share/sleep-actions/`, not in the original plugin's directory.
- Plugin id renamed to `ericvrp.sleep-actions`; the original
  time-left / time-in-use number and its right-click cycling were removed.

## Install this fork

```bash
omarchy plugin add https://github.com/ericvrp/omarchy-battery-session.git --enable
```

The plugin id is `ericvrp.sleep-actions`. If the widget is not in the bar yet:

```bash
omarchy plugin enable ericvrp.sleep-actions --section right
```

Updates come from this repo with `omarchy plugin update ericvrp.sleep-actions`.
To merge changes from the original, add it as a remote:
`git remote add upstream https://github.com/hungmi/omarchy-battery-session.git`.

Then click the battery icon in the bar: the "Sleep periods" list fills as you
suspend on battery, grouped by the checkboxes' settings.

## Credits

- **hungmi** — original Battery Session: the sampler, awake-time model, bar
  widget, translations and the documentation kept below.
- **Eric van Riet Paap** — this fork: sleep-time radio actions, sleep-period
  measurement and grouping, live UPower bar state, logging, packaging and
  documentation.

---

## Original README: Battery Session

_The text below is the original README from
[hungmi/omarchy-battery-session](https://github.com/hungmi/omarchy-battery-session),
kept verbatim. It documents the original plugin id and install command; the
differences of this fork are described above._

# Battery Session

An [Omarchy](https://omarchy.org) bar widget that tells you how long this battery
charge has **actually** been in use.

Omarchy's power panel shows the current draw and charge level, but not how long
you have been running on this charge. Simple wall-clock time is wrong: it counts
the hours the lid was closed. This plugin counts only the time the machine was
awake, so lock screen and idle time count (the machine is still drawing power),
while suspend and shutdown do not.

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
```

plus a list of your last eight discharges.

Averages use awake power only. Suspend still draws roughly 1 W on many laptops;
that energy is reported separately as "Used while asleep" so it does not
inflate your estimate.

Languages: English, Traditional Chinese and Simplified Chinese, following the
system locale (`zh_TW` / `zh_HK` / `zh_MO` → Traditional, other `zh` → Simplified).

## How it works

Every 60 seconds a small bash script records the battery state together with
the kernel's scheduler tick count (`/proc/schedstat`). That counter only
advances while the machine is awake, so the awake time between any two samples
is just the difference. Nothing needs to observe suspend or resume events, and
a missed sample, a shell restart, or a reboot self-corrects on the next sample.

Samples go to `~/.local/share/battery-session/YYYY-MM.tsv`, one file per month,
last 12 months kept. Roughly 2.5 MB per month, so about 30 MB on disk at most.

Sampling runs inside the Omarchy shell. When the shell is not running (before
login, or after `omarchy restart shell`) no samples are taken. Awake time is
unaffected; a charge that happened entirely during such a gap is detected from
the jump in stored energy.

## Security notes

The plugin runs as your user inside the Omarchy shell, like every shell plugin.
What it does with that:

- **One child process at a time.** At startup and then every 60 seconds the
  service starts `/usr/bin/bash` by absolute path with `--noprofile --norc`, a
  cleared environment (`PATH=/usr/bin`, `LC_ALL=C`, and the system `TZ` so
  month file names agree), stdin and stderr closed, and a hard deadline
  (SIGTERM after 20 s for a sample or 30 s for the startup load, SIGKILL 5 s
  later). Both are stopped when the service is destroyed.
- **The script is bash builtins.** `sample.sh` reads `/sys/class/power_supply`
  and `/proc/schedstat` with `read`; there is no awk, cut, ls, sort or xargs.
  The only external programs are `/usr/bin/dd` (every file read and write),
  `/usr/bin/mkdir` (missing directories) and `/usr/bin/rm` (monthly
  retention), all by absolute path.
- **File opens are bound to the checks.** Every data file is opened by `dd`
  with `O_NOFOLLOW` (a symlink at the path fails), `O_NONBLOCK` (a fifo or
  device cannot block), and `O_EXCL` when a month file is created (anything
  that appeared at the path in between fails). Reads are capped at 4 MiB per
  month file on the producer side, so the shell never buffers more than three
  such files. `mkdir` refuses a symlink at the target and `rm` never follows
  one. Ownership and type are additionally checked on the path before each
  open.
- **The data directory is not taken from the environment.** It is always
  `~/.local/share/battery-session`, with `~` resolved from the password
  database. Missing directory levels are created; `~`, `~/.local`,
  `~/.local/share` and the data directory must be owned by the current user
  and not be symlinks. The data directory is created with mode 0700. Any
  failure aborts the sample (exit 5, shown in the popup).
- **Bounded parsing.** At most 150 000 rows are kept in memory and a sampler
  line over 256 characters is discarded.
- **No network, no sudo, no systemd units, no writes outside the data
  directory, no configuration changes** other than the `barLabel` value the
  widget writes to `shell.json` when you right-click it.

## Install

```bash
omarchy plugin add https://github.com/hungmi/omarchy-battery-session
```

The widget appears on the right side of the bar next to the power indicator.
It needs two samples (about a minute) before showing numbers.

Settings, via `omarchy bar set hungmi.battery-session <key> <value>`:

| Key | Values | Default |
|---|---|---|
| `barLabel` | `remainHist` `remainCur` `awake` | `remainHist` |
| `lang` | `auto` `en` `zh-Hant` `zh-Hans` | `auto` |

## Remove

```bash
omarchy plugin remove hungmi.battery-session
```

Removal does not delete the recorded data. To remove that too:

```bash
rm -rf ~/.local/share/battery-session
```

## Requirements

- Omarchy 4.x shell (Quickshell based)
- A laptop battery exposed under `/sys/class/power_supply/` with either
  `energy_now` or `charge_now` + `voltage_now`
- `/usr/bin/bash` 4.3 or newer (part of any Arch base install). No Python, no awk, no extra packages.

## Development

`Model.js` holds the algorithm and is plain JavaScript, so it can be tested
outside the shell:

```bash
node tests/cases.js
```

After editing QML or JS, `omarchy restart shell`. If the widget disappears from
the bar, check `journalctl --user -o cat | grep 'Plugin widget'` for the error.

## License

MIT. No external dependencies.
