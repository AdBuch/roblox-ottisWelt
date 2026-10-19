#!/usr/bin/env sh
# Builds both Places into build/ (git-ignored). Usage: sh scripts/build-places.sh
set -e
cd "$(dirname "$0")/.."
ROJO="${ROJO:-rojo}"
command -v "$ROJO" >/dev/null 2>&1 || ROJO="$HOME/.aftman/bin/rojo"
mkdir -p build
"$ROJO" build places/hub.project.json -o build/OttiHub.rbxlx
"$ROJO" build places/arena.project.json -o build/OttiArena.rbxlx
