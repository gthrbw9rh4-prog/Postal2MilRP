# Postal 2: Share The Pain - MilRP (Military Roleplay)

Multiplayer total-conversion game type for Postal 2 (Steam build 5025+) inspired by
SA-MP and Garry's Mod military roleplay servers: factions, ranks, on/off duty,
paychecks and a roleplay HUD.

## Layout

```
Postal2-MilRP/
  MilRP/Classes/            UnrealScript sources -> compiles to System/MilRP.u
    MilRP.upkg              package flags (downloadable, required on client + server)
    MilRPGameInfo.uc        server rules, login, economy loop, factions, loadouts
    MilRPGameReplicationInfo.uc  faction/rank tables + broadcast ring buffer (server -> all)
    MilRPPlayerReplicationInfo.uc faction/rank/duty per player (server -> all)
    MilRPPlayer.uc          player controller: duty toggle, wallet (owner-only), RPCs   [Phase 2]
    MilRPHUD.uc             canvas overlay: rank / faction / duty / broadcast feed       [Phase 2]
    MilRPAddon.uc           base class for runtime, config-loaded content modules
    MilRPWorld.uc           world coordinator: addon registry, interaction spawners, sirens
    MilRPLog.uc             plain-text admin + economy event logger
    MilRPInteractPoint.uc   base for USE-driven interaction points
    MilRPEnlistTerminal.uc  faction selection / enlistment
    MilRPDutyStation.uc     clock on/off
    MilRPArmoryLocker.uc    faction/rank-locked equipment
    MilRPATMPaymaster.uc    bank, deposit/withdraw/transfer, physical paycheck pickup
    MilRPShopLocker.uc      rank/faction-locked item shop
    MilRPSiren.uc           DEFCON / lockdown siren and visual alarm
    MilRPTestBot.uc         internal headless stress agent
    MilRPAdminInteraction.uc   client-side admin board interaction (mouse UI)
    MilRPArmoryInteraction.uc  armory locker GUI interaction
    MilRPDEFCONConsole.uc   DEFCON alert terminal placeable
    MilRPDEFCONInteraction.uc  DEFCON console GUI interaction
    MilRPShopInteraction.uc quartermaster shop GUI interaction
    MilRPSpawnMenu.uc       F2 admin spawn menu (weapons/props/NPCs/skins)
    MilRPScoreboardMenu.uc  F1/Tab roleplay scoreboard interaction
    MilRPCapturePoint.uc    faction territory capture zone (tug-of-war + paycheck bonus)
  LaunchDedicatedServer.bat   headless dedicated server launcher (ports 7777/7778)
  SERVER_HOST_GUIDE.md      how to host, open ports, add admins, customize factions
  System/
    MilRP.ini               runtime configuration template (copied once on build)
    MilRP.int               English localization
    MilRP.u                 build artifact (git-ignored)
  Tools/
    make.bat                ucc make wrapper (syncs sources, generates build ini, compiles)
    gen-makeini.ps1         builds MilRP_Make.ini from the game's Postal2.ini + EditPackages=MilRP
  Maps/ Textures/ Sounds/ StaticMeshes/   content packages (empty for now)
```

## Base classes targeted (Postal 2 build 5025 script tree)

| MilRP class                    | Extends                              | Why |
|--------------------------------|--------------------------------------|-----|
| `MilRPGameInfo`                | `MultiBase.DeathMatch`               | keeps login/PostLogin handshake, respawn, roster and match state machine; end conditions forced off |
| `MilRPGameReplicationInfo`     | `MultiBase.MpGameReplicationInfo`    | static faction/rank tables sent on `bNetInitial`, broadcast ring buffer on `bNetDirty` |
| `MilRPPlayerReplicationInfo`   | `MultiBase.MpPlayerReplicationInfo`  | faction/rank/duty visible to everyone; `Score` is reused as RP score |
| `MilRPPlayer`                  | `MultiStuff.xMpPlayer`               | the stock MP controller (`xMpPlayer -> DudePlayer -> MpPlayer -> P2Player`) |
| `MilRPHUD`                     | `MultiGame.MpHUD`                    | stock MP HUD (`MpHUD -> MpHUDBase -> P2HUD -> FPSHUD -> HUD`), draws via `DrawHUD(Canvas)` |

