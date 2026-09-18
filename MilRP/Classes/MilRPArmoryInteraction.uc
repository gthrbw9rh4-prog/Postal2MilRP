////////////////////////////////////////////////////////////////////////////////
// MilRPArmoryInteraction.uc
//
// Mouse-driven tactical armory crate screen. Opened client-side via
// MilRPPlayer.ClientOpenArmoryMenu after the locker validates access.
// Left column lists the issued kit, right side holds [RESTOCK MUNITIONS].
////////////////////////////////////////////////////////////////////////////////
class MilRPArmoryInteraction extends Interaction;

var float MouseX, MouseY;
var MilRPPlayer RPO;

var string KitLines[16];
var int KitCount;

var float PanelX, PanelY, PanelW, PanelH;
var float ListX, ListY, ListW;
var float RowH, Pad;
var float BtnX, BtnY, BtnW, BtnH;		// [RESTOCK MUNITIONS]
var float CloseX, CloseY;				// [CLOSE]


event Initialized()
{
	local MilRPHUD RH;

	Super.Initialized();
	bRequiresTick = true;
	RPO = MilRPPlayer(ViewportOwner.Actor);
	if (RPO != None)
		RPO.ActiveArmoryMenu = self;

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
		RPO.ActiveArmoryMenu = None;
	Master.RemoveInteraction(self);
}

// Packed = comma-separated duty loadout class paths from the server.
function SetKit(string Packed)
{
	local string Tmp, Item;
	local int Pos;

	KitCount = 0;
	Tmp = Packed;
	while (Tmp != "" && KitCount < 16)
	{
		Pos = InStr(Tmp, ",");
		if (Pos < 0)
		{
			Item = Tmp;
			Tmp = "";
		}
		else
		{
			Item = Left(Tmp, Pos);
			Tmp = Mid(Tmp, Pos + 1);
		}
		if (Item != "")
		{
			KitLines[KitCount] = Item;
			KitCount++;
		}
	}
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
	if (RPO == None)
		return;

	if (MouseX >= BtnX && MouseX <= BtnX + BtnW && MouseY >= BtnY && MouseY <= BtnY + BtnH)
	{
		RPO.ServerArmoryResupply();
		return;
	}
	if (MouseX >= CloseX && MouseX <= CloseX + BtnW && MouseY >= CloseY && MouseY <= CloseY + BtnH)
		CloseMenu();
}

function CloseMenu()
{
	if (RPO != None)
	{
		RPO.ServerInteractClosed();
		RPO.ActiveArmoryMenu = None;
	}
	Master.RemoveInteraction(self);
}
