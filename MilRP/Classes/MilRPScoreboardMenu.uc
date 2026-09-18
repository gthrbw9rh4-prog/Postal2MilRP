////////////////////////////////////////////////////////////////////////////////
// MilRPScoreboardMenu.uc
//
// Client-side Interaction backing the Tab roleplay scoreboard, drawn by
// MilRPHUD.DrawScoreboardMenu. Tab is bound to `Scoreboard`, which only
// fires on key press - this interaction watches for the IK_Tab IST_Release
// event to detect the key being let go, giving hold-to-view behaviour with
// zero per-frame polling.
//
// Input model (GMod-style): while the board is up the mouse still drives the
// camera. Pressing RightMouse unlocks a free cursor; pressing it again (or
// releasing Tab) returns control. Hovering a roster row highlights it;
// LeftMouse on a row opens a [Slap]/[Freeze]/[Kick] dropdown at the cursor,
// and every action routes through ServerAdminMenuAction, which validates
// staff permission server-side.
////////////////////////////////////////////////////////////////////////////////
class MilRPScoreboardMenu extends Interaction;

var float MouseX, MouseY;
var bool bMouseActive;				// right-click unlocked cursor

var MilRPPlayer RPO;

// Roster geometry synced from MilRPHUD.DrawScoreboardMenu every frame, so
// click hitboxes always match the pixels on screen.
var float PanelX, PanelY, PanelW, PanelH;
var float ListX, ListY, ListW;
var float RowH, Pad;
var int   ItemCount;				// roster rows actually drawn
var int   HoveredIndex;				// row under the mouse (-1 = none)
var int   SelectedIndex;			// row the dropdown is bound to (-1 = none)

// Admin action dropdown anchored at the last left-click.
var bool   bDropOpen;
var float  DropX, DropY, DropW, DropH;
var string DropTargetName;
var int    DropHover;				// 0..2 -> Slap / Freeze / Kick

const NUM_DROP_ACTIONS = 3;


event Initialized()
{
	local MilRPHUD RH;

	Super.Initialized();
	bRequiresTick = true;
	RPO = MilRPPlayer(ViewportOwner.Actor);
	if (RPO != None)
		RPO.ActiveScoreboard = self;
	CenterMouse();
	bMouseActive = false;
	bDropOpen = false;
	SelectedIndex = -1;
	HoveredIndex = -1;
}

function CenterMouse()
{
	local MilRPHUD RH;

	if (RPO != None && RPO.MyHUD != None)
	{
		RH = MilRPHUD(RPO.MyHUD);
		if (RH != None && RH.CanvasWidth > 0.0)
		{
			MouseX = RH.CanvasWidth * 0.5;
			MouseY = RH.CanvasHeight * 0.5;
			return;
		}
	}
	MouseX = 512.0;
	MouseY = 384.0;
}

event NotifyLevelChange()
{
	if (RPO != None)
		RPO.ActiveScoreboard = None;
	Master.RemoveInteraction(self);
}

function CloseMenu()
{
	if (RPO != None)
		RPO.ActiveScoreboard = None;
	Master.RemoveInteraction(self);
}

// Dropdown row -> ServerAdminMenuAction index (see MilRPPlayer).
function int DropActionForIndex(int Index)
{
	switch (Index)
	{
		case 0:		return 9;	// Slap
		case 1:		return 3;	// Freeze
		default:	return 0;	// Kick
	}
}

function ProcessClick()
{
	local int i;
	local float IY;
	local MilRPGameReplicationInfo GRI;

	if (RPO == None)
		return;

	// Dropdown clicks take priority while it is open; a click anywhere else
	// dismisses it.
	if (bDropOpen)
	{
		for (i = 0; i < NUM_DROP_ACTIONS; i++)
		{
			IY = DropY + Pad + i * RowH;
			if (MouseX >= DropX && MouseX <= DropX + DropW
				&& MouseY >= IY && MouseY <= IY + RowH)
			{
				RPO.ServerAdminMenuAction(DropTargetName, DropActionForIndex(i), "Scoreboard menu");
				bDropOpen = false;
				return;
			}
		}
		bDropOpen = false;
		return;
	}

	// Roster row click -> open the admin dropdown anchored at the cursor.
	// HoveredIndex is a PRIArray index (ItemCount is the drawn-row count -
	// they can diverge when a PRI slot is None), so bound against the array.
	GRI = MilRPGameReplicationInfo(RPO.GameReplicationInfo);
	if (HoveredIndex >= 0 && GRI != None && HoveredIndex < GRI.PRIArray.Length
		&& GRI.PRIArray[HoveredIndex] != None)
	{

		SelectedIndex = HoveredIndex;
		DropTargetName = GRI.PRIArray[SelectedIndex].PlayerName;
		DropW = FMax(140.0, ListW * 0.25);
		DropH = Pad * 2.0 + RowH * NUM_DROP_ACTIONS;
		DropX = MouseX;
		DropY = MouseY;
		// Clamp the dropdown inside the panel bounds.
		if (DropX + DropW > PanelX + PanelW - Pad)
			DropX = PanelX + PanelW - Pad - DropW;
		if (DropY + DropH > PanelY + PanelH - Pad)
			DropY = PanelY + PanelH - Pad - DropH;
		bDropOpen = true;
	}
}

function bool KeyEvent(EInputKey Key, EInputAction Action, float Delta)
{
	if (RPO == None)
	{
		Master.RemoveInteraction(self);
		return true;
	}

	// Tab released -> the whole board goes away (hold-to-view).
	if (Action == IST_Release && Key == IK_Tab)
	{
		CloseMenu();
		return false;
	}

	if (Action == IST_Axis)
	{
		// Only steal the mouse while the cursor is unlocked; otherwise the
		// camera keeps working under the overlay.
		if (!bMouseActive)
			return false;
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
		return false;
	}

	if (Action == IST_Press)
	{
		if (Key == IK_RightMouse)
		{
			// GMod-style cursor toggle: right-click grabs/releases the mouse.
			bMouseActive = !bMouseActive;
			if (bMouseActive)
				CenterMouse();
			else
				bDropOpen = false;
			return true;
		}
		if (Key == IK_LeftMouse)
		{
			if (bMouseActive)
			{
				ProcessClick();
				return true;
			}
			return false;
		}
		if (Key == IK_Escape)
		{
			CloseMenu();
			return true;
		}
	}
	return false;
}
