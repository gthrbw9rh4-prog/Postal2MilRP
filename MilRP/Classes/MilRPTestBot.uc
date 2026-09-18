///////////////////////////////////////////////////////////////////////////////
// MilRPTestBot.uc
//
// Headless stress-test controller. Does not render or possess a pawn; it exists
// to exercise the GameInfo record, economy, and radio systems with synthetic
// controllers on a dedicated server.
///////////////////////////////////////////////////////////////////////////////
class MilRPTestBot extends AIController
	config(MilRP);


var float			NextAction;


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	local MilRPGameInfo Game;

	Super.PostBeginPlay();

	bIsPlayer = true;
	NetUpdateFrequency = 0.1;

	Game = MilRPGameInfo(Level.Game);
	if (Game != None)
		Game.RegisterTestBot(self);
}


///////////////////////////////////////////////////////////////////////////////
// LIFE CYCLE
///////////////////////////////////////////////////////////////////////////////
function Tick(float Delta)
{
	Super.Tick(Delta);

	if (Level.TimeSeconds < NextAction)
		return;
	NextAction = Level.TimeSeconds + 2.0 + FRand() * 3.0;

	if (MilRPGameInfo(Level.Game) != None)
		MilRPGameInfo(Level.Game).RunBotAction(self);
}


///////////////////////////////////////////////////////////////////////////////
// CLEANUP
///////////////////////////////////////////////////////////////////////////////
function Destroyed()
{
	local MilRPGameInfo Game;

	Game = MilRPGameInfo(Level.Game);
	if (Game != None)
		Game.UnregisterTestBot(self);

	Super.Destroyed();
}


defaultproperties
{
	PlayerReplicationInfoClass=class'MilRP.MilRPPlayerReplicationInfo'
	bIsPlayer=true
	bCanDoSpecial=false
}