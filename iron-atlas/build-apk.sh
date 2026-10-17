#!/usr/bin/env bash
# Builds Iron Atlas into a signed APK without Gradle.
# Needs: aapt2, dx (or d8), zipalign, apksigner, an android.jar, javac, keytool.
#   Ubuntu: apt install android-sdk-build-tools android-sdk-platform-23 apksigner zipalign
# Usage: ./build-apk.sh [output.apk]
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
OUT=${1:-$ROOT/../downloads/IronAtlas.apk}
SDK=${ANDROID_SDK:-/usr/lib/android-sdk}
JAR=${ANDROID_JAR:-$(ls -d "$SDK"/platforms/android-*/android.jar | sort -V | tail -1)}
BT=$(ls -d "$SDK"/build-tools/*/ | sort -V | grep -v debian | tail -1)
DX=${DX:-$BT/dx}
VERSION_CODE=${VERSION_CODE:-3}
VERSION_NAME=${VERSION_NAME:-1.2.0}
KEYSTORE=${KEYSTORE:-$ROOT/android/ironatlas.keystore}
KS_PASS=${KS_PASS:-ironatlas}

B=$ROOT/build
rm -rf "$B" && mkdir -p "$B"/{res,gen,classes,assets,dex}

echo "> assets"
cp -r "$ROOT/www" "$B/assets/www"

echo "> resources"
aapt2 compile --dir "$ROOT/android/res" -o "$B/res/res.zip"
aapt2 link -o "$B/base.apk" -I "$JAR" --manifest "$ROOT/android/AndroidManifest.xml" \
  --min-sdk-version 21 --target-sdk-version 34 --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
  -A "$B/assets" --java "$B/gen" --auto-add-overlay "$B/res/res.zip"

echo "> java"
javac -nowarn -Xlint:-options -source 8 -target 8 -bootclasspath "$JAR" -d "$B/classes" \
  $(find "$ROOT/android/src" "$B/gen" -name '*.java')
"$DX" --dex --output="$B/dex/classes.dex" "$B/classes"

echo "> package"
cp "$B/base.apk" "$B/unaligned.apk"
(cd "$B/dex" && zip -q -X "$B/unaligned.apk" classes.dex)
zipalign -f -p 4 "$B/unaligned.apk" "$B/aligned.apk"

if [ ! -f "$KEYSTORE" ]; then
  echo "> creating signing key $KEYSTORE"
  keytool -genkeypair -keystore "$KEYSTORE" -storepass "$KS_PASS" -keypass "$KS_PASS" -alias ironatlas \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Iron Atlas, O=Nova Systems LLC, C=US" >/dev/null 2>&1
fi
echo "> sign"
apksigner sign --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" --ks-key-alias ironatlas --out "$OUT" "$B/aligned.apk"
apksigner verify "$OUT"
rm -f "$OUT.idsig"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
