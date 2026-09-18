///////////////////////////////////////////////////////////////////////////////
// MilRPGameInfo.uc
//
// Military Roleplay game type for Postal 2: Share The Pain.
//
// Base class choice: MultiBase.DeathMatch (not TeamGame). DeathMatch owns the
// proven multiplayer plumbing we want to keep - login/PostLogin handshake with
// MpPlayer (bFullyLoggedIn / match intro), PendingMatch -> MatchInProgress
// state machine, respawn handling, roster-constrained pawn classes, GRI setup.
// TeamGame is hard-wired to exactly two teams, which is useless for an N-faction
// RP server, so factions are implemented here on top of the PRI instead and
// PlayerReplicationInfo.Team is left at None.
//
// Everything that ends a deathmatch (frag limit, time limit, max lives) is
// forced off so the server behaves as a persistent world.
//
// Server-authoritative state lives here:
//   * per-player economy records (wallet, rank, faction, RP score, duty time)
//   * paycheck / duty progression loop (1 Hz Timer)
//   * faction assignment + faction/duty loadouts
//   * RDM (random deathmatch) penalties
//
// Everything a client needs to render is pushed through
// MilRPGameReplicationInfo (global tables, broadcast feed) and
// MilRPPlayerReplicationInfo (per-player faction/rank/duty). The wallet is
// pushed owner-only through MilRPPlayer.SetWallet().
///////////////////////////////////////////////////////////////////////////////
class MilRPGameInfo extends DeathMatch
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION - all values live in System\MilRP.ini
// URL overrides: ?StartingCurrency= ?PaycheckInterval= ?EnforceFactions=
//                ?PersistRecords= ?AutoPromote=
///////////////////////////////////////////////////////////////////////////////

// --- Ruleset toggles -------------------------------------------------------
var config bool			bEnforceFactions;			// players without a faction cannot go on duty and spawn with OffDutyLoadout only
var config bool			bAllowFactionSwitch;		// players may change faction after their first pick
var config int			FactionSwitchCooldown;		// seconds between faction changes
var config int			MaxFactionSize;				// 0 = unlimited members per faction
var config int			DutyToggleCooldown;			// seconds between duty on/off toggles
var config byte			DutyChangeMode;				// 0 = swap loadout in place, 1 = respawn on duty change
var config bool			bBlockSameFactionDamage;	// scale damage between members of the same faction
var config float		SameFactionDamageScale;		// 0.0 = no friendly damage, 1.0 = full
var config bool			bOffDutyCannotDamage;		// off-duty players deal zero damage to others
var config bool			bUseFactionSpawns;			// PlayerStart.TeamNumber is treated as a faction id
var config bool			bAllowMatchTimers;			// false = force TimeLimit/GoalScore to 0 (persistent world)
var config string		HostTestName;				// fallback name for local Steam offline tests (default "Player")

// --- Announcements ---------------------------------------------------------
var config bool			bAnnounceDutyChanges;
var config bool			bAnnouncePromotions;
var config bool			bAnnounceFactionJoins;
var config bool			bEchoBroadcastsToChat;		// mirror HUD feed lines into the chat console

// --- Economy ---------------------------------------------------------------
var config int			StartingCurrency;			// wallet for a brand new record
var config int			PaycheckInterval;			// seconds between paychecks
var config int			BasePaycheck;				// paid to a rank-0 player each interval
var config float		RankPaycheckMultiplier;		// paycheck *= 1 + Rank * this
var config float		OnDutyPayMultiplier;		// paycheck *= this while on duty
var config float		OffDutyPayScale;			// paycheck *= this while off duty (0 = no pay off duty)
var config bool			bAllowNegativeWallet;		// fines may push the wallet below zero
var config bool			bPaycheckDirectDeposit;		// true = auto, false = must collect from paymaster
var config int			StartingBank;				// bank account for a new record
var config int			MaxBankBalance;				// 0 = unlimited

// --- Progression -----------------------------------------------------------
var config bool			bAutoPromote;				// promote automatically when RP score crosses a rank threshold
var config int			RPScorePerDutyMinute;		// RP score gained per full minute on duty
var config int			RPScoreLossPerRDM;			// RP score lost for an RDM kill
var config int			FinePerRDM;					// currency lost for an RDM kill
var config int			RankHealthBonus[16];		// extra HealthMax per rank
var config float		RankSpeedMultiplier;		// GroundSpeed *= 1 + Rank * this
var config bool			bPunishOffDutyKills;		// kills by/against off-duty players count as RDM
var config bool			bPunishSameFactionKills;	// kills within a faction count as RDM
var config bool			bPunishCivilianKills;		// kills of non-combatant faction members count as RDM

// --- Persistence -----------------------------------------------------------
var config bool			bPersistPlayerRecords;		// write SavedRecords to MilRP.ini on logout / map change
var config int			MaxSavedRecords;			// oldest records are dropped beyond this

// --- Loadouts (comma separated Inventory class names, e.g. "Inventory.PistolWeapon") --
var config string		OffDutyLoadout;				// given to everyone not on duty (on top of GameBaseEquipment)

// --- Faction table ---------------------------------------------------------
struct FactionDef
{
	var string	Name;			// full display name
	var string	Tag;			// short tag for name plates / chat
	var color	Tint;			// HUD colour
	var bool	bCombatant;		// true = gets DutyLoadout when on duty
	var string	DutyLoadout;	// comma separated inventory classes
	var string	PawnClass;		// optional custom pawn, e.g. "MultiStuff.xMpMilitary"
	var vector	StartLocation;	// admin-set faction spawn point (zero = use map starts)
	var rotator	StartRotation;	// admin-set faction spawn rotation
};
var config array<FactionDef>	Factions;

// --- Rank ladder (index = rank id, must be sorted by MinScore ascending) ----
struct RankDef
{
	var string	Title;
	var int		MinScore;
};
var config array<RankDef>		Ranks;

// --- User group hierarchy (0 = player, 4 = owner) ---
enum EUserGroup
{
	Group_Player,
	Group_Moderator,
	Group_Admin,
	Group_SuperAdmin,
	Group_Owner
};

struct AdminUserDef
{
	var config string	UniqueID;		// primary unique identifier (IP / Steam account hash)
	var config string	StaffIP;		// verification IP address
	var config string	StaffMemo;		// human-readable label / Steam name
	var config int		GroupLevel;		// 0..4 (EUserGroup)
};
var config array<AdminUserDef>	StaffRegistry;

struct BanRecordDef
{
	var config string	BannedID;		// primary unique ID (Steam account hash / signature)
	var config string	BannedIP;		// banned IP address
	var config string	BannedName;		// banned player's last known name
	var config string	Reason;
};
var config array<BanRecordDef>	BanRegistry;

// --- Dev diagnostics ---
var config bool			bMeshProbe;				// run the StaticMesh path probe in PostBeginPlay
var array<string>		MeshProbeList;			// candidate StaticMesh paths (see defaultproperties)

// Localised display names for each group level.
var string			GroupNames[5];

// --- Persisted player records (managed by code, keyed by upper-case name) ---
struct PlayerRecord
{
	var string	Key;
	var int		Wallet;
	var int		Bank;
	var byte	Rank;
	var byte	FactionID;
	var int		RPScore;
	var int		DutySeconds;
	var int		Warnings;
};
var config array<PlayerRecord>	SavedRecords;


///////////////////////////////////////////////////////////////////////////////
// Runtime state (server only)
///////////////////////////////////////////////////////////////////////////////
struct LiveRecord
{
	var int				PlayerID;		// PRI.PlayerID, unique for the session
	var PlayerRecord	Data;
};
var array<LiveRecord>			LiveRecords;

var int							RPClock;				// seconds since the RP world went live
var int							NextPaycheckClock;		// RPClock value of the next paycheck
var MilRPGameReplicationInfo	RPGRI;
var MilRPWorld					RPWorld;
var array<MilRPTestBot>			TestBots;

// Localized strings (MilRP.int)
var localized string			MsgWelcome;				// "%n reported for service"
var localized string			MsgPaycheck;			// "Paycheck: +$%a"
var localized string			MsgNoPaycheck;			// "No paycheck: you are off duty"
var localized string			MsgOnDuty;				// "%n is now ON DUTY"
var localized string			MsgOffDuty;				// "%n is now OFF DUTY"
var localized string			MsgJoinedFaction;		// "%n enlisted with %f"
var localized string			MsgPromoted;			// "%n has been promoted to %r"
var localized string			MsgDemoted;				// "%n has been demoted to %r"
var localized string			MsgRDM;					// "%n was penalised for RDM"
var localized string			MsgFineApplied;			// "Fine applied: -$%a"
var localized string			FailNoFaction;			// "You must join a faction first"
var localized string			FailNonCombatant;		// "Your faction has no duty roster"
var localized string			FailCooldown;			// "Wait %a seconds before doing that again"
var localized string			FailFactionFull;		// "That faction is full"
var localized string			FailNoSwitch;			// "Faction changes are disabled on this server"
var localized string			FailInvalidFaction;		// "Unknown faction"
var localized string			FailNotAdmin;			// "Admin access required"
var localized string			FailFunds;				// "Insufficient funds"
var localized string			MsgPaycheckPending;		// "Paycheck ready: collect $%a"
var localized string			MsgPaycheckCollected;	// "Collected $%a"
var localized string			MsgBankTransfer;		// "Bank: $%a"
var localized string			MsgRadio;				// "[%c] %n: %m"
var localized string			MsgFrozen;				// "%n has been frozen"
var localized string			MsgUnFrozen;			// "%n has been unfrozen"


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
event InitGame(out string Options, out string Error)
{
	local string InOpt;

	Super.InitGame(Options, Error);

	StartingCurrency = GetIntOption(Options, "StartingCurrency", StartingCurrency);
	PaycheckInterval = GetIntOption(Options, "PaycheckInterval", PaycheckInterval);

	InOpt = ParseOption(Options, "EnforceFactions");
	if (InOpt != "")
		bEnforceFactions = bool(InOpt);
	InOpt = ParseOption(Options, "PersistRecords");
	if (InOpt != "")
		bPersistPlayerRecords = bool(InOpt);
	InOpt = ParseOption(Options, "AutoPromote");
	if (InOpt != "")
		bAutoPromote = bool(InOpt);

	ValidateConfig();

	// Persistent world: nothing may end the "match".
	if (!bAllowMatchTimers)
	{
		TimeLimit = 0;
		GoalScore = 0;
		RemainingTime = 0;
	}
	bOverTime = false;
	bGameEnded = false;
	MaxLives = 0;
	bForceRespawn = false;
	bMustJoinBeforeStart = false;
	bTournament = false;
	bPlayersMustBeReady = false;

	// Joiners must become active players immediately, not wait for a match
	// intro, click-to-join overlay, or delayed spawn.
	bDelayedStart = false;
	bRestartLevel = false;
	Default.bRestartLevel = false;
	MatchIntroClassName = "";
	bWaitingToStartMatch = false;

	NextPaycheckClock = PaycheckInterval;

	log("MilRPGameInfo::InitGame : Factions=" $ Factions.Length $ " Ranks=" $ Ranks.Length
		$ " StartingCurrency=" $ StartingCurrency $ " PaycheckInterval=" $ PaycheckInterval
		$ " EnforceFactions=" $ bEnforceFactions $ " Persist=" $ bPersistPlayerRecords);
}

// Clamp config into sane ranges and guarantee at least one faction and one rank
// so the rest of the code never has to special-case an empty table.
function ValidateConfig()
{
	local int i;
	local FactionDef DefFaction;
	local RankDef DefRank;

	PaycheckInterval = Max(10, PaycheckInterval);
	FactionSwitchCooldown = Max(0, FactionSwitchCooldown);
	DutyToggleCooldown = Max(0, DutyToggleCooldown);
	MaxFactionSize = Max(0, MaxFactionSize);
	StartingCurrency = Max(0, StartingCurrency);
	BasePaycheck = Max(0, BasePaycheck);
	RankPaycheckMultiplier = FMax(0.0, RankPaycheckMultiplier);
	OnDutyPayMultiplier = FMax(0.0, OnDutyPayMultiplier);
	OffDutyPayScale = FClamp(OffDutyPayScale, 0.0, 10.0);
	SameFactionDamageScale = FClamp(SameFactionDamageScale, 0.0, 1.0);
	RPScorePerDutyMinute = Max(0, RPScorePerDutyMinute);
	RPScoreLossPerRDM = Max(0, RPScoreLossPerRDM);
	FinePerRDM = Max(0, FinePerRDM);
	MaxSavedRecords = Max(16, MaxSavedRecords);
	StartingBank = Max(0, StartingBank);
	MaxBankBalance = Max(0, MaxBankBalance);
	RankSpeedMultiplier = FMax(0.0, RankSpeedMultiplier);
	if (DutyChangeMode > 1)
		DutyChangeMode = 0;

	if (Factions.Length > 8)
		Factions.Length = 8;
	if (Factions.Length == 0)
	{
		DefFaction.Name = "Civilian";
		DefFaction.Tag = "CIV";
		DefFaction.Tint = class'Canvas'.static.MakeColor(200, 200, 200);
		DefFaction.bCombatant = false;
		DefFaction.DutyLoadout = "";
		Factions[0] = DefFaction;
	}

	if (Ranks.Length > 16)
		Ranks.Length = 16;
	if (Ranks.Length == 0)
	{
		DefRank.Title = "Recruit";
		DefRank.MinScore = 0;
		Ranks[0] = DefRank;
	}
	Ranks[0].MinScore = 0;
	for (i = 1; i < Ranks.Length; i++)
		if (Ranks[i].MinScore < Ranks[i - 1].MinScore)
			Ranks[i].MinScore = Ranks[i - 1].MinScore;
}

