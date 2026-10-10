# Dino Duel

Realistic-ish 1v1 dinosaur combat, as a personality-driven AI sim. Part of the Precog sim suite.

**Live:** https://dino-duel.apps.precogsoftwareservices.com

Pick two animals and a personality for each, then watch them fight it out. The animal decides
what it *can* do; the personality decides what it *wants* to do.

## The animals

| | Mass | Speed | Weapons | Defences |
|---|---|---|---|---|
| T. rex | 8 t | 7.5 m/s | bone-crushing bite that holds and shakes, body slam, stomp | sheer size; slow to turn |
| Triceratops | 9 t | 7 m/s | 1 m brow horns (charge bonus), beak, shove | frill shields neck from the front |
| Ankylosaurus | 6 t | 3.6 m/s | tail club (breaks legs) | fused armour everywhere but the belly |
| Stegosaurus | 5 t | 4.6 m/s | thagomizer - four tail spikes, deep bleeding wounds | little |
| Allosaurus | 2 t | 9 m/s | "hatchet" slashing bite, claw rake | agility |
| Utahraptor | 0.5 t | 8.5 m/s | leap-and-cling, sickle-claw kicks, bite | very agile, tiny |

Numbers are rounded from the literature (Hutchinson 2011, Sellers 2017, Bates & Falkingham 2012,
Arbour 2009, McWhinney 2001, Rayfield 2001, Snively 2013) and tuned for a game, not a verdict.

## What "realistic" means here

- **Anatomy.** Each body has hitboxes - head, neck, chest, flank, belly, hips, tail, each leg -
  built from the same body plan as the 3D model. Weapons reach only what their arc, reach and
  height allow; armour is per zone and per damage type (crush / pierce / slash), and the
  Triceratops frill only protects from the front.
- **Wounds.** Damage is scaled by bone size. Breaks have consequences: a theropod with a broken
  leg goes down for good, a quadruped limps until it loses two; a broken tail disables a club or
  thagomizer; a crushed skull or a snapped neck kills; a chest stove in kills shortly after.
  Open wounds bleed according to the zone, the weapon and the size of attacker vs victim, and
  clot slowly. Below 60% blood the animal dies.
- **Stamina, shock, fear.** Running and attacking cost stamina; exhausted animals slow and hit
  weaker. Pain, blood loss and an outsized opponent build fear - past a personality-set
  threshold the animal runs, and if it gets clear the other wins.
- **Weapons behave differently.** Bites are aimed; tail swings hit what's in the way; horns get a
  charge bonus; a Rex bite can turn into a hold-and-shake; a Utahraptor can leap on and cling,
  kicking, until it's thrown off or bitten.

## Personalities

Eight traits (aggression, caution, cunning, persistence, nerve, pacing, display, opportunism)
drive a utility brain: where to stand around the other animal (weighing what each weapon can
reach there against the other's weapons covering that spot), when to commit, when to hit and run,
rest, roar, press a downed opponent, chase or let go. Presets: Balanced, Berserker, Stalker,
Bully, Bleeder, Bulwark, Brawler, Skittish, Random, or Custom sliders - for each animal.

## Modes

- **Duel** - watch it in 3D at 0.5x-4x, with a live log, per-animal bars and status, and a full
  results breakdown (wounds by zone, weapon hit rates, bleeding, fear, holds, charges...).
- **Sim x20 / x100** - the current matchup run instantly, with win rates (+-1 sigma), how duels
  ended, and per-side weapon and wound statistics.
- **Personality league** - every personality on the Red animal against Blue as set, 20 duels each.

Query string = settings: `?a=anky&b=rex&pa=Bulwark&pb=Stalker&seed=7&intents`.
Custom traits: `?ca=aggression:0.9,caution:0.2`.

## Code

Pure simulation (no nodes) in `species.gd`, `personality.gd`, `fighter.gd`, `duel.gd`,
`batch.gd`; rendering in `dino_view.gd` (procedural models), `arena.gd`, `camera_rig.gd`,
`sfx.gd` (all sound synthesised); UI in `hud.gd`; `main.gd` steps the sim at 30 Hz and
interpolates the views.

Headless (no window):

```
godot --headless --path . -- --sim=50 --a=rex --b=trike --pa=Stalker [--log]
godot --headless --path . -- --matrix=40            # every species v every other
godot --headless --path . -- --presets=40 --a=rex --b=trike
tools/stats.sh allo stego 40                         # one pairing, digested
godot --headless --path . -s tools/trace.gd -- --a=allo --b=stego --seed=3
```

Build: `./build.sh` (Godot 4.7.2 + web templates) writes `dist/`; `Dockerfile` serves it with nginx.
