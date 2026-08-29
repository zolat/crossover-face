#!/bin/sh
# Launch the simulator MCP server with an interpreter that actually has `mcp`.
#
# MCP servers are started by the editor, not from your shell, so PATH can be leaner than
# the one you tested with - and a bare `python3` may then resolve to a system interpreter
# without the dependencies. Picking the first candidate that can import mcp turns a
# confusing "server failed to start" into either a working server or one clear message.
#
# Override with CROSSOVER_PYTHON if you keep the dependencies somewhere else.
HERE="$(cd "$(dirname "$0")" && pwd)"

# pyenv first among the fallbacks: where a version manager is in use, the system
# interpreter is exactly the one that will not have the packages. Measured here - under
# PATH=/usr/bin:/bin nothing else on this machine can import mcp.
for candidate in "${CROSSOVER_PYTHON:-}" python3 \
                 "${PYENV_ROOT:-$HOME/.pyenv}/shims/python3" \
                 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    [ -n "$candidate" ] || continue
    if "$candidate" -c 'import mcp, PIL' >/dev/null 2>&1; then
        exec "$candidate" "$HERE/sim_mcp.py" "$@"
    fi
done

echo "sim_mcp: no python3 with the 'mcp' and 'pillow' packages was found." >&2
echo "         Install them (pip install mcp pillow) or set CROSSOVER_PYTHON." >&2
exit 1