function InitGameReplicationInfo()
{
	local int i;

	Super.InitGameReplicationInfo();

	RPGRI = MilRPGameReplicationInfo(GameReplicationInfo);
	if (RPGRI == None)
	{
		warn("MilRPGameInfo requires MilRPGameReplicationInfo, got " $ GameReplicationInfo);
		return;
	}

	RPGRI.ClearTables();
	for (i = 0; i < Factions.Length; i++)
		RPGRI.AddFaction(Factions[i].Name, Factions[i].Tag, Factions[i].Tint, Factions[i].bCombatant);
	for (i = 0; i < Ranks.Length; i++)
		RPGRI.AddRank(Ranks[i].Title, Ranks[i].MinScore);

	RPGRI.PaycheckInterval = PaycheckInterval;
	RPGRI.NextPaycheckTime = NextPaycheckClock;
	RPGRI.bEnforceFactions = bEnforceFactions;
	RPGRI.MaxSlots = MaxPlayers;
	RPGRI.AlertLevel = 0;
	RPGRI.bLockdown = false;
}

function PostBeginPlay()
{
	Super.PostBeginPlay();
	if (RPGRI == None)
		RPGRI = MilRPGameReplicationInfo(GameReplicationInfo);
	if (RPWorld == None)
		RPWorld = Spawn(class'MilRPWorld');
	if (bMeshProbe)
		ProbeStaticMeshes();
}

// Dev diagnostic: enable via [MilRP.MilRPGameInfo] bMeshProbe=true, run a
// listen/dedicated server once, then read ucc.log/Launch.log for results.
function ProbeStaticMeshes()
{
	local int i;

	log("=== MESHPROBE BEGIN ===");
	for (i = 0; i < MeshProbeList.Length; i++)
	{
		if (StaticMesh(DynamicLoadObject(MeshProbeList[i], class'StaticMesh')) != None)
			log("MESHPROBE OK   " $ MeshProbeList[i]);
		else
			log("MESHPROBE FAIL " $ MeshProbeList[i]);
	}
	log("=== MESHPROBE END ===");
}


///////////////////////////////////////////////////////////////////////////////
// MATCH LIFECYCLE - persistent world, never end
///////////////////////////////////////////////////////////////////////////////
function bool CheckEndGame(PlayerReplicationInfo Winner, string Reason)
{
	return false;
}

function CheckScore(PlayerReplicationInfo Scorer)
{
	// no score-based match ending
}

function EndGame(PlayerReplicationInfo Winner, string Reason)
{
	// Never transition to MatchOver / GameEnded.
	bGameEnded = false;
	bOverTime = false;
}

// Never let the engine life-pool check end the match.
function bool CheckMaxLives(PlayerReplicationInfo Scorer)
{
	return false;
}

// Handle pawn death manually without calling Super.Killed() so the parent
// frag-limit / match-end logic is never reached.  Keep the standard
// bookkeeping, then call our own ScoreKill for RP consequences.
function Killed(Controller Killer, Controller Killed, Pawn KilledPawn, class<DamageType> damageType)
{
	if (Killed != None && Killed.bIsPlayer && Killed.PlayerReplicationInfo != None)
	{
		Killed.PlayerReplicationInfo.Deaths += 1.0;
		BroadcastDeathMessage(Killer, Killed, damageType);

		if (Killer == None || Killer == Killed)
		{
			if (Killer != None)
				KillEvent("K", Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, damageType);
			else
				KillEvent("K", None, Killed.PlayerReplicationInfo, damageType);
		}
		else
			KillEvent("K", Killer.PlayerReplicationInfo, Killed.PlayerReplicationInfo, damageType);
	}

	if (KilledPawn != None)
		DiscardInventory(KilledPawn);
	NotifyKilled(Killer, Killed, KilledPawn);

	// RP consequences (RDM warnings/fines, logging, kills) are handled in the
	// existing ScoreKill override and do NOT call Super.ScoreKill().
	if (Killed != None)
		ScoreKill(Killer, Killed);
}


///////////////////////////////////////////////////////////////////////////////
// LOGIN / LOGOUT
///////////////////////////////////////////////////////////////////////////////
event PostLogin(PlayerController NewPlayer, string Options)
{
	local MilRPPlayerReplicationInfo PRI;
	local int Idx;
	local MpPlayer MPP;

	// Mark the player as fully ready and not a spectator *before* the base
	// PostLogin / StartMatch sequence, otherwise the intro/ready checks leave
	// them stuck in a noclip PlayerWaiting state.
	if (NewPlayer != None)
	{
		MPP = MpPlayer(NewPlayer);
		if (MPP != None)
		{
			MPP.bFullyLoggedIn = true;
			MPP.bIntroFinished = true;
		}

		if (NewPlayer.PlayerReplicationInfo != None)
		{
			NewPlayer.PlayerReplicationInfo.bIsSpectator = false;
			NewPlayer.PlayerReplicationInfo.bOnlySpectator = false;
			NewPlayer.PlayerReplicationInfo.bOutOfLives = false;
			NewPlayer.PlayerReplicationInfo.bReadyToPlay = true;
			NewPlayer.PlayerReplicationInfo.NumLives = 0;
		}
	}

	Super.PostLogin(NewPlayer, Options);

	// If base logic still didn't spawn them (e.g. delayed intro), force it now.
	if (NewPlayer != None && NewPlayer.Pawn == None)
		RestartPlayer(NewPlayer);

	if (NewPlayer != None && NewPlayer.Pawn != None)
		NewPlayer.Pawn.SetPhysics(PHYS_Walking);

	PRI = GetRPPRI(NewPlayer);
	if (PRI == None)
	{
		warn("MilRPGameInfo::PostLogin : " $ NewPlayer $ " has no MilRPPlayerReplicationInfo - check PlayerControllerClassName");
		return;
	}

	Idx = AcquireLiveRecord(NewPlayer);
	ApplyRecordToPlayer(NewPlayer, LiveRecords[Idx].Data);
	PRI.bRoleplayReady = true;

	if (MilRPPlayer(NewPlayer) != None)
	{
		MilRPPlayer(NewPlayer).SetWallet(LiveRecords[Idx].Data.Wallet);
		MilRPPlayer(NewPlayer).SetBank(LiveRecords[Idx].Data.Bank);
		MilRPPlayer(NewPlayer).SetPaycheck(0, false);
		// Owner-only replicated staff level, so the client HUD can apply
		// admin display rules (scoreboard wallet column, etc.).
		MilRPPlayer(NewPlayer).GroupLevel = GetGroupLevel(NewPlayer);
	}

	BroadcastRP(FormatMsg(MsgWelcome, PRI.PlayerName));
	Logf("LOGIN", NewPlayer.PlayerReplicationInfo.PlayerName $ " connected");
	if (RPWorld != None)
		RPWorld.FireAddonEvent('OnPlayerLogin', MilRPPlayer(NewPlayer));

	if (MilRPPlayer(NewPlayer) != None)
		MilRPPlayer(NewPlayer).ClientRPNotify(MilRPPlayer(NewPlayer).VoiceChatPrompt);
}

// Ensure no connecting player is marked out-of-lives or a spectator by default.
// The controller may pass through GameInfo.Login which sets bOutOfLives for
// spectators; for a persistent world we always want respawn to be possible.
// Reject banned clients before they download content or spawn a pawn.
event PreLogin(string Options, string Address, out string Error, out string FailCode)
{
	local int i;
	local string IP;

	Super.PreLogin(Options, Address, Error, FailCode);
	if (Error != "")
		return;

	IP = StripPort(Address);
	if (IP == "")
		return;

	for (i = 0; i < BanRegistry.Length; i++)
		if (IP == StripPort(BanRegistry[i].BannedID) || IP == StripPort(BanRegistry[i].BannedIP))
		{
			Error = "You are permanently banned from this server. Reason: " $ BanRegistry[i].Reason;
			return;
		}
}

event PlayerController Login(string Portal, string Options, out string Error)
{
	local PlayerController NewPlayer;
	local int i;

	NewPlayer = Super.Login(Portal, Options, Error);
	if (NewPlayer != None && NewPlayer.PlayerReplicationInfo != None)
	{
		NewPlayer.PlayerReplicationInfo.bOutOfLives = false;
		NewPlayer.PlayerReplicationInfo.bOnlySpectator = false;
		NewPlayer.PlayerReplicationInfo.bIsSpectator = false;
		NewPlayer.PlayerReplicationInfo.NumLives = 0;

		// Triple-layer ban fallback: reject by last known Steam name.
		for (i = 0; i < BanRegistry.Length; i++)
			if (Caps(NewPlayer.PlayerReplicationInfo.PlayerName) == Caps(BanRegistry[i].BannedName))
			{
				Error = "You are permanently banned from this server. Reason: " $ BanRegistry[i].Reason;
				break;
			}
	}
	return NewPlayer;
}

function Logout(Controller Exiting)
{
	if (PlayerController(Exiting) != None)
	{
		CaptureRecordFromPlayer(Exiting);
		if (bPersistPlayerRecords)
			PersistRecord(Exiting);
		ReleaseLiveRecord(Exiting);
		if (Exiting.PlayerReplicationInfo != None)
			Logf("LOGOUT", Exiting.PlayerReplicationInfo.PlayerName $ " disconnected");
		if (RPWorld != None)
			RPWorld.FireAddonEvent('OnPlayerLogout', MilRPPlayer(Exiting));
	}
	Super.Logout(Exiting);
}


///////////////////////////////////////////////////////////////////////////////
// STATE MACHINE - persistent world, never match-over
///////////////////////////////////////////////////////////////////////////////
// Joiners should never be stuck waiting for a match to start.  Start
// immediately once the world is loaded.
auto state PendingMatch
{
	function Timer()
	{
		Global.Timer();
		if (!bGameEnded)
			StartMatch();
	}
}

// Once we leave PendingMatch we stay here and only run the 1 Hz global loop.
// All EndGame(), MaxLives, and time-limit checks are stripped out.
state MatchInProgress
{
	function Timer()
	{
		Global.Timer();

		if (!bFinalStartup)
		{
			bFinalStartup = true;
			PlayStartupMessage();
		}

		// Keep the world clock ticking for the HUD / GRI; do NOT call EndGame,
		// CheckMaxLives, or the auto-respawn loop here.
		ElapsedTime++;
		if (GameReplicationInfo != None)
			GameReplicationInfo.ElapsedTime = ElapsedTime;
	}
}

// If the engine somehow tries to enter MatchOver, immediately leave it.
state MatchOver
{
	function BeginState()
	{
		bGameEnded = false;
		bOverTime = false;
		GotoState('MatchInProgress');
	}

	function Timer()
	{
		bGameEnded = false;
		bOverTime = false;
		GotoState('MatchInProgress');
	}
}


///////////////////////////////////////////////////////////////////////////////
// RECORD MANAGEMENT
///////////////////////////////////////////////////////////////////////////////
function string MakeRecordKey(string PlayerName)
{
	local string S;

	S = Caps(PlayerName);
	ReplaceText(S, " ", "_");
	return S;
}

function int FindLiveRecord(Controller C)
{
	local int i;

	if (C == None || C.PlayerReplicationInfo == None)
		return -1;
	for (i = 0; i < LiveRecords.Length; i++)
		if (LiveRecords[i].PlayerID == C.PlayerReplicationInfo.PlayerID)
			return i;
	return -1;
}

function int FindSavedRecord(string Key)
{
	local int i;

	for (i = 0; i < SavedRecords.Length; i++)
		if (SavedRecords[i].Key == Key)
			return i;
	return -1;
}

// Returns the live record index for this controller, creating it from the
// saved store (or from StartingCurrency defaults) if needed.
function int AcquireLiveRecord(Controller C)
{
	local int Idx, SavedIdx;
	local LiveRecord NewRec;

	Idx = FindLiveRecord(C);
	if (Idx >= 0)
		return Idx;

	NewRec.PlayerID = C.PlayerReplicationInfo.PlayerID;
	NewRec.Data.Key = MakeRecordKey(C.PlayerReplicationInfo.PlayerName);

	SavedIdx = -1;
	if (bPersistPlayerRecords)
		SavedIdx = FindSavedRecord(NewRec.Data.Key);

	if (SavedIdx >= 0)
	{
		NewRec.Data = SavedRecords[SavedIdx];
		if (NewRec.Data.FactionID != 255 && NewRec.Data.FactionID >= Factions.Length)
			NewRec.Data.FactionID = 255;
		if (NewRec.Data.Rank >= Ranks.Length)
			NewRec.Data.Rank = Ranks.Length - 1;
	}
	else
	{
		NewRec.Data.Wallet = StartingCurrency;
		NewRec.Data.Bank = StartingBank;
		NewRec.Data.Rank = 0;
		NewRec.Data.FactionID = 255;
		NewRec.Data.RPScore = 0;
		NewRec.Data.DutySeconds = 0;
		NewRec.Data.Warnings = 0;
	}

	Idx = LiveRecords.Length;
	LiveRecords[Idx] = NewRec;
	return Idx;
}

