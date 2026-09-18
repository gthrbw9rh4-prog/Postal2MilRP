////////////////////////////////////////////////////////////////////////////////
// MilRPDEFCONInteraction.uc
//
// Mouse-driven DEFCON control board. Opened client-side via
// MilRPPlayer.ClientOpenDEFCONMenu after the console validates admin access.
// Left column holds the three threat-level buttons, right column shows the
// live server status readout drawn by MilRPHUD.DrawDEFCONMenu.
//
// Internal level mapping (MilRPGameReplicationInfo.GetAlertName scale):
//   button 0  DEFCON 3 - NORMAL    -> level 2  (sirens silent)
//   button 1  DEFCON 2 - ELEVATED  -> level 3  (radio alert tone loop)
//   button 2  DEFCON 1 - LOCKDOWN  -> level 5  (klaxon + bLockdown)
////////////////////////////////////////////////////////////////////////////////
class MilRPDEFCONInteraction extends Interaction;

var float MouseX, MouseY;
var MilRPPlayer RPO;

var float PanelX, PanelY, PanelW, PanelH;
var float ListX, ListY, ListW;			// threat button column
var float RowH, Pad;
var float CloseX, CloseY;				// [CLOSE]
var float BtnW, BtnH;

const NUM_LEVELS = 3;


event Initialized()
{
	local MilRPHUD RH;

	Super.Initialized();
	bRequiresTick = true;
	RPO = MilRPPlayer(ViewportOwner.Actor);
	if (RPO != None)
		RPO.ActiveDEFCONMenu = self;

	if (RPO != None && RPO.MyHUD != None)
	{
		RH = MilRPHUD(RPO.MyHUD);
		if (RH != None && RH.CanvasWidth > 0.0)
		{
			MouseX = RH.CanvasWidth * 0.5;
			MouseY = RH.CanvasHeight * 0.5;
		}
		else
		{
			MouseX = 512.0;
			MouseY = 384.0;
		}
	}
	else
	{
		MouseX = 512.0;
		MouseY = 384.0;
	}
}

event NotifyLevelChange()
{
	if (RPO != None)
		RPO.ActiveDEFCONMenu = None;
	Master.RemoveInteraction(self);
}

// Button index -> internal alert level (see header for the mapping).
function int LevelForButton(int Index)
{
	switch (Index)
	{
		case 0:		return 2;	// DEFCON 3 - normal
		case 1:		return 3;	// DEFCON 2 - elevated
		case 2:		return 5;	// DEFCON 1 - lockdown
	}
	return 0;
}

function bool KeyEvent(EInputKey Key, EInputAction Action, float Delta)
{
	if (RPO == None)
	{
		Master.RemoveInteraction(self);
		return true;
	}

	if (Action == IST_Axis)
	{
		if (Key == IK_MouseX)
		{
			MouseX += Delta;
			return true;
		}
		if (Key == IK_MouseY)
		{
			MouseY -= Delta;
			return true;
		}
	}

	if (Action == IST_Press)
	{
		if (Key == IK_LeftMouse)
		{
			ProcessClick();
			return true;
		}
		if (Key == IK_RightMouse || Key == IK_Escape)
		{
			CloseMenu();
			return true;
		}
	}
	return false;
}

function ProcessClick()
{
	local int i;
	local float IY;

	if (RPO == None)
		return;

	// Close button
	if (MouseX >= CloseX && MouseX <= CloseX + BtnW && MouseY >= CloseY && MouseY <= CloseY + BtnH)
	{
		CloseMenu();
		return;
	}

	// Threat-level buttons
	for (i = 0; i < NUM_LEVELS; i++)
	{
		IY = ListY + (i * (BtnH + Pad));
		if (MouseX >= ListX && MouseX <= ListX + ListW && MouseY >= IY && MouseY <= IY + BtnH)
		{
			RPO.ServerUpdateDEFCON(LevelForButton(i));
			return;
		}
	}
}

function CloseMenu()
{
	if (RPO != None)
	{
		RPO.ServerInteractClosed();
		RPO.ActiveDEFCONMenu = None;
	}
	Master.RemoveInteraction(self);
}
