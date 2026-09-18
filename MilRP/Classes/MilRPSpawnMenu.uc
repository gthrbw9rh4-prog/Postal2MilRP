////////////////////////////////////////////////////////////////////////////////
// MilRPSpawnMenu.uc
//
// Admin-only GMod-style Q spawn menu using a client-side Interaction.
// Mouse-driven tabs on the left, item grid on the right.
////////////////////////////////////////////////////////////////////////////////
class MilRPSpawnMenu extends Interaction;

var float MouseX, MouseY;
var int ActiveTab;
var bool bGiveToSelf;
var string TabLabels[5];
var int ItemsPerTab[5];
var string ItemNames[135];
var string ItemValueA[135]; // Weapon class / Mesh / Prop class / NPC class
var string ItemValueB[135]; // Texture for skins

var MilRPPlayer RPO;

var float TabX, TabY, TabW;
var float GridX, GridY, GridW;
var float RowH;
var float Pad;
var float ModeX, ModeY, ModeW, ModeH;
var float ResetX, ResetY, ResetW, ResetH;
var float ClearX, ClearY, ClearW, ClearH;
var int   HoveredIndex;				// grid row under the mouse (-1 = none)
var int   SelectedIndex;			// flat item index (tab * MAX_ROWS + row)
var string SelectedItemName;

const NUM_TABS = 5;
const MAX_ROWS = 27;

event Initialized()
{
	local MilRPHUD RH;

	Super.Initialized();
	bRequiresTick = true;
	RPO = MilRPPlayer(ViewportOwner.Actor);
	if (RPO != None)
		RPO.ActiveSpawnMenu = self;

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

	BuildItems();
	bGiveToSelf = true;
}