function ReleaseLiveRecord(Controller C)
{
	local int Idx;

	Idx = FindLiveRecord(C);
	if (Idx >= 0)
		LiveRecords.Remove(Idx, 1);
}

function ApplyRecordToPlayer(Controller C, PlayerRecord Rec)
{
	local MilRPPlayerReplicationInfo PRI;

	PRI = GetRPPRI(C);
	if (PRI == None)
		return;

	PRI.FactionID = Rec.FactionID;
	PRI.Rank = Rec.Rank;
	PRI.Score = Rec.RPScore;
	PRI.DutySeconds = Rec.DutySeconds;
	PRI.WarningCount = Rec.Warnings;
	PRI.bOnDuty = false;
	PRI.bFrozen = false;
	PRI.LastDutyChangeTime = -DutyToggleCooldown;
	PRI.LastFactionChangeTime = -FactionSwitchCooldown;
}

// Pull the replicated PRI fields back into the live record (wallet is already there).
function CaptureRecordFromPlayer(Controller C)
{
	local MilRPPlayerReplicationInfo PRI;
	local int Idx;

	PRI = GetRPPRI(C);
	Idx = FindLiveRecord(C);
	if (PRI == None || Idx < 0)
		return;

	LiveRecords[Idx].Data.FactionID = PRI.FactionID;
	LiveRecords[Idx].Data.Rank = PRI.Rank;
	LiveRecords[Idx].Data.RPScore = int(PRI.Score);
	LiveRecords[Idx].Data.DutySeconds = PRI.DutySeconds;
	LiveRecords[Idx].Data.Warnings = PRI.WarningCount;
	// Bank/wallet are updated immediately by the economy functions.
}

function PersistRecord(Controller C)
{
	local int Idx, SavedIdx;

	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return;

	SavedIdx = FindSavedRecord(LiveRecords[Idx].Data.Key);
	if (SavedIdx < 0)
	{
		while (SavedRecords.Length >= MaxSavedRecords)
			SavedRecords.Remove(0, 1);
		SavedIdx = SavedRecords.Length;
	}
	SavedRecords[SavedIdx] = LiveRecords[Idx].Data;
	SaveConfig();
}

// Flush every connected player's record - used on map change / shutdown.
function PersistAllRecords()
{
	local Controller C;

	if (!bPersistPlayerRecords)
		return;
	for (C = Level.ControllerList; C != None; C = C.NextController)
		if (PlayerController(C) != None && C.PlayerReplicationInfo != None && !C.PlayerReplicationInfo.bBot)
		{
			CaptureRecordFromPlayer(C);
			PersistRecord(C);
		}
}

function RestartGame()
{
	// Persist records, but do NOT call Super.RestartGame() or Level.ServerTravel().
	// The GameEnded state and any accidental map-restart requests must never
	// terminate the persistent RP world.
	PersistAllRecords();
	bGameRestarted = false;
	bGameEnded = false;
}


///////////////////////////////////////////////////////////////////////////////
// ECONOMY
///////////////////////////////////////////////////////////////////////////////
function int GetWallet(Controller C)
{
	local int Idx;

	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return 0;
	return LiveRecords[Idx].Data.Wallet;
}

// Adds (or subtracts) currency, clamps, pushes the new value to the owner.
// Returns the resulting wallet.
function int AddCurrency(Controller C, int Amount, string Reason)
{
	local int Idx, NewWallet;

	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return 0;

	NewWallet = LiveRecords[Idx].Data.Wallet + Amount;
	if (!bAllowNegativeWallet && NewWallet < 0)
		NewWallet = 0;
	LiveRecords[Idx].Data.Wallet = NewWallet;

	if (MilRPPlayer(C) != None)
		MilRPPlayer(C).SetWallet(NewWallet);

	if (Reason != "")
		ScoreEvent(C.PlayerReplicationInfo, Amount, Reason);

	return NewWallet;
}

// Attempts to remove Amount from the wallet. Fails without changing anything
// if the player cannot cover it (unless negative wallets are allowed).
function bool TryCharge(Controller C, int Amount, string Reason)
{
	local int Idx;

	if (Amount <= 0)
		return true;
	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return false;
	if (!bAllowNegativeWallet && LiveRecords[Idx].Data.Wallet < Amount)
	{
		NotifyPlayer(C, FailFunds);
		return false;
	}
	AddCurrency(C, -Amount, Reason);
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// BANK
///////////////////////////////////////////////////////////////////////////////
function int GetBank(Controller C)
{
	local int Idx;

	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return 0;
	return LiveRecords[Idx].Data.Bank;
}

function int AddBank(Controller C, int Amount)
{
	local int Idx, NewBank;

	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return 0;

	NewBank = LiveRecords[Idx].Data.Bank + Amount;
	if (MaxBankBalance > 0 && NewBank > MaxBankBalance)
		NewBank = MaxBankBalance;
	if (NewBank < 0)
		NewBank = 0;

	LiveRecords[Idx].Data.Bank = NewBank;
	if (MilRPPlayer(C) != None)
		MilRPPlayer(C).SetBank(NewBank);

	return NewBank;
}

function bool TryBankCharge(Controller C, int Amount)
{
	local int Idx;

	if (Amount <= 0)
		return true;
	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return false;
	if (LiveRecords[Idx].Data.Bank < Amount)
	{
		NotifyPlayer(C, FailFunds);
		return false;
	}
	AddBank(C, -Amount);
	return true;
}

// Move Amount between wallet and bank. Positive = deposit, negative = withdraw.
function bool BankTransfer(Controller C, int Amount)
{
	local int Idx;

	Idx = FindLiveRecord(C);
	if (Idx < 0)
		return false;

	if (Amount > 0)
	{
		// deposit
		if (LiveRecords[Idx].Data.Wallet < Amount)
			return false;
		AddCurrency(C, -Amount, "");
		AddBank(C, Amount);
	}
	else if (Amount < 0)
	{
		// withdraw
		if (LiveRecords[Idx].Data.Bank < -Amount)
			return false;
		AddBank(C, Amount);
		AddCurrency(C, -Amount, "");
	}
	return true;
}

function HandleBank(MilRPPlayer RPO, string Action, int Amount, string Target)
{
	local int NewBank, NewWallet;
	local Controller TargetC;
	local string Msg;

	if (RPO == None)
		return;

	if (Action ~= "deposit")
	{
		if (TryCharge(RPO, Amount, "bank_deposit"))
		{
			NewBank = AddBank(RPO, Amount);
			Msg = "Deposited $" $ Amount $ ". Bank: $" $ NewBank;
			LogEconomy(RPO, "deposit", Amount, "");
		}
		else
			Msg = "Insufficient wallet funds.";
	}
	else if (Action ~= "withdraw")
	{
		if (BankTransfer(RPO, -Amount))
		{
			NewBank = GetBank(RPO);
			NewWallet = GetWallet(RPO);
			Msg = "Withdrew $" $ Amount $ ". Wallet: $" $ NewWallet $ " Bank: $" $ NewBank;
			LogEconomy(RPO, "withdraw", Amount, "");
		}
		else
			Msg = "Insufficient bank funds.";
	}
	else if (Action ~= "transfer")
	{
		TargetC = FindPlayerByName(Target);
		if (TargetC == None)
			Msg = "Recipient not found.";
		else if (BankTransfer(RPO, -Amount))
		{
			AddBank(TargetC, Amount);
			Msg = "Transferred $" $ Amount $ " to " $ TargetC.PlayerReplicationInfo.PlayerName $ ".";
			LogEconomy(RPO, "transfer", -Amount, Target);
			LogEconomy(MilRPPlayer(TargetC), "transfer", Amount, RPO.PlayerReplicationInfo.PlayerName);
		}
		else
			Msg = "Insufficient bank funds.";
	}
	else
		Msg = "Unknown bank action.";

	RPO.ClientRPNotify(Msg);
}


///////////////////////////////////////////////////////////////////////////////
// PLAYER-TO-PLAYER PAY
///////////////////////////////////////////////////////////////////////////////
function PayPlayer(MilRPPlayer RPO, string TargetName, int Amount)
{
	local Controller TargetC;
	local Actor Ref1, Ref2;

	if (RPO == None || Amount <= 0)
		return;

	TargetC = FindPlayerByName(TargetName);
	if (TargetC == None || TargetC.Pawn == None)
	{
		RPO.ClientRPNotify("Player not found or not spawned.");
		return;
	}

	Ref1 = RPO.Pawn;
	if (Ref1 == None)
		Ref1 = RPO;
	Ref2 = TargetC.Pawn;
	if (Ref2 == None)
		Ref2 = TargetC;

	if (VSize(Ref1.Location - Ref2.Location) > RPO.PayRadius)
	{
		RPO.ClientRPNotify("You are too far away to pay that player.");
		return;
	}

	if (!TryCharge(RPO, Amount, "player_pay"))
	{
		RPO.ClientRPNotify(FailFunds);
		return;
	}

	AddCurrency(TargetC, Amount, "player_pay");
	RPO.ClientRPNotify("You paid $" $ Amount $ " to " $ TargetC.PlayerReplicationInfo.PlayerName $ ".");
	if (MilRPPlayer(TargetC) != None)
		MilRPPlayer(TargetC).ClientRPNotify(RPO.PlayerReplicationInfo.PlayerName $ " paid you $" $ Amount $ ".");
	LogEconomy(RPO, "pay", -Amount, TargetC.PlayerReplicationInfo.PlayerName);
	LogEconomy(MilRPPlayer(TargetC), "pay", Amount, RPO.PlayerReplicationInfo.PlayerName);
}


///////////////////////////////////////////////////////////////////////////////
// FINES
///////////////////////////////////////////////////////////////////////////////
function bool FinePlayer(MilRPPlayer Admin, string TargetName, int Amount, string Reason)
{
	local Controller Target;

	Target = FindPlayerByName(TargetName);
	if (Target == None)
		return false;

	AddCurrency(Target, -Amount, "fine");
	Target.PlayerReplicationInfo.Score = FMax(0.0, Target.PlayerReplicationInfo.Score - Amount / 10);
	if (MilRPPlayer(Target) != None)
		MilRPPlayer(Target).ClientRPNotify("Fined $" $ Amount $ ": " $ Reason);
	LogAdmin(Admin, "FINE", Target.PlayerReplicationInfo.PlayerName, Reason $ " amount=" $ Amount);
	LogEconomy(MilRPPlayer(Target), "fine", -Amount, Reason);
	return true;
}

function int CalcPaycheck(MilRPPlayerReplicationInfo PRI)
{
	local float Pay;

	Pay = BasePaycheck * (1.0 + float(PRI.Rank) * RankPaycheckMultiplier);
	if (PRI.bOnDuty)
		Pay *= OnDutyPayMultiplier;
	else
		Pay *= OffDutyPayScale;
	return int(Pay);
}

function PayEveryone()
{
	local Controller C;
	local MilRPPlayerReplicationInfo PRI;
	local int Pay;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (!IsRPParticipant(C))
			continue;
		PRI = GetRPPRI(C);
		if (PRI == None || !PRI.bRoleplayReady || PRI.bOnlySpectator)
			continue;

		Pay = CalcPaycheck(PRI) + TerritoryBonusFor(PRI.FactionID);
		if (Pay <= 0)
		{
			NotifyPlayer(C, MsgNoPaycheck);
			continue;
		}

		if (bPaycheckDirectDeposit)
		{
			AddCurrency(C, Pay, "paycheck");
			NotifyPlayer(C, FormatMsg(MsgPaycheck, PRI.PlayerName, "", "", Pay));
			if (RPWorld != None)
				RPWorld.FireAddonEvent('OnPaycheck', MilRPPlayer(C), None, Pay, 0, true);
		}
		else
		{
			SetPaycheckPending(C, Pay);
			NotifyPlayer(C, FormatMsg(MsgPaycheckPending, PRI.PlayerName, "", "", Pay));
		}
	}
}

// Sum of PassivePaycheck across every MilRPCapturePoint this faction holds.
// Called once per player per paycheck tick; the point list is small so the
// scan is cheap.
function int TerritoryBonusFor(int FactionID)
{
	local int i, Bonus;
	local MilRPCapturePoint CP;

	if (RPWorld == None || FactionID == 255 || FactionID < 0)
		return 0;
	for (i = 0; i < RPWorld.Points.Length; i++)
	{
		CP = MilRPCapturePoint(RPWorld.Points[i]);
		if (CP != None && CP.CurrentOwnerID == FactionID)
			Bonus += CP.PassivePaycheck;
	}
	return Bonus;
}

