#!/usr/bin/bash
# Sampler and history reader for the Battery Session plugin. Called by
# Service.qml as
#   /usr/bin/bash --noprofile --norc sample.sh          one sample
#   /usr/bin/bash --noprofile --norc sample.sh load     bounded history dump
# with a cleared environment (PATH=/usr/bin, LC_ALL=C and TZ only).
#
# Sample line, printed to stdout and appended to this month's file:
#   wall  jiffies  boot  pct  state  ac  energy_wh  power_w  settings
# settings is the sleep action policy in effect at sample time, compact and
# tab-free: "bt=off;wifi=keep" (see sleepctl.sh). Empty if unreadable. The
# column was added by the renamed fork; rows written before it simply have
# eight fields and the reader treats them as "no settings recorded".
# jiffies is the global tick count from the second line of /proc/schedstat. It
# only advances while the machine is awake and freezes during suspend. Stored
# raw; the reader derives HZ from adjacent samples.
#
# Trust boundary. Everything is bash builtins reading /sys and /proc. External
# programs, all by absolute path: /usr/bin/dd for every file read and write,
# /usr/bin/mkdir for missing directories, /usr/bin/rm for monthly retention.
# The data directory is ~/.local/share/battery-session with ~ taken from the
# password database (HOME is unset), never from environment strings. File
# opens are bound to the checks: dd opens with O_NOFOLLOW (a symlink at the
# path fails), O_NONBLOCK (a fifo or device cannot block), O_EXCL when creating
# (an object that appeared in between fails), and reads are capped by bytes.
# Directories are created with mkdir, which never follows a symlink at the
# target. Ownership and type checks happen on the path before the open; a
# same-user race there can only substitute another object of the same user,
# and the open flags above still refuse symlinks and blocking specials.
#
# Exit codes read by Service.qml: 2 bad argument, 3 no battery, 4 clock not
# synced yet, 5 data directory or file failed verification.
set -u
umask 077
export PATH=/usr/bin LC_ALL=C
unset -v HOME CDPATH IFS
shopt -s nullglob

DD=/usr/bin/dd
MKDIR=/usr/bin/mkdir
RM=/usr/bin/rm

keep_months=12
load_months=3
max_file_bytes=4194304      # 4 MiB per month file; a month at one row per minute is ~2.5 MB

mode=${1-sample}
[[ $mode == sample || $mode == load ]] || exit 2

# ---- data directory: ~/.local/share/battery-session, verified at every level ----
# HOME is unset above, so ~ comes from the password database.
home=~
[[ $home == /* && -d $home && ! -L $home && -O $home ]] || exit 5
owned_dir() { [[ -d $1 && ! -L $1 && -O $1 ]]; }
# Create if missing (mkdir refuses a symlink at the target), then verify.
# Shared XDG parents get the default mode; our own directory is 0700.
ensure_dir() {  # ensure_dir <path> [mode]
  if [[ ! -e $1 && ! -L $1 ]]; then $MKDIR ${2:+-m "$2"} -- "$1" || return 1; fi
  owned_dir "$1"
}
ensure_dir "$home/.local" || exit 5
ensure_dir "$home/.local/share" || exit 5
dir=$home/.local/share/battery-session
ensure_dir "$dir" 700 || exit 5

# Owned regular file, not a symlink. Path-based; the dd flags re-check symlink
# and blocking at open time.
owned_file() { [[ -f $1 && ! -L $1 && -O $1 ]]; }

printf -v year '%(%Y)T' -1
printf -v mon  '%(%m)T' -1

# ================= load: dump the last N month files, bounded =================
if [[ $mode == load ]]; then
  for (( i = load_months - 1; i >= 0; i-- )); do
    y=$year; m=$(( 10#$mon - i ))
    while (( m <= 0 )); do m=$(( m + 12 )); y=$(( y - 1 )); done
    printf -v f '%s/%04d-%02d.tsv' "$dir" "$y" "$m"
    [[ -e $f || -L $f ]] || continue
    owned_file "$f" || continue
    $DD if="$f" iflag=nofollow,nonblock,count_bytes count=$max_file_bytes status=none
    printf '\n'
  done
  exit 0
fi

# ================= sample =================
# ---- locate the system battery (skip mouse/keyboard batteries) ----
ps=/sys/class/power_supply
bat=""
for d in "$ps"/*; do
  [[ -r $d/type ]] && read -r t < "$d/type" || continue
  [[ $t == Battery ]] || continue
  if [[ -r $d/scope ]]; then read -r s < "$d/scope"; [[ $s == System ]] || continue; fi
  bat=$d; break
done
[[ -n $bat ]] || exit 3

printf -v wall '%(%s)T' -1
(( wall > 1500000000 )) || exit 4   # Asahi boots at 1970 until timesyncd catches up

# ---- awake-only tick counter ----
{ read -r _; read -r _ jiffies _; } < /proc/schedstat
[[ $jiffies =~ ^[0-9]{1,20}$ ]] || exit 4

read -r bootid < /proc/sys/kernel/random/boot_id
boot=${bootid:0:8}

# Reads a sysfs integer into the named variable; empty if missing or malformed.
rdint() {
  local -n out=$1; out=""
  local v
  [[ -r $2 ]] && read -r v < "$2" || return 0
  [[ $v =~ ^-?[0-9]{1,18}$ ]] && out=$v
}
# Fixed-point: value / 10^scale with two decimals, sign kept, integers only.
fix2() {  # fix2 <int> <scale>
  local v=$1 s="" div=1 i
  (( v < 0 )) && { s=-; v=$(( -v )); }
  for (( i = 0; i < $2; i++ )); do div=$(( div * 10 )); done
  printf '%s%d.%02d' "$s" $(( v / div )) $(( v % div / (div / 100) ))
}

rdint pct "$bat/capacity"
read -r state < "$bat/status" 2>/dev/null || state=""
state_re='^[A-Za-z ]{1,20}$'
[[ $state =~ $state_re ]] || state=Unknown

# Mains power. Ignore per-port USB-C source supplies such as tps6598x.
ac=""
for d in "$ps"/*; do
  [[ ${d##*/} == tps* ]] && continue
  [[ -r $d/type && -r $d/online ]] && read -r t < "$d/type" || continue
  [[ $t == Mains ]] || continue
  rdint ac "$d/online"; break