function BuildItems()
{
	local int o;

	TabLabels[0] = "Weapons";
	TabLabels[1] = "Vehicles";
	TabLabels[2] = "Props";
	TabLabels[3] = "NPCs";
	TabLabels[4] = "Skins";

	// Weapons tab: ShareThePain weapon class names (not pickup classes)
	o = 0;
	ItemNames[o] = "Pistol";
	ItemValueA[o] = "Inventory.PistolWeaponSS";
	ItemNames[o + 1] = "Shotgun";
	ItemValueA[o + 1] = "Inventory.ShotGunWeaponSS";
	ItemNames[o + 2] = "Machine Gun";
	ItemValueA[o + 2] = "Inventory.MachineGunWeaponSS";
	ItemNames[o + 3] = "Hunting Rifle";
	ItemValueA[o + 3] = "Inventory.RifleWeaponSS";
	ItemNames[o + 4] = "Grenades";
	ItemValueA[o + 4] = "Inventory.GrenadeWeaponSS";
	ItemNames[o + 5] = "Molotovs";
	ItemValueA[o + 5] = "Inventory.MolotovWeaponSS";
	ItemNames[o + 6] = "Rocket Launcher";
	ItemValueA[o + 6] = "Inventory.LauncherWeaponSS";
	ItemNames[o + 7] = "Baton";
	ItemValueA[o + 7] = "Inventory.BatonWeaponSS";
	ItemNames[o + 8] = "Scissors";
	ItemValueA[o + 8] = "Inventory.ScissorsWeaponSS";
	ItemNames[o + 9] = "Shovel";
	ItemValueA[o + 9] = "Inventory.ShovelWeaponSS";
	ItemNames[o + 10] = "Cow Head Launcher";
	ItemValueA[o + 10] = "Inventory.CowHeadWeaponSS";
	ItemNames[o + 11] = "Anthrax Nade";
	ItemValueA[o + 11] = "Inventory.MrDKNadeWeaponSS";
	ItemsPerTab[0] = 12;

	// Vehicles / Deployables tab: heavy static hardware as solid props
	o = MAX_ROWS;
	ItemNames[o] = "APC (Stationary)";
	ItemValueA[o] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o] = "Zo_BaseMeshes.zo_base_newapc";
	ItemNames[o + 1] = "Radar Base";
	ItemValueA[o + 1] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 1] = "Zo_BaseMeshes.zo_base_radarbase";
	ItemNames[o + 2] = "Heavy Doorway";
	ItemValueA[o + 2] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 2] = "Zo_BaseMeshes.zo_base_heavydoorway";
	ItemNames[o + 3] = "Caution Doorway";
	ItemValueA[o + 3] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 3] = "Zo_BaseMeshes.zo_base_cautiondoorway";
	ItemNames[o + 4] = "Blast Door";
	ItemValueA[o + 4] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 4] = "Zo_BaseMeshes.zo_base_door1";
	ItemNames[o + 5] = "Blast Door Alt";
	ItemValueA[o + 5] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 5] = "Zo_BaseMeshes.zo_base_door2";
	ItemNames[o + 6] = "Watchtower";
	ItemValueA[o + 6] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 6] = "Zo_BaseMeshes.zo_base_watchtower";
	ItemNames[o + 7] = "Concrete Barricade";
	ItemValueA[o + 7] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 7] = "dj-protostuff.Barricade";
	ItemNames[o + 8] = "Warehouse Shelf";
	ItemValueA[o + 8] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 8] = "Zo_Industry_Meshes.zo_warehouse_shelf";
	ItemNames[o + 9] = "Kennel Door";
	ItemValueA[o + 9] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 9] = "Zo_Industry_Meshes.zo_kennel_door";
	ItemNames[o + 10] = "Light Pole";
	ItemValueA[o + 10] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 10] = "Zo_BaseMeshes.zo_base_lightpole";
	ItemNames[o + 11] = "Wall Light";
	ItemValueA[o + 11] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 11] = "Zo_Generic.zo_generic_walllight";
	ItemNames[o + 12] = "Roof Light";
	ItemValueA[o + 12] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 12] = "Zo_Generic.zo_generic_rooflight";
	ItemsPerTab[1] = 13;

	// Props tab: MoveableStaticMeshActor + static meshes verified against the
	// installed .usx packages via MilRPGameInfo::ProbeStaticMeshes, plus the
	// interactive MilRP placeables (lockers, sirens, consoles, capture zones).
	o = 2 * MAX_ROWS;
	ItemNames[o] = "Ammo Crate";
	ItemValueA[o] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o] = "Zo_BaseMeshes.zo_base_ammocrate2";
	ItemNames[o + 1] = "Open Crate";
	ItemValueA[o + 1] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 1] = "Zo_BaseMeshes.zo_base_opencrate";
	ItemNames[o + 2] = "Ammo Box";
	ItemValueA[o + 2] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 2] = "Zo_Meshes.zo_ammobox1";
	ItemNames[o + 3] = "Ammo Barrel";
	ItemValueA[o + 3] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 3] = "Zo_BaseMeshes.zo_base_ammobarrel";
	ItemNames[o + 4] = "Military Barrier";
	ItemValueA[o + 4] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 4] = "Zo_BaseMeshes.zo_base_barrier1";
	ItemNames[o + 5] = "Police Barricade";
	ItemValueA[o + 5] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 5] = "dj-protostuff.Barricade_Police";
	ItemNames[o + 6] = "Warning Barricade";
	ItemValueA[o + 6] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 6] = "dj-protostuff.Barricade_Warning";
	ItemNames[o + 7] = "Bunker";
	ItemValueA[o + 7] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 7] = "Zo_BaseMeshes.zo_base_bunker1";
	ItemNames[o + 8] = "Watchtower";
	ItemValueA[o + 8] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 8] = "Zo_BaseMeshes.zo_base_watchtower";
	ItemNames[o + 9] = "Camo Netting";
	ItemValueA[o + 9] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 9] = "Zo_BaseMeshes.zo_base_camothing";
	ItemNames[o + 10] = "Chain Link Fence";
	ItemValueA[o + 10] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 10] = "Zo_Industry_Meshes.zo_tallchainlinkfence";
	ItemNames[o + 11] = "Rusted Fence";
	ItemValueA[o + 11] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 11] = "p2-outdoors-SW.rustedfence_sw";
	ItemNames[o + 12] = "Couch";
	ItemValueA[o + 12] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 12] = "dj-protostuff.Couch_Sectional";
	ItemNames[o + 13] = "Street Lamp";
	ItemValueA[o + 13] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 13] = "dj-protostuff.Lamp_Street";
	ItemNames[o + 14] = "Faction Armory Box";
	ItemValueA[o + 14] = "MilRP.MilRPArmoryLocker";
	ItemNames[o + 15] = "Quartermaster Shop Crate";
	ItemValueA[o + 15] = "MilRP.MilRPShopLocker";
	ItemNames[o + 16] = "Ammo Footlocker";
	ItemValueA[o + 16] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 16] = "Zo_BaseMeshes.zo_base_ammocrate3";
	ItemNames[o + 17] = "Bunker Large";
	ItemValueA[o + 17] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 17] = "Zo_BaseMeshes.zo_base_bunker2";
	ItemNames[o + 18] = "Bunker XL";
	ItemValueA[o + 18] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 18] = "Zo_BaseMeshes.zo_base_bunker3";
	ItemNames[o + 19] = "Metal Locker";
	ItemValueA[o + 19] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 19] = "ben_mesh.locker_functional01_ben";
	ItemNames[o + 20] = "Control Desk";
	ItemValueA[o + 20] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 20] = "Zo_BaseMeshes.zo_base_desk1";
	ItemNames[o + 21] = "AW Ammo Box";
	ItemValueA[o + 21] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 21] = "AW7Mesh.AMN.Box";
	ItemNames[o + 22] = "Supply Package";
	ItemValueA[o + 22] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 22] = "stuff.stuff1.Package";
	ItemNames[o + 23] = "Floodlight";
	ItemValueA[o + 23] = "FPSGame.MoveableStaticMeshActor";
	ItemValueB[o + 23] = "Zo_Generic.zo_generic_floodlight_stand";
	ItemNames[o + 24] = "Alarm Siren";
	ItemValueA[o + 24] = "MilRP.MilRPSiren";
	ItemNames[o + 25] = "DEFCON Control Console";
	ItemValueA[o + 25] = "MilRP.MilRPDEFCONConsole";
	ItemNames[o + 26] = "Faction Capture Flag";
	ItemValueA[o + 26] = "MilRP.MilRPCapturePoint";
	ItemsPerTab[2] = 27;

	// NPCs / Armies tab: live Pawn/AI classes from the base game
	o = 3 * MAX_ROWS;
	ItemNames[o] = "Military Soldier";
	ItemValueA[o] = "AWPawns.AWMilitary";
	ItemNames[o + 1] = "ATF Agent";
	ItemValueA[o + 1] = "BasePeople.ATFAgent";
	ItemNames[o + 2] = "K9 Unit";
	ItemValueA[o + 2] = "AWPawns.AWDogPawn";
	ItemNames[o + 3] = "RWS Staff";
	ItemValueA[o + 3] = "AWPawns.AWRWSStaff";
	ItemNames[o + 4] = "RWS Bryan";
	ItemValueA[o + 4] = "AWPawns.AWRWSBryan";
	ItemNames[o + 5] = "RWS MikeJ";
	ItemValueA[o + 5] = "AWPawns.AWRWSMikeJ";
	ItemNames[o + 6] = "RWS Vince";
	ItemValueA[o + 6] = "AWPawns.AWRWSVince";
	ItemNames[o + 7] = "Civilian (Gary)";
	ItemValueA[o + 7] = "AWPawns.AWGary";
	ItemNames[o + 8] = "Scared Civilian";
	ItemValueA[o + 8] = "AWPawns.AWScaredGary";
	ItemNames[o + 9] = "Zombie Charger";
	ItemValueA[o + 9] = "AWPawns.AWZombieCharger";
	ItemNames[o + 10] = "Zombie Spitter";
	ItemValueA[o + 10] = "AWPawns.AWZombieSpitter";
	ItemNames[o + 11] = "Mad Cow";
	ItemValueA[o + 11] = "AWPawns.AWCowPawn";
	ItemsPerTab[3] = 12;

	// Skins tab: mesh + skin texture
	o = 4 * MAX_ROWS;
	ItemNames[o] = "Average Dude";
	ItemValueA[o] = "Characters.Avg_M_SS_Pants";
	ItemValueB[o] = "ChameleonSkins.Dude";
	ItemNames[o + 1] = "Fat Dude";
	ItemValueA[o + 1] = "Characters.Fat_M_SS_Pants";
	ItemValueB[o + 1] = "ChameleonSkins.Fat";
	ItemNames[o + 2] = "Female";
	ItemValueA[o + 2] = "Characters.Fem_LS_Pants";
	ItemValueB[o + 2] = "ChameleonSkins.Female";
	ItemsPerTab[4] = 3;
}

