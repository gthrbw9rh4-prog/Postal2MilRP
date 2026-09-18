///////////////////////////////////////////////////////////////////////////////
// MilRPDutyStation.uc
//
// Clock in / out station. On-duty status and loadout changes are still
// processed by MilRPGameInfo.RequestDuty; this point is just a physical UI.
///////////////////////////////////////////////////////////////////////////////
class MilRPDutyStation extends MilRPInteractPoint;


function int BuildMenu(MilRPPlayer RPO, out string Options[8])
{
	local MilRPPlayerReplicationInfo PRI;

	PRI = RPO.GetRPPRI();
	if (PRI == None)
		return 0;

	MenuTitle = "Duty Station";
	if (PRI.bOnDuty)
	{
		Options[0] = "1. Clock OUT";
		return 1;
	}

	Options[0] = "1. Clock IN";
	return 1;
}

function bool HandleSelection(MilRPPlayer RPO, int Index, out string Feedback)
{
	local MilRPGameInfo Game;
	local MilRPPlayerReplicationInfo PRI;
	local string FailReason;
	local bool bWant;

	Game = GetGame();
	PRI = RPO.GetRPPRI();
	if (Game == None || PRI == None)
	{
		Feedback = "System offline.";
		return false;
	}

	bWant = !PRI.bOnDuty;
	if (Game.RequestDuty(RPO, bWant, FailReason))
	{
		if (bWant)
			Feedback = "Clocked in.";
		else
			Feedback = "Clocked out.";
	}
	else
		Feedback = FailReason;
	return true;
}


defaultproperties
{
	PointLabel="Press USE for duty"
	MenuTitle="Duty Station"
	bOffDutyOk=true
}