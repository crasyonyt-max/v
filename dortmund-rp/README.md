# Dortmund RP (Roblox)

German roleplay game set in Dortmund. Built entirely as code, with no Roblox Studio needed.
`python3 build.py` turns `src/` into `build/DortmundRP.rbxlx`, which is uploaded to the
experience through Roblox Open Cloud.

## Phase 1: core systems (this version)

| System | Status |
|---|---|
| Saving (DataStore, session lock, autosave, safe shutdown) | ✅ |
| Money in € (bank, transfers, transaction history, paychecks, Bürgergeld) | ✅ server-validated |
| XP: global level + separate XP per job, level-up messages, XP bar | ✅ |
| Jobs: Police, Fire, Rettungsdienst, Notarzt, ADMC, DXL, LKW (start at station, quit in phone) | ✅ |
| Emergency calls 110 / 112 → matching jobs, accept, navigate, complete for XP + € | ✅ anti-farm checks |
| Phone with apps: Telefon, ChatsApp, Bank, Jobs, Garage, Einsätze, Einstellungen, Admin | ✅ |
| ChatsApp across servers + offline inbox, **23646 → all Game Admins** (with replies) | ✅ text-filtered |
| Handyland: all 10 phones; **NVDR P1** Game-Admin phone with rebuilt boot animation | ✅ |
| Autohaus: 20 cars, 5 gamepass packs (Robux + €), selling at 50 % | ✅ |
| Free starter car choice (Golfo IV, Korsa C, Fiesto) | ✅ |
| Every car in the catalog is drivable (procedural body + interior, seats, dashboard) | ✅ |
| Job vehicles unlocked by job XP, spawn at the station | ✅ |
| German plates "DO-AB 1234", customizable, unique game-wide, filtered | ✅ |
| Lights, indicators, hazards, blue lights (German double flash), siren, fuel + Arol station | ✅ |
| Dashboard: speed, RPM, fuel, PRND, indicators; first-person camera | ✅ |
| Admin system (Game Admin / Server Admin), all actions server-checked + logged | ✅ |
| Day/night cycle, weather (clear, cloudy, rain, fog), street lights | ✅ |
| German + English | ✅ |
| Test map: Hbf, Königswall, Westenhellweg, Ferdinandstraße 24, all stations | ✅ (placeholder) |

## Admin rules

* **Game Admin** = the experience owner (automatic) + UserIds in `Config.GameAdmins`.
  Whole game: global bans (Roblox Ban API, temporary or permanent), global announcements,
  shutdown of all servers, **giving money / XP / cars (Game Admins only)**, 23646 inbox.
* **Server Admin** = private server owner + people they appoint. Same moderation tools, but
  only on their own server: bans are server bans, announcements and shutdown are local, and
  they cannot give anything.
* Nobody can act on someone of the same or higher rank.

## Coming next (planned phases)

2. **Map**: real Dortmund areas at closer-to-real scale (Innenstadt, Hbf, Westenhellweg,
   Phoenix-See, Hörde, Kreuzviertel, Nordstadt, U-Tower, Florianturm, stadium, B1, Autobahn).
3. **Job gameplay**: police tools (cuffs, ticket book, breathalyzer, jail), fires + hoses,
   patients + defibrillator, ADMC repairs + towing, DXL parcels, LKW freight routes.
4. **Housing** (all 7 addresses, keys, mailbox, Ikora furniture), shops (Lindl, Alda, Rewo, Ikora).
5. **Server browser** (Public / RP / Private with codes, ReserveServer), traffic lights, Blitzer,
   driving licence, insurance, more phone apps (Camera, Gallery, Amazo, Maps, Instaframe, Car Market).

## Setup checklist

1. Add your UserId (and other Game Admins) to `Config.GameAdmins` in
   `src/ReplicatedStorage/Shared/Config.lua`. The experience owner is already a Game Admin.
2. Create the 5 gamepasses (creator hub → experience → Monetization → Passes) and paste
   their IDs into `Config.Gamepasses`.
3. Upload `assets/martinshorn.ogg` and `assets/nvdr_boot.ogg` as audio, put the IDs into
   `Config.Sounds`.

## Building and publishing

```
python3 build.py
curl -X POST "https://apis.roblox.com/universes/v1/<UNIVERSE_ID>/places/<PLACE_ID>/versions?versionType=Published" \
  -H "x-api-key: <OPEN_CLOUD_KEY>" -H "Content-Type: application/xml" \
  --data-binary @build/DortmundRP.rbxlx
```

The API key needs the `universe-places:write` permission for this experience.

## Layout

```
src/ReplicatedStorage/Shared      catalogs + config shared by server and client
src/ServerScriptService/Server    all game logic (the only place money/XP/items change)
src/StarterPlayer/StarterPlayerScripts/Client   UI, phone, driving, effects
assets/                           NVDR P1 artwork, boot sound, Martinshorn
```

All brand names are parodies; no real logos, Red Cross emblem or coats of arms are used.
