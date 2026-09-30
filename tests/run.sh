#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
lua tests/cctv.lua