function SetPaycheckPending(Controller C, int Amount)
{
	if (MilRPPlayer(C) != None)
		MilRPPlayer(C).SetPaycheck(Amount, true);
}

function string CollectPaycheck(MilRPPlayer RPO)
{
	if (RPO == None)
		return "System error.";

	if (!RPO.bPaycheckReady || RPO.PendingPaycheck <= 0)
		return "No pending paycheck.";

	AddCurrency(RPO, RPO.PendingPaycheck, "paycheck_collect");
	RPO.SetPaycheck(0, false);
	if (RPWorld != None)
		RPWorld.FireAddonEvent('OnPaycheck', RPO, None, RPO.PendingPaycheck, 0, false);
	return FormatMsg(MsgPaycheckCollected, "", "", "", RPO.PendingPaycheck);
}


///////////////////////////////////////////////////////////////////////////////
// PARTICIPANT CHECK
// Treats human players and stress bots as valid RP actors. Excludes real bots
// and spectators.
///////////////////////////////////////////////////////////////////////////////
function bool IsRPParticipant(Controller C)
{
	local MilRPPlayerReplicationInfo PRI;

	if (C == None || C.PlayerReplicationInfo == None || C.PlayerReplicationInfo.bOnlySpectator)
		return false;
	PRI = GetRPPRI(C);
	if (PRI == None)
		return false;
	if (C.bIsPlayer && MilRPTestBot(C) != None)
		return true;
	return (PlayerController(C) != None && !C.PlayerReplicationInfo.bBot);
}


///////////////////////////////////////////////////////////////////////////////
// 1 Hz SERVER LOOP
// GameInfo runs SetTimer(1.0,true); the DeathMatch state Timers call
// Global.Timer() which lands here.
///////////////////////////////////////////////////////////////////////////////
function Timer()
{
	Super.Timer();

	if (bWaitingToStartMatch || bGameEnded)
		return;

	RPClock++;
	TickPlayerIdentity();
	TickDutyProgression();
	TickFreeze();

	if (RPClock >= NextPaycheckClock)
	{
		PayEveryone();
		NextPaycheckClock = RPClock + PaycheckInterval;
		if (RPGRI != None)
			RPGRI.NextPaycheckTime = NextPaycheckClock;
	}
}

// Keep each player's NetSignature and name current. PostLogin is too early for
// GetPlayerNetworkAddress() to return a real IP, and local offline tests start
// with the generic "Player" name from User.ini. Retry once per second.
function TickPlayerIdentity()
{
	local Controller C;
	local PlayerController PC;
	local MilRPPlayerReplicationInfo PRI;
	local string Sig, SteamID, SteamName;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (!IsRPParticipant(C))
			continue;
		PRI = GetRPPRI(C);
		if (PRI == None || !PRI.bRoleplayReady)
			continue;

		// Real network signature.
		Sig = GetConnectionID(C);
		if (Sig != "")
			PRI.NetSignature = Sig;

		// Try to pull native Steam identity from the client wrapper.
		PC = PlayerController(C);
		if (PC != None && !PRI.bSteamQueried)
		{
			SteamID = PC.ConsoleCommand("getsteamid");
			if (SteamID != "")
				PRI.NetSignature = SteamID;

			SteamName = PC.ConsoleCommand("getsteamname");
			if (SteamName != "" && (PRI.PlayerName == "" || PRI.PlayerName == "Player"))
				PRI.PlayerName = SteamName;

			PRI.bSteamQueried = true;
		}

		// Offline local host Steam name fallback.
		if (HostTestName != "" && PRI.PlayerName == "Player" && InStr(Caps(Sig), "127.0.0.1") >= 0)
			PRI.PlayerName = HostTestName;
	}
}

// Every second on duty is credited; every full minute converts into RP score.
function TickDutyProgression()
{
	local Controller C;
	local MilRPPlayerReplicationInfo PRI;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (!IsRPParticipant(C))
			continue;
		PRI = GetRPPRI(C);
		if (PRI == None || !PRI.bOnDuty || !PRI.bRoleplayReady)
			continue;

		PRI.DutySeconds++;
		if (RPScorePerDutyMinute > 0 && (PRI.DutySeconds % 60) == 0)
		{
			PRI.Score += RPScorePerDutyMinute;
			ScoreEvent(PRI, RPScorePerDutyMinute, "duty_minute");
			CheckPromotion(C);
		}
	}
}

// Server-side freeze enforcement. Movement input is also zeroed client-side
// in MilRPPlayer.PlayerTick, but this makes sure a dedicated server stays
// authoritative.
function TickFreeze()
{
	local Controller C;
	local MilRPPlayerReplicationInfo PRI;
	local Pawn P;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (!IsRPParticipant(C))
			continue;
		PRI = GetRPPRI(C);
		P = C.Pawn;
		if (PRI == None || P == None)
			continue;
		if (!PRI.bFrozen)
			continue;

		P.Velocity = vect(0,0,0);
		P.Acceleration = vect(0,0,0);
		C.bFire = 0;
		C.bAltFire = 0;
		if (P.Weapon != None && P.Weapon.IsInState('NormalFire'))
			P.Weapon.GotoState('Idle');
	}
}


///////////////////////////////////////////////////////////////////////////////
// FACTIONS
///////////////////////////////////////////////////////////////////////////////
function int CountFactionMembers(int FactionID)
{
	local Controller C;
	local MilRPPlayerReplicationInfo PRI;
	local int Count;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		PRI = GetRPPRI(C);
		if (PRI != None && PRI.FactionID == FactionID)
			Count++;
	}
	return Count;
}

function bool IsCombatantFaction(int FactionID)
{
	return (FactionID >= 0 && FactionID < Factions.Length && Factions[FactionID].bCombatant);
}

