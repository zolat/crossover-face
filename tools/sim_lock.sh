#!/bin/sh
# Serialise access to the Connect IQ simulator across parallel sessions.
#
# There is one simulator per machine, holding one persisted app-data store, and
# monkeydo sideloads into it by device id. Two sessions doing that at once take
# each other's run down, and a killed test run prints a bare "TESTS FAILED"
# with no output at all — which reads like a real failure rather than like
# contention. That is the whole reason this exists: not to make parallel work
# faster, but to stop it lying about test results.
#
# The lock lives outside the repo, so every worktree of this project shares one.
#
# It is a *directory* because mkdir is atomic, and it holds the PID of the shell
# that owns it so that a session which dies without cleaning up leaves a lock
# the next one can prove is stale rather than one that wedges the machine.
# BSD shlock(1) would be the obvious thing to use and is already on macOS — but
# the copy shipped with this system does not reclaim a lock whose PID is gone
# (measured: a lock naming a genuinely absent PID is still refused), so it would
# turn one crashed run into a permanently blocked project.
#
#   sim_lock.sh acquire <pid>   take the lock, waiting for it; fails on timeout
#   sim_lock.sh release <pid>   give it back, if <pid> is what holds it
#   sim_lock.sh wait            wait for it to be free, but do not take it
#
# Override the location with CROSSOVER_SIM_LOCK, and the patience with
# CROSSOVER_SIM_LOCK_WAIT (seconds).

set -u

LOCK="${CROSSOVER_SIM_LOCK:-/tmp/crossover-face-simulator.lock}"
OWNER="$LOCK/owner"
WAIT_SECONDS="${CROSSOVER_SIM_LOCK_WAIT:-300}"

holder() {
    cat "$OWNER" 2>/dev/null
}

#! Is the lock held by a process that still exists? A lock with no PID recorded
#! counts as stale: it means a session died between mkdir and writing the file.
#!
#! Note the underscore. Shell functions share one variable namespace, so a bare
#! `pid=` here would overwrite acquire()'s own pid — and acquire would then
#! stamp the lock it just reclaimed with the *dead* owner's PID, leaving every
#! later session free to declare it stale and steal it from a live run.
held_by_live_process() {
    _owner_pid=$(holder)
    [ -n "$_owner_pid" ] || return 1
    kill -0 "$_owner_pid" 2>/dev/null
}

#! Clear the lock if whoever took it is gone. Returns 0 when the lock is now
#! free to compete for, 1 when someone alive still holds it.
drop_if_stale() {
    [ -d "$LOCK" ] || return 0
    held_by_live_process && return 1
    echo "sim-lock: clearing a lock left behind by PID $(holder), which is gone" >&2
    rm -rf "$LOCK"
    return 0
}

acquire() {
    _mine="$1"
    _waited=0
    while :; do
        if mkdir "$LOCK" 2>/dev/null; then
            echo "$_mine" > "$OWNER"
            return 0
        fi
        drop_if_stale && continue
        if [ "$_waited" -eq 0 ]; then
            echo "sim-lock: the simulator is busy (PID $(holder)); waiting up to ${WAIT_SECONDS}s" >&2
        fi
        _waited=$((_waited + 1))
        if [ "$_waited" -ge "$WAIT_SECONDS" ]; then
            echo "sim-lock: gave up after ${WAIT_SECONDS}s — PID $(holder) still holds $LOCK" >&2
            return 1
        fi
        sleep 1
    done
}

#! Only the owner may release, so a stale-lock reclaim racing with the original
#! owner's trap cannot have the loser delete the winner's lock.
release() {
    _mine="${1:-}"
    if [ -n "$_mine" ] && [ -d "$LOCK" ]; then
        _held=$(holder)
        if [ -n "$_held" ] && [ "$_held" != "$_mine" ]; then
            return 0
        fi
    fi
    rm -rf "$LOCK"
}

#! Wait for a test run to finish without queueing behind it. Used by `make sim`,
#! which wants to avoid sideloading into someone's test run but must not hold
#! the simulator for as long as it stays attached — that would block every other
#! session's tests until the human pressed Ctrl-C.
wait_free() {
    _waited=0
    while [ -d "$LOCK" ]; do
        drop_if_stale && continue
        if [ "$_waited" -eq 0 ]; then
            echo "sim-lock: a test run holds the simulator (PID $(holder)); waiting" >&2
        fi
        _waited=$((_waited + 1))
        if [ "$_waited" -ge "$WAIT_SECONDS" ]; then
            echo "sim-lock: still busy after ${WAIT_SECONDS}s — sideloading anyway" >&2
            return 0
        fi
        sleep 1
    done
    return 0
}

case "${1:-}" in
    acquire) shift; acquire "${1:?acquire needs a pid}" ;;
    release) shift; release "${1:-}" ;;
    wait)    wait_free ;;
    *)       echo "usage: sim_lock.sh acquire <pid> | release <pid> | wait" >&2; exit 2 ;;
esac
