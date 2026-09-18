///////////////////////////////////////////////////////////////////////////////
// MilRPWorld.uc
//
// Persistent server-side world manager. One instance is spawned by
// MilRPGameInfo.PostBeginPlay. Responsibilities:
//
//   * Load and host third-party MilRPAddon packages.
//   * Spawn configured interaction points, sirens, and other placeables on
//     any map without requiring a map rebuild.
//   * Own the economy / admin log file.
//   * Maintain the base alert level and associated siren actors.
//
// The placement list is config-driven: server owners can add map-specific
// armories, ATMs, enlistment terminals, etc. by editing MilRP.ini.
///////////////////////////////////////////////////////////////////////////////
class MilRPWorld extends Info
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
struct PlacementDef
{
	var string	MapName;				// partial match against level URL/title
	var string	ClassName;				// full class, e.g. "MilRP.MilRPArmoryLocker"
	var float	X, Y, Z;				// world location
	var int		Yaw;					// rotation around Z (0..65535 maps to 0..360)
	var int		FactionID;				// 255 = usable by any faction, else faction-only
	var string	Extra;					// subclass-specific data (prices, loadout, etc.)
};
var config array<PlacementDef>	Placeables;

var config array<string>			AddonPackages;		// full class paths to load

var config float				SirenInterval;		// seconds between siren pulses
var config string				SirenSoundClass;		// klaxon sound class name or leave blank
var config string				SirenAlertToneClass;	// elevated-alert radio tone class name
var config float				SirenRadius;
var config byte					MaxSirens;

var config bool					bStressTest;			// spawn test bots if ?RPTest=1
var config int					StressTestBots;
var config float				StressTestInterval;


///////////////////////////////////////////////////////////////////////////////
// RUNTIME
///////////////////////////////////////////////////////////////////////////////
var MilRPGameInfo				RPGame;
var MilRPLog					Logger;
var array<MilRPAddon>			Addons;
var array<MilRPInteractPoint>	Points;
var array<MilRPSiren>			Sirens;

var int							PendingBots;
var float						NextBotSpawn;


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	Super.PostBeginPlay();

	RPGame = MilRPGameInfo(Level.Game);
	if (RPGame == None)
	{
		warn("MilRPWorld spawned in a non-MilRP game");
		Destroy();
		return;
	}

	RPGame.SetRPWorld(self);

	Logger = Spawn(class'MilRPLog');
	if (Logger != None)
		Logf("WORLD", "MilRPWorld initialised on " $ Level.GetLocalURL());

	InitAddons();
	InitPlacements();
	InitSirens();

	if (bStressTest)
		PendingBots = StressTestBots;
}


///////////////////////////////////////////////////////////////////////////////
// ADDON LOADING
///////////////////////////////////////////////////////////////////////////////
function InitAddons()
{
	local int i;
	local class<MilRPAddon> AddonClass;
	local MilRPAddon Addon;

	for (i = 0; i < AddonPackages.Length; i++)
	{
		if (AddonPackages[i] == "")
			continue;
		AddonClass = class<MilRPAddon>(DynamicLoadObject(AddonPackages[i], class'Class'));
		if (AddonClass == None)
		{
			warn("MilRPWorld::InitAddons : cannot load addon " $ AddonPackages[i]);
			continue;
		}
		Addon = Spawn(AddonClass);
		if (Addon == None)
		{
			warn("MilRPWorld::InitAddons : failed to spawn addon " $ AddonPackages[i]);
			continue;
		}
		Addon.PostInit(RPGame, self);
		Addons[Addons.Length] = Addon;
		Logf("ADDON", "Loaded " $ AddonPackages[i]);
	}
}

