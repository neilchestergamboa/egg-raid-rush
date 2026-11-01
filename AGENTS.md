# AGENTS.md — shared rules for every AI tool in this repo

Game: **Egg Raid Rush** (working title), a Roblox game for kids aged 9+. Design source of truth: `docs/GDD_v0.11.docx` (current version). If code and the GDD disagree, stop and ask; do not guess. Keep this master copy synchronized with `CLAUDE.md` and `.cursor/rules/project.mdc`.

## Game loop

Eight players share a straight map. A Safe Zone sits at one end, with six themed egg zones beyond it. The player presses E on an egg; their equipped Champion pet breaks it; the hatched creature fights the pet; the winner carries the creature while the zone Guard chases; reaching the Safe Gate banks it. Pets earn Gold on the Ranch. The Treadmill trains player Speed. Each species has one fixed size that never affects stats; condition is the only hatch roll.

## Hard rules

1. **Server is the truth.** Claims, damage, fight results, Guard tags, drops, banking, costs, and rewards are decided on the server. The client only presents state and sends requests.
2. **Everything is data.** Zones, eggs, pets, guards, rarities, conditions, and treadmill tiers live in `src/shared/Config/`. Never hard-code gameplay numbers in a service.
3. **Pure rules.** Gameplay math lives in `src/shared/Rules/` as pure functions with unit tests. Services call Rules; Rules never touch Roblox services.
4. **Luau strict mode.** Use `--!strict` in every Luau file. StyLua and Selene must pass.
5. **Framework shim.** Only `src/shared/Framework.luau` may require Knit. Hot-path remotes use Zap (`net/net.zap`).
6. **Every remote** has a schema, a per-player rate limit, and a typed result code.
7. **Idempotent and safe.** Banking, purchases, fusing, and grants must be idempotent. Commit the result before consuming inputs. Never reset or overwrite progression silently; version and migrate profiles.
8. **Retired design is excluded.** No Hook, crystal, pickaxe, Catch Bar, mining, Strength, or size-roll code.
9. **Kid-friendly (9+).** No blood or gore. Create original characters only; do not use look-alikes of existing franchises.
10. **Folder ownership is strict.** Do not edit outside your task's owned folders. If another folder needs a change, note it in the pull request.

## Folder ownership

| Folder | Owner |
| --- | --- |
| `docs/`, `sim/` (simulations and balance notes) | Claude |
| `src/shared/Config/`, `src/shared/Rules/`, `src/shared/Types/`, `tests/` | Codex (Claude reviews numbers) |
| `src/server/Services/` | Codex |
| `src/client/Controllers/`, `src/client/UI/` | Cursor |
| Studio map, models, art, audio | Human + image/audio tools |

## Workflow

- One task per branch (for example `task/T07-egg-service`) and pull request.
- Every PR states the task ID, GDD sections implemented, and how it was tested.
- CI must pass StyLua, Selene, Zap generation check, `rojo build`, and unit tests.
- A different tool reviews each PR; Claude reviews against the GDD.
- Never push directly to `main`.

## Repository layout

```text
repo root/
  default.project.json  wally.toml  selene.toml  stylua.toml
  net/net.zap
  src/shared/  Framework.luau  Config/  Rules/  Types/  Util/
  src/server/  Bootstrap.server.luau  Services/
  src/client/  Bootstrap.client.luau  Controllers/  UI/
  tests/  docs/  sim/
```

## Naming

Services: `EggService`, `ClaimService`, `EggBreakService`, `FightService`, `GuardService`, `CarryService`, `TreadmillService`, `PetService`, `RanchService`, `EconomyService`, `DataService`.

Config modules: `ZoneDefs`, `EggDefs`, `PetDefs`, `GuardDefs`, `RarityDefs`, `ConditionDefs`, `TreadmillDefs`.

## Phase A: playable egg raid prototype

Goal (GDD section 16, Phase A): straight map blockout, Safe Gate, one egg zone (Zone 1), claim, break, fight, carry, Guard chase, and bank. Use contest model A only (no Challenge window). Starter pet only; no Ranch, shop, or fusing yet.

Done when one player can press E on a Zone 1 egg, see their pet break it and win the fight, outrun the Pride King to the Safe Gate, and see the creature enter inventory. Then repeat with eight bots or players.

