#!/bin/sh
# Self-test for tools/sim_lock.sh. Run it directly: tools/sim_lock_test.sh
#
# This exists because the lock's first cut had a bug that every casual test
# missed: held_by_live_process() assigned to `pid`, and shell functions share
# one variable namespace, so it clobbered acquire()'s own pid. The lock still
# *looked* fine — it was taken, waited for and released correctly — but after
# reclaiming a stale lock it stamped the new one with the DEAD owner's PID, so
# the next session would declare it stale in turn and take the simulator from a
# live test run. Exactly the failure the lock is meant to prevent.
#
# The lesson worth keeping: a lock cannot be tested with made-up PIDs. A fake
# PID is a *dead* PID, so a lock "held" by 7777 is correctly reclaimed as stale
# and every contention test silently passes for the wrong reason. Contention
# has to be staged with a process that is genuinely running.

set -u

here=$(dirname "$0")
LOCK_UNDER_TEST="$here/sim_lock.sh"

CROSSOVER_SIM_LOCK="${TMPDIR:-/tmp}/crossover-sim-lock-selftest.$$"
CROSSOVER_SIM_LOCK_WAIT=3
export CROSSOVER_SIM_LOCK CROSSOVER_SIM_LOCK_WAIT

failures=0
owner_file="$CROSSOVER_SIM_LOCK/owner"

check() {
    printf '%-62s' "$1"
    if [ "$2" = 0 ]; then
        echo "PASS"
    else
        echo "FAIL"
        failures=$((failures + 1))
    fi
}

owner_is() {
    [ "$(cat "$owner_file" 2>/dev/null)" = "$1" ]
}

cleanup() {
    kill "$live" 2>/dev/null
    rm -rf "$CROSSOVER_SIM_LOCK"
}
trap cleanup EXIT INT TERM

rm -rf "$CROSSOVER_SIM_LOCK"

# A real process, so that "held" means held rather than stale.
sleep 60 &
live=$!

"$LOCK_UNDER_TEST" acquire "$live" 2>/dev/null && owner_is "$live"
check "acquire on a free lock records the caller" $?

"$LOCK_UNDER_TEST" acquire 4242 2>/dev/null
[ $? -eq 1 ]
check "a live holder blocks, then gives up with exit 1" $?

owner_is "$live"
check "the lock survives that contention, still owned by the holder" $?

"$LOCK_UNDER_TEST" release 4242 2>/dev/null
[ -d "$CROSSOVER_SIM_LOCK" ]
check "a non-owner cannot release someone else's lock" $?

"$LOCK_UNDER_TEST" release "$live" 2>/dev/null
[ ! -d "$CROSSOVER_SIM_LOCK" ]
check "the owner can release" $?

# wait sleeps once per tick and gives up on the last one, so a budget of N
# seconds spends N-1 of them asleep. What matters is that it does not return
# immediately while someone alive holds the lock.
"$LOCK_UNDER_TEST" acquire "$live" 2>/dev/null
started=$(date +%s)
"$LOCK_UNDER_TEST" wait 2>/dev/null
waited=$(($(date +%s) - started))
[ "$waited" -ge $((CROSSOVER_SIM_LOCK_WAIT - 1)) ]
check "wait does not return while a live holder has it" $?

# The regression that started all this: reclaiming must also restamp. If the
# owner file still names the dead process, every later session sees a stale
# lock and helps itself.
kill "$live" 2>/dev/null
wait "$live" 2>/dev/null
"$LOCK_UNDER_TEST" acquire 4242 2>/dev/null && owner_is 4242
check "a dead holder's lock is reclaimed AND restamped to the new owner" $?

"$LOCK_UNDER_TEST" release 4242 2>/dev/null
mkdir -p "$CROSSOVER_SIM_LOCK"
"$LOCK_UNDER_TEST" acquire 4242 2>/dev/null && owner_is 4242
check "a lock directory with no owner file counts as stale" $?

echo
if [ "$failures" -eq 0 ]; then
    echo "sim_lock: all checks pass"
else
    echo "sim_lock: $failures check(s) FAILED"
fi
exit "$failures"
