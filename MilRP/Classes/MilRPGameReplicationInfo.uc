///////////////////////////////////////////////////////////////////////////////
// MilRPGameReplicationInfo.uc
//
// Server -> all clients snapshot of the roleplay ruleset that every HUD and
// menu needs: the faction table, the rank ladder, and a small ring buffer of
// base-wide broadcast lines.
//
// Replication strategy (UE2, low bandwidth):
//   * Faction / rank tables are static arrays sent once (bNetInitial).
//   * Broadcast lines live in a fixed ring; only the slot that changed and the
//     write cursor are dirtied, so a broadcast costs one string + one byte.
//   * Dynamic arrays never replicate in UE2, hence the fixed-size arrays with
//     explicit counts.
///////////////////////////////////////////////////////////////////////////////
class MilRPGameReplicationInfo extends MpGameReplicationInfo;


///////////////////////////////////////////////////////////////////////////////
// Configuration / limits
///////////////////////////////////////////////////////////////////////////////
const MAX_FACTIONS			= 8;		// hard cap on selectable factions
const MAX_RANKS				= 16;		// hard cap on rank ladder length
const MAX_BROADCAST_LINES	= 6;		// ring buffer depth for HUD feed
const FACTION_NONE			= 255;		// sentinel: player has no faction


///////////////////////////////////////////////////////////////////////////////
// Replicated state
///////////////////////////////////////////////////////////////////////////////
var byte		FactionCount;
var string		FactionNames[8];			// display name per faction id
var string		FactionTags[8];				// short tag, e.g. "USMC", "RU", "CIV"
var color		FactionColors[8];			// HUD tint per faction
var byte		FactionCombatant[8];		// 0 = civilian style faction (no duty loadout)

var byte		RankCount;
var string		RankTitles[16];				// display title per rank index
var int			RankMinScore[16];			// RP score required to hold this rank

var string		BroadcastLines[6];			// ring buffer of base-wide messages
var byte		BroadcastCursor;			// index of the NEXT slot to be written
var byte		BroadcastSerial;			// increments on every write, lets clients detect new lines

var int			PaycheckInterval;			// seconds, mirrored from GameInfo for HUD countdown
var int			NextPaycheckTime;			// server ElapsedTime at which the next paycheck fires
var bool		bEnforceFactions;			// mirrored from GameInfo for menus
var byte		MaxSlots;					// GameInfo.MaxPlayers, for the scoreboard header

// Alert / lockdown state (DEFCON 0-5)
var byte		AlertLevel;					// 0 = green, 5 = red/lockdown
var bool		bLockdown;					// movement + duty restrictions active
var byte		CommandChannelRank;			// minimum rank to use command radio


replication
{
	// Static tables: sent once when the GRI first becomes relevant.
	reliable if ( bNetInitial && (Role == ROLE_Authority) )
		FactionCount, FactionNames, FactionTags, FactionColors, FactionCombatant,
		RankCount, RankTitles, RankMinScore,
		PaycheckInterval, bEnforceFactions, MaxSlots;

	// Volatile state: only sent when it actually changes.
	reliable if ( bNetDirty && (Role == ROLE_Authority) )
		BroadcastLines, BroadcastCursor, BroadcastSerial, NextPaycheckTime,
		AlertLevel, bLockdown, CommandChannelRank;
}


///////////////////////////////////////////////////////////////////////////////
// Server-side mutators
///////////////////////////////////////////////////////////////////////////////
function ClearTables()
{
	local int i;

	FactionCount = 0;
	RankCount = 0;
	for (i = 0; i < MAX_FACTIONS; i++)
	{
		FactionNames[i] = "";
		FactionTags[i] = "";
		FactionCombatant[i] = 0;
		FactionColors[i] = class'Canvas'.static.MakeColor(255, 255, 255);
	}
	for (i = 0; i < MAX_RANKS; i++)
	{
		RankTitles[i] = "";
		RankMinScore[i] = 0;
	}
}