| ID | Task | Tool | GDD sections | Depends on | Acceptance |
| --- | --- | --- | --- | --- | --- |
| T01 | Repo scaffold: Rojo, Wally, StyLua, Selene, Jest-Lua, GitHub Actions CI, Framework shim, Zap schema stub | Codex | 14.1 | none | Empty place boots; CI green on fresh clone |
| T02 | Map blockout in Studio: Safe Zone, 8 bases, Safe Gate, Zone 1 egg field with 6 slots, equal path length from every base to gate | You | 3 | none | Path-length check within 0.1 stud |
| T03 | Pacing and fight simulation: confirm fight duration, Speed Rank needed vs Guard speed, tutorial values; output tuned Zone 1 numbers | Claude | 4, 5, 6, 8 | none | `sim/` script plus short table of final values |
| T04 | Shared Config: ZoneDefs, EggDefs, PetDefs, GuardDefs, RarityDefs, ConditionDefs for Zone 1, with boot validation | Codex | 4.3, 4.6, 5, 9 | T01, T03 | Broken def fails boot with a clear message |
| T05 | Shared Rules and unit tests: PetPower, EggDamage, FightSim (seeded, 0.5 s ticks), GuardSpeed, SpeedRank | Codex | 4.2, 4.3, 5, 6, 8.1 | T04 | Tests pass; parity fight lasts about 10 s |
| T06 | DataService with ProfileStore and Phase A profile template (Pets, ChampionPetUid, SpeedPoints) | Codex | 14.3 | T01 | Save on leave, load on rejoin, session lock works |
| T07 | EggService: slots, rarity, respawn timers, claim state, replicated attributes | Codex | 5.2, 5.3 | T04, T06 | State machine logged and idempotent; late joiner sees live state |
| T08 | ClaimService and EggBreakService: press E, validate, pet damage over time, claim timeout, crack stages | Codex | 6, 7 | T07, T05 | Simultaneous presses resolve by server time; 60 s timeout releases egg |
| T09 | FightService: committed condition roll at claim, auto-battle, retreat, knockout timer, starter-pet fallback rule | Codex | 4.3, 6 | T08 | Condition cannot be rerolled by disconnect; losing pet recovers |
| T10 | GuardService and CarryService: Guard wake/chase, tag drops creature, pickup, Safe Gate banking, death/disconnect rules | Codex | 8 | T09, T02 | Banking idempotent; no duplication on death or disconnect |
| T11 | Client HUD: E prompt, claim ring, egg health bar/crack stages, fight HP bars, rising audio cue | Cursor | 6 | T08 (remote shapes) | Desktop and phone, with on-screen action button |
| T12 | Client chase UI: carry indicator, Guard warning, drop timer, pickup prompt, Safe Gate banking effect | Cursor | 8 | T10 (remote shapes) | Readable on a small screen |
| T13 | First-five-minutes tutorial: tutorial egg, half-power hatchling, slow tutorial Guard, forgiven first drop | Cursor + Codex | 2.1 | T10, T11, T12 | First success inside 60 seconds in stranger playtest |
| T14 | Review each merged PR against GDD and check numbers against Config | Claude | all | each PR | Written review on each PR |
| T15 | Playtest with 8 bots or testers; log fight, chase, and claim data | You + Claude | 15 | T13 | Report with fixes ranked |

### Parallel lanes

- Lane 1 (you): T02 map.
- Lane 2 (Claude): T03 simulation, then T14 reviews.
- Lane 3 (Codex): T01, then T04, T05, T06, T07, T08, T09, T10 in order.
- Lane 4 (Cursor): T11 and T12 can start once Zap remote shapes from T08 and T10 are agreed; use stubs until then.

### Task handoff

Copy the task row, link the GDD sections, point to `AGENTS.md`, and add “do not edit outside the owned folders”. Ask for tests with every service.

## ServerEngineer guidance for Codex

You are a senior Luau server and systems engineer for Egg Raid Rush. Build server-authoritative gameplay code, shared config, and pure rules; do not touch client UI or art.

Before each task, read this file and the named sections of `docs/GDD_v0.11.docx`. If task, code, and GDD disagree, stop and record the question in the PR. List assumptions. Write Rules and tests before services. Run StyLua, Selene, unit tests, and `rojo build`. Do not claim completion if checks fail or are skipped.

Seed randomness for reproducibility and log seeds. Condition is the only hatch roll; species size is fixed and never affects stats. Save with retry/backoff and migrate profiles by version. Replicate state through attributes or state folders so late joiners see the correct state. Unit-test every Rules function and state transition, including failures and duplicate calls.

Every task's delivery includes code only in owned folders, tests, and a short PR note with task ID, GDD sections, test results, and uncertainties. Never edit `src/client/`, `docs/`, or `sim/` as Codex.
