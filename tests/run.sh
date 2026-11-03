#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lua tests/cctv.lua
lua tests/garbage.lua
lua tests/recycle.lua
lua tests/recycle-client.lua
lua tests/recycle-sales.lua
lua tests/hotdog.lua
lua tests/mechanic.lua
lua tests/taxi-authorization.lua
lua tests/taxi.lua
lua tests/taxi-meter.lua
if command -v node >/dev/null 2>&1; then node tests/taxi-meter.test.js; fi
lua tests/config-toggles.lua
lua tests/tow.lua