event NotifyLevelChange()
{
	if (RPO != None)
		RPO.ActiveSpawnMenu = None;
	Master.RemoveInteraction(self);
}

simulated function Draw(Canvas C)
{
	local int i, Count;
	local float TY, IY;
	local bool bHover;
	local float MX, MY;
	local float WinX, WinY, WinW, WinH, BorderW;
	local float TitleRowH, ToolbarH, FootY, ToolbarY, ContentTop, ContentBottom;
	local float SepY;

	if (RPO == None)
	{
		Master.RemoveInteraction(self);
		return;
	}

	MX = MouseX;
	MY = MouseY;
	Pad = 8.0;
	BorderW = 2.0;

	// --- Centered window frame -----------------------------------------
	WinW = 0.86 * C.ClipX;
	WinH = 0.86 * C.ClipY;
	WinX = (C.ClipX - WinW) * 0.5;
	WinY = (C.ClipY - WinH) * 0.5;

	TitleRowH = 34.0;
	ToolbarH = 34.0;

	// Vertical bands: title row, item area, footer, admin toolbar.
	ContentTop = WinY + Pad + TitleRowH + Pad;
	ToolbarY = WinY + WinH - Pad - ToolbarH;
	FootY = ToolbarY - Pad - 22.0;
	ContentBottom = FootY - Pad;

	// Row height adapts so the full 27-row Props tab always fits inside
	// the item band at any resolution.
	RowH = FMin(28.0, (ContentBottom - ContentTop) / float(MAX_ROWS));

	// Charcoal window panel
	C.SetPos(WinX, WinY);
	C.Style = 5;
	C.DrawColor = C.MakeColor(24, 24, 28, 225);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW, WinH);

	// Thin solid border frame
	C.DrawColor = C.MakeColor(95, 95, 110, 255);
	C.SetPos(WinX, WinY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW, BorderW);
	C.SetPos(WinX, WinY + WinH - BorderW);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW, BorderW);
	C.SetPos(WinX, WinY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', BorderW, WinH);
	C.SetPos(WinX + WinW - BorderW, WinY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', BorderW, WinH);

	// Header band behind the title row: dark steel bar inset inside the
	// border frame, with an admin-violet accent stripe on the left edge.
	SepY = WinY + Pad + TitleRowH + Pad * 0.5;
	C.DrawColor = C.MakeColor(34, 38, 46, 245);
	C.SetPos(WinX + BorderW, WinY + BorderW);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW - BorderW * 2.0, SepY - WinY - BorderW);
	C.DrawColor = C.MakeColor(170, 110, 235, 255);
	C.SetPos(WinX + BorderW, WinY + BorderW);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 4.0, SepY - WinY - BorderW);

	// Title (left side of the header row, clear of the accent stripe)
	C.SetPos(WinX + Pad + 6.0, WinY + Pad + 4.0);
	C.DrawColor = C.MakeColor(230, 230, 235, 255);
	C.DrawText("MilRP Admin Spawn Menu", false);

	// [Mode] toggle: right side of the header row, drawn as a bounded,
	// bordered button so its label can never bleed outside the window.
	ModeW = 0.24 * WinW;
	ModeH = TitleRowH - 8.0;
	ModeX = WinX + WinW - Pad - ModeW;
	ModeY = WinY + Pad + 4.0;
	if (MouseX >= ModeX && MouseX <= ModeX + ModeW && MouseY >= ModeY && MouseY <= ModeY + ModeH)
		C.DrawColor = C.MakeColor(30, 90, 160, 235);
	else
		C.DrawColor = C.MakeColor(45, 45, 55, 235);
	C.SetPos(ModeX, ModeY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ModeW, ModeH);
	C.DrawColor = C.MakeColor(110, 130, 170, 255);
	C.SetPos(ModeX, ModeY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ModeW, 1.0);
	C.SetPos(ModeX, ModeY + ModeH - 1.0);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ModeW, 1.0);
	C.SetPos(ModeX, ModeY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ModeH);
	C.SetPos(ModeX + ModeW - 1.0, ModeY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ModeH);
	C.DrawColor = C.MakeColor(200, 220, 255, 255);
	C.SetPos(ModeX + Pad, ModeY + 3.0);
	if (bGiveToSelf)
		C.DrawText("[Mode: Give to Self]", false);
	else
		C.DrawText("[Mode: Spawn in World]", false);

	// Header separator line under the title row
	C.DrawColor = C.MakeColor(70, 70, 85, 255);
	C.SetPos(WinX, SepY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW, 1.0);

	// --- Columns ---------------------------------------------------------
	// Tabs: left column; item list: right column with a doubled gutter so
	// the two columns never crowd each other.
	TabX = WinX + Pad;
	TabY = ContentTop;
	TabW = 0.20 * WinW;
	GridX = TabX + TabW + Pad * 2.0;
	GridY = ContentTop;
	GridW = WinX + WinW - Pad - GridX;

	// Tabs (left column): active tab gets a highlight bar + violet accent
	// stripe, hovered tabs get a subtle fill.
	for (i = 0; i < NUM_TABS; i++)
	{
		TY = TabY + (i * RowH);
		bHover = (MX >= TabX && MX <= TabX + TabW && MY >= TY && MY <= TY + RowH);
		if (i == ActiveTab)
		{
			C.DrawColor = C.MakeColor(48, 52, 72, 230);
			C.SetPos(TabX, TY);
			C.DrawRect(Texture'Engine.WhiteSquareTexture', TabW, RowH);
			C.DrawColor = C.MakeColor(170, 110, 235, 255);
			C.SetPos(TabX, TY);
			C.DrawRect(Texture'Engine.WhiteSquareTexture', 3.0, RowH);
		}
		else if (bHover)
		{
			C.DrawColor = C.MakeColor(38, 42, 58, 210);
			C.SetPos(TabX, TY);
			C.DrawRect(Texture'Engine.WhiteSquareTexture', TabW, RowH);
		}
		if (i == ActiveTab)
			C.DrawColor = C.MakeColor(0, 255, 0, 220);
		else if (bHover)
			C.DrawColor = C.MakeColor(200, 220, 200, 255);
		else
			C.DrawColor = C.MakeColor(120, 120, 130, 255);
		C.SetPos(TabX + Pad, TY);
		C.DrawText(TabLabels[i], false);
	}

	// Vertical divider between the tab column and the item grid.
	C.DrawColor = C.MakeColor(70, 70, 85, 200);
	C.SetPos(GridX - Pad, ContentTop);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ContentBottom - ContentTop);

	// Item grid (right column): hovered/selected rows get a highlight bar
	// so the current pick is always visible at a glance.
	HoveredIndex = -1;
	Count = ItemsPerTab[ActiveTab];
	for (i = 0; i < Count; i++)
	{
		IY = GridY + (i * RowH);
		bHover = (MX >= GridX && MX <= GridX + GridW && MY >= IY && MY <= IY + RowH);
		if (ActiveTab * MAX_ROWS + i == SelectedIndex)
		{
			C.DrawColor = C.MakeColor(50, 60, 95, 235);
			C.SetPos(GridX - Pad * 0.5, IY);
			C.DrawRect(Texture'Engine.WhiteSquareTexture', GridW + Pad, RowH);
			C.DrawColor = C.MakeColor(170, 110, 235, 255);
			C.SetPos(GridX - Pad * 0.5, IY);
			C.DrawRect(Texture'Engine.WhiteSquareTexture', 3.0, RowH);
		}
		else if (bHover)
		{
			C.DrawColor = C.MakeColor(40, 48, 75, 210);
			C.SetPos(GridX - Pad * 0.5, IY);
			C.DrawRect(Texture'Engine.WhiteSquareTexture', GridW + Pad, RowH);
		}
		if (bHover)
		{
			HoveredIndex = i;
			C.DrawColor = C.MakeColor(230, 235, 255, 255);
		}
		else if (ActiveTab * MAX_ROWS + i == SelectedIndex)
			C.DrawColor = C.MakeColor(255, 215, 100, 255);
		else
			C.DrawColor = C.MakeColor(200, 200, 200, 255);
		C.SetPos(GridX + Pad * 0.5, IY);
		C.DrawText(ItemNames[ActiveTab * MAX_ROWS + i], false);
	}

	// Selected / hovered item description footer, directly above the toolbar
	if (HoveredIndex >= 0)
		SelectedItemName = ItemNames[ActiveTab * MAX_ROWS + HoveredIndex];
	else if (SelectedIndex >= 0 && ActiveTab == (SelectedIndex / MAX_ROWS))
		SelectedItemName = ItemNames[SelectedIndex];
	if (SelectedItemName == "")
		SelectedItemName = "No item selected";

	C.SetPos(GridX, FootY);
	C.DrawColor = C.MakeColor(255, 255, 0, 255);
	C.DrawText("Selected: " $ SelectedItemName, false);

	// --- Administrative Tools toolbar (bottom edge of the window) --------
	// Sunken toolbar band behind the buttons, then a separator rule.
	SepY = ToolbarY - Pad * 0.5;
	C.DrawColor = C.MakeColor(30, 30, 38, 240);
	C.SetPos(WinX + BorderW, SepY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW - BorderW * 2.0, WinY + WinH - BorderW - SepY);
	C.DrawColor = C.MakeColor(70, 70, 85, 255);
	C.SetPos(WinX, SepY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', WinW, 1.0);

	// [EMERGENCY RESET MENU STATES] - left side of the toolbar
	ResetW = 0.32 * WinW;
	ResetH = ToolbarH - 6.0;
	ResetX = WinX + Pad;
	ResetY = ToolbarY + 3.0;
	if (MouseX >= ResetX && MouseX <= ResetX + ResetW && MouseY >= ResetY && MouseY <= ResetY + ResetH)
		C.DrawColor = C.MakeColor(255, 60, 60, 255);
	else
		C.DrawColor = C.MakeColor(200, 40, 40, 255);
	C.SetPos(ResetX, ResetY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ResetW, ResetH);
	C.DrawColor = C.MakeColor(255, 140, 140, 255);
	C.SetPos(ResetX, ResetY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ResetW, 1.0);
	C.SetPos(ResetX, ResetY + ResetH - 1.0);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ResetW, 1.0);
	C.SetPos(ResetX, ResetY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ResetH);
	C.SetPos(ResetX + ResetW - 1.0, ResetY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ResetH);
	C.DrawColor = C.MakeColor(255, 235, 235, 255);
	C.SetPos(ResetX + Pad, ResetY + 4.0);
	C.DrawText("[EMERGENCY RESET MENU STATES]", false);

	// [Clear Sandbox] - directly right of the reset button
	ClearW = 0.20 * WinW;
	ClearH = ToolbarH - 6.0;
	ClearX = ResetX + ResetW + Pad;
	ClearY = ToolbarY + 3.0;
	if (MouseX >= ClearX && MouseX <= ClearX + ClearW && MouseY >= ClearY && MouseY <= ClearY + ClearH)
		C.DrawColor = C.MakeColor(255, 80, 80, 235);
	else
		C.DrawColor = C.MakeColor(150, 40, 40, 235);
	C.SetPos(ClearX, ClearY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ClearW, ClearH);
	C.DrawColor = C.MakeColor(255, 140, 140, 255);
	C.SetPos(ClearX, ClearY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ClearW, 1.0);
	C.SetPos(ClearX, ClearY + ClearH - 1.0);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', ClearW, 1.0);
	C.SetPos(ClearX, ClearY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ClearH);
	C.SetPos(ClearX + ClearW - 1.0, ClearY);
	C.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, ClearH);
	C.DrawColor = C.MakeColor(255, 235, 235, 255);
	C.SetPos(ClearX + Pad, ClearY + 4.0);
	C.DrawText("[Clear Sandbox]", false);

	// Close hint, right-aligned inside the toolbar
	C.DrawColor = C.MakeColor(140, 140, 150, 255);
	C.SetPos(ClearX + ClearW + Pad * 2.0, ClearY + 4.0);
	C.DrawText("Right-click / Esc to close", false);

	// Mouse cursor
	C.SetPos(MX, MY);
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
				RPO.ActiveSpawnMenu = None;
			Master.RemoveInteraction(self);
			return true;
		}
	}
	return false;
}

