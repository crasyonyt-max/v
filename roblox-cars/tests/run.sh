#!/usr/bin/env bash
# Runs the headless physics tests with the Luau CLI.
#   LUAU=/path/to/luau tests/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$here/../src/RealisticCars"
build="$here/.build"
LUAU="${LUAU:-luau}"

rm -rf "$build" && mkdir -p "$build"
prelude='local __m = require("./mocks"); local Vector3, CFrame, Color3 = __m.Vector3, __m.CFrame, __m.Color3'
for f in Configs Tire Layout Sim; do
	{ echo "$prelude"; sed -E 's/require\(script\.Parent\.([A-Za-z]+)\)/require(".\/\1")/g' "$src/$f.lua"; } > "$build/$f.luau"
done
cp "$here/mocks.lua" "$build/mocks.luau"
cp "$here/run_tests.lua" "$build/run_tests.luau"
"$LUAU" "$build/run_tests.luau"
