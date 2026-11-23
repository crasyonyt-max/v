#!/usr/bin/env bash
# Publish the built place. Default = the admin TESTING place; "live" only after the
# owner's OK for a global update.
#   tools/publish.sh          -> testing place (Config.TestPlaceId)
#   tools/publish.sh live     -> the real game (Config.MainPlaceId)
set -euo pipefail
cd "$(dirname "$0")/.."
UNIVERSE=9590202839
MAIN=$(grep -oP '^Config.MainPlaceId = \K[0-9]+' src/ReplicatedStorage/Shared/Config.lua)
TEST=$(grep -oP '^Config.TestPlaceId = \K[0-9]+' src/ReplicatedStorage/Shared/Config.lua)
TARGET=${1:-test}
if [ "$TARGET" = live ]; then PLACE=$MAIN; else PLACE=$TEST; fi
if [ "$PLACE" = 0 ]; then echo "Config.TestPlaceId is not set" >&2; exit 1; fi
python3 build.py
for t in 0 4 8 16; do
	sleep $t
	r=$(curl -sS -m 300 -X POST \
		"https://apis.roblox.com/universes/v1/$UNIVERSE/places/$PLACE/versions?versionType=Published" \
		-H "x-api-key: proxy-injected" -H "Content-Type: application/xml" \
		--data-binary @build/DortmundRP.rbxlx) || true
	echo "$TARGET ($PLACE): $r"
	echo "$r" | grep -q versionNumber && exit 0
done
exit 1