function ProcessClick()
{
	local int i, Count;
	local float TY, IY;

	if (RPO == None)
		return;

	// Emergency reset button (checked before the mode toggle, whose hitbox
	// spans the whole top row).
	if (MouseX >= ResetX && MouseX <= ResetX + ResetW && MouseY >= ResetY && MouseY <= ResetY + ResetH)
	{
		RPO.ResetMenuState();
		return;
	}

	// Mode toggle
	if (MouseX >= ModeX && MouseX <= ModeX + ModeW && MouseY >= ModeY && MouseY <= ModeY + ModeH)
	{
		bGiveToSelf = !bGiveToSelf;
		return;
	}

	// Clear Sandbox button
	if (MouseX >= ClearX && MouseX <= ClearX + ClearW && MouseY >= ClearY && MouseY <= ClearY + ClearH)
	{
		RPO.ServerClearProps();
		return;
	}

	// Tab selection
	for (i = 0; i < NUM_TABS; i++)
	{
		TY = TabY + (i * RowH);
		if (MouseX >= TabX && MouseX <= TabX + TabW && MouseY >= TY && MouseY <= TY + RowH)
			ActiveTab = i;
	}

	// Item selection
	Count = ItemsPerTab[ActiveTab];
	for (i = 0; i < Count; i++)
	{
		IY = GridY + (i * RowH);
		if (MouseX >= GridX && MouseX <= GridX + GridW && MouseY >= IY && MouseY <= IY + RowH)
		{
			SelectedIndex = ActiveTab * MAX_ROWS + i;
			SelectedItemName = ItemNames[SelectedIndex];
			switch (ActiveTab)
			{
			case 0:		// Weapons
				if (bGiveToSelf)
					RPO.ServerSpawnWeapon(ItemValueA[SelectedIndex]);
				else
					RPO.ServerSpawnWeaponPickup(ItemValueA[SelectedIndex]);
				break;
			case 1:		// Vehicles / Deployables
			case 2:		// Props / Furniture
				RPO.ServerSpawnProp(ItemValueA[SelectedIndex], ItemValueB[SelectedIndex]);
				break;
			case 3:		// NPCs / Armies
				RPO.ServerSpawnProp(ItemValueA[SelectedIndex], "");
				break;
			case 4:		// Skins
				RPO.ServerSetSkin(ItemValueA[SelectedIndex], ItemValueB[SelectedIndex]);
				break;
			}
		}
	}
}
