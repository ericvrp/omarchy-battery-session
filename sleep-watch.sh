#!/usr/bin/bash
# Sleep watcher for the Sleep Actions plugin. Long-lived child of Service.qml:
#   /usr/bin/bash --noprofile --norc sleep-watch.sh
# with a cleared environment (PATH=/usr/bin, LC_ALL=C and TZ only).
#
# It subscribes to logind's PrepareForSleep signal on the system bus and runs
# sleepctl.sh apply-pre before the machine suspends and sleepctl.sh apply-post
# after it wakes. All file and radio work lives in sleepctl.sh; this script
# only listens and dispatches, so a failure here can never hold up a suspend:
# if the listener dies, the session simply behaves as if the plugin were not
# installed.
#
# On startup, and again when the process is told to stop (shell restart, plugin
# disable), it runs sleepctl.sh reconcile so a radio blocked by a previous
# sleep is never left blocked without a watcher to restore it.
#
# Trust boundary: bash builtins plus /usr/bin/dbus-monitor (read-only system
# bus subscription), /usr/bin/sleep and /usr/bin/bash for the controller.
set -u
umask 077
export PATH=/usr/bin LC_ALL=C
unset -v HOME CDPATH IFS

DBUS_MONITOR=/usr/bin/dbus-monitor
SLEEP=/usr/bin/sleep
BASH=/usr/bin/bash

dir=${BASH_SOURCE[0]%/*}
[[ $dir == "${BASH_SOURCE[0]}" ]] && dir=.
dir=$(cd -- "$dir" && pwd -P) || exit 1
[[ $dir == /* && -x $dir/sleepctl.sh && -x $DBUS_MONITOR ]] || exit 1
ctl=$dir/sleepctl.sh

run_ctl() { $BASH --noprofile --norc "$ctl" "$@" >/dev/null 2>&1; }

mon_pid=""
stopping=0

on_signal() {
  stopping=1
  [[ -n $mon_pid ]] && kill "$mon_pid" 2>/dev/null
  run_ctl reconcile
  exit 0
}
trap on_signal TERM INT

# Leftovers from a crash, a reboot or a plugin restart while awake.
run_ctl reconcile

while (( ! stopping )); do
  coproc MON { exec "$DBUS_MONITOR" --system \
    "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null; }
  mon_pid=$MON_PID

  while IFS= read -r line <&"${MON[0]}"; do
    case $line in
    *member=PrepareForSleep*)
      value=""
      for (( i = 0; i < 6; i++ )); do
        IFS= read -r vline <&"${MON[0]}" || break
        [[ -n $vline ]] && { value=$vline; break; }
      done
      case $value in
      *true*)  run_ctl apply-pre ;;
      *false*) run_ctl apply-post ;;
      esac
      ;;
    esac
  done

  [[ -n $mon_pid ]] && wait "$mon_pid" 2>/dev/null
  mon_pid=""
  (( stopping )) && break
  $SLEEP 1
done
exit 0
