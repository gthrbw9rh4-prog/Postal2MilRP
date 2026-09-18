///////////////////////////////////////////////////////////////////////////////
// MilRPAddon.uc
//
// Base class for third-party MilRP plugins. Addons are loaded automatically
// from the [MilRP.MilRPWorld] AddonPackages= list and receive lifecycle
// events from the game. They can veto faction/duty requests, modify loadout
// strings, react to economy events, or implement entirely new systems without
// touching the core package.
//
// To create an addon, extend this class, place the .uc in a separate package,
// compile it, and add the full class path ("MyAddon.MyCoolAddon") to
// MilRP.ini under [MilRP.MilRPWorld].
///////////////////////////////////////////////////////////////////////////////
class MilRPAddon extends Info
	abstract;


var string			AddonName;
var bool			bEnabled;


///////////////////////////////////////////////////////////////////////////////
// Lifecycle
///////////////////////////////////////////////////////////////////////////////
function PostInit(MilRPGameInfo Game, MilRPWorld World)
{
}


///////////////////////////////////////////////////////////////////////////////
// Player events
///////////////////////////////////////////////////////////////////////////////
event OnPlayerLogin(MilRPPlayer Player)
{
}

event OnPlayerLogout(MilRPPlayer Player)
{
}

event OnFactionJoin(MilRPPlayer Player, int OldFaction, int NewFaction)
{
}

event OnDutyChange(MilRPPlayer Player, bool bOnDuty)
{
}

event OnPaycheck(MilRPPlayer Player, int Amount)
{
}

event OnRankChange(MilRPPlayer Player, int OldRank, int NewRank)
{
}

event OnPlayerKilled(MilRPPlayer Killer, MilRPPlayer Victim, bool bRDM)
{
}


///////////////////////////////////////////////////////////////////////////////
// Veto hooks - return false to block, fill FailReason with a player message
///////////////////////////////////////////////////////////////////////////////
function bool AllowFactionJoin(MilRPPlayer Player, int FactionID, out string FailReason)
{
	return true;
}

function bool AllowDuty(MilRPPlayer Player, bool bWantOnDuty, out string FailReason)
{
	return true;
}

function bool AllowLoadout(MilRPPlayer Player, out string Loadout)
{
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// State mutators
///////////////////////////////////////////////////////////////////////////////
function ModifyLoadout(MilRPPlayer Player, out string Loadout)
{
}
