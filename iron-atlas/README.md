# Iron Atlas — Conquest of Europe

A real-time grand-strategy war game played on satellite imagery of Europe.
Download: [`downloads/IronAtlas.apk`](../downloads/IronAtlas.apk) (Android 5.0+).

![icon](art/icon-512.png)

## Gameplay
- **Play as a country** (45 European nations) or **create your own nation** (name, color, emblem)
  by breaking away from a country.
- Europe is split into 275 provinces. Each earns 💰 gold and raises 🪖 troops.
- Tap one of your provinces, then a **red** neighbor to attack or a **green** one to move troops.
  Dashed links are sea crossings (slower, 25% weaker).
- Recruit troops, build 🛡 forts, declare war and make peace in **Diplomacy**.
- Take an enemy capital ★ once it has lost most of its land and the whole country surrenders.
- 45 AI nations wage their own wars. Control 70% of Europe to win.
- Scenarios: *Present day (2026)* or *Peaceful Europe*. AI aggression: Calm / Normal / Chaos.
- Auto-saves; continue from the title screen.

## Map data
- Satellite imagery: Esri World Imagery (needs internet; the game still works offline on a plain map).
  Google Maps/Earth tiles can't be used: Google's terms forbid loading their tiles outside their own SDKs.
- Borders: Natural Earth 1:50m (via `world-atlas`), split into provinces by `tools/build-data.js`.

## Building
```bash
# 1. (optional) regenerate provinces
cd tools && npm install && node build-data.js && cd ..
# 2. build the APK (Ubuntu: apt install android-sdk-build-tools android-sdk-platform-23 apksigner zipalign)
./build-apk.sh            # writes ../downloads/IronAtlas.apk
```
Bump `VERSION_CODE=2 VERSION_NAME=1.0.1 ./build-apk.sh` for updates. Updates must be signed with
`android/ironatlas.keystore` (password `ironatlas`) or Android won't install them over the old version.

To try it in a browser, open `www/index.html`.
