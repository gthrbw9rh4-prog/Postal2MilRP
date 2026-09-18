# MilRP - agent notes

## Build / verify
- Build: `Tools\make.bat "<Postal 2 install dir>"` (needs POSTed SDK `System\ucc.exe`). Errors land in `<Postal 2>\System\ucc.log`.
- Installs: game = `C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete`, SDK (`UCC.exe`) = `...\POSTAL2Editor`. Always build against POSTAL2Editor: `Tools\make.bat "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor"`.
- Runtime smoke test / headless hosting: copy `POSTAL2Editor\System\UCC.exe` into `POSTAL2Complete\System` once, then run `UCC.exe server MPDGT-Asylum?Game=MilRP.MilRPGameInfo` - true headless console, no window, no Steam session lock (verified `Init: Version: 5100`; engine version comes from the DLLs in the working dir, all SDK DLLs are byte-identical to retail). `Postal2.exe server` also works but opens a client window and holds the Steam profile. Never run from `ShareThePain\System` (legacy 1409-era engine, stripped APIs). 333networks is the correct Postal 2 master - both server uplink and the in-game browser already point there. Use a relative exe name; UE2 mis-parses absolute paths containing `(x86)`.
- UE2 has no `bool` static arrays (use `byte`) and `Do` is a reserved word (`do..until`). `Goto` and `Warn` are also reserved built-ins; use `GotoPlayer`/`WarnPlayer` instead.
- Pre-compile lint (brace balance, misplaced `local`, duplicate functions, missing MilRP.* refs): `powershell -File Tools\lint.ps1`. Run it before every `make.bat`.
- Exec commands run on the client; anything touching RP state must go through a `Server*` RPC in `MilRPPlayer` (`reliable if (Role < ROLE_Authority)`). Stock `Say`/`TeamSay` are already replicated that way.
- `FontInfo.DrawTextEx(Canvas, CanvasWidth, x, y, str, FontSize 0-3, bPlain, EJ_Left|EJ_Right|EJ_Center, Color)` draws shadowed, resolution-scaled text; measure with `Canvas.Font = MyFont.GetFont(size, true, CanvasWidth); Canvas.StrLen(...)`.
- `GRI.ElapsedTime` ticks client-side, so HUD countdowns can be derived from it without extra replication.
- Base-class reference: https://github.com/Kizoky/p2unrealscript (Steam build 5025 script tree). MP packages are `MultiBase`, `MultiGame`, `MultiStuff` (not the old `MPShell`).

## Engine facts that bit us (Postal 2 = UE2 build ~1417 with 2110 subsystems)
- `ReplaceText` is a non-static `Actor` function - cannot be called from `static` functions.
- `Actor` has no `NetUpdateTime`; rely on `bNetDirty` for replication.
- Dynamic arrays never replicate - use fixed arrays + counts in ReplicationInfos.
- `GameInfo.Timer()` runs at 1 Hz; `DeathMatch` state `Timer()`s call `Global.Timer()`.
- `GameInfo.Killed()` already increments `Deaths` and fires `KillEvent`; `ScoreKill` only handles score.
- `Canvas` has `SetDrawColor`, `MakeColor`, `DrawRect(Texture'Engine.WhiteSquareTexture', W, H)`; HUD fonts via `MyFont.GetFont(size, bPlain, CanvasWidth)` (FPSHUD).
- `P2Pawn.CreateInventory(string ClassName, optional out byte CreatedNow)` is the safe way to grant inventory.
- `Pawn.KilledBy(None)` is the engine suicide path (uses `class'Suicided'`).
- `P2Pawn` owns `HealthMax`; base `Pawn` does not.
- `Weapon` does not have `bFire`/`bAltFire`; clear `Controller.bFire`/`bAltFire` to stop input.
- `MilRPWorld` auto-spawns interaction points and sirens; it is created by `MilRPGameInfo.PostBeginPlay`.

