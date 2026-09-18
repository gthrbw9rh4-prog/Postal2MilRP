///////////////////////////////////////////////////////////////////////////////
// MilRPShowcaseRelauncher.uc
//
// One-shot travel helper spawned by MilRPShowcaseGame. Waits for the level
// and gameinfo to finish initializing, then performs a local ServerTravel
// into the configured MilRP map+game so the workshop showcase lands players
// inside the real mod in a single click.
///////////////////////////////////////////////////////////////////////////////
class MilRPShowcaseRelauncher extends Actor;

var string TravelURL;		// destination URL, e.g. "MPDGT-Asylum?Game=MilRP.MilRPGameInfo"
var float  TravelDelay;		// seconds to wait before travelling

// Arm() is called by the showcase game after TravelURL/TravelDelay are set,
// so the timer never fires on stale defaults.
function Arm()
{
	SetTimer(TravelDelay, false);
}

function Timer()
{
	Level.ServerTravel(TravelURL, false);
}

defaultproperties
{
	TravelDelay=0.500000
	TravelURL="MPDGT-Asylum?Game=MilRP.MilRPGameInfo"
	bHidden=true
}
