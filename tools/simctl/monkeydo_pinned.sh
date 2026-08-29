#!/bin/bash
# Argument-compatible with the SDK's monkeydo, but routed at one instance.
#
# Drop-in for the Makefile's MONKEYDO, so an isolated instance can run the existing
# targets unchanged:
#
#   make test SIM_LOCK=true MONKEYDO=tools/simctl/monkeydo_pinned.sh
#
# The SDK's monkeydo is a bash script whose only real line is a java invocation; this
# reproduces it with -s pointed at shell_pinned.sh. Arguments after the device id are
# passed straight through, which covers -n, -a and -t exactly as monkeydo does.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
: "${CROSSOVER_SIM_PORT:?monkeydo_pinned.sh needs CROSSOVER_SIM_PORT}"
SDK="${CROSSOVER_SDK:-$(connect-iq-sdk-manager sdk current-path)}"

PRG="$1"
DEVICE="$2"
shift 2

export CROSSOVER_SIM_PORT
export CROSSOVER_SDK_SHELL="${CROSSOVER_SDK_SHELL:-${SDK}bin/shell}"

exec java -classpath "${SDK}bin/monkeybrains.jar" \
     com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux \
     -f "$PRG" -d "$DEVICE" -s "$HERE/shell_pinned.sh" "$@"
