///////////////////////////////////////////////////////////////////////////////
// MilRPShowcaseGame.uc
//
// Workshop launch shim. Registered under MetaClass=P2GameInfoSingle so the
// Steam Workshop item appears as a playable single-player game type instead
// of shipping with the "Manual Install Required" tag.
//
// All this class does is forward the session into the real MilRP game type
// with a local ServerTravel. In a local game the player is the authority,
// so every server-side path runs exactly as it does on a dedicated server:
// the F1 scoreboard, F2 spawn menu, admin board, territory capture flags,
// DEFCON console and sirens all work offline for showcase purposes.
///////////////////////////////////////////////////////////////////////////////
class MilRPShowcaseGame extends P2GameInfoSingle
	config(MilRP);

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
var config string ShowcaseMap;			// map the showcase hops into
var config string ShowcaseGameClass;	// game class to run on that map
var config float  ShowcaseDelay;		// seconds to wait before travelling

// ---------------------------------------------------------------------------
// PostBeginPlay
// Spawn a dedicated helper actor to fire the travel. Doing it on a timer
// from a separate Actor avoids racing the level/gameinfo init sequence and
// keeps us clear of P2GameInfoSingle's state-machine timers.
// ---------------------------------------------------------------------------
function PostBeginPlay()
{
	local MilRPShowcaseRelauncher R;

	Super.PostBeginPlay();

	R = Spawn(class'MilRPShowcaseRelauncher');
	R.TravelURL = ShowcaseMap $ "?Game=" $ ShowcaseGameClass;
	R.TravelDelay = ShowcaseDelay;
	R.Arm();
}

defaultproperties
{
	ShowcaseMap="MPDGT-Asylum"
	ShowcaseGameClass="MilRP.MilRPGameInfo"
	ShowcaseDelay=0.500000
}
