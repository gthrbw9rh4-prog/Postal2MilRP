///////////////////////////////////////////////////////////////////////////////
// MilRPCapturePoint.uc
//
// Placeable faction territory zone ("Checkpoint Alpha", "North Bunker").
// Extends MilRPInteractPoint so it registers into MilRPWorld.Points (F2 spawn
// menu and [MilRP.MilRPWorld] Placeables both work) and inherits the [E]
// prompt plumbing - pressing USE reports zone status instead of a menu.
//
// Capture is proximity-based: a 1 Hz server Timer() counts on-duty faction
// soldiers inside CaptureRadius. Tug-of-war rules:
//   * exactly one faction inside  -> progress toward that faction
//   * owners inside their own zone -> enemy progress erodes
//   * multiple factions inside    -> contested, progress holds
//   * empty zone                  -> progress decays
// At 100% the zone flips owner, a radio fanfare plays, and BroadcastRP
// announces the capture server-wide. Holding a zone pays PassivePaycheck to
// every member of the owning faction each paycheck interval (see
// MilRPGameInfo.PayEveryone -> TerritoryBonusFor).
///////////////////////////////////////////////////////////////////////////////
class MilRPCapturePoint extends MilRPInteractPoint
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
var config string	ZoneName;			// display name (overridden by Placeables Extra)
var config byte		CurrentOwnerID;		// owning faction index; 255 = neutral
var config int		PassivePaycheck;	// wallet bonus per paycheck tick for holders
var config float	CaptureRadius;		// zone radius in UU (also sets collision)
var config int		CaptureRate;		// capture % gained per second
var config int		DecayRate;			// capture % lost per second when empty/overrun
var config string	SirenFanfareClass;	// fanfare played at the flag on capture


///////////////////////////////////////////////////////////////////////////////
// REPLICATED STATE (HUD meter + ownership)
///////////////////////////////////////////////////////////////////////////////
var byte			CaptureProgress;	// 0..100 toward CapturingFactionID
var byte			CapturingFactionID;	// faction currently progressing, 255 = none


///////////////////////////////////////////////////////////////////////////////
// SERVER RUNTIME
///////////////////////////////////////////////////////////////////////////////
var sound			CaptureSound;


replication
{
	reliable if ( bNetInitial && Role == ROLE_Authority )
		ZoneName, CaptureRadius;
	reliable if ( bNetDirty && Role == ROLE_Authority )
		CurrentOwnerID, CaptureProgress, CapturingFactionID;
}


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	// Per-placement zone names ride in the PlacementDef.Extra string that
	// MilRPWorld.InitPlacements writes into ExtraConfig.
	if (ExtraConfig != "")
		ZoneName = ExtraConfig;

	UseRadius = CaptureRadius;
	Super.PostBeginPlay();
	SetCollisionSize(CaptureRadius, CollisionHeight);

	if (PointLabel == "" || PointLabel == "Press USE to interact")
		PointLabel = ZoneName $ " - stand inside to capture";
	if (MenuTitle == "" || MenuTitle == "Interact")
		MenuTitle = ZoneName;

	if (SirenFanfareClass != "")
		CaptureSound = sound(DynamicLoadObject(SirenFanfareClass, class'Sound', true));

	// Only the authority advances the tug-of-war clock; clients read the
	// replicated progress fields for their HUD meter.
	if (Role == ROLE_Authority)
		SetTimer(1.0, true);
	NetUpdateFrequency = 2.0;
}


