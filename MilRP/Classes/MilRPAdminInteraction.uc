////////////////////////////////////////////////////////////////////////////////
// MilRPAdminInteraction.uc
//
// Mouse-driven admin control board implemented as a client-side Interaction.
// Heavily inspired by the mouse/canvas framework in GotiLab's GmodMenu.
////////////////////////////////////////////////////////////////////////////////
class MilRPAdminInteraction extends Interaction;

var float MouseX, MouseY;
var float ListX, ListY, ListW, ListH;
var float ActionX, ActionY, ActionW, ActionH;
var float RowH;
var float Pad;
var float BtnW, BtnH;
var int   SelectedActionIndex;

var MilRPPlayer RPO;

const MAX_ACTIONS = 10;
const COLS = 2;

var string ActionLabels[10];

event Initialized()
{
	local MilRPHUD RH;

	Super.Initialized();
	bRequiresTick = true;
	RPO = MilRPPlayer(ViewportOwner.Actor);
	if (RPO != None)
		RPO.ActiveAdminInteraction = self;

	// Spawn cursor in the exact screen centre
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

	ActionLabels[0] = "Kick";
	ActionLabels[1] = "Ban";
	ActionLabels[2] = "Warn";
	ActionLabels[3] = "Freeze";
	ActionLabels[4] = "Goto";
	ActionLabels[5] = "Bring";
	ActionLabels[6] = "DEFCON";
	ActionLabels[7] = "Lockdown";
	ActionLabels[8] = "Noclip";
	ActionLabels[9] = "Slap";
}

event NotifyLevelChange()
{
	if (RPO != None)
		RPO.ActiveAdminInteraction = None;
	Master.RemoveInteraction(self);
}

simulated function Draw(Canvas C)
{
	local GameReplicationInfo GRI;
	local int i, Max;
	local float Y, AX, AY, AW, AH;
	local bool bHover;
	local string Txt;

	if (RPO == None)
	{
		Master.RemoveInteraction(self);
		return;
	}

	// Layout scaled to current Canvas size.
	ListX = 0.04 * C.ClipX;
	ListY = 0.10 * C.ClipY;
	ListW = 0.30 * C.ClipX;
	ListH = 0.70 * C.ClipY;
	ActionX = 0.40 * C.ClipX;
	ActionY = 0.10 * C.ClipY;
	ActionW = 0.50 * C.ClipX;
	ActionH = 0.70 * C.ClipY;
	RowH = 20.0;
	AW = (ActionW / 2.0) - 4.0;
	AH = RowH - 2.0;

	// Title
	C.SetPos(0.04 * C.ClipX, 0.04 * C.ClipY);
	C.DrawColor = C.MakeColor(255, 255, 255, 255);
	C.DrawText("MilRP Admin Control Board", false);

	// Player list
	GRI = RPO.GameReplicationInfo;
	if (GRI != None)
	{
		Max = GRI.PRIArray.Length;
		for (i = 0; i < Max; i++)
		{
			Y = ListY + (i * RowH);
			bHover = (MouseX >= ListX && MouseX <= ListX + ListW && MouseY >= Y && MouseY <= Y + RowH);
			if (bHover || (i == RPO.SelectedPlayerIndex))
				C.DrawColor = C.MakeColor(0, 255, 0, 200);
			else
				C.DrawColor = C.MakeColor(255, 255, 255, 255);
			C.SetPos(ListX, Y);
			C.DrawText(GRI.PRIArray[i].PlayerName, false);
		}
	}

	// Action grid (2 columns x 5 rows)
	for (i = 0; i < MAX_ACTIONS; i++)
	{
		AX = ActionX + ((i % COLS) * (ActionW / 2.0));
		AY = ActionY + ((i / COLS) * RowH);
		bHover = (MouseX >= AX && MouseX <= AX + AW && MouseY >= AY && MouseY <= AY + AH);
		if (bHover || (i == SelectedActionIndex))
			C.DrawColor = C.MakeColor(0, 128, 255, 200);
		else
			C.DrawColor = C.MakeColor(255, 255, 255, 255);
		C.SetPos(AX, AY);
		C.DrawText("[" $ ActionLabels[i] $ "]", false);
	}

	// Selected player / reason footer
	C.SetPos(ActionX, ActionY + 180.0);
	C.DrawColor = C.MakeColor(255, 255, 0, 255);
	Txt = "Selected: ";
	if (GRI != None && RPO.SelectedPlayerIndex >= 0 && RPO.SelectedPlayerIndex < GRI.PRIArray.Length)
		Txt = Txt $ GRI.PRIArray[RPO.SelectedPlayerIndex].PlayerName;
	else
		Txt = Txt $ "None";
	C.DrawText(Txt, false);

	C.SetPos(ActionX, ActionY + 200.0);
	C.DrawText("Reason: " $ RPO.AdminMenuReason, false);

	// Mouse cursor
	C.SetPos(MouseX, MouseY);
	C.Style = 5;
	C.DrawColor = C.MakeColor(255, 255, 255, 255);
	C.DrawTile(Texture'UWindow.Icons.MouseCursor', 20, 20, 0, 0, 32, 32);
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
			if (RPO != None)
				RPO.ActiveAdminInteraction = None;
			Master.RemoveInteraction(self);
			return true;
		}
	}

	return false;
}

function ProcessClick()
{
	local GameReplicationInfo GRI;
	local int i, idx;
	local float AX, AY;
	local string TargetName;

	if (RPO == None)
		return;

	GRI = RPO.GameReplicationInfo;
	if (GRI == None)
		return;

	// Player list selection
	if (RowH > 0.0 && MouseX >= ListX && MouseX <= ListX + ListW)
	{
		idx = int((MouseY - ListY) / RowH);
		if (idx >= 0 && idx < GRI.PRIArray.Length)
			RPO.SelectedPlayerIndex = idx;
	}

	// Action grid clicks
	if (BtnW <= 0.0 || BtnH <= 0.0 || ActionH <= 0.0)
		return;

	for (i = 0; i < MAX_ACTIONS; i++)
	{
		AX = ActionX + ((i % COLS) * (BtnW + Pad));
		AY = ActionY + ((i / COLS) * ActionH);
		if (MouseX >= AX && MouseX <= AX + BtnW && MouseY >= AY && MouseY <= AY + BtnH)
		{
			RPO.SelectedActionIndex = i;
			SelectedActionIndex = i;
			if (RPO.SelectedPlayerIndex >= 0 && RPO.SelectedPlayerIndex < GRI.PRIArray.Length)
				TargetName = GRI.PRIArray[RPO.SelectedPlayerIndex].PlayerName;
			else
				TargetName = "";
			if (RPO.AdminMenuReason == "")
				RPO.AdminMenuReason = "Admin menu";
			RPO.ServerAdminMenuAction(TargetName, i, RPO.AdminMenuReason);
		}
	}
}
