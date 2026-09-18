///////////////////////////////////////////////////////////////////////////////
// MilRPSiren.uc
//
// Base alarm siren / loudspeaker horn. Responds to the global DEFCON alert
// level pushed by MilRPWorld.SetAlertLevel:
//   AlertLevel <= 2  (DEFCON 3 / Normal)   -> silent
//   AlertLevel == 3  (DEFCON 2 / Elevated) -> looping military radio alert tone
//   AlertLevel >= 4  (DEFCON 1 / Lockdown) -> loud looping base klaxon
//
// Spawned by MilRPWorld.SpawnSirens (config) or via the F2 Props tab - spawned
// sirens are registered into MilRPWorld.Sirens by MilRPPlayer.ServerSpawnProp
// so they join the same broadcast.
///////////////////////////////////////////////////////////////////////////////
class MilRPSiren extends AmbientSound
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
var config string		KlaxonSoundClass;	// DEFCON 1 / lockdown klaxon loop
var config string		AlertToneClass;		// DEFCON 2 / elevated radio tone loop
var config float		KlaxonRadius;		// klaxon audible range
var config float		AlertToneRadius;	// radio tone audible range


///////////////////////////////////////////////////////////////////////////////
// RUNTIME
///////////////////////////////////////////////////////////////////////////////
var sound				KlaxonSound;
var sound				AlertTone;
var byte				CurrentLevel;


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	Super.PostBeginPlay();

	SoundRadius = KlaxonRadius;
	SoundVolume = 200;
	SoundPitch = 32;

	// Load the config defaults so F2-spawned sirens work without any
	// MilRPWorld wiring.
	if (KlaxonSound == None && KlaxonSoundClass != "")
		SetSoundClass(KlaxonSoundClass);
	if (AlertTone == None && AlertToneClass != "")
		SetAlertToneClass(AlertToneClass);
}


///////////////////////////////////////////////////////////////////////////////
// SOUND MANAGEMENT
///////////////////////////////////////////////////////////////////////////////
// Klaxon channel (kept under the old name so MilRPWorld.SirenSoundClass maps
// straight onto it).
function SetSoundClass(string ClassName)
{
	KlaxonSoundClass = ClassName;
	KlaxonSound = None;

	if (ClassName != "")
		KlaxonSound = Sound(DynamicLoadObject(ClassName, class'Sound'));

	if (KlaxonSound == None && ClassName != "")
		warn("MilRPSiren: cannot load klaxon sound " $ ClassName);
}

function SetAlertToneClass(string ClassName)
{
	AlertToneClass = ClassName;
	AlertTone = None;

	if (ClassName != "")
		AlertTone = Sound(DynamicLoadObject(ClassName, class'Sound'));

	if (AlertTone == None && ClassName != "")
		warn("MilRPSiren: cannot load alert tone " $ ClassName);
}

function SetAlertLevel(byte NewLevel)
{
	CurrentLevel = NewLevel;

	if (NewLevel >= 4 && KlaxonSound != None)
	{
		// DEFCON 1 / lockdown - full-volume looping klaxon.
		AmbientSound = KlaxonSound;
		SoundVolume = 230;
		SoundRadius = KlaxonRadius;
	}
	else if (NewLevel >= 3 && AlertTone != None)
	{
		// DEFCON 2 / elevated alert - lower radio alert tone loop.
		AmbientSound = AlertTone;
		SoundVolume = 140;
		SoundRadius = AlertToneRadius;
	}
	else
	{
		// DEFCON 3 / normal - all alarms off.
		AmbientSound = None;
	}
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	// Verified looping emergency tracks pulled from the installed .uax
	// packages (name tables scanned on disk):
	//   jail.fireAlarm                - loud looping fire-alarm klaxon
	//   AmbientSounds.PoliceSiren2    - elevated alert siren loop
	// Both live in packages shipped with POSTAL2Complete AND POSTAL2Editor,
	// so listen-server and dedicated tests resolve them identically.
	KlaxonSoundClass="jail.fireAlarm"
	AlertToneClass="AmbientSounds.PoliceSiren2"
	KlaxonRadius=6000.000000
	AlertToneRadius=4000.000000

	bHidden=false
	bStatic=false
	RemoteRole=ROLE_SimulatedProxy
	bAlwaysRelevant=true
	DrawType=DT_StaticMesh
	StaticMesh=StaticMesh'Zo_Generic.zo_generic_floodlight_head'
	// Solid prop body so F2-spawned sirens don't float or ghost through walls.
	bCollideActors=true
	bBlockActors=true
	bBlockPlayers=true
	CollisionRadius=20.000000
	CollisionHeight=40.000000
}
