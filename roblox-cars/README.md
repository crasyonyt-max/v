# Realistic Cars for Roblox

Eight drivable cars built entirely from parts, with simulation-grade physics.

| Car | Drive | Power | Character |
|---|---|---|---|
| Sedan | FWD | 2.5 L, 245 N·m | Comfortable family car |
| Hot Hatch | FWD + LSD | 1.6 turbo, 310 N·m | Light and nimble |
| Sports Coupe | RWD + LSD | 3.0 L, 380 N·m | Balanced, stiff, high-revving |
| Supercar | AWD | V10, 565 N·m | Downforce, 7 gears, 0.09 s shifts |
| Muscle Car | RWD | V8, 565 N·m | Heavy and tail-happy |
| SUV | AWD | 420 N·m | Tall, soft, rolls in corners |
| Pickup Truck | RWD | V8, 600 N·m | Long wheelbase, open bed |
| Police Interceptor | RWD | V8, 520 N·m | Livery, lightbar and siren lights |

## What makes it realistic

- **Raycast suspension** per wheel: springs and dampers set from real ride frequencies, plus anti-roll bars and bump stops. The body dives under braking, squats under power and rolls in corners.
- **Pacejka "magic formula" tires** with combined slip. Grip peaks at about 10% slip, then the tire slides. Braking and cornering share the same grip, and grip drops as load rises.
- **Drivetrain**: interpolated torque curves, a slipping clutch at launch, a rev limiter, engine braking, open or limited-slip differentials, FWD/RWD/AWD, and wheel spin that feels the engine's inertia.
- **Gearbox**: an automatic that kicks down and creeps at idle, or manual shifting with a shift-time torque cut.
- **ABS and traction control**, each of which you can turn off.
- **Aerodynamic drag and downforce**, plus speed-sensitive steering with Ackermann geometry.
- **Real gravity for cars** (9.81 m/s²), whatever `workspace.Gravity` is set to, so character jumping is unaffected.
- **Smooth driving online**: the driver's client owns the car's physics, and everyone else sees animated wheels, brake lights and steering.

All specs live in `src/RealisticCars/Configs.lua` in real units (kg, meters, N·m). To make a new car, copy an entry and change the numbers.

## Install (Roblox Studio, no tools needed)

1. Download `RealisticCars.rbxmx`.
2. In Studio, drag the file into **ReplicatedStorage**. You can also right-click ReplicatedStorage → *Insert from File...*.
3. Press **Play**. A row of cars spawns in front of the SpawnLocation. Walk up to one and press **E** to drive.

The scripts use `RunContext`, so the folder must stay in ReplicatedStorage. If there's no ground, a test baseplate is created.

### With Rojo
`rojo serve` from this folder (the project uses `emitLegacyScripts: false`).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle / brake | W / S (hold S at a stop to reverse) | RT / LT |
| Steer | A / D | Left stick |
| Handbrake | Space | X |
| Shift up / down (switches to manual) | E / Q | RB / LB |
| Auto / manual | M | |
| Traction control / ABS | T / B | |
| Headlights / siren | L / G | D-pad up / down |
| Flip car | R | Y |
| km/h / mph | U | |
| Get out | F | A |

On mobile, use the on-screen thumbstick to drive. A Brake button and a Flip button appear on screen.

## Options

- `Configs.METERS_PER_STUD` (default 0.25) sets the car scale relative to characters.
- `Configs.ENGINE_SOUND_ID`: set a looping engine sound you own. Its pitch follows the rpm.
- In `CarServer`: `SPAWN_SHOWROOM`, spacing, and abandoned-car respawn time. To spawn a car from your own server code, call `_G.RealisticCars.Spawn("Supercar", CFrame.new(0, 0, 0))`.

## Tests

`tests/run.sh` runs every car headless on a virtual track using the Luau CLI. It reports 0–100 km/h time, quarter mile, top speed, braking distance and cornering g, and checks for stability (no drift, flips or NaNs).

```
LUAU=/path/to/luau tests/run.sh
```

After editing the scripts, rebuild the Studio file with `python3 tools/build_rbxmx.py`.
