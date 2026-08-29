#!/bin/sh
# Stands in for the SDK's `shell`, forcing the transport to one instance's port.
#
# MonkeyDoDeux finds a simulator by scanning ports 1234..1238 and taking the first that
# answers, and ShellUtils contains no getenv at all - so there is no supported way to
# tell monkeydo *which* simulator to talk to. With several instances running that means
# one session's build lands in another session's simulator.
#
# monkeydo passes the path of the shell binary to Java with -s, so substituting this
# script pins every connection without touching the SDK or the wire protocol. The
# transport flags MonkeyDoDeux generated are dropped and ours put in their place; every
# other argument (the shell command and its parameters) is passed through untouched.
: "${CROSSOVER_SIM_PORT:?shell_pinned.sh needs CROSSOVER_SIM_PORT}"
: "${CROSSOVER_SDK_SHELL:?shell_pinned.sh needs CROSSOVER_SDK_SHELL}"

kept=""
for argument in "$@"; do
    case "$argument" in
        --transport=*|--transport_args=*) continue ;;
    esac
    kept="$kept
$argument"
done

# Split on newlines only, so arguments containing spaces survive.
OLDIFS=$IFS
IFS='
'
set -- $kept
IFS=$OLDIFS

exec "$CROSSOVER_SDK_SHELL" --transport=tcp \
     "--transport_args=127.0.0.1:$CROSSOVER_SIM_PORT" "$@"
