////////////////////////////////////////////////////////////////////////////////
// MilRPShopInteraction.uc
//
// Mouse-driven quartermaster shop screen. Opened client-side via
// MilRPPlayer.ClientOpenShopMenu after the locker validates access.
// Left panel lists the catalog, right panel shows details + [PURCHASE ITEM].
////////////////////////////////////////////////////////////////////////////////
class MilRPShopInteraction extends Interaction;

var float MouseX, MouseY;
var MilRPPlayer RPO;

var string ItemNames[16];
var int ItemPrices[16];
var int ItemRanks[16];
var int ItemCount;
var int SelectedIndex;

var float PanelX, PanelY, PanelW, PanelH;
var float ListX, ListY, ListW;
var float RowH, Pad;
var float BtnX, BtnY, BtnW, BtnH;		// [PURCHASE ITEM]
var float CloseX, CloseY;				// [CLOSE]


event Initialized()
{
	local MilRPHUD RH;

	Super.Initialized();
	bRequiresTick = true;
	RPO = MilRPPlayer(ViewportOwner.Actor);
	if (RPO != None)
		RPO.ActiveShopMenu = self;
	SelectedIndex = -1;

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
		RPO.ActiveShopMenu = None;
	Master.RemoveInteraction(self);
}

// Packed = "Name~Price~Rank|Name~Price~Rank|..."
function SetCatalog(string Packed)
{
	local string Tmp, Entry, Field;
	local int Pos, F;
	local array<string> Fields;

	ItemCount = 0;
	Tmp = Packed;
	while (Tmp != "" && ItemCount < 16)
	{
		Pos = InStr(Tmp, "|");
		if (Pos < 0)
		{
			Entry = Tmp;
			Tmp = "";
		}
		else
		{
			Entry = Left(Tmp, Pos);
			Tmp = Mid(Tmp, Pos + 1);
		}
		if (Entry == "")
			continue;

		// Split entry into fields on '~'
		Fields.Length = 0;
		while (Entry != "")
		{
			F = InStr(Entry, "~");
			if (F < 0)
			{
				Field = Entry;
				Entry = "";
			}
			else
			{
				Field = Left(Entry, F);
				Entry = Mid(Entry, F + 1);
			}
			Fields[Fields.Length] = Field;
		}
		if (Fields.Length < 3)
			continue;

		ItemNames[ItemCount] = Fields[0];
		ItemPrices[ItemCount] = int(Fields[1]);
		ItemRanks[ItemCount] = int(Fields[2]);
		ItemCount++;
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
	local int i;
	local float IY;

	if (RPO == None)
		return;

	// Purchase button
	if (MouseX >= BtnX && MouseX <= BtnX + BtnW && MouseY >= BtnY && MouseY <= BtnY + BtnH)
	{
		if (SelectedIndex >= 0 && SelectedIndex < ItemCount)
			RPO.ServerShopBuy(SelectedIndex);
		return;
	}
	// Close button
	if (MouseX >= CloseX && MouseX <= CloseX + BtnW && MouseY >= CloseY && MouseY <= CloseY + BtnH)
	{
		CloseMenu();
		return;
	}
	// Catalog rows
	for (i = 0; i < ItemCount; i++)
	{
		IY = ListY + (i * RowH);
		if (MouseX >= ListX && MouseX <= ListX + ListW && MouseY >= IY && MouseY <= IY + RowH)
		{
			SelectedIndex = i;
			return;
		}
	}
}

function CloseMenu()
{
	if (RPO != None)
	{
		RPO.ServerInteractClosed();
		RPO.ActiveShopMenu = None;
	}
	Master.RemoveInteraction(self);
}