function FireAddonEvent(name Event, optional MilRPPlayer Player1, optional MilRPPlayer Player2, optional int Int1, optional int Int2, optional bool bFlag)
{
	local int i;

	for (i = 0; i < Addons.Length; i++)
	{
		if (Addons[i] == None || !Addons[i].bEnabled)
			continue;
		if (Event == 'OnPlayerLogin')
			Addons[i].OnPlayerLogin(Player1);
		else if (Event == 'OnPlayerLogout')
			Addons[i].OnPlayerLogout(Player1);
		else if (Event == 'OnFactionJoin')
			Addons[i].OnFactionJoin(Player1, Int1, Int2);
		else if (Event == 'OnDutyChange')
			Addons[i].OnDutyChange(Player1, bFlag);
		else if (Event == 'OnPaycheck')
			Addons[i].OnPaycheck(Player1, Int1);
		else if (Event == 'OnRankChange')
			Addons[i].OnRankChange(Player1, Int1, Int2);
		else if (Event == 'OnPlayerKilled')
			Addons[i].OnPlayerKilled(Player1, Player2, bFlag);
	}
}

function bool AllowAddonFactionJoin(MilRPPlayer Player, int FactionID, out string FailReason)
{
	local int i;

	for (i = 0; i < Addons.Length; i++)
	{
		if (Addons[i] == None || !Addons[i].bEnabled)
			continue;
		if (!Addons[i].AllowFactionJoin(Player, FactionID, FailReason))
			return false;
	}
	return true;
}

function bool AllowAddonDuty(MilRPPlayer Player, bool bWantOnDuty, out string FailReason)
{
	local int i;

	for (i = 0; i < Addons.Length; i++)
	{
		if (Addons[i] == None || !Addons[i].bEnabled)
			continue;
		if (!Addons[i].AllowDuty(Player, bWantOnDuty, FailReason))
			return false;
	}
	return true;
}

function string ModifyAddonLoadout(MilRPPlayer Player, string Loadout)
{
	local int i;

	for (i = 0; i < Addons.Length; i++)
	{
		if (Addons[i] == None || !Addons[i].bEnabled)
			continue;
		Addons[i].ModifyLoadout(Player, Loadout);
	}
	return Loadout;
}


///////////////////////////////////////////////////////////////////////////////
// PLACEMENTS
///////////////////////////////////////////////////////////////////////////////
function InitPlacements()
{
	local int i;
	local class<MilRPInteractPoint> PtClass;
	local MilRPInteractPoint Pt;
	local rotator R;
	local vector Loc;
	local string Map;

	Map = CurrentMapName();
	for (i = 0; i < Placeables.Length; i++)
	{
		if (Placeables[i].ClassName == "")
			continue;
		if (!MapNameMatches(Placeables[i].MapName, Map))
			continue;

		PtClass = class<MilRPInteractPoint>(DynamicLoadObject(Placeables[i].ClassName, class'Class'));
		if (PtClass == None)
		{
			warn("MilRPWorld::InitPlacements : unknown interact class " $ Placeables[i].ClassName);
			continue;
		}

		Loc.X = Placeables[i].X;
		Loc.Y = Placeables[i].Y;
		Loc.Z = Placeables[i].Z;
		R.Yaw = Placeables[i].Yaw;
		Pt = Spawn(PtClass,,, Loc, R);
		if (Pt == None)
		{
			warn("MilRPWorld::InitPlacements : failed to spawn " $ Placeables[i].ClassName $ " at " $ Loc);
			continue;
		}
		Pt.PointFaction = byte(Placeables[i].FactionID);
		Pt.ExtraConfig = Placeables[i].Extra;
		Pt.RegisterWorld(self);
		Points[Points.Length] = Pt;
	}
}

function string CurrentMapName()
{
	local string Url, Title;

	Url = Level.GetLocalURL();
	Title = Level.Title;
	if (InStr(Caps(Url), ".") >= 0)
		Url = Left(Url, InStr(Caps(Url), "."));
	if (InStr(Caps(Title), ".") >= 0)
		Title = Left(Title, InStr(Caps(Title), "."));
	return Caps(Url) @ Caps(Title);
}

function bool MapNameMatches(string ConfigName, string LevelName)
{
	local string Needle;

	if (ConfigName == "" || ConfigName == "*")
		return true;
	Needle = Caps(ConfigName);
	if (Needle == "ALL" || Needle == "ANY")
		return true;
	return (InStr(LevelName, Needle) >= 0);
}


