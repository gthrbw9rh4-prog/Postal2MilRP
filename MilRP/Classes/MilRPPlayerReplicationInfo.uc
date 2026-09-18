///////////////////////////////////////////////////////////////////////////////
// MilRPPlayerReplicationInfo.uc
//
// Per-player roleplay identity that EVERY client needs to see (name plates,
// scoreboard, HUD identity trace): faction, rank, duty status.
//
// Private economy data (wallet) is deliberately NOT here - it is replicated
// owner-only from MilRPPlayer so other clients never pay for it.
//
// PlayerReplicationInfo.Score is reused as the persistent "RP score" that
// drives promotions, so no extra float is replicated for it.
///////////////////////////////////////////////////////////////////////////////
class MilRPPlayerReplicationInfo extends MpPlayerReplicationInfo;


///////////////////////////////////////////////////////////////////////////////
// Replicated roleplay identity
///////////////////////////////////////////////////////////////////////////////
var byte	FactionID;			// index into MilRPGameReplicationInfo faction tables, 255 = none
var byte	Rank;				// index into MilRPGameReplicationInfo rank ladder
var bool	bOnDuty;			// true while the player is clocked in
var bool	bRoleplayReady;		// server has finished restoring/initialising this player
var bool	bFrozen;			// admin/moderation freeze - no movement or fire's record
var string	NetSignature;		// IP / network signature (visible to admin HUD only)

// Server-only bookkeeping (never replicated)
var int		DutySeconds;		// total seconds spent on duty this session
var int		LastDutyChangeTime;	// GameInfo ElapsedTime of the last duty toggle
var int		LastFactionChangeTime;
var int		WarningCount;		// admin warnings / RDM strikes
var bool	bSteamQueried;		// server-only: native Steam ID/name already attempted


replication
{
	reliable if ( bNetDirty && (Role == ROLE_Authority) )
		FactionID, Rank, bOnDuty, bRoleplayReady, bFrozen, NetSignature;
}


///////////////////////////////////////////////////////////////////////////////
// Match reset (called by GameInfo.Reset via PRI.Reset)
///////////////////////////////////////////////////////////////////////////////
function Reset()
{
	Super.Reset();
	bOnDuty = false;
	LastDutyChangeTime = 0;
}


///////////////////////////////////////////////////////////////////////////////
// Client/server helpers
///////////////////////////////////////////////////////////////////////////////
simulated function bool HasFaction()
{
	return (FactionID != 255);
}

simulated function MilRPGameReplicationInfo GetRPGRI()
{
	local GameReplicationInfo GRI;

	foreach DynamicActors(class'GameReplicationInfo', GRI)
		return MilRPGameReplicationInfo(GRI);
	return None;
}

simulated function string GetFactionName()
{
	local MilRPGameReplicationInfo GRI;

	GRI = GetRPGRI();
	if (GRI == None || !HasFaction())
		return "";
	return GRI.GetFactionName(FactionID);
}

simulated function string GetRankTitle()
{
	local MilRPGameReplicationInfo GRI;

	GRI = GetRPGRI();
	if (GRI == None)
		return "";
	return GRI.GetRankTitle(Rank);
}

// "[USMC] Sgt. PlayerName" style tag used on name plates and chat.
simulated function string GetDisplayName()
{
	local MilRPGameReplicationInfo GRI;
	local string Result;

	GRI = GetRPGRI();
	if (GRI != None && HasFaction() && GRI.GetFactionTag(FactionID) != "")
		Result = "[" $ GRI.GetFactionTag(FactionID) $ "] ";
	if (GRI != None && GRI.GetRankTitle(Rank) != "")
		Result = Result $ GRI.GetRankTitle(Rank) $ " ";
	return Result $ PlayerName;
}


defaultproperties
{
	FactionID=255
	Rank=0
	bOnDuty=false
	bRoleplayReady=false
}