///////////////////////////////////////////////////////////////////////////////
// 1 Hz CAPTURE LOOP (authority only)
///////////////////////////////////////////////////////////////////////////////
function Timer()
{
	local MilRPGameInfo			Game;
	local Controller			C;
	local MilRPPlayerReplicationInfo PRI;
	local array<int>			Occupants;
	local int					i, NumFactions, OccupiedCount, OccupiedFaction;

	Game = MilRPGameInfo(Level.Game);
	if (Game == None)
		return;
	NumFactions = Game.Factions.Length;
	if (NumFactions <= 0)
		return;
	Occupants.Length = NumFactions;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (!Game.IsRPParticipant(C))
			continue;
		PRI = Game.GetRPPRI(C);
		if (PRI == None || !PRI.bRoleplayReady || !PRI.bOnDuty || !PRI.HasFaction())
			continue;
		if (C.Pawn == None || C.Pawn.Health <= 0)
			continue;
		if (VSize(C.Pawn.Location - Location) > CaptureRadius)
			continue;
		Occupants[PRI.FactionID]++;
	}

	OccupiedCount = 0;
	OccupiedFaction = 255;
	for (i = 0; i < NumFactions; i++)
		if (Occupants[i] > 0)
		{
			OccupiedCount++;
			OccupiedFaction = i;
		}

	if (OccupiedCount > 1)
		return;	// contested: progress holds

	if (OccupiedCount == 0)
	{
		// Empty zone: progress decays toward zero.
		if (CaptureProgress > 0)
			SetProgress(Max(0, CaptureProgress - DecayRate), CapturingFactionID);
		if (CaptureProgress == 0 && CapturingFactionID != 255)
			SetProgress(0, 255);
		return;
	}

	if (OccupiedFaction == CurrentOwnerID)
	{
		// Owners holding their own flag erode any enemy progress.
		if (CaptureProgress > 0)
			SetProgress(Max(0, CaptureProgress - DecayRate), CapturingFactionID);
		if (CaptureProgress == 0 && CapturingFactionID != 255)
			SetProgress(0, 255);
		return;
	}

	if (OccupiedFaction == CapturingFactionID)
	{
		if (CaptureProgress + CaptureRate >= 100)
		{
			DoCapture(OccupiedFaction, Game);
			return;
		}
		SetProgress(CaptureProgress + CaptureRate, CapturingFactionID);
		return;
	}

	// A different faction is standing on someone else's progress: it must
	// erode to zero before their own progress can begin.
	if (CaptureProgress > 0)
	{
		SetProgress(Max(0, CaptureProgress - CaptureRate), CapturingFactionID);
		return;
	}
	SetProgress(CaptureRate, OccupiedFaction);
}


///////////////////////////////////////////////////////////////////////////////
// CAPTURE COMPLETION
///////////////////////////////////////////////////////////////////////////////
function DoCapture(int NewOwner, MilRPGameInfo Game)
{
	CurrentOwnerID = byte(NewOwner);
	CapturingFactionID = 255;
	CaptureProgress = 0;

	Game.BroadcastRP("[Territory] The " $ Game.Factions[NewOwner].Name
		$ " have captured " $ ZoneName $ "!");

	if (CaptureSound != None)
		PlaySound(CaptureSound, SLOT_Interact, 4.0, false, CaptureRadius * 6.0, 1.0, false);

	if (World != None)
		World.Logf("ZONE", ZoneName $ " captured by faction " $ NewOwner);
}


///////////////////////////////////////////////////////////////////////////////
// REPLICATION HELPERS
///////////////////////////////////////////////////////////////////////////////
function SetProgress(int NewProgress, int NewFaction)
{
	if (CaptureProgress != byte(NewProgress) || CapturingFactionID != byte(NewFaction))
	{
		CaptureProgress = byte(NewProgress);
		CapturingFactionID = byte(NewFaction);
	}
}


///////////////////////////////////////////////////////////////////////////////
// INTERACTION - pressing USE reports zone status (no menu grid)
///////////////////////////////////////////////////////////////////////////////
function OpenMenu(MilRPPlayer RPO)
{
	local string OwnerName, Line;
	local MilRPGameInfo Game;

	Game = MilRPGameInfo(Level.Game);
	if (Game != None && CurrentOwnerID != 255 && CurrentOwnerID < Game.Factions.Length)
		OwnerName = Game.Factions[CurrentOwnerID].Name;
	else
		OwnerName = "Neutral";

	Line = ZoneName $ " - held by " $ OwnerName;
	if (CapturingFactionID != 255 && Game != None && CapturingFactionID < Game.Factions.Length)
		Line = Line $ " (" $ Game.Factions[CapturingFactionID].Name $ " capturing: " $ CaptureProgress $ "%)";
	RPO.ClientRPNotify(Line);
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	ZoneName="Checkpoint"
	CurrentOwnerID=255
	PassivePaycheck=50
	CaptureRadius=250.000000
	CaptureRate=5
	DecayRate=2
	SirenFanfareClass="AmbientSounds.radioPolice"
	CapturingFactionID=255
	bOffDutyOk=true
	// Flagpole silhouette: a plain pole admins can reskin with the spawn
	// menu's mesh column or swap for any verified static mesh.
	DrawType=DT_StaticMesh
	StaticMesh=StaticMesh'Zo_BaseMeshes.zo_base_lightpole'
}