## Chat / voice architecture
- Custom chat routing is implemented in `MilRPPlayer.Say` and `ServerReceiveChat`.
- The `B` key is bound to the native `Talk` command in `DefUser.ini/User.ini`. The engine opens the chat prompt and toggles the controller's `bIsTyping` flag via `PlayerController.Typing()`. `MilRPPlayer` never sets `bIsTyping` manually.
- `MilRPPlayer.IsTyping()` reads the engine's native `bIsTyping` flag (in this build `Player.Console.bTyping` does not exist, so `bIsTyping` is the authoritative flag set by the console).
- `UpdateRotation`, the `PlayerWalking` `PlayerMove`, and `PlayerTick` all use `IsTyping()`. While the prompt is open, camera and movement are frozen and weapon input is cleared.
- Mouse wheel is bound to `NextWeapon`/`PrevWeapon`; `MilRPPlayer` overrides those to call `ChatScrollUp`/`ChatScrollDown` while the prompt is active, so the player can scroll history while typing.
- `PlayerTick` resets `ChatScrollOffset` to `0` whenever the prompt closes (empty `Enter`, `Escape`, or any other close path), and zeroes `Pawn.Velocity`/`Pawn.Acceleration` while the prompt is active.
- `PawnDied` resets `ChatScrollOffset` before the normal death flow.
- `Say` receives the typed line from the prompt. Client-only menu commands (`/pick`, `/close`) are handled locally; all other slash commands and plain text are passed to the server-side `ServerReceiveChat`, which strips the slash, case-insensitively isolates the command, extracts arguments, and executes the matching mod function. Plain text and unknown slash commands default to `ServerLocalSay` -> `BroadcastLocal` -> `ClientRPChat`.
- Chat history is stored in `MilRPPlayer.ChatLog` (up to `MaxChatLogLines` entries), rendered with `ChatScrollOffset`, and displayed in `MilRPHUD.DrawChatMenu` while `RPOwner.IsTyping()` is true. `ChatScrollOffset` resets to `0` when the prompt closes so the left-side log resumes real-time.
- The engine does not expose a `bShowMouseCursor` toggle in this Postal 2 build, so the interactive menu is keyboard/wheel driven and no mouse cursor is drawn.
- UE2 has no built-in VoIP in this Postal 2 build. Voice chat is external (Discord/TeamSpeak/etc.); `VoiceChatPrompt` in `System\MilRP.ini` is shown to every connecting player as a HUD toast and console message. A future bridge could use a Discord bot that watches the server log (`MilRP_YYYY-MM-DD.txt`) for `LOGIN/LOGOUT/FACTION/DUTY` events and moves Discord users into role-locked voice rooms.
- The `POSTAL2Editor` and `POSTAL2Complete\System` builds use the same 5 MB `Engine.u`, so packages compiled with `make.bat "...\POSTAL2Editor"` work there. `POSTAL2Complete\ShareThePain\System` ships a smaller MP `Engine.u` (1.9 MB) and has stripped `UseTrigger`/`FontInfo` APIs; running the editor-built `MilRP.u` under `ShareThePain` will crash. For a Share-The-Pain-specific package, run `make.bat "...\POSTAL2Complete\ShareThePain"` and fix the resulting API errors.

## Faction / roleplay commands
- `/join <id|tag>`, `/joinfaction <id|tag>`, and `/faction <id|tag>` are all handled by `ServerReceiveChat` in `MilRPPlayer.uc` and routed to `ServerRequestFaction`.
- `ResolveFactionArg` accepts a numeric index, an exact tag, or a partial faction name (case-insensitive), so `/join 1`, `/join RGF`, and `/join Russian` all work.
- `ServerRequestFaction` validates the faction, calls `MilRPGameInfo.RequestFaction` to update `PRI.FactionID`, then immediately calls `SetDutyInternal` to strip the old kit and equip the new faction's default duty loadout (combatants go on-duty, non-combatants receive off-duty gear).
- On success the player gets a client toast: `You have joined the <FactionName>.`
- Invalid IDs produce: `Invalid faction. Use /join [1-<count>] or see /factions.`
- `/factions` lists every faction ID, tag, and name directly into the left-hand chat log via `ClientRPChat`.

