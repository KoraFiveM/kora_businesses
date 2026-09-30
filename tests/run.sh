#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lua tests/cctv.lua
lua tests/garbage.lua
lua tests/recycle.lua
lua tests/hotdog.lua