done

# µWh/µW → Wh/W. Devices exposing only charge_now use µAh × µV = 1e-12 Wh.
wh=""; pw=""
rdint e "$bat/energy_now";  rdint p "$bat/power_now"
rdint q "$bat/charge_now";  rdint i "$bat/current_now"; rdint v "$bat/voltage_now"
if   [[ -n $e ]];            then wh=$(fix2 "$e" 6)
elif [[ -n $q && -n $v ]];   then wh=$(fix2 $(( q * v )) 12); fi
if   [[ -n $p ]];            then pw=$(fix2 "$p" 6)
elif [[ -n $i && -n $v ]];   then pw=$(fix2 $(( i * v )) 12); fi

# ---- sleep action policy at sample time ----
sbt=keep; swifi=keep; settings=""
scfg=$home/.config/omarchy/sleep-actions.conf
if [[ -f $scfg && ! -L $scfg && -O $scfg && -r $scfg ]]; then
  sn=0
  while IFS='=' read -r sk sv; do
    (( sn++ >= 16 )) && break
    [[ $sk == bluetooth && $sv == off ]] && sbt=off
    [[ $sk == wifi && $sv == off ]] && swifi=off
  done < "$scfg"
  settings="bt=$sbt;wifi=$swifi"
fi

printf -v line '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
  "$wall" "$jiffies" "$boot" "$pct" "$state" "$ac" "$wh" "$pw" "$settings"

# ---- append to this month's file ----
f=$dir/$year-$mon.tsv
if [[ ! -e $f && ! -L $f ]]; then
  # O_CREAT|O_EXCL|O_NOFOLLOW: fails if anything appeared at the path meanwhile.
  printf 'wall\tjiffies\tboot\tpct\tstate\tac\tenergy_wh\tpower_w\tsettings\n' \
    | $DD of="$f" conv=excl,notrunc oflag=nofollow status=none || exit 5
fi
owned_file "$f" || exit 5
# O_APPEND|O_NOFOLLOW|O_NONBLOCK: a symlink fails, a fifo/device cannot block.
printf '%s\n' "$line" | $DD of="$f" oflag=append,nofollow,nonblock conv=notrunc status=none || exit 5

# ---- keep only the last N month files (glob is sorted, LC_ALL=C) ----
# rm unlinks the name and never follows a symlink.
files=("$dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9].tsv)
if (( ${#files[@]} > keep_months )); then
  for old in "${files[@]:0:${#files[@]}-keep_months}"; do
    owned_file "$old" && $RM -f -- "$old"
  done
fi

printf '%s\n' "$line"
