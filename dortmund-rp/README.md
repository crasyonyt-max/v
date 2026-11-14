# Dortmund RP: Vehicle System

## Install (Studio)
1. Drag `ReplicatedStorage.rbxmx` into **ReplicatedStorage**. It adds `VehicleConfig` and `LiveryConfig`.
2. Drag `RealisticCars.rbxmx` into **ReplicatedStorage**. It adds the driving physics, the HUD and the part-built car bodies.
3. Drag `VehicleSystem.rbxmx` into **ServerScriptService**.
4. Game Settings → Security → turn on **Enable Studio Access to API Services** to test saving in Studio.

On server start, every vehicle without a model in `ServerStorage/Vehicles` gets a **drivable 3D placeholder** built from parts. It comes with all the livery parts (stripes, accent band, lettering, lightbar, window grilles, LKW cargo box), so liveries and lights work right away. When you put a real model with the same name in `ServerStorage/Vehicles`, it is used instead. Body shapes are chosen in `VehicleModelGenerator` (`BODY_RULES`).

In game: press **E** at a car to drive, **G** for the blue/orange lights, **L** for headlights, **H** for all controls.

Alternatively, run `rojo serve`. `default.project.json` maps everything, including `../roblox-cars`.

## Tagging your models (CollectionService / Tag Editor)
| Tag | What happens |
|---|---|
| `Body`, `Stripe`, `Accent` | The part gets that livery color |
| `Lettering` | Shows the livery text. It uses a TextLabel already in the part, or creates SurfaceGuis on the faces in the attribute `LetteringFaces` (default `Left,Right`). Attribute `LetteringSlot = "Secondary"` shows `DRH` on EMS cars |
| `EmergencyLight` | Colored blue or orange by LightType. Hidden on `none` and `hidden_blue` (the model gets attributes `LightType` and `LightsHidden` for your light script) |
| `Extra` + attribute `ExtraName` | Kept only if the vehicle lists it (for example `WindowGrilles` on the police Sprintor) |
| Child model named `Trailer` | LKW: painted with a random market livery (LINDL / ALDA / REWO / IKORA) |

## Connecting your job system
```lua
local PlayerData = require(game.ServerScriptService.VehicleSystem.PlayerDataAdapter)
PlayerData.SetCurrentJob(player, "Police")   -- on duty ("Police","Fire","EMS","Notarzt","ADMC","DXL","LKW")
PlayerData.SetCurrentJob(player, nil)        -- off duty (their job vehicle despawns)
PlayerData.AddJobXP(player, "Police", 50)
PlayerData.AddMoney(player, 1200)
```

## Client remotes (`ReplicatedStorage.VehicleRemotes`, RemoteFunctions)
`GetPlayerVehicleData`, `PurchaseVehicle(id)`, `ClaimStarter(id)`, `SpawnVehicle(id)`, `DespawnVehicle()`,
`RepaintVehicle(id, {Body=Color3, Stripe=Color3, Accent=Color3} or "reset")`,
`AppointServerAdmin(userId)`, `RemoveServerAdmin(userId)`, `GetServerAdmins()`.
Each returns `{ Success, Message, ... }`. Vehicle ids are in `VehicleConfig.List[i].Id`.

## Before release
- Replace `GamepassId = 0` in VehicleConfig with your real gamepass IDs. Placeholder packs work in Studio and are locked in live servers.
- Add Game Admin UserIds in `AdminConfig`.
- After editing the scripts, rebuild the Studio files with `python3 tools/build_rbxmx.py`.