## Match / respawn lifecycle
- `MilRPGameInfo.InitGame` forces `TimeLimit=0`, `GoalScore=0`, `RemainingTime=0`, `MaxLives=0`, `bOverTime=false`, and `bGameEnded=false`.
- `CheckEndGame`, `CheckScore`, `CheckMaxLives`, and `EndGame` are overridden to never transition to `MatchOver`. `Killed` is overridden to keep death bookkeeping without calling `Super.Killed()`; `ScoreKill` is the existing RP-only handler and does not call `Super.ScoreKill()`, so no frag limit or life pool can end the world.
- `state PendingMatch` starts the match immediately, and `state MatchInProgress` only runs the 1 Hz global / RP loop (no auto-respawn, no EndGame, no time/life checks). `state MatchOver` immediately returns to `MatchInProgress` if the engine ever tries to enter it.
- `Login` resets `bOutOfLives`, `bOnlySpectator`, `bIsSpectator`, and `NumLives` for every connecting controller so joining players are never flagged as out-of-lives.
- `InitGame` also sets `bDelayedStart=false`, `bRestartLevel=false`, and `MatchIntroClassName=""` so the base engine does not hold joining players in a pre-match spectator limbo.
- `PostLogin` now flags the new player as `bFullyLoggedIn`, `bIntroFinished`, `bReadyToPlay`, and a non-spectator *before* calling `Super.PostLogin`; if the base spawn did not happen, it immediately calls `RestartPlayer` and forces `PHYS_Walking`.
- `MilRPPlayer` overrides `state Spectating` so `Fire`/`AltFire` request a respawn instead of cycling view, and `ActivateItem` (Enter) requests a respawn when the player has no live pawn.
- `MilRPPlayer` overrides `state PlayerWaiting` to immediately force a spawn on `Fire`/`AltFire` and clears any spectator/freeze flags.
- `MilRPPlayer.state PlayerWalking.BeginState` forces `Pawn.SetPhysics(PHYS_Walking)` and clears `bBehindView`/`bOnlySpectator` flags so the player is never stuck in noclip.
- `MilRPPlayer.PlayStartupMessage` is a no-op, preventing the "Press to join the match!" overlay from ever drawing.
- `MilRPPlayer.GameHasEnded` and `ClientGameEnded` are no-ops so the engine can never push the player into the `GameEnded` state.
- `MilRPPlayer` overrides `state Dead`, `state GameEnded`, and `state WaitingForPawn` to cancel all freeze / auto-respawn / `AskForPawn` timers (`SetTimer(0,false)`), block `ServerReStartGame` (which would call `Level.Game.RestartGame()` / `ServerTravel`), and make `Fire`/`AltFire` respawn through `ServerRestartPlayer`.
- `MilRPGameInfo.RestartGame` persists records but never calls `Super.RestartGame()` or `Level.ServerTravel()`, so an accidental map reload is impossible.
- `MilRPGameInfo.FactionDef` includes `StartLocation` and `StartRotation`. Admin `/setspawn <id|tag>` captures the admin's current location/rotation and calls `MilRPGameInfo.SetFactionSpawn`, which updates the `Factions` table and calls `SaveConfig()` to persist it to `System\MilRP.ini`.
- `MilRPGameInfo.FindPlayerStart` selects the `PlayerStart` nearest the faction's saved spawn, stores the exact saved point in `MilRPPlayer.DesiredSpawnLocation`/`DesiredSpawnRotation`, and `RestartPlayer` snaps the newly spawned pawn to that exact location/rotation. Factions without a saved spawn (or civilians with no base) fall back to the normal map `PlayerStart` selection.
- `AddDefaultInventory` still runs through `GameInfo.RestartPlayer`, so every respawn gives the correct faction duty/off-duty kit without touching the wallet or roleplay record.

## Conventions
- All tunables are `var config` at the top of each class, mirrored in `System\MilRP.ini`.
- Server-authoritative; clients only get PRI/GRI replication and owner-only RPCs from `MilRPPlayer`.

## Staff authentication
- Staff and ban records store three layers: `UniqueID` (primary IP / Steam hash when available), `StaffIP`/`BannedIP`, and `StaffMemo`/`BannedName` (current Steam/ player name).
- `PreLogin` rejects by IP (`UniqueID` or `BannedIP`); `Login` rejects by last-known name (`BannedName`).
- New staff are added in-game with `/addstaff <PlayerName> <GroupLevel 0-4>` (owner only), which appends to `StaffRegistry` and calls `SaveConfig()` so the entry persists to `System\MilRP.ini`.

## Noclip / admin flight
- `/noclip` and `/fly` put the admin into the engine's native `PlayerHelicoptering` state (`bCheatFlying=true`) instead of manual physics, giving smooth mouse-look flight with `W/S/A/D` and `Jump/Crouch`.
- Toggling off returns to `PlayerWalking` and restores `PHYS_Walking` + full collision.
- The admin panel can be opened while flying; opening zeroes `Pawn.Velocity` so the admin hovers, and closing resumes `PlayerHelicoptering`.
