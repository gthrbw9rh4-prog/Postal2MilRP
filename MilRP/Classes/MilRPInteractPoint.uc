///////////////////////////////////////////////////////////////////////////////
// MilRPInteractPoint.uc
//
// Base class for world interactables: armories, ATMs, duty stations, shops,
// enlistment terminals. Extends UseTrigger so the engine's existing "Use" key
// (ServerUse -> UsedBy) works without rebinding.
//
// Interact points are configured via [MilRP.MilRPWorld] Placeables= and can be
// spawned on any map without a level rebuild.
///////////////////////////////////////////////////////////////////////////////
class MilRPInteractPoint extends UseTrigger
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
var() string		PointLabel;			// shown in the HUD prompt
var() string		MenuTitle;			// title of the text menu
var() byte			PointFaction;		// 255 = any, else limited to this faction
var() int			RankRequired;		// minimum rank index
var() bool			bOffDutyOk;			// can be used while off duty
var() bool			bSingleUse;			// goes dormant after one successful use
var() float			ReUseDelay;			// seconds before it can be used again
var() float			UseRadius;			// interaction radius (also sets collision)
var() string		ExtraConfig;		// subclass-specific config string


///////////////////////////////////////////////////////////////////////////////
// RUNTIME
///////////////////////////////////////////////////////////////////////////////
var MilRPWorld			World;
var float				LastUseTime;


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	Super.PostBeginPlay();

	if (UseRadius <= 0)
		UseRadius = 96.0;

	SetCollisionSize(UseRadius, CollisionHeight);
	bHidden = false;
	Message = PointLabel;
	NetUpdateFrequency = 0.5;
}

function RegisterWorld(MilRPWorld W)
{
	World = W;
}


///////////////////////////////////////////////////////////////////////////////
// USETRIGGER HOOK
///////////////////////////////////////////////////////////////////////////////
function UsedBy(Pawn user)
{
	local MilRPPlayer RPO;
	local string FailReason;

	if (user == None || user.Controller == None)
		return;

	RPO = MilRPPlayer(user.Controller);
	if (RPO == None)
	{
		Super.UsedBy(user);
		return;
	}

	if (!CanUse(RPO, FailReason))
	{
		RPO.ClientRPNotify(FailReason);
		return;
	}

	OpenMenu(RPO);
	LastUseTime = Level.TimeSeconds;

	if (bSingleUse)
		SetCollision(false, false, false);
}


///////////////////////////////////////////////////////////////////////////////
// VALIDATION
///////////////////////////////////////////////////////////////////////////////
function bool CanUse(MilRPPlayer RPO, out string FailReason)
{
	local MilRPPlayerReplicationInfo PRI;
	local MilRPGameReplicationInfo GRI;

	PRI = RPO.GetRPPRI();
	GRI = RPO.GetRPGRI();
	FailReason = "";

	if (Level.TimeSeconds - LastUseTime < ReUseDelay)
	{
		FailReason = "Please wait before using this again.";
		return false;
	}

	if (PRI != None && PRI.bFrozen)
	{
		FailReason = "You are frozen.";
		return false;
	}

	if (GRI != None && GRI.bLockdown && !bOffDutyOk)
	{
		FailReason = "Base lockdown is active.";
		return false;
	}

	if (PointFaction != 255)
	{
		if (PRI == None || PRI.FactionID != PointFaction)
		{
			if (GRI != None)
				FailReason = "This terminal is for " $ GRI.GetFactionName(PointFaction) $ " only.";
			else
				FailReason = "This terminal is faction-locked.";
			return false;
		}
	}

	if (PRI != None && PRI.Rank < RankRequired)
	{
		if (GRI != None)
			FailReason = "Rank " $ GRI.GetRankTitle(RankRequired) $ " required.";
						
		if (FailReason == "")
			FailReason = "Higher rank required.";
		return false;
	}

	if (!bOffDutyOk && PRI != None && !PRI.bOnDuty)
	{
		FailReason = "You must be on duty.";
		return false;
	}

	return true;
}


///////////////////////////////////////////////////////////////////////////////
// MENU
///////////////////////////////////////////////////////////////////////////////
function OpenMenu(MilRPPlayer RPO)
{
	local string Options[8];
	local int Count;
	local string Packed;
	local int i;

	Count = BuildMenu(RPO, Options);
	if (Count <= 0)
	{
		RPO.ClientRPNotify("Nothing to do here.");
		return;
	}

	Packed = MenuTitle;
	for (i = 0; i < Count; i++)
		Packed = Packed $ "|" $ Options[i];

	RPO.ServerOpenMenu(self, Packed);
}

// Subclasses override this to fill the 8-slot option list.
// Return the number of options (max 8).
function int BuildMenu(MilRPPlayer RPO, out string Options[8])
{
	return 0;
}

// Subclass handles a selection. Return a player-facing message.
function bool HandleSelection(MilRPPlayer RPO, int Index, out string Feedback)
{
	Feedback = "Invalid selection.";
	return false;
}


///////////////////////////////////////////////////////////////////////////////
// HELPERS
///////////////////////////////////////////////////////////////////////////////
function MilRPGameInfo GetGame()
{
	if (World != None)
		return World.RPGame;
	return MilRPGameInfo(Level.Game);
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	bHidden=false
	bCollideActors=true
	UseRadius=96.000000
	ReUseDelay=0.500000
	PointFaction=255
	RankRequired=0
	bOffDutyOk=true
	bSingleUse=false
	PointLabel="Press USE to interact"
	MenuTitle="Interact"
	RemoteRole=ROLE_SimulatedProxy
	bAlwaysRelevant=false
}