#!/bin/sh
# Builds bruh.apk without the Android SDK.
# Needs: JDK, python3, and in $TOOLS: android.jar (com.google.android:android:4.1.1.4)
# and dx.jar (com.jakewharton.android.repackaged:dalvik-dx:16.0.1), both from Maven Central.
set -e
cd "$(dirname "$0")"
TOOLS=${TOOLS:?set TOOLS to the folder with android.jar and dx.jar}
OUT=build
rm -rf $OUT && mkdir -p $OUT/classes $OUT/apk/assets

javac --release 8 -nowarn -cp "$TOOLS/android.jar" -d $OUT/classes src/com/novasystems/bruh/*.java
java -cp "$TOOLS/dx.jar" com.android.dx.command.Main --dex --min-sdk-version=16 --output=$OUT/apk/classes.dex $OUT/classes
python3 make_manifest.py $OUT/apk/AndroidManifest.xml
cp assets/bruh.png $OUT/apk/assets/

[ -f $OUT/../bruh.keystore ] || keytool -genkeypair -keystore bruh.keystore -storepass bruhbruh -keypass bruhbruh \
    -alias bruh -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=bruh" >/dev/null 2>&1
(cd $OUT/apk && rm -f ../unsigned.apk && jar cfM ../unsigned.apk AndroidManifest.xml classes.dex assets)
jarsigner -keystore bruh.keystore -storepass bruhbruh -sigalg SHA256withRSA -digestalg SHA-256 \
    -signedjar $OUT/bruh.apk $OUT/unsigned.apk bruh >/dev/null
echo "built $OUT/bruh.apk"
