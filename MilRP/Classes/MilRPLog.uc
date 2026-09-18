///////////////////////////////////////////////////////////////////////////////
// MilRPLog.uc
//
// Thin wrapper around Engine.FileLog. MilRP writes admin actions, economy
// events, and addon messages to a dated text file for server operators.
//
// FileLog native: OpenLog("prefix") creates "prefix.txt".
///////////////////////////////////////////////////////////////////////////////
class MilRPLog extends Info;


var FileLog			Log;
var string			CurrentFile;
var float			FlushInterval;
var float			LastFlush;


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	local string Day;

	Super.PostBeginPlay();
	Log = Spawn(class'FileLog');
	if (Log == None)
	{
		warn("MilRPLog failed to spawn FileLog");
		return;
	}

	Day = Level.Year $ "-" $ Pad(Level.Month) $ "-" $ Pad(Level.Day);
	CurrentFile = "MilRP_" $ Day;
	Log.OpenLog(CurrentFile);
	Logf("SYSTEM", "MilRP logging started - " $ Level.GetLocalURL());
}


///////////////////////////////////////////////////////////////////////////////
// PUBLIC
///////////////////////////////////////////////////////////////////////////////
function Logf(string Category, string Text)
{
	if (Log == None)
		return;

	Log.Logf("[" $ FormatTime() $ "][" $ Category $ "] " $ Text);
}

function LogAdmin(MilRPPlayer Admin, string Action, string Target, string Details)
{
	local string Who;

	Who = "CONSOLE";
	if (Admin != None && Admin.PlayerReplicationInfo != None)
		Who = Admin.PlayerReplicationInfo.PlayerName;
	Logf("ADMIN", Who $ " | " $ Action $ " | " $ Target $ " | " $ Details);
}

function LogEconomy(MilRPPlayer Player, string Action, int Amount, string Reason)
{
	local string Who;

	Who = "?";
	if (Player != None && Player.PlayerReplicationInfo != None)
		Who = Player.PlayerReplicationInfo.PlayerName;
	Logf("ECONOMY", Who $ " | " $ Action $ " | " $ Amount $ " | " $ Reason);
}


///////////////////////////////////////////////////////////////////////////////
// HELPERS
///////////////////////////////////////////////////////////////////////////////
function string Pad(int N)
{
	if (N < 10)
		return "0" $ N;
	return string(N);
}

function string FormatTime()
{
	return Pad(Level.Hour) $ ":" $ Pad(Level.Minute) $ ":" $ Pad(Level.Second);
}


defaultproperties
{
	FlushInterval=5.000000
}