Factions are **not** UE2 teams: `TeamGame` is hard-wired to two teams, so faction id
lives on the PRI and `PlayerReplicationInfo.Team` stays `None`.

## Addon framework

`MilRPWorld` loads packages listed in `MilRP.ini [MilRP.MilRPWorld] AddonPackages=` and
registers any `MilRPAddon` subclasses it finds. Addons can subscribe to events
(`OnPlayerLogin`, `OnFactionJoin`, `OnDutyChange`, `OnPaycheck`, `OnPlayerKilled`,
`OnRankChange`) and provide custom loadout modifiers, without recompiling MilRP.

Interaction points can be auto-spawned from `Placeables=` in the same section; they
use Postal 2's built-in `UsedBy()` pipeline and the `MilRPInteractPoint` menu system.

## Building

```
Tools\make.bat "C:\Program Files (x86)\Steam\steamapps\common\Postal 2"
```

or set `POSTAL2_DIR`. Requires the POSTed SDK (`System\ucc.exe`). Compile errors are
written to `<Postal 2>\System\ucc.log`.

Local installs on this machine:
- game: `C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete`
- SDK / compiler: `C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor` (build against this one)

Build status: compiles clean (`Success - 0 error(s)`) against build 5100 and a headless
`ucc server` boots `MilRPGameInfo` with no script warnings.

## Running a server

1. Add `ServerPackages=MilRP` under `[Engine.GameEngine]` in `System\Postal2.ini` so clients
   download/load `MilRP.u` (the stock list only contains the RWS packages).
2. From the game's `System` folder (use a *relative* exe name - the UE2 command-line parser
   trips over the `(x86)` in an absolute path):

```
cd /d "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"
ucc server MPDGT-Asylum?Game=MilRP.MilRPGameInfo?StartingCurrency=500?PaycheckInterval=300
```

URL options: `StartingCurrency`, `PaycheckInterval`, `EnforceFactions`, `PersistRecords`, `AutoPromote`, `RPTest`.
Everything else is in `System\MilRP.ini`.

## In-game commands

| Chat (`/…`) or console | Effect |
|---|---|
| `/factions`, `/ranks`, `/status` | list factions / rank ladder / your wallet, bank, RP status |
| `/join <tag|name|id>` (console: `joinfaction`) | request a faction |
| `/duty` (console: `duty`, `toggleduty`) | clock on / off |
| `/me <text>`, `/do <text>`, `/l <text>` | proximity roleplay chat (console: `me`, `doemote`, `l`) |
| `/radio <msg>`, `/command <msg>`, `/adminradio <msg>` | rank/faction radio channels (console: `radio`, `commandradio`, `adminradio`) |
| `/pay <player> <amount>` | pay a nearby player from wallet |
| `/bank <deposit\|withdraw\|transfer> <amount> [player]` | ATM / bank operations |
| `/pick <n>` / `/close` | select or close an interaction menu |
| `/admin` | open the Canvas admin menu (requires moderator or higher) |
|| `/addstaff <player> <0-4>` | add a player to `StaffRegistry` and persist to `MilRP.ini` (owner only) |
| `/setrank <player> <rank>`, `/setfaction`, `/givemoney`, `/announce` | admin |
| `/kick`, `/ban`, `/warn`, `/fine`, `/freeze`, `/unfreeze` | admin moderation |
| `/goto`, `/bring`, `/pos`, `/defcon <1-5>` | admin position / alert |
| `/noclip`, `/fly` | native `PlayerHelicoptering` free-cam flight (admin) |