function bool AddFaction(string DisplayName, string Tag, color Tint, bool bCombatant)
{
	if (FactionCount >= MAX_FACTIONS || DisplayName == "")
		return false;

	FactionNames[FactionCount] = DisplayName;
	FactionTags[FactionCount] = Tag;
	FactionColors[FactionCount] = Tint;
	FactionCombatant[FactionCount] = byte(bCombatant);
	FactionCount++;
	return true;
}

function bool AddRank(string Title, int MinScore)
{
	if (RankCount >= MAX_RANKS || Title == "")
		return false;

	RankTitles[RankCount] = Title;
	RankMinScore[RankCount] = MinScore;
	RankCount++;
	return true;
}

function PushBroadcast(string Line)
{
	if (Line == "")
		return;

	BroadcastLines[BroadcastCursor] = Line;
	BroadcastCursor = (BroadcastCursor + 1) % MAX_BROADCAST_LINES;
	BroadcastSerial++;
}


///////////////////////////////////////////////////////////////////////////////
// Shared accessors (safe on client and server)
///////////////////////////////////////////////////////////////////////////////
simulated function bool IsValidFaction(int FactionID)
{
	return (FactionID >= 0 && FactionID < FactionCount);
}

simulated function string GetFactionName(int FactionID)
{
	if (IsValidFaction(FactionID))
		return FactionNames[FactionID];
	return "";
}

simulated function string GetFactionTag(int FactionID)
{
	if (IsValidFaction(FactionID))
		return FactionTags[FactionID];
	return "";
}

simulated function color GetFactionColor(int FactionID)
{
	if (IsValidFaction(FactionID))
		return FactionColors[FactionID];
	return class'Canvas'.static.MakeColor(200, 200, 200);
}

simulated function bool IsCombatantFaction(int FactionID)
{
	return IsValidFaction(FactionID) && (FactionCombatant[FactionID] != 0);
}

simulated function string GetRankTitle(int RankIndex)
{
	if (RankIndex >= 0 && RankIndex < RankCount)
		return RankTitles[RankIndex];
	return "";
}

// Highest rank index whose score threshold the given score satisfies.
simulated function int RankForScore(int Score)
{
	local int i, Best;

	Best = 0;
	for (i = 0; i < RankCount; i++)
		if (Score >= RankMinScore[i])
			Best = i;
	return Best;
}

simulated function string GetAlertName()
{
	switch (AlertLevel)
	{
		case 0:		return "DEFCON 5 - Peacetime";
		case 1:		return "DEFCON 4 - Vigilance";
		case 2:		return "DEFCON 3 - Round-Clock";
		case 3:		return "DEFCON 2 - Ready";
		case 4:
		case 5:		return "DEFCON 1 - Lockdown";
	}
	return "UNKNOWN";
}

simulated function color GetAlertColor()
{
	switch (AlertLevel)
	{
		case 0:		return class'Canvas'.static.MakeColor(60, 200, 60);
		case 1:		return class'Canvas'.static.MakeColor(120, 200, 60);
		case 2:		return class'Canvas'.static.MakeColor(220, 200, 60);
		case 3:		return class'Canvas'.static.MakeColor(220, 120, 60);
		case 4:		case 5:		return class'Canvas'.static.MakeColor(220, 60, 60);
	}
	return class'Canvas'.static.MakeColor(255, 255, 255);
}


// Returns the i-th most recent broadcast line (0 = newest). Empty when unused.
simulated function string GetBroadcastLine(int Age)
{
	local int Idx;

	if (Age < 0 || Age >= MAX_BROADCAST_LINES)
		return "";
	Idx = (int(BroadcastCursor) - 1 - Age + (MAX_BROADCAST_LINES * 2)) % MAX_BROADCAST_LINES;
	return BroadcastLines[Idx];
}


defaultproperties
{
	ServerName="MilRP Military Roleplay Server"
	ShortName="MilRP"
	FactionCount=0
	RankCount=0
	BroadcastCursor=0
	BroadcastSerial=0
	AlertLevel=0
	bLockdown=false
	CommandChannelRank=3
}
