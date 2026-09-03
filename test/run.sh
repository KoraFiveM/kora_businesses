#!/usr/bin/env bash
# Runs every qbbusinesses smoke test with plain Lua -- no FiveM, no database.
#
# The schema is realm-agnostic on purpose, so it is exercised for real here.
# The server/client files cannot run outside FXServer, so their suites read the
# source and assert the invariants that matter (authorisation, rate limits,
# rollbacks) are actually written down rather than assumed.
set -uo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua_bin="${LUA:-lua}"
status=0
headers=0

for file in "$dir"/smoke/*.lua; do
    echo "== $(basename "$file" .lua) =="
    headers=$((headers + 1))
    if ! ( cd "$dir/.." && "$lua_bin" "$file" ); then status=1; fi
    echo
done

echo "-- ran $headers suite(s) --"
exit "$status"