///////////////////////////////////////////////////////////////////////////////
// SIRENS / ALERT
///////////////////////////////////////////////////////////////////////////////
function InitSirens()
{
	// MaxSirens=0 keeps auto-placement off; set it >0 in MilRP.ini to ring
	// the map with DEFCON sirens at map start (positions via FindSirenLocation).
	if (MaxSirens > 0)
		SpawnSirens(MaxSirens);
}

function SetAlertLevel(byte NewLevel)
{
	local int i;
	local byte Old;

	if (RPGame == None || RPGame.RPGRI == None)
		return;

	Old = RPGame.RPGRI.AlertLevel;
	RPGame.RPGRI.AlertLevel = Clamp(NewLevel, 0, 5);
	RPGame.RPGRI.bLockdown = (RPGame.RPGRI.AlertLevel >= 4);

	if (RPGame.RPGRI.AlertLevel != Old)
		Logf("ALERT", "DEFCON changed from " $ Old $ " to " $ RPGame.RPGRI.AlertLevel);

	for (i = 0; i < Sirens.Length; i++)
		if (Sirens[i] != None)
			Sirens[i].SetAlertLevel(RPGame.RPGRI.AlertLevel);
}

function SpawnSirens(int Count)
{
	local int i;
	local MilRPSiren S;
	local vector Loc;

	for (i = 0; i < Count && i < MaxSirens; i++)
	{
		Loc = FindSirenLocation(i, Count);
		S = Spawn(class'MilRPSiren',,, Loc);
		if (S != None)
		{
			// Empty world config keeps the siren's own class defaults.
			if (SirenSoundClass != "")
				S.SetSoundClass(SirenSoundClass);
			if (SirenAlertToneClass != "")
				S.SetAlertToneClass(SirenAlertToneClass);
			if (RPGame != None && RPGame.RPGRI != None)
			S.SetAlertLevel(RPGame.RPGRI.AlertLevel);
		else
			S.SetAlertLevel(0);
			Sirens[Sirens.Length] = S;
		}
	}
}

function vector FindSirenLocation(int Index, int Count)
{
	local PlayerStart PS;
	local int i;

	if (Count <= 0)
		return vect(0,0,0);
	foreach AllActors(class'PlayerStart', PS)
	{
		if (i == Index % Count)
			return PS.Location + vect(0,0,256);
		i++;
	}
	return vect(0,0,256);
}


///////////////////////////////////////////////////////////////////////////////
// TEST BOTS
///////////////////////////////////////////////////////////////////////////////
function Tick(float Delta)
{
	Super.Tick(Delta);

	if (bStressTest && PendingBots > 0 && Level.TimeSeconds >= NextBotSpawn)
	{
		PendingBots--;
		NextBotSpawn = Level.TimeSeconds + StressTestInterval;
		if (RPGame != None)
			RPGame.SpawnStressBot();
	}
}


///////////////////////////////////////////////////////////////////////////////
// LOGGING API
///////////////////////////////////////////////////////////////////////////////
function Logf(string Category, string Text)
{
	if (Logger != None)
		Logger.Logf(Category, Text);
}

function MilRPLog GetLogger()
{
	return Logger;
}


///////////////////////////////////////////////////////////////////////////////
// POINTS
///////////////////////////////////////////////////////////////////////////////
function MilRPInteractPoint FindPointFor(Pawn P, float Radius)
{
	local int i;
	local Actor Ref;

	Ref = P;
	if (Ref == None)
		Ref = P.Controller;
	if (Ref == None)
		return None;

	for (i = 0; i < Points.Length; i++)
		if (Points[i] != None && VSize(Points[i].Location - Ref.Location) <= Radius)
			return Points[i];
	return None;
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	SirenInterval=2.000000
	SirenRadius=2000.000000
	MaxSirens=4
	bStressTest=false
	StressTestBots=0
	StressTestInterval=5.000000
	bHidden=false
	bStatic=false
	bAlwaysRelevant=true
}