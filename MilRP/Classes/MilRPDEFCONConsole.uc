///////////////////////////////////////////////////////////////////////////////
// MilRPDEFCONConsole.uc
//
// Physical DEFCON control desk. Pressing USE on the console opens the
// mouse-driven MilRPDEFCONInteraction board; the three threat buttons route
// back through MilRPPlayer.ServerUpdateDEFCON -> MilRPGameInfo.SetAlertLevel
// -> MilRPWorld.SetAlertLevel, which pushes the new level to every
// registered MilRPSiren on the map.
//
// Access is gated to Admin clearance (EUserGroup Group_Admin = 2).
//
// Placement:
//   [MilRP.MilRPWorld] Placeables -> ClassName="MilRP.MilRPDEFCONConsole"
//   or F2 Props tab -> "DEFCON Control Console".
///////////////////////////////////////////////////////////////////////////////
class MilRPDEFCONConsole extends MilRPInteractPoint
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
var() config string	DeskMeshPath;	// optional per-instance mesh override
var() config int	RequiredGroup;	// EUserGroup level needed (2 = Admin)


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	Super.PostBeginPlay();

	// Base PostBeginPlay sizes the cylinder to UseRadius for touch
	// detection; 'E' routes through MilRPPlayer.ServerUse's look-at trace,
	// so shrink the cylinder to the solid desk body footprint instead.
	SetCollisionSize(60.0, CollisionHeight);

	if (DeskMeshPath != "")
		SetStaticMesh(StaticMesh(DynamicLoadObject(DeskMeshPath, class'StaticMesh')));
}


///////////////////////////////////////////////////////////////////////////////
// USETRIGGER HOOK - opens the DEFCON board
///////////////////////////////////////////////////////////////////////////////
function UsedBy(Pawn user)
{
	local MilRPPlayer RPO;
	local MilRPGameInfo Game;

	if (user == None || user.Controller == None)
		return;

	RPO = MilRPPlayer(user.Controller);
	if (RPO == None)
	{
		Super.UsedBy(user);
		return;
	}

	if (Level.TimeSeconds - LastUseTime < ReUseDelay)
	{
		RPO.ClientRPNotify("Please wait before using this again.");
		return;
	}

	Game = GetGame();
	if (Game == None || !Game.CheckPermission(RPO, RequiredGroup))
	{
		RPO.ClientRPNotify("Access Denied: DEFCON control requires Admin clearance.");
		return;
	}

	RPO.ActiveInteractPoint = self;
	RPO.ClientOpenDEFCONMenu();
	LastUseTime = Level.TimeSeconds;
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	RequiredGroup=2
	PointLabel="Press USE for DEFCON console"
	MenuTitle="DEFCON Control"
	bOffDutyOk=true

	DrawType=DT_StaticMesh
	StaticMesh=StaticMesh'Zo_BaseMeshes.zo_base_desk1'
	// Solid body: 'E' reaches UsedBy through MilRPPlayer.ServerUse's look-at
	// trace (bBlockZeroExtentTraces catches the crosshair line).
	bCollideActors=true
	bBlockActors=true
	bBlockPlayers=true
	bBlockZeroExtentTraces=true
	bBlockNonZeroExtentTraces=true
	UseRadius=150.000000
	CollisionRadius=60.000000
	CollisionHeight=45.000000
}
