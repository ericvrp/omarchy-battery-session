#!/usr/bin/bash
# Sleep action controller for the Sleep Actions plugin (a fork of Battery
# Session). Called by Service.qml and sleep-watch.sh as
#   /usr/bin/bash --noprofile --norc sleepctl.sh <mode> [args]
# with a cleared environment (PATH=/usr/bin, LC_ALL=C and TZ only).
#
# Modes:
#   get                    print the current settings (bluetooth=keep, wifi=keep)
#   set <key> <value>      validate, persist, and immediately restore a radio
#                          that is switched back to keep while still blocked
#   status                 print what this plugin has blocked right now
#   apply-pre              run the configured pre-suspend actions
#   apply-post             restore whatever apply-pre changed
#   reconcile              restore leftovers (start/stop of the watcher)
#
# Settings are ~/.config/omarchy/sleep-actions.conf, one "key=value" per line:
#   bluetooth=keep|off   wifi=keep|off
# "off" means: block that radio before suspend and unblock it on wake. Radios
# already blocked by the user are left alone, so we never unblock something we
# did not block.
#
# State and logs:
#   ~/.local/state/omarchy/sleep-actions/applied   what this plugin blocked
#   ~/.local/share/sleep-actions/events.tsv      timestamped action log
#
# Trust boundary: parsing is bash builtins; external programs are all by
# absolute path - /usr/bin/dd for every file read and write, /usr/bin/mkdir,
# /usr/bin/rm and /usr/bin/mv, /usr/bin/rfkill plus /usr/bin/timeout for the
# actions, /usr/bin/bash for the helpers. File opens use O_NOFOLLOW and
# O_NONBLOCK, settings and state are written to an exclusive temp file and
# renamed into place, and every directory level is verified owned and not a
# symlink before use.
#
# Exit codes read by the callers: 2 bad argument, 5 path verification failed,
# 6 an action failed.
set -u
umask 077
export PATH=/usr/bin LC_ALL=C
unset -v HOME CDPATH IFS
shopt -s nullglob

DD=/usr/bin/dd
MKDIR=/usr/bin/mkdir
RM=/usr/bin/rm
MV=/usr/bin/mv
RFKILL=/usr/bin/rfkill
TIMEOUT=/usr/bin/timeout