// Server entry point for a faction change request (called by MilRPPlayer RPC
// or by admin commands). Returns false and fills FailReason on rejection.
function bool RequestFaction(Controller C, int NewFaction, out string FailReason, optional bool bForce)
{
	local MilRPPlayerReplicationInfo PRI;
	local int Remaining, OldFaction;

	PRI = GetRPPRI(C);
	if (PRI == None)
	{
		FailReason = FailInvalidFaction;
		return false;
	}
	if (NewFaction < 0 || NewFaction >= Factions.Length)
	{
		FailReason = FailInvalidFaction;
		return false;
	}
	if (PRI.FactionID == NewFaction)
		return true;

	if (!bForce)
	{
		if (PRI.FactionID != 255 && !bAllowFactionSwitch)
		{
			FailReason = FailNoSwitch;
			return false;
		}
		Remaining = (PRI.LastFactionChangeTime + FactionSwitchCooldown) - RPClock;
		if (PRI.FactionID != 255 && Remaining > 0)
		{
			FailReason = FormatMsg(FailCooldown, "", "", "", Remaining);
			return false;
		}
		if (MaxFactionSize > 0 && CountFactionMembers(NewFaction) >= MaxFactionSize)
		{
			FailReason = FailFactionFull;
			return false;
		}
	}

	// Leaving a faction always clocks you out and strips the old kit.
	if (PRI.bOnDuty)
		SetDutyInternal(C, PRI, false, true);

	if (RPWorld != None && !RPWorld.AllowAddonFactionJoin(MilRPPlayer(C), NewFaction, FailReason))
		return false;

	OldFaction = PRI.FactionID;
	PRI.FactionID = NewFaction;
	PRI.LastFactionChangeTime = RPClock;
	CaptureRecordFromPlayer(C);

	if (bAnnounceFactionJoins)
		BroadcastRP(FormatMsg(MsgJoinedFaction, PRI.PlayerName, Factions[NewFaction].Name));
	GameEvent("FactionChange", string(NewFaction), PRI);
	if (RPWorld != None)
		RPWorld.FireAddonEvent('OnFactionJoin', MilRPPlayer(C), None, OldFaction, NewFaction);
	Logf("FACTION", PRI.PlayerName $ " joined " $ Factions[NewFaction].Name);
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// DUTY
///////////////////////////////////////////////////////////////////////////////
function bool RequestDuty(Controller C, bool bWantOnDuty, out string FailReason)
{
	local MilRPPlayerReplicationInfo PRI;
	local int Remaining;

	PRI = GetRPPRI(C);
	if (PRI == None)
		return false;
	if (PRI.bOnDuty == bWantOnDuty)
		return true;

	if (bWantOnDuty)
	{
		if (PRI.FactionID == 255)
		{
			FailReason = FailNoFaction;
			return false;
		}
		if (!IsCombatantFaction(PRI.FactionID))
		{
			FailReason = FailNonCombatant;
			return false;
		}
	}

	Remaining = (PRI.LastDutyChangeTime + DutyToggleCooldown) - RPClock;
	if (Remaining > 0)
	{
		FailReason = FormatMsg(FailCooldown, "", "", "", Remaining);
		return false;
	}

	if (RPWorld != None && !RPWorld.AllowAddonDuty(MilRPPlayer(C), bWantOnDuty, FailReason))
		return false;

	SetDutyInternal(C, PRI, bWantOnDuty, false);
	return true;
}

function SetDutyInternal(Controller C, MilRPPlayerReplicationInfo PRI, bool bNewOnDuty, bool bSilent)
{
	local Pawn P;

	PRI.bOnDuty = bNewOnDuty;
	PRI.LastDutyChangeTime = RPClock;

	P = C.Pawn;
	if (P != None && P.Health > 0)
	{
		// Duty kit enforcement lives exclusively in AddDefaultInventory /
		// RestartPlayer - once a pawn is alive and walking, the server never
		// grants, strips, or swaps its weapons automatically. DutyChangeMode 1
		// respawns through the normal death path, which re-runs
		// AddDefaultInventory and is therefore still allowed to change kit.
		if (DutyChangeMode == 1)
		{
			// Respawn with the correct kit. Routed through the normal death
			// path so bForceRespawn re-spawns the player with the new loadout.
			P.KilledBy(None);
		}
	}

	if (!bSilent && bAnnounceDutyChanges)
	{
		if (bNewOnDuty)
			BroadcastRP(FormatMsg(MsgOnDuty, PRI.PlayerName));
		else
			BroadcastRP(FormatMsg(MsgOffDuty, PRI.PlayerName));
	}
	GameEvent("DutyChange", string(bNewOnDuty), PRI);
	if (RPWorld != None)
		RPWorld.FireAddonEvent('OnDutyChange', MilRPPlayer(C), None, 0, 0, bNewOnDuty);
	if (bNewOnDuty)
		Logf("DUTY", PRI.PlayerName $ " on duty");
	else
		Logf("DUTY", PRI.PlayerName $ " off duty");
}


///////////////////////////////////////////////////////////////////////////////
// LOADOUTS
// GameBaseEquipment (hands/foot/urethra etc.) is still handed out by the pawn
// via Super.AddDefaultInventory(); we layer the roleplay kit on top.
///////////////////////////////////////////////////////////////////////////////
function AddDefaultInventory(Pawn PlayerPawn)
{
	local MilRPPlayerReplicationInfo PRI;
	local string Loadout;

	Super.AddDefaultInventory(PlayerPawn);

	if (PlayerPawn == None || PlayerPawn.Controller == None)
		return;
	PRI = GetRPPRI(PlayerPawn.Controller);
	if (PRI == None)
		return;

	if (PRI.bOnDuty && IsCombatantFaction(PRI.FactionID))
		Loadout = Factions[PRI.FactionID].DutyLoadout;
	else
		Loadout = OffDutyLoadout;

	if (RPWorld != None)
		Loadout = RPWorld.ModifyAddonLoadout(MilRPPlayer(PlayerPawn.Controller), Loadout);

	GiveLoadout(PlayerPawn, Loadout);
}

// Splits "A,B,C" into trimmed class names. Returns count.
static function int SplitLoadout(string Loadout, out array<string> Names)
{
	local int Pos;
	local string Item;

	Names.Length = 0;
	while (Loadout != "")
	{
		Pos = InStr(Loadout, ",");
		if (Pos < 0)
		{
			Item = Loadout;
			Loadout = "";
		}
		else
		{
			Item = Left(Loadout, Pos);
			Loadout = Mid(Loadout, Pos + 1);
		}
		Item = TrimSpaces(Item);
		if (Item != "")
			Names[Names.Length] = Item;
	}
	return Names.Length;
}

static function string TrimSpaces(string S)
{
	while (Len(S) > 0 && Left(S, 1) == " ")
		S = Mid(S, 1);
	while (Len(S) > 0 && Right(S, 1) == " ")
		S = Left(S, Len(S) - 1);
	return S;
}

function GiveLoadout(Pawn P, string Loadout)
{
	local array<string> Names;
	local int i;
	local class<Inventory> InvClass;

	if (P == None || Loadout == "")
		return;

	SplitLoadout(Loadout, Names);
	for (i = 0; i < Names.Length; i++)
	{
		InvClass = class<Inventory>(DynamicLoadObject(Names[i], class'Class'));
		if (InvClass == None)
		{
			warn("MilRPGameInfo::GiveLoadout : unknown inventory class '" $ Names[i] $ "'");
			continue;
		}
		if (P.FindInventoryType(InvClass) != None)
			continue;
		if (P2Pawn(P) != None)
			P2Pawn(P).CreateInventory(Names[i]);
		else
			P.GiveWeapon(Names[i]);
	}
}

function RemoveLoadout(Pawn P, string Loadout)
{
	local array<string> Names;
	local int i;
	local class<Inventory> InvClass;
	local Inventory Inv;
	local bool bDroppedCurrent;
	local MilRPPlayer MRP;

	if (P == None || Loadout == "")
		return;

	MRP = MilRPPlayer(P.Controller);

	SplitLoadout(Loadout, Names);
	for (i = 0; i < Names.Length; i++)
	{
		InvClass = class<Inventory>(DynamicLoadObject(Names[i], class'Class'));
		if (InvClass == None)
			continue;
		Inv = P.FindInventoryType(InvClass);
		if (Inv == None)
			continue;
		// Enforcement freeze: shop-purchased items and anything an admin is
		// holding are never stripped. Deleting the in-hand weapon triggers
		// SwitchToBestWeapon() below, which is what snapped players back to
		// the default rifle.
		if (MRP != None && (MRP.OwnsPurchased(InvClass) || CheckPermission(MRP, 2)))
			continue;
		if (P.Weapon == Inv)
			bDroppedCurrent = true;
		P.DeleteInventory(Inv);
		Inv.Destroy();
	}

	if (bDroppedCurrent && P.Controller != None)
		P.Controller.SwitchToBestWeapon();
}


///////////////////////////////////////////////////////////////////////////////
// PROGRESSION
///////////////////////////////////////////////////////////////////////////////
function CheckPromotion(Controller C)
{
	local MilRPPlayerReplicationInfo PRI;
	local int NewRank;

	if (!bAutoPromote || RPGRI == None)
		return;
	PRI = GetRPPRI(C);
	if (PRI == None)
		return;

	NewRank = RPGRI.RankForScore(int(PRI.Score));
	if (NewRank > PRI.Rank)
		SetRank(C, NewRank, true);
}

// Admin/system rank change. bAnnounce controls the base-wide broadcast.
function SetRank(Controller C, int NewRank, bool bAnnounce)
{
	local MilRPPlayerReplicationInfo PRI;
	local int OldRank;

	PRI = GetRPPRI(C);
	if (PRI == None)
		return;
	NewRank = Clamp(NewRank, 0, Ranks.Length - 1);
	if (NewRank == PRI.Rank)
		return;

	OldRank = PRI.Rank;
	PRI.Rank = NewRank;
	CaptureRecordFromPlayer(C);

	if (bAnnounce && bAnnouncePromotions)
	{
		if (NewRank > OldRank)
			BroadcastRP(FormatMsg(MsgPromoted, PRI.PlayerName, "", Ranks[NewRank].Title));
		else
			BroadcastRP(FormatMsg(MsgDemoted, PRI.PlayerName, "", Ranks[NewRank].Title));
	}
	GameEvent("RankChange", string(NewRank), PRI);
	if (RPWorld != None)
		RPWorld.FireAddonEvent('OnRankChange', MilRPPlayer(C), None, OldRank, NewRank);
	if (NewRank > OldRank)
		Logf("RANK", PRI.PlayerName $ " promoted to " $ Ranks[NewRank].Title);
	else
		Logf("RANK", PRI.PlayerName $ " demoted to " $ Ranks[NewRank].Title);
}


///////////////////////////////////////////////////////////////////////////////
// COMBAT RULES
///////////////////////////////////////////////////////////////////////////////
function bool IsRDM(Controller Killer, Controller Victim)
{
	local MilRPPlayerReplicationInfo KPRI, VPRI;

	if (Killer == None || Victim == None || Killer == Victim)
		return false;
	if (PlayerController(Killer) == None)
		return false;

	KPRI = GetRPPRI(Killer);
	VPRI = GetRPPRI(Victim);
	if (KPRI == None || VPRI == None)
		return false;

	if (bPunishOffDutyKills && (!KPRI.bOnDuty || !VPRI.bOnDuty))
		return true;
	if (bPunishSameFactionKills && KPRI.FactionID != 255 && KPRI.FactionID == VPRI.FactionID)
		return true;
	if (bPunishCivilianKills && !IsCombatantFaction(VPRI.FactionID))
		return true;
	return false;
}

// Replaces frag scoring entirely: PRI.Score is RP score, never kill count.
// Deaths are already tallied in GameInfo.Killed().
function ScoreKill(Controller Killer, Controller Other)
{
	local MilRPPlayerReplicationInfo KPRI;
	local bool bRDM;

	if (Other == None || Other.PlayerReplicationInfo == None)
		return;

	if (Killer != None && Killer.PlayerReplicationInfo != None && Killer != Other)
		Killer.PlayerReplicationInfo.Kills++;

	bRDM = IsRDM(Killer, Other);
	if (bRDM)
	{
		KPRI = GetRPPRI(Killer);
		KPRI.WarningCount++;
		if (RPScoreLossPerRDM > 0)
		{
			KPRI.Score = FMax(0.0, KPRI.Score - RPScoreLossPerRDM);
			ScoreEvent(KPRI, -RPScoreLossPerRDM, "rdm");
		}
		if (FinePerRDM > 0)
		{
			AddCurrency(Killer, -FinePerRDM, "rdm_fine");
			NotifyPlayer(Killer, FormatMsg(MsgFineApplied, "", "", "", FinePerRDM));
		}
		BroadcastRP(FormatMsg(MsgRDM, KPRI.PlayerName));
		CaptureRecordFromPlayer(Killer);
	}

	if (RPWorld != None)
		RPWorld.FireAddonEvent('OnPlayerKilled', MilRPPlayer(Killer), MilRPPlayer(Other), 0, 0, bRDM);
	if (Killer != None && Other != None)
	if (bRDM)
		Logf("KILL", Killer.PlayerReplicationInfo.PlayerName $ " killed " $ Other.PlayerReplicationInfo.PlayerName $ " (RDM)");
	else
		Logf("KILL", Killer.PlayerReplicationInfo.PlayerName $ " killed " $ Other.PlayerReplicationInfo.PlayerName);
}

function int ReduceDamage(int Damage, Pawn Injured, Pawn InstigatedBy, vector HitLocation, out vector Momentum, class<DamageType> DamageType)
{
	local MilRPPlayerReplicationInfo IPRI, APRI;

	if (InstigatedBy != None && InstigatedBy != Injured
		&& InstigatedBy.Controller != None && Injured.Controller != None)
	{
		APRI = GetRPPRI(InstigatedBy.Controller);
		IPRI = GetRPPRI(Injured.Controller);
		if (APRI != None && IPRI != None)
		{
			if (RPGRI != None && RPGRI.bLockdown && !APRI.bOnDuty)
				return 0;
			if (bOffDutyCannotDamage && !APRI.bOnDuty)
				return 0;
			if (bBlockSameFactionDamage && APRI.FactionID != 255 && APRI.FactionID == IPRI.FactionID)
			{
				if (SameFactionDamageScale <= 0.0)
					return 0;
				Damage = int(float(Damage) * SameFactionDamageScale);
			}
		}
	}
	return Super.ReduceDamage(Damage, Injured, InstigatedBy, HitLocation, Momentum, DamageType);
}

// Faction spawn areas: PlayerStart.TeamNumber doubles as a faction id when
// bUseFactionSpawns is on. Maps without tagged starts degrade gracefully
// because every start receives the same penalty.
function float RatePlayerStart(NavigationPoint N, byte Team, Controller Player)
{
	local PlayerStart P;
	local MilRPPlayerReplicationInfo PRI;

	P = PlayerStart(N);
	if (P != None && bUseFactionSpawns && Player != None)
	{
		PRI = GetRPPRI(Player);
		if (PRI != None && PRI.FactionID != 255 && P.TeamNumber != PRI.FactionID)
			return -9000000;
	}
	return Super.RatePlayerStart(N, Team, Player);
}


///////////////////////////////////////////////////////////////////////////////
// SPAWN SELECTION
///////////////////////////////////////////////////////////////////////////////
// Update a faction's saved spawn point and immediately persist it.
function SetFactionSpawn(Controller C, int FactionID)
{
	if (!IsAdmin(C))
	{
		NotifyPlayer(C, FailNotAdmin);
		return;
	}
	if (FactionID < 0 || FactionID >= Factions.Length)
	{
		NotifyPlayer(C, FailInvalidFaction);
		return;
	}
	if (C == None || C.Pawn == None)
		return;

	Factions[FactionID].StartLocation = C.Pawn.Location;
	Factions[FactionID].StartRotation = C.Rotation;
	SaveConfig();

	NotifyPlayer(C, "Spawn set for " $ Factions[FactionID].Name $ ".");
	Logf("ADMIN", C.PlayerReplicationInfo.PlayerName $ " set " $ Factions[FactionID].Name $ " spawn to " $ Factions[FactionID].StartLocation);
}

// If a faction has a saved spawn, pick the nearest PlayerStart and remember
// the exact target location/rotation so RestartPlayer can snap to it.
function NavigationPoint FindPlayerStart(Controller Player, optional byte InTeam, optional string incomingName)
{
	local NavigationPoint N, Best;
	local MilRPPlayer RPO;
	local MilRPPlayerReplicationInfo PRI;
	local int FactionID;
	local float BestDist, Dist;

	PRI = GetRPPRI(Player);
	if (PRI != None)
	{
		FactionID = PRI.FactionID;
		if (FactionID >= 0 && FactionID < Factions.Length
			&& Factions[FactionID].StartLocation != vect(0,0,0))
		{
			BestDist = 9999999.0;
			for (N = Level.NavigationPointList; N != None; N = N.NextNavigationPoint)
			{
				if (PlayerStart(N) == None)
					continue;
				Dist = VSize(N.Location - Factions[FactionID].StartLocation);
				if (Dist < BestDist)
				{
					BestDist = Dist;
					Best = N;
				}
			}

			if (Best != None)
			{
				RPO = MilRPPlayer(Player);
				if (RPO != None)
				{
					RPO.DesiredSpawnLocation = Factions[FactionID].StartLocation;
					RPO.DesiredSpawnRotation = Factions[FactionID].StartRotation;
				}
				return Best;
			}
		}
	}

	return Super.FindPlayerStart(Player, InTeam, incomingName);
}

// Spawn normally, then snap to the exact saved faction spawn/rotation.
function RestartPlayer(Controller aPlayer)
{
	local MilRPPlayer RPO;
	local vector SnapLoc;
	local rotator SnapRot;

	Super.RestartPlayer(aPlayer);

	RPO = MilRPPlayer(aPlayer);
	if (RPO != None)
	{
		RPO.bNoclip = false;
		RPO.ClientToggleNoclip(false);
	}
	if (RPO == None || aPlayer.Pawn == None)
		return;

	if (RPO.DesiredSpawnLocation != vect(0,0,0))
	{
		SnapLoc = RPO.DesiredSpawnLocation;
		SnapRot = RPO.DesiredSpawnRotation;

		aPlayer.Pawn.SetLocation(SnapLoc);
		aPlayer.Pawn.SetRotation(SnapRot);
		aPlayer.SetRotation(SnapRot);
		aPlayer.ClientSetRotation(SnapRot);

		RPO.DesiredSpawnLocation = vect(0,0,0);
		RPO.DesiredSpawnRotation = rot(0,0,0);
	}
}


///////////////////////////////////////////////////////////////////////////////
// PAWN SPAWN CUSTOMISATION
// Allows factions to override the default player pawn and applies rank-based
// health/speed bonuses.
///////////////////////////////////////////////////////////////////////////////
function class<Pawn> GetDefaultPlayerClass(Controller C)
{
	local class<Pawn> PawnClass;
	local MilRPPlayerReplicationInfo PRI;

	PawnClass = Super.GetDefaultPlayerClass(C);

	PRI = GetRPPRI(C);
	if (PRI != None && PRI.FactionID >= 0 && PRI.FactionID < Factions.Length
		&& Factions[PRI.FactionID].PawnClass != "")
	{
		PawnClass = class<Pawn>(DynamicLoadObject(Factions[PRI.FactionID].PawnClass, class'Class'));
		if (PawnClass == None)
			warn("MilRPGameInfo::GetDefaultPlayerClass : cannot load " $ Factions[PRI.FactionID].PawnClass);
	}

	return PawnClass;
}

function SetPlayerDefaults(Pawn PlayerPawn)
{
	local MilRPPlayerReplicationInfo PRI;
	local float SpeedMult;

	Super.SetPlayerDefaults(PlayerPawn);

	if (PlayerPawn == None)
		return;

	PRI = GetRPPRI(PlayerPawn.Controller);
	if (PRI != None)
	{
		if (PRI.Rank >= 0 && PRI.Rank < 16)
		{
			if (P2Pawn(PlayerPawn) != None)
			{
				P2Pawn(PlayerPawn).HealthMax += RankHealthBonus[PRI.Rank];
				P2Pawn(PlayerPawn).Health = P2Pawn(PlayerPawn).HealthMax;
			}
			else
			{
				PlayerPawn.Health += RankHealthBonus[PRI.Rank];
			}
			SpeedMult = 1.0 + float(PRI.Rank) * RankSpeedMultiplier;
			PlayerPawn.GroundSpeed *= SpeedMult;
			PlayerPawn.WaterSpeed *= SpeedMult;
			PlayerPawn.AirSpeed *= SpeedMult;
		}
	}
}


///////////////////////////////////////////////////////////////////////////////
// ADMIN HELPERS (called from MilRPPlayer admin RPCs)
///////////////////////////////////////////////////////////////////////////////
// Strip the trailing port from an address of the form 192.168.1.50:7777.
function string StripPort(string Address)
{
	local int Colon;

	Colon = InStr(Address, ":");
	if (Colon >= 0)
		return Left(Address, Colon);
	return Address;
}

// Return the network signature for a controller, or "" if none is available.
function string GetConnectionID(Controller C)
{
	local PlayerController PC;
	local string IP;

	if (C == None)
		return "";

	PC = PlayerController(C);
	if (PC == None)
		return "";

	// Local listen server / loopback hosts have no NetConnection; give them a
	// readable local signature so the admin panel never shows a blank IP.
	if (NetConnection(PC.Player) == None)
		return "127.0.0.1 (Local Host)";

	IP = StripPort(PC.GetPlayerNetworkAddress());
	if (IP == "" || IP ~= "none")
		return "127.0.0.1 (Local Host)";

	return IP;
}

// Return the group level for a controller, or 0 if not registered.
function int GetGroupLevel(Controller C)
{
	local int i;
	local string ID;
	local PlayerController PC;

	PC = PlayerController(C);
	if (PC != None && NetConnection(PC.Player) == None)
		return 4;

	ID = Caps(GetConnectionID(C));
	if (ID == "")
		return 0;

	for (i = 0; i < StaffRegistry.Length; i++)
		if (Caps(StripPort(StaffRegistry[i].UniqueID)) == ID
			|| Caps(StripPort(StaffRegistry[i].StaffIP)) == ID)
			return Clamp(StaffRegistry[i].GroupLevel, 0, 4);

	return 0;
}

function string GetGroupName(int Level)
{
	Level = Clamp(Level, 0, 4);
	if (GroupNames[Level] != "")
		return GroupNames[Level];
	switch (Level)
	{
		case 0:  return "Player";
		case 1:  return "Moderator";
		case 2:  return "Admin";
		case 3:  return "SuperAdmin";
		case 4:  return "Owner";
	}
	return "Unknown";
}

// Main permission gate.  RequiredLevel is an EUserGroup value (0..4).
function bool CheckPermission(MilRPPlayer P, int RequiredLevel)
{
	if (Level.NetMode == NM_Standalone)
		return true;
	if (P == None)
		return false;
	return (GetGroupLevel(P) >= Clamp(RequiredLevel, 0, 4));
}

// Legacy binary check: admin or higher.
function bool IsAdmin(Controller C)
{
	return (C != None && C.IsA('MilRPPlayer') && CheckPermission(MilRPPlayer(C), 2));
}

function Controller FindPlayerByName(string PartialName)
{
	local Controller C;
	local string Needle;

	Needle = Caps(PartialName);
	if (Needle == "")
		return None;
	for (C = Level.ControllerList; C != None; C = C.NextController)
		if (PlayerController(C) != None && C.PlayerReplicationInfo != None
			&& InStr(Caps(C.PlayerReplicationInfo.PlayerName), Needle) >= 0)
			return C;
	return None;
}

function bool AdminSetRank(Controller Admin, string TargetName, int NewRank)
{
	local Controller Target;

	if (!IsAdmin(Admin))
	{
		NotifyPlayer(Admin, FailNotAdmin);
		return false;
	}
	Target = FindPlayerByName(TargetName);
	if (Target == None)
		return false;
	SetRank(Target, NewRank, true);
	return true;
}

function bool AdminSetFaction(Controller Admin, string TargetName, int NewFaction)
{
	local Controller Target;
	local string FailReason;

	if (!IsAdmin(Admin))
	{
		NotifyPlayer(Admin, FailNotAdmin);
		return false;
	}
	Target = FindPlayerByName(TargetName);
	if (Target == None)
		return false;
	if (!RequestFaction(Target, NewFaction, FailReason, true))
	{
		NotifyPlayer(Admin, FailReason);
		return false;
	}
	return true;
}

function bool AdminGiveCurrency(Controller Admin, string TargetName, int Amount)
{
	local Controller Target;

	if (!IsAdmin(Admin))
	{
		NotifyPlayer(Admin, FailNotAdmin);
		return false;
	}
	Target = FindPlayerByName(TargetName);
	if (Target == None)
		return false;
	AddCurrency(Target, Amount, "admin_grant");
	return true;
}

function bool AdminBroadcast(Controller Admin, string Msg)
{
	if (!IsAdmin(Admin))
	{
		NotifyPlayer(Admin, FailNotAdmin);
		return false;
	}
	BroadcastRP(Msg);
	LogAdmin(MilRPPlayer(Admin), "ANNOUNCE", "", Msg);
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// UNIFIED ADMIN ACTION
///////////////////////////////////////////////////////////////////////////////
// Required group for each command.  Values match EUserGroup (0..4).
function int GetActionLevel(string Action)
{
	Action = Caps(Action);

	switch (Action)
	{
		case "KICK":
		case "WARN":
		case "FREEZE":
		case "UNFREEZE":
		case "THAW":
		case "SLAP":
			return 1;

		case "BAN":
		case "GOTO":
		case "BRING":
		case "NOCLIP":
		case "POS":
		case "FINE":
			return 2;

		case "ALERT":
		case "DEFCON":
		case "LOCKDOWN":
		case "SPAWN":
		case "SETSPAWN":
			return 3;
	}

	return 4;
}

function AdminAction(MilRPPlayer Admin, string Action, string Target, int Amount, string Reason)
{
	local int NeedLevel;

	if (Admin == None)
		return;

	NeedLevel = GetActionLevel(Action);
	if (!CheckPermission(Admin, NeedLevel))
	{
		Admin.ClientRPNotify("This command requires " $ GetGroupName(NeedLevel) $ " clearance.");
		return;
	}

	Action = Caps(Action);

	if (Action == "KICK")
		KickPlayer(Admin, Target, Reason);
	else if (Action == "BAN")
		BanPlayer(Admin, Target, Reason);
	else if (Action == "WARN")
		WarnPlayer(Admin, Target, Reason);
	else if (Action == "FINE")
		FinePlayer(Admin, Target, Amount, Reason);
	else if (Action == "FREEZE")
		ToggleFreeze(Admin, Target, Reason);
	else if (Action == "UNFREEZE" || Action == "THAW")
		SetFreeze(Admin, Target, false, Reason);
	else if (Action == "GOTO")
		GotoPlayer(Admin, Target);
	else if (Action == "BRING")
		BringPlayer(Admin, Target);
	else if (Action == "POS")
		ReportPos(Admin);
	else if (Action == "ALERT" || Action == "DEFCON")
		SetAlertLevel(Admin, byte(Amount));
	else if (Action == "LOCKDOWN")
		ToggleLockdown(Admin);
	else if (Action == "NOCLIP")
		ToggleNoclip(Admin);
	else if (Action == "SLAP")
		SlapPlayer(Admin, Target, Reason);
}

// Formats and broadcasts a standardised admin action, then logs it to MilRPLog.
function BroadcastAdminAction(MilRPPlayer Admin, string Action, string Target, string Reason)
{
	local string Msg;

	if (Admin == None || Admin.PlayerReplicationInfo == None)
		return;

	Msg = "[Admin] " $ GetGroupName(GetGroupLevel(Admin)) $ " "
		$ Admin.PlayerReplicationInfo.PlayerName $ " has " $ Action $ " " $ Target;
	if (Reason != "")
		Msg = Msg $ " (Reason: " $ Reason $ ")";

	BroadcastRP(Msg);
	LogAdmin(Admin, Caps(Action), Target, Reason);
}

function bool KickPlayer(MilRPPlayer Admin, string TargetName, string Reason)
{
	local Controller Target;

	if (Admin == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.PlayerReplicationInfo == None)
		return false;

	BroadcastAdminAction(Admin, "kicked", Target.PlayerReplicationInfo.PlayerName, Reason);
	if (Level.Game.AccessControl != None)
		Level.Game.AccessControl.Kick(Target.PlayerReplicationInfo.PlayerName);
	return true;
}

function bool BanPlayer(MilRPPlayer Admin, string TargetName, string Reason)
{
	local Controller Target;
	local string IP;
	local int Idx;

	if (Admin == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.PlayerReplicationInfo == None)
		return false;

	IP = GetConnectionID(Target);
	if (IP == "")
		return false;

	// Never ban the local host / loopback listener.
	if (NetConnection(PlayerController(Target).Player) == None
		|| Left(IP, 4) == "127."
		|| Target.PlayerReplicationInfo.bAdmin)
	{
		if (Admin != None)
			Admin.ClientRPNotify("[System] You cannot ban the server host/owner.");
		return false;
	}

	// Persist the ban in the registry.
	Idx = BanRegistry.Length;
	BanRegistry.Length = BanRegistry.Length + 1;
	BanRegistry[Idx].BannedID = IP;
	BanRegistry[Idx].BannedIP = IP;
	BanRegistry[Idx].BannedName = Target.PlayerReplicationInfo.PlayerName;
	BanRegistry[Idx].Reason = Reason;
	if (Reason == "")
		BanRegistry[Idx].Reason = "Admin ban";
	SaveConfig();

	BroadcastAdminAction(Admin, "banned", Target.PlayerReplicationInfo.PlayerName $ " (" $ IP $ ")", BanRegistry[Idx].Reason);
	if (Level.Game.AccessControl != None)
		Level.Game.AccessControl.KickBan(Target.PlayerReplicationInfo.PlayerName);
	return true;
}

function bool AddStaff(MilRPPlayer Admin, string TargetName, int GroupLevel)
{
	local Controller Target;
	local int Idx;
	local string IP, Name;

	if (Admin == None)
		return false;
	if (!CheckPermission(Admin, 4))
	{
		Admin.ClientRPNotify("Only the server owner can add staff.");
		return false;
	}
	if (GroupLevel < 0 || GroupLevel > 4)
	{
		Admin.ClientRPNotify("Invalid group level.  Use 0-4.");
		return false;
	}

	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.PlayerReplicationInfo == None)
	{
		Admin.ClientRPNotify("Player not found: " $ TargetName);
		return false;
	}

	IP = GetConnectionID(Target);
	Name = Target.PlayerReplicationInfo.PlayerName;
	if (IP == "")
	{
		Admin.ClientRPNotify("Could not resolve a network signature for that player.");
		return false;
	}

	Idx = StaffRegistry.Length;
	StaffRegistry.Length = StaffRegistry.Length + 1;
	StaffRegistry[Idx].UniqueID = IP;
	StaffRegistry[Idx].StaffIP = IP;
	StaffRegistry[Idx].StaffMemo = Name;
	StaffRegistry[Idx].GroupLevel = GroupLevel;
	SaveConfig();

	// If the target is online, push their new staff level so admin-only
	// client features (scoreboard wallet column, menus) activate at once.
	if (MilRPPlayer(Target) != None)
		MilRPPlayer(Target).GroupLevel = GroupLevel;

	Admin.ClientRPNotify(Name $ " added to staff at group " $ GroupLevel $ ".");
	Logf("STAFF", "Added " $ Name $ " (" $ IP $ ") to group " $ GroupLevel);
	return true;
}

function bool WarnPlayer(MilRPPlayer Admin, string TargetName, string Reason)
{
	local Controller Target;
	local MilRPPlayerReplicationInfo PRI;

	if (Admin == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.PlayerReplicationInfo == None)
		return false;

	PRI = GetRPPRI(Target);
	if (PRI != None)
		PRI.WarningCount++;

	if (MilRPPlayer(Target) != None)
		MilRPPlayer(Target).ClientRPNotify("WARNING: " $ Reason);
	BroadcastAdminAction(Admin, "warned", Target.PlayerReplicationInfo.PlayerName, Reason);
	return true;
}

function bool SlapPlayer(MilRPPlayer Admin, string TargetName, string Reason)
{
	local Controller Target;
	local Pawn P;

	if (Admin == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.Pawn == None)
		return false;

	P = Target.Pawn;
	P.Health -= 5;

	// Force the target out of any frozen/noclip physics so the impulse is visible.
	P.SetPhysics(PHYS_Walking);
	P.SetLocation(P.Location - Vector(Admin.Rotation) * 50.0);
	P.Velocity += VRand() * 400.0;

	BroadcastAdminAction(Admin, "slapped", Target.PlayerReplicationInfo.PlayerName, Reason);
	return true;
}

function bool SetFreeze(MilRPPlayer Admin, string TargetName, bool bFreeze, string Reason)
{
	local Controller Target;
	local MilRPPlayerReplicationInfo PRI;
	local string FreezeMsg;

	if (Admin == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None)
		return false;

	PRI = GetRPPRI(Target);
	if (PRI == None)
		return false;

	PRI.bFrozen = bFreeze;
	if (bFreeze)
		FreezeMsg = "You have been frozen.";
	else
		FreezeMsg = "You have been unfrozen.";
	if (MilRPPlayer(Target) != None)
		MilRPPlayer(Target).ClientRPNotify(FreezeMsg);

	if (bFreeze)
		BroadcastAdminAction(Admin, "frozen", Target.PlayerReplicationInfo.PlayerName, Reason);
	else
		BroadcastAdminAction(Admin, "unfrozen", Target.PlayerReplicationInfo.PlayerName, Reason);
	return true;
}

function bool ToggleFreeze(MilRPPlayer Admin, string TargetName, string Reason)
{
	local Controller Target;
	local MilRPPlayerReplicationInfo PRI;

	if (Admin == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None)
		return false;

	PRI = GetRPPRI(Target);
	if (PRI == None)
		return false;

	return SetFreeze(Admin, TargetName, !PRI.bFrozen, Reason);
}

function bool GotoPlayer(MilRPPlayer Admin, string TargetName)
{
	local Controller Target;

	if (Admin == None || Admin.Pawn == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.Pawn == None)
		return false;

	Admin.Pawn.SetLocation(Target.Pawn.Location + vect(0,0,64));
	BroadcastAdminAction(Admin, "teleported to", Target.PlayerReplicationInfo.PlayerName, "");
	return true;
}

function bool BringPlayer(MilRPPlayer Admin, string TargetName)
{
	local Controller Target;

	if (Admin == None || Admin.Pawn == None)
		return false;
	Target = FindPlayerByName(TargetName);
	if (Target == None || Target.Pawn == None)
		return false;

	Target.Pawn.SetLocation(Admin.Pawn.Location + vect(0,0,64));
	BroadcastAdminAction(Admin, "brought", Target.PlayerReplicationInfo.PlayerName, "");
	return true;
}

function bool ReportPos(MilRPPlayer Admin)
{
	if (Admin == None || Admin.Pawn == None)
		return false;
	Admin.ClientRPNotify("POS: " $ Admin.Pawn.Location);
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// RADIO
///////////////////////////////////////////////////////////////////////////////
function RadioMessage(MilRPPlayer Sender, int Channel, string Msg)
{
	local Controller C;
	local MilRPPlayerReplicationInfo SPRI, CPRI;
	local string Prefix;
	local bool bCanSend;

	if (Sender == None || Sender.PlayerReplicationInfo == None || RPGRI == None)
		return;

	SPRI = GetRPPRI(Sender);
	if (SPRI == None)
		return;

	bCanSend = true;
	if (Channel == 1 && SPRI.Rank < RPGRI.CommandChannelRank)
	{
		Sender.ClientRPNotify("Command radio requires rank " $ RPGRI.GetRankTitle(RPGRI.CommandChannelRank) $ ".");
		return;
	}
	if (Channel == 2 && !IsAdmin(Sender))
	{
		Sender.ClientRPNotify("Admin radio requires admin rights.");
		return;
	}

	Msg = Left(Msg, 120);
	switch (Channel)
	{
		case 0:		Prefix = "[RADIO " $ RPGRI.GetFactionTag(SPRI.FactionID) $ "] ";		break;
		case 1:		Prefix = "[COMMAND] ";												break;
		case 2:		Prefix = "[ADMIN] ";												break;
		default:		Prefix = "[RADIO] ";
	}

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (!IsRPParticipant(C) || MilRPPlayer(C) == None)
			continue;
		CPRI = GetRPPRI(C);
		if (CPRI == None)
			continue;

		if (Channel == 0)
		{
			// faction radio
			if (CPRI.FactionID != SPRI.FactionID)
				continue;
		}
		else if (Channel == 1)
		{
			// command radio: officers + admins
			if (CPRI.Rank < RPGRI.CommandChannelRank && !IsAdmin(C))
				continue;
		}
		// Channel 2 goes to all admins
		if (Channel == 2 && !IsAdmin(C))
			continue;

		MilRPPlayer(C).ClientRPChat(Sender.PlayerReplicationInfo, Prefix $ Sender.PlayerReplicationInfo.PlayerName $ ": " $ Msg, 'TeamSay');
	}
}


///////////////////////////////////////////////////////////////////////////////
// ALERT / LOCKDOWN
///////////////////////////////////////////////////////////////////////////////
function SetAlertLevel(MilRPPlayer Admin, byte NewLevel)
{
	if (Admin != None && !IsAdmin(Admin))
	{
		Admin.ClientRPNotify(FailNotAdmin);
		return;
	}

	if (RPGRI == None)
		return;

	if (NewLevel > 5)
		NewLevel = 5;

	if (RPWorld != None)
		RPWorld.SetAlertLevel(NewLevel);
	else
	{
		RPGRI.AlertLevel = NewLevel;
		RPGRI.bLockdown = (NewLevel >= 4);
	}

	BroadcastRP("DEFCON " $ NewLevel $ " - " $ RPGRI.GetAlertName());
	LogAdmin(Admin, "ALERT", "", "DEFCON " $ NewLevel);
}

function ToggleLockdown(MilRPPlayer Admin)
{
	if (RPGRI == None)
		return;

	RPGRI.bLockdown = !RPGRI.bLockdown;
	if (RPGRI.bLockdown)
	{
		BroadcastAdminAction(Admin, "enabled lockdown", "", "");
		if (!RPGRI.bLockdown)
			RPGRI.bLockdown = true; // sanity
	}
	else
		BroadcastAdminAction(Admin, "disabled lockdown", "", "");
}

function ToggleNoclip(MilRPPlayer Admin)
{
	local Pawn P;

	if (Admin == None)
		return;
	P = Admin.Pawn;
	if (P == None)
		return;

	Admin.bNoclip = !Admin.bNoclip;
	if (Admin.bNoclip)
	{
		Admin.bCheatFlying = true;
		P.Velocity = vect(0,0,0);
		P.Acceleration = vect(0,0,0);
		P.SetCollision(false, false, false);
		P.bCollideWorld = false;
		Admin.GotoState('PlayerHelicoptering');
		Admin.ClientRPNotify("[Admin] Noclip Enabled");
		LogAdmin(Admin, "NOCLIP", "", "enabled");
	}
	else
	{
		Admin.bCheatFlying = false;
		P.Velocity = vect(0,0,0);
		P.Acceleration = vect(0,0,0);
		P.SetCollision(true, true, true);
		P.bCollideWorld = true;
		P.SetPhysics(PHYS_Walking);
		Admin.GotoState('PlayerWalking');
		Admin.ClientRPNotify("[Admin] Noclip Disabled");
		LogAdmin(Admin, "NOCLIP", "", "disabled");
	}
	Admin.ClientToggleNoclip(Admin.bNoclip);
}


///////////////////////////////////////////////////////////////////////////////
// STRESS TEST BOTS
///////////////////////////////////////////////////////////////////////////////
function SetRPWorld(MilRPWorld W)
{
	RPWorld = W;
}

function RegisterTestBot(MilRPTestBot Bot)
{
	local int Idx;

	if (Bot == None)
		return;
	Idx = AcquireLiveRecord(Bot);
	LiveRecords[Idx].Data.Wallet = StartingCurrency;
	LiveRecords[Idx].Data.Bank = StartingBank;
	LiveRecords[Idx].Data.FactionID = 0;
	LiveRecords[Idx].Data.Rank = 0;
	LiveRecords[Idx].Data.RPScore = 0;
	LiveRecords[Idx].Data.DutySeconds = 0;
	LiveRecords[Idx].Data.Warnings = 0;
	if (Bot.PlayerReplicationInfo != None)
		Bot.PlayerReplicationInfo.PlayerName = "BOT_" $ TestBots.Length;
	TestBots[TestBots.Length] = Bot;
	Logf("TEST", "Registered stress bot " $ Bot $ " as " $ Bot.PlayerReplicationInfo.PlayerName);
}

function UnregisterTestBot(MilRPTestBot Bot)
{
	local int i;

	if (Bot == None)
		return;
	for (i = 0; i < TestBots.Length; i++)
		if (TestBots[i] == Bot)
		{
			TestBots.Remove(i, 1);
			break;
		}
	ReleaseLiveRecord(Bot);
	Logf("TEST", "Unregistered stress bot " $ Bot);
}

function SpawnStressBot()
{
	local MilRPTestBot Bot;

	if (TestBots.Length >= 16)
		return;
	Bot = Spawn(class'MilRPTestBot');
	if (Bot == None)
		warn("MilRPGameInfo::SpawnStressBot failed");
}

function RunBotAction(MilRPTestBot Bot)
{
	local MilRPPlayerReplicationInfo PRI;
	local string Fail;

	if (Bot == None)
		return;
	PRI = GetRPPRI(Bot);
	if (PRI == None)
		return;

	if (!PRI.bOnDuty && FRand() < 0.5)
		RequestDuty(Bot, true, Fail);
	else if (PRI.bOnDuty && FRand() < 0.3)
		RequestDuty(Bot, false, Fail);

	if (FRand() < 0.2)
		AddCurrency(Bot, Rand(50) - 25, "bot_sim");
}


///////////////////////////////////////////////////////////////////////////////
// MESSAGING
///////////////////////////////////////////////////////////////////////////////
function Logf(string Category, string Text)
{
	if (RPWorld != None)
		RPWorld.Logf(Category, Text);
}

function LogAdmin(MilRPPlayer Admin, string Action, string Target, string Details)
{
	if (RPWorld != None && RPWorld.Logger != None)
		RPWorld.Logger.LogAdmin(Admin, Action, Target, Details);
}

function LogEconomy(MilRPPlayer Player, string Action, int Amount, string Reason)
{
	if (RPWorld != None && RPWorld.Logger != None)
		RPWorld.Logger.LogEconomy(Player, Action, Amount, Reason);
}


// Base-wide broadcast: lands in the replicated GRI ring buffer (HUD feed) and
// optionally in every player's chat console.
function BroadcastRP(string Msg)
{
	local Controller C;

	if (Msg == "")
		return;
	if (RPGRI != None)
		RPGRI.PushBroadcast(Msg);
	if (bEchoBroadcastsToChat)
		for (C = Level.ControllerList; C != None; C = C.NextController)
			if (PlayerController(C) != None)
				PlayerController(C).ClientMessage(Msg);
}

function NotifyPlayer(Controller C, string Msg)
{
	if (PlayerController(C) != None && Msg != "")
		PlayerController(C).ClientMessage(Msg);
}

// Token substitution for localized templates:
//   %n = player name, %f = faction name, %r = rank title, %a = amount
function string FormatMsg(string Template, optional string PlayerName, optional string FactionName, optional string RankTitle, optional int Amount)
{
	local string S;

	S = Template;
	ReplaceText(S, "%n", PlayerName);
	ReplaceText(S, "%f", FactionName);
	ReplaceText(S, "%r", RankTitle);
	ReplaceText(S, "%a", string(Amount));
	return S;
}


///////////////////////////////////////////////////////////////////////////////
// UTILITY
///////////////////////////////////////////////////////////////////////////////
function MilRPPlayerReplicationInfo GetRPPRI(Controller C)
{
	if (C == None)
		return None;
	return MilRPPlayerReplicationInfo(C.PlayerReplicationInfo);
}

// Server browser rule keys.
function string GetRules()
{
	local string ResultSet;

	ResultSet = Super.GetRules();
	ResultSet = ResultSet $ "\\milrp\\1";
	ResultSet = ResultSet $ "\\factions\\" $ Factions.Length;
	ResultSet = ResultSet $ "\\paycheck\\" $ PaycheckInterval;
	ResultSet = ResultSet $ "\\enforcefactions\\" $ bEnforceFactions;
	return ResultSet;
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	// --- Ruleset
	bEnforceFactions=true
	bAllowFactionSwitch=true
	FactionSwitchCooldown=300
	MaxFactionSize=0
	DutyToggleCooldown=15
	DutyChangeMode=0
	bBlockSameFactionDamage=true
	SameFactionDamageScale=0.0
	bOffDutyCannotDamage=false
	bUseFactionSpawns=true
	bAllowMatchTimers=false
	HostTestName="Owner_Marcus"

	// --- Announcements
	bAnnounceDutyChanges=true
	bAnnouncePromotions=true
	bAnnounceFactionJoins=true
	bEchoBroadcastsToChat=false

	// --- Economy
	StartingCurrency=500
	StartingBank=0
	PaycheckInterval=300
	BasePaycheck=100
	RankPaycheckMultiplier=0.25
	OnDutyPayMultiplier=1.5
	OffDutyPayScale=0.25
	bAllowNegativeWallet=false
	bPaycheckDirectDeposit=true
	MaxBankBalance=1000000

	// --- Progression
	bAutoPromote=true
	RPScorePerDutyMinute=1
	RPScoreLossPerRDM=10
	FinePerRDM=250
	bPunishOffDutyKills=true
	bPunishSameFactionKills=true
	bPunishCivilianKills=true
	RankSpeedMultiplier=0.02

	// --- Persistence
	bPersistPlayerRecords=true
	MaxSavedRecords=512

	// --- Loadouts
	OffDutyLoadout=""

	Factions(0)=(Name="Civilian Population",Tag="CIV",Tint=(R=200,G=200,B=200,A=255),bCombatant=false,DutyLoadout="")
	Factions(1)=(Name="United States Army",Tag="USA",Tint=(R=70,G=130,B=60,A=255),bCombatant=true,DutyLoadout="Inventory.PistolWeapon,Inventory.MachinegunWeapon,Inventory.GrenadeWeapon")
	Factions(2)=(Name="Russian Ground Forces",Tag="RGF",Tint=(R=180,G=50,B=50,A=255),bCombatant=true,DutyLoadout="Inventory.PistolWeapon,Inventory.RifleWeapon,Inventory.GrenadeWeapon")
	Factions(3)=(Name="Military Police",Tag="MP",Tint=(R=60,G=90,B=200,A=255),bCombatant=true,DutyLoadout="Inventory.BatonWeapon,Inventory.PistolWeapon,Inventory.ShotgunWeapon")

	Ranks(0)=(Title="Recruit",MinScore=0)
	Ranks(1)=(Title="Private",MinScore=30)
	Ranks(2)=(Title="Corporal",MinScore=90)
	Ranks(3)=(Title="Sergeant",MinScore=180)
	Ranks(4)=(Title="Lieutenant",MinScore=360)
	Ranks(5)=(Title="Captain",MinScore=600)
	Ranks(6)=(Title="Major",MinScore=900)
	Ranks(7)=(Title="Colonel",MinScore=1400)
	Ranks(8)=(Title="General",MinScore=2000)
	RankHealthBonus(0)=0
	RankHealthBonus(1)=0
	RankHealthBonus(2)=5
	RankHealthBonus(3)=10
	RankHealthBonus(4)=15
	RankHealthBonus(5)=20
	RankHealthBonus(6)=25
	RankHealthBonus(7)=30
	RankHealthBonus(8)=35

	// --- Localized defaults (overridden by System\MilRP.int)
	MsgWelcome="%n reported for service."
	MsgPaycheck="Paycheck received: +$%a"
	MsgNoPaycheck="No paycheck this period - you are off duty."
	MsgOnDuty="%n is now ON DUTY."
	MsgOffDuty="%n is now OFF DUTY."
	MsgJoinedFaction="%n enlisted with %f."
	MsgPromoted="%n has been promoted to %r."
	MsgDemoted="%n has been demoted to %r."
	MsgRDM="%n has been penalised for random deathmatch."
	MsgFineApplied="Fine applied: -$%a"
	MsgPaycheckPending="Paycheck ready: collect $%a"
	MsgPaycheckCollected="Collected $%a"
	MsgBankTransfer="Bank: $%a"
	MsgRadio="[%c] %n: %m"
	MsgFrozen="%n has been frozen"
	MsgUnFrozen="%n has been unfrozen"

	// --- Group hierarchy
	GroupNames(0)="Player"
	GroupNames(1)="Moderator"
	GroupNames(2)="Admin"
	GroupNames(3)="SuperAdmin"
	GroupNames(4)="Owner"
	StaffRegistry=(UniqueID="",StaffMemo="",GroupLevel=0)
	BanRegistry=(BannedID="",BannedIP="",Reason="")

	FailNoFaction="You must join a faction before going on duty."
	FailNonCombatant="Your faction has no duty roster."
	FailCooldown="Wait %a seconds before doing that again."
	FailFactionFull="That faction is full."
	FailNoSwitch="Faction changes are disabled on this server."
	FailInvalidFaction="Unknown faction."
	FailNotAdmin="Admin access required."
	FailFunds="Insufficient funds."

	// --- Engine / DeathMatch wiring
	GameName="Military Roleplay"
	BeaconName="MilRP"
	MaxPlayers=16
	MinPlayers=0
	InitialBots=0
	bAutoFillBots=false
	bTeamGame=false
	bChangeLevels=false
	bForceRespawn=true
	bMustJoinBeforeStart=false
	bPlayersMustBeReady=false
	bTournament=false
	bExtendedScoring=false
	GoalScore=0
	TimeLimit=0
	MaxLives=0
	MinNetPlayers=1
	NetWait=2
	CountDown=2
	SpawnProtectionTime=3.0

	PlayerControllerClassName="MilRP.MilRPPlayer"
	DefaultPlayerClassName="MultiStuff.MpMilitary"
	DefaultEnemyRosterClass="MultiGame.TeamMilitary"
	HUDType="MilRP.MilRPHUD"
	ScoreBoardType="MultiGame.DMScoreBoard"
	GameReplicationInfoClass=class'MilRP.MilRPGameReplicationInfo'
	DeathMessageClass=class'MultiGame.xDeathMessage'
	MutatorClass="MultiGame.xMutator"
	LevelRulesClass=class'MultiGame.LevelGamePlay'
	MapNameGameCode="d"
	MapListType="MultiGame.DMMapList"

	GameBaseEquipment(0)=(weapclass=class'Inventory.UrethraWeapon')
	GameBaseEquipment(1)=(weapclass=class'Inventory.FootWeapon')

	// --- Dev diagnostics: candidate prop StaticMesh paths
	bMeshProbe=false
	MeshProbeList(0)="Zo_BaseMeshes.zo_base_ammocrate2"
	MeshProbeList(1)="Zo_BaseMeshes.zo_base_ammocrate3"
	MeshProbeList(2)="Zo_BaseMeshes.zo_base_ammobarrel"
	MeshProbeList(3)="Zo_BaseMeshes.zo_base_opencrate"
	MeshProbeList(4)="Zo_BaseMeshes.zo_base_sandbags"
	MeshProbeList(5)="Zo_BaseMeshes.zo_base_barrier1"
	MeshProbeList(6)="Zo_BaseMeshes.zo_base_bunker1"
	MeshProbeList(7)="Zo_BaseMeshes.zo_base_bunker2"
	MeshProbeList(8)="Zo_BaseMeshes.zo_base_bunker3"
	MeshProbeList(9)="Zo_BaseMeshes.zo_base_watchtower"
	MeshProbeList(10)="Zo_BaseMeshes.zo_base_camothing"
	MeshProbeList(11)="Zo_BaseMeshes.zo_base_lightpole"
	MeshProbeList(12)="Zo_BaseMeshes.zo_base_door1"
	MeshProbeList(13)="Zo_BaseMeshes.zo_base_door2"
	MeshProbeList(14)="Zo_BaseMeshes.zo_base_heavydoorway"
	MeshProbeList(15)="Zo_BaseMeshes.zo_base_cautiondoorway"
	MeshProbeList(16)="Zo_BaseMeshes.zo_base_radarbase"
	MeshProbeList(17)="Zo_BaseMeshes.zo_base_desk1"
	MeshProbeList(18)="Zo_BaseMeshes.zo_base_newapc"
	MeshProbeList(19)="Zo_BaseMeshes.zo_base_newtank"
	MeshProbeList(20)="Zo_Meshes.zo_ammobox1"
	MeshProbeList(21)="Zo_Meshes.zo_guncabinet_door"
	MeshProbeList(22)="Zo_Meshes.zo_guncabinet_shelf"
	MeshProbeList(23)="Zo_Meshes.zo_lamptable"
	MeshProbeList(24)="Zo_Meshes.zo_kennel_fence"
	MeshProbeList(25)="Zo_Meshes.zo_hanginglight1"
	MeshProbeList(26)="Zo_Meshes.searchlight"
	MeshProbeList(27)="Zo_Meshes.WIndows_and_Doors.zo_guncabinet_door"
	MeshProbeList(28)="Zo_Meshes.Doors.zo_boiler_door"
	MeshProbeList(29)="Zo_Meshes.zo_boiler_door"
	MeshProbeList(30)="dj-protostuff.Barricade"
	MeshProbeList(31)="dj-protostuff.Barricade_Police"
	MeshProbeList(32)="dj-protostuff.Barricade_Warning"
	MeshProbeList(33)="dj-protostuff.Couch_Sectional"
	MeshProbeList(34)="dj-protostuff.Couch_Section_A"
	MeshProbeList(35)="dj-protostuff.Lamp_Street"
	MeshProbeList(36)="dj-protostuff.Sign_DoNotEnter"
	MeshProbeList(37)="dj-protostuff.Table_Dining"
	MeshProbeList(38)="dj-protostuff.Table_Patio"
	MeshProbeList(39)="dj-protostuff.table_small"
	MeshProbeList(40)="stv-protocrap.couch"
	MeshProbeList(41)="stv-protocrap.coffeetable"
	MeshProbeList(42)="stv-protocrap.bookshelf"
	MeshProbeList(43)="stv-protocrap.table"
	MeshProbeList(44)="stv-protocrap.fenceslats"
	MeshProbeList(45)="stv-protocrap.light"
	MeshProbeList(46)="ben_mesh.locker_ben"
	MeshProbeList(47)="ben_mesh.locker_functional01_ben"
	MeshProbeList(48)="ben_mesh.locker_functional02_ben"
	MeshProbeList(49)="ben_mesh.lockers_ben"
	MeshProbeList(50)="ben_mesh.poolTable_ben"
	MeshProbeList(51)="ben_mesh.lightFixture01_ben"
	MeshProbeList(52)="ben_mesh.indoor_ENV.locker_ben"
	MeshProbeList(53)="JW_Meshes.wood_crate_timb"
	MeshProbeList(54)="mex_props.roadbarrier_curve"
	MeshProbeList(55)="mex_props.outdoor.roadbarrier_curve"
	MeshProbeList(56)="mex_props.rws_employeedesk"
	MeshProbeList(57)="mex_props.metal_door1"
	MeshProbeList(58)="mex_props.boxlamppost"
	MeshProbeList(59)="mex_props.mex_flourescentlight"
	MeshProbeList(60)="mex_props.zo_garagedoor"
	MeshProbeList(61)="p2-outdoors-SW.dumpster"
	MeshProbeList(62)="p2-outdoors-SW.outdoors.dumpster"
	MeshProbeList(63)="p2-outdoors-SW.fence"
	MeshProbeList(64)="p2-outdoors-SW.FENCES.fence"
	MeshProbeList(65)="p2-outdoors-SW.rustedfence_sw"
	MeshProbeList(66)="p2-outdoors-SW.slatfence"
	MeshProbeList(67)="Zo_Generic.zo_generic_floodlight_stand"
	MeshProbeList(68)="Zo_Generic.zo_generic_floodlight_head"
	MeshProbeList(69)="Zo_Generic.zo_generic_walllight"
	MeshProbeList(70)="Zo_Generic.Lighting.zo_generic_walllight"
	MeshProbeList(71)="Zo_Generic.zo_generic_rooflight"
	MeshProbeList(72)="furniture-STV.table"
	MeshProbeList(73)="furniture-STV.cabinet"
	MeshProbeList(74)="furniture-STV.shelf"
	MeshProbeList(75)="furniture-STV.deskpic"
	MeshProbeList(76)="furniture-STV.Misc.PIZZASLICE"
	MeshProbeList(77)="Zo_AsylumMeshes.zo_as_roundtable"
	MeshProbeList(78)="Zo_AsylumMeshes.Surgical_Lamp"
	MeshProbeList(79)="AW7Mesh.AMN.Box"
	MeshProbeList(80)="stuff.stuff1.Package"
	MeshProbeList(81)="stuff.stuff1.Gift"
	MeshProbeList(82)="stuff.stuff1.DogTreatBox"
	MeshProbeList(83)="P2EMeshes.camo_banner"
	MeshProbeList(84)="Zo_Industry_Meshes.zo_tallchainlinkfence"
	MeshProbeList(85)="Zo_Industry_Meshes.zo_kennel_fence"
	MeshProbeList(86)="Zo_Industry_Meshes.zo_kennel_door"
	MeshProbeList(87)="Zo_Industry_Meshes.zo_palletewood"
	MeshProbeList(88)="Zo_Industry_Meshes.zo_warehouse_shelf"
	MeshProbeList(89)="Zo_Industry_Meshes.zo_streetlight1"
	MeshProbeList(90)="Zo_Industry_Meshes.zo_glassdoor"
	MeshProbeList(91)="Zo_Industry_Meshes.WIndows_and_Doors.zo_glassdoor"
	MeshProbeList(92)="library-sw.outdoors.blockery"
	MeshProbeList(93)="library-sw.blockery"
	MeshProbeList(94)="p2-outdoors-SW.Signage.sign"
	MeshProbeList(95)="Zo_AsylumMeshes.zo_streetlight1"
}
