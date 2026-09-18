///////////////////////////////////////////////////////////////////////////////
// MilRPEnlistTerminal.uc
//
// Allows an unassigned player to join a faction by physically walking up to a
// terminal and selecting one. This is the in-world equivalent of /joinfaction.
///////////////////////////////////////////////////////////////////////////////
class MilRPEnlistTerminal extends MilRPInteractPoint;


function int BuildMenu(MilRPPlayer RPO, out string Options[8])
{
	local int i;
	local MilRPGameInfo Game;

	Game = GetGame();
	if (Game == None || RPO.GetRPGRI() == None)
		return 0;

	MenuTitle = "Enlistment Terminal";
	for (i = 0; i < Game.Factions.Length && i < 8; i++)
		Options[i] = (i + 1) $ ". Join " $ Game.Factions[i].Name;

	return Min(Game.Factions.Length, 8);
}

function bool HandleSelection(MilRPPlayer RPO, int Index, out string Feedback)
{
	local int FactionID;
	local MilRPGameInfo Game;
	local string FailReason;

	Game = GetGame();
	if (Game == None)
	{
		Feedback = "System offline.";
		return false;
	}

	FactionID = Index;
	if (FactionID < 0 || FactionID >= Game.Factions.Length)
	{
		Feedback = "Invalid faction.";
		return false;
	}

	if (Game.RequestFaction(RPO, FactionID, FailReason))
		Feedback = "Enlisted with " $ Game.Factions[FactionID].Name $ ".";
	else
		Feedback = FailReason;
	return true;
}


defaultproperties
{
	PointLabel="Press USE to enlist"
	MenuTitle="Enlistment Terminal"
	bOffDutyOk=true
}