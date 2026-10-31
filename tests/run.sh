#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lua tests/cctv.lua
lua tests/garbage.lua
lua tests/recycle.lua
lua tests/recycle-client.lua
lua tests/recycle-sales.lua
lua tests/hotdog.lua
lua tests/taxi-authorization.lua
lua tests/taxi.lua
lua tests/tow.lua
