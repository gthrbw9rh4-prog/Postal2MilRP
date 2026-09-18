# MilRP Server Host Guide

How to run a public Postal 2: Share The Pain Military Roleplay server.

## 1. Install the mod

Copy the contents of `System\` (`MilRP.u`, `MilRP.ini`, `MilRP.int`) into the
server install's `System\` folder, and add the package to the load list:

```ini
; System\Postal2.ini
[Engine.GameEngine]
ServerPackages=MilRP
```

## 2. Open firewall / router ports

| Port  | Proto | Purpose                                |
|-------|-------|----------------------------------------|
| 7777  | UDP   | Game traffic — players connect here    |
| 7778  | UDP   | Server browser query                   |

Forward both on the router and allow them through Windows Firewall for
`Postal2.exe`. Without the query port the server shows in the list but pings "??".

## 3. Start the server

```
LaunchDedicatedServer.bat
```

Edit the `GAME_DIR` / `MAP` / `PORT` variables at the top of the script to fit
your install. Equivalent manual command:

```
cd /d "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"
UCC.exe server MPDGT-Asylum?Game=MilRP.MilRPGameInfo?VAC=1?Port=7777?QueryPort=7778 -log=server.log
```

**Important — which binary to run:**

- The retail `System` folder ships **no** `UCC.exe`. Copy
  `POSTAL2Editor\System\UCC.exe` into `POSTAL2Complete\System` once
  (`LaunchDedicatedServer.bat` does this automatically). Engine version is
  determined by the DLLs in the working dir, so the copied launcher still
  reports the modern protocol — verified: `Init: Version: 5100`.
- `UCC.exe server` = true headless console — no window, no Steam session
  lock, so you can launch your own client on the same machine.
- `Postal2.exe server` opens a "Postal2 (Running)" client window and holds
  your Steam profile — only a fallback when no `UCC.exe` is available.
- Never run from `ShareThePain\System` — that is the legacy 1409-era MP
  engine; it reports an old protocol and crashes on this mod.

**Master list:** Postal 2's official community master is
`master.333networks.com` (GameSpy is defunct). Both server uplink
(`ServerActors=IpDrv.UdpServerUplink`) and the in-game browser
(`ListFactories[0]`) already point there — no change needed.

The server announces itself automatically as long as `bLANServer=False` in
`System\Postal2.ini` and outbound internet is allowed. Check `server.log` for
`Uplink`/`MasterServer` lines to confirm.

## 4. First login — make yourself admin

Staff groups are 0–4 (`0`=player, `1`=moderator, `2`=admin,
`3`=superadmin, `4`=owner). Ownership is granted in-game:

1. Create a character and log in.
2. From any existing owner/admin account: `/addstaff <playername> 4`
   — or if nobody is staff yet, edit `System\MilRP.ini`,
   `[MilRP.MilRPGameInfo] StaffRegistry=` and add:
   `StaffRegistry=(UniqueID="<your-ip-or-steam-id>",StaffIP="",StaffMemo="<playername>",GroupLevel=4)`
   then restart the server.
3. Staff commands appear in `/help`; the admin board opens with `/admin`
   and the spawn menu with `F2` (SuperAdmin+).

`/addstaff` writes to `StaffRegistry` in `MilRP.ini` and persists via
`SaveConfig()` — it survives restarts.

## 5. Customizing factions and ranks

All content tables live in `System\MilRP.ini` under `[MilRP.MilRPGameInfo]`:

```ini
Factions=(Name="United States Army",Tag="USA",Tint=(R=70,G=130,B=60,A=255),bCombatant=True,DutyLoadout="Inventory.PistolWeapon,Inventory.MachinegunWeapon,Inventory.GrenadeWeapon")
Ranks=(Title="Recruit",MinScore=0)
```

- `DutyLoadout` is a comma-separated list of inventory classes granted on `/duty`.
- `Ranks` are ordered by `MinScore` — RP score drives promotion.
- `StartingCurrency`, `PaycheckInterval`, `BasePaycheck`,
  `RankPaycheckMultiplier` control the economy.
- `[MilRP.MilRPCapturePoint]` controls territory zones (see README).

Restart the server after editing the ini.

## 6. In-game admin quick reference

| Command | Effect |
|---|---|
| `/addstaff <player> <0-4>` | grant staff rank (0=player … 4=owner); persists to ini |
| `/admin` | graphical admin board (kick/ban/freeze/slap/…) |
| `F2` | spawn menu (props, weapons, NPCs, sirens, consoles, flags) |
| `/setspawn <faction>` | save faction spawn at your position |
| `/setrank <p> <r>` `/setfaction <p> <f>` | adjust players |
| `/announce <msg>` | server-wide banner |

## Files in this package

| File | Purpose |
|---|---|
| `System\MilRP.u` | compiled mod package (required on server **and** every client) |
| `System\MilRP.ini` | all runtime configuration |
| `System\MilRP.int` | English strings |
| `LaunchServer.bat` | listen-server (host + play on one client) |
| `LaunchDedicatedServer.bat` | headless dedicated server |