home=~
[[ $home == /* && -d $home && ! -L $home && -O $home ]] || exit 5

owned_dir()  { [[ -d $1 && ! -L $1 && -O $1 ]]; }
owned_file() { [[ -f $1 && ! -L $1 && -O $1 ]]; }
# Create if missing (mkdir refuses a symlink at the target), then verify.
ensure_dir() {  # ensure_dir <path> [mode]
  if [[ ! -e $1 && ! -L $1 ]]; then $MKDIR ${2:+-m "$2"} -- "$1" || return 1; fi
  owned_dir "$1"
}

ensure_dir "$home/.local" || exit 5
ensure_dir "$home/.local/share" || exit 5
data=$home/.local/share/sleep-actions
ensure_dir "$data" 700 || exit 5
ensure_dir "$home/.local/state" || exit 5
ensure_dir "$home/.local/state/omarchy" || exit 5
state=$home/.local/state/omarchy/sleep-actions
ensure_dir "$state" 700 || exit 5
ensure_dir "$home/.config" || exit 5
ensure_dir "$home/.config/omarchy" || exit 5

cfg=$home/.config/omarchy/sleep-actions.conf
applied=$state/applied
events=$data/events.tsv

wall_now() {
  local w
  printf -v w '%(%s)T' -1
  (( w > 1500000000 )) || return 1
  printf '%s' "$w"
}

sanitize() {
  local s=$1
  s=${s//$'\t'/ }
  s=${s//$'\n'/ }
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

log_event() {  # log_event <kind> [detail]
  local wall line detail
  wall=$(wall_now) || return 0
  detail=$(sanitize "${2:-}")
  if [[ ! -e $events && ! -L $events ]]; then
    printf 'wall\tevent\tdetail\n' \
      | $DD of="$events" conv=excl,notrunc oflag=nofollow status=none || return 0
  fi
  owned_file "$events" || return 0
  printf -v line '%s\t%s\t%s' "$wall" "$1" "$detail"
  printf '%s\n' "$line" | $DD of="$events" oflag=append,nofollow,nonblock conv=notrunc status=none || return 0
}

# ---- settings ----
bt=keep
wifi=keep

load_settings() {
  bt=keep
  wifi=keep
  [[ -f $cfg && ! -L $cfg && -O $cfg && -r $cfg ]] || return 0
  local k v n=0
  while IFS='=' read -r k v; do
    (( n++ >= 16 )) && break
    [[ $k == bluetooth && $v == off ]] && bt=off
    [[ $k == wifi && $v == off ]] && wifi=off
  done < "$cfg"
}

print_settings() { printf 'bluetooth=%s\nwifi=%s\n' "$bt" "$wifi"; }

write_settings() {  # write_settings <bluetooth> <wifi>
  local tmp="$home/.config/omarchy/.sleep-actions.conf.tmp.$$"
  if ! printf 'bluetooth=%s\nwifi=%s\n' "$1" "$2" \
      | $DD of="$tmp" conv=excl,notrunc oflag=nofollow status=none; then
    $RM -f -- "$tmp"
    exit 5
  fi
  if ! owned_file "$tmp"; then $RM -f -- "$tmp"; exit 5; fi
  $MV -f -- "$tmp" "$cfg" || { $RM -f -- "$tmp"; exit 5; }
}

# ---- state of what this plugin has blocked ----
applied_bt=no
applied_wifi=no

load_applied() {
  applied_bt=no
  applied_wifi=no
  [[ -f $applied && ! -L $applied && -O $applied && -r $applied ]] || return 0
  local k v n=0
  while IFS='=' read -r k v; do
    (( n++ >= 8 )) && break
    [[ $k == bluetooth && $v == blocked ]] && applied_bt=blocked
    [[ $k == wifi && $v == blocked ]] && applied_wifi=blocked
  done < "$applied"
}

write_applied() {
  local tmp="$state/.applied.tmp.$$" body=""
  [[ $applied_bt == blocked ]] && body+=$'bluetooth=blocked\n'
  [[ $applied_wifi == blocked ]] && body+=$'wifi=blocked\n'
  if ! printf '%s' "$body" \
      | $DD of="$tmp" conv=excl,notrunc oflag=nofollow status=none; then
    $RM -f -- "$tmp"
    exit 5
  fi
  if ! owned_file "$tmp"; then $RM -f -- "$tmp"; exit 5; fi
  $MV -f -- "$tmp" "$applied" || { $RM -f -- "$tmp"; exit 5; }
}

# ---- radios ----
# $1 is an rfkill identifier: bluetooth or wlan. 0 = soft blocked, 1 = not.
radio_is_blocked() {
  local out
  out=$($TIMEOUT 5 "$RFKILL" list "$1" 2>/dev/null) || return 1
  [[ $out == *"Soft blocked: yes"* ]]
}

radio_block()   { $TIMEOUT 5 "$RFKILL" block   "$1" >/dev/null 2>&1; }
radio_unblock() { $TIMEOUT 5 "$RFKILL" unblock "$1" >/dev/null 2>&1; }

# ---- modes ----
do_pre() {
  load_settings
  load_applied
  local detail=""
  if [[ $bt == off ]]; then
    if radio_is_blocked bluetooth; then
      detail+="bluetooth=already-blocked "
    elif radio_block bluetooth; then
      applied_bt=blocked
      detail+="bluetooth=blocked "
    else
      detail+="bluetooth=block-failed "
    fi
  elif [[ $applied_bt == blocked ]]; then
    if radio_unblock bluetooth; then applied_bt=no; detail+="bluetooth=unblocked "; fi
  fi
  if [[ $wifi == off ]]; then
    if radio_is_blocked wlan; then
      detail+="wifi=already-blocked "
    elif radio_block wlan; then
      applied_wifi=blocked
      detail+="wifi=blocked "
    else
      detail+="wifi=block-failed "
    fi
  elif [[ $applied_wifi == blocked ]]; then
    if radio_unblock wlan; then applied_wifi=no; detail+="wifi=unblocked "; fi
  fi
  write_applied
  log_event pre "settings=bluetooth=$bt,wifi=$wifi ${detail}"
}

do_restore() {  # do_restore <event-kind>
  load_applied
  local detail=""
  if [[ $applied_bt == blocked ]]; then
    if radio_unblock bluetooth; then applied_bt=no; detail+="bluetooth=unblocked "
    else detail+="bluetooth=unblock-failed "; fi
  fi
  if [[ $applied_wifi == blocked ]]; then
    if radio_unblock wlan; then applied_wifi=no; detail+="wifi=unblocked "
    else detail+="wifi=unblock-failed "; fi
  fi
  write_applied
  log_event "$1" "${detail:-nothing-to-restore}"
}

do_set() {  # do_set <key> <value>, value already validated
  load_settings
  case $1 in
    bluetooth) bt=$2 ;;
    wifi)      wifi=$2 ;;
  esac
  write_settings "$bt" "$wifi"
  log_event settings "$1=$2"
  # Switching a radio back to keep restores it right away, even if a previous
  # sleep left it blocked (for example when the post event was missed).
  load_applied
  local detail=""
  if [[ $bt == keep && $applied_bt == blocked ]]; then
    if radio_unblock bluetooth; then applied_bt=no; detail+="bluetooth=unblocked "; fi
  fi
  if [[ $wifi == keep && $applied_wifi == blocked ]]; then
    if radio_unblock wlan; then applied_wifi=no; detail+="wifi=unblocked "; fi
  fi
  if [[ -n $detail ]]; then
    write_applied
    log_event restore "$detail"
  fi
  print_settings
}

do_status() {
  load_applied
  local out=""
  [[ $applied_bt == blocked ]] && out+="bluetooth "
  [[ $applied_wifi == blocked ]] && out+="wifi "
  printf 'blocked=%s\n' "${out:-none}"
}

mode=${1:-}
case $mode in
  get)
    load_settings
    print_settings
    ;;
  set)
    (( $# >= 3 )) || exit 2
    [[ $2 == bluetooth || $2 == wifi ]] || exit 2
    [[ $3 == keep || $3 == off ]] || exit 2
    do_set "$2" "$3"
    ;;
  status)
    do_status
    ;;
  apply-pre)
    do_pre
    ;;
  apply-post)
    do_restore post
    ;;
  reconcile)
    do_restore reconcile
    ;;
  *)
    exit 2
    ;;
esac
exit 0
