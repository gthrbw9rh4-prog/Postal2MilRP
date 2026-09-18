///////////////////////////////////////////////////////////////////////////////
// MilRPPlayer.uc
//
// Roleplay player controller. Sits on top of the stock multiplayer controller
// chain (xMpPlayer -> DudePlayer -> MpPlayer -> P2Player) so all of Postal 2's
// match-intro, loadout and camera behaviour is preserved.
//
// Responsibilities:
//   * owner-only replication of the wallet (nobody else pays for it)
//   * console/exec commands that forward roleplay requests to MilRPGameInfo
//     through server RPCs (the client never mutates RP state itself)
//   * proximity roleplay chat (/me, /do, local say) with a server-side radius
//   * admin commands that defer authorisation to MilRPGameInfo.IsAdmin()
//   * a small client-side notification queue the HUD renders as toasts
//
// Networking: every Server* function is "reliable if (Role < ROLE_Authority)",
// every Client* function is "reliable if (Role == ROLE_Authority)". Wallet is
// a plain replicated variable gated on bNetOwner so it costs one int when it
// changes and nothing otherwise.
///////////////////////////////////////////////////////////////////////////////
class MilRPPlayer extends xMpPlayer
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
var config float		LocalChatRadius;		// world units for /me /do /l (default ~ 25 m)
var config float		NoticeLifetime;			// seconds a HUD toast stays visible
var config int			MaxNotices;				// toast queue depth (1..8)
var config bool			bPlayNoticeSound;		// beep on incoming notice

var config float		MenuTimeout;			// seconds a point menu stays open
var config float		InteractRadius;			// how far the HUD scans for a point prompt
var config float		PayRadius;				// max distance for /pay
var config int			MaxBankBalance;			// cap on bank balance (0 = no cap)

// Localized prefixes for roleplay chat (MilRP.int)
var localized string	MePrefix;				// "* "
var localized string	DoPrefix;				// "** "
var localized string	LocalPrefix;			// "[Local] "
var localized string	WalletLabel;			// "Wallet"
var localized string	FactionListHeader;		// "Factions:"
var localized string	RankListHeader;			// "Ranks:"
var localized string	StatusFormat;			// "%f | %r | %d | $%a"
var localized string	DutyOnText;				// "ON DUTY"
var localized string	DutyOffText;			// "OFF DUTY"
var localized string	NoFactionText;			// "No faction"
var localized string	MenuHint;				// "Type /pick <number> or close with /close"
var localized string	RadioPrefix;			// "[RADIO] "
var localized string	CommandPrefix;			// "[COMMAND] "
var localized string	AdminPrefix;			// "[ADMIN] "
var localized string	PayPrefix;				// "[PAY] "
var localized string	BankLabel;				// "Bank"
var localized string	ChatPrefix;				// default "[Chat] "
var localized string	EmotePrefix;			// "* "
var localized string	DoEmotePrefix;			// "** "
var localized string	FactionChatPrefix;		// "[Faction] "
var localized string	AdminChatPrefix;		// "[Admin] "


///////////////////////////////////////////////////////////////////////////////
// CHAT CONFIG
///////////////////////////////////////////////////////////////////////////////
var config int			ChatMaxLength;			// max characters in one line
var config string		VoiceChatPrompt;		// printed to console + shown as HUD toast


///////////////////////////////////////////////////////////////////////////////
// REPLICATED STATE
///////////////////////////////////////////////////////////////////////////////
var int					Wallet;					// authoritative copy pushed by MilRPGameInfo
var int					BankBalance;			// owner-only replicated
var int					PendingPaycheck;		// owner-only, set when payday fires in physical-pay mode
var bool				bPaycheckReady;			// owner-only, true when a paycheck can be collected
var byte				GroupLevel;				// owner-only replicated staff group (0-4, from CheckPermission)


///////////////////////////////////////////////////////////////////////////////
// CLIENT-ONLY STATE (never replicated)
///////////////////////////////////////////////////////////////////////////////
struct RPNotice
{
	var string	Text;
	var float	Time;		// Level.TimeSeconds when received
};
var array<RPNotice>		Notices;

struct RPMenu
{
	var string		Title;
	var string		Options[8];
	var int			Count;
	var MilRPInteractPoint Source;
	var float		OpenTime;
};
var RPMenu				CurrentMenu;
var bool				bMenuOpen;

// Client-only chat state.
struct RPChatLine
{
	var PlayerReplicationInfo	Sender;
	var string					Text;
	var name					Type;
	var float					Time;
};
var array<RPChatLine>	ChatLog;
var int					ChatScrollOffset;		// how far back the player has scrolled in ChatLog

// Graphical admin menu
var bool				bShowAdminMenu;			// client-only: HUD overlay open
var int					SelectedPlayerIndex;	// index in the player list
var int					SelectedActionIndex;	// index in the action grid
var string				AdminMenuReason;		// default reason for menu-driven actions
var bool				bAdminMenuActionFocus;	// true = focus is on the right action grid
var bool				bNoclip;				// server: current noclip flight state
var MilRPAdminInteraction	ActiveAdminInteraction;	// client-only: current mouse admin board
var MilRPSpawnMenu		ActiveSpawnMenu;		// client-only: current mouse spawn menu
var MilRPArmoryInteraction	ActiveArmoryMenu;		// client-only: armory crate GUI
var MilRPShopInteraction	ActiveShopMenu;			// client-only: quartermaster GUI
var MilRPDEFCONInteraction	ActiveDEFCONMenu;		// client-only: DEFCON console GUI
var MilRPScoreboardMenu		ActiveScoreboard;		// client-only: Tab scoreboard overlay
var MilRPInteractPoint		ActiveInteractPoint;	// server-only: locker terminal in use

// Server-only: shop item classes this player has bought. Loadout stripping
// (RemoveLoadout on duty/faction changes) skips these classes so a purchased
// gun is never deleted out of the player's hands and swapped back to the
// default rifle by SwitchToBestWeapon.
var array<class>			PurchasedItems;

// Spawn override requested by MilRPGameInfo.FindPlayerStart and applied in RestartPlayer.
var vector				DesiredSpawnLocation;
var rotator				DesiredSpawnRotation;

var config int			MaxChatLogLines;		// max chat history kept on client
var config float		ChatLogLifetime;		// seconds before a chat line fades out


replication
{
	// Server -> owning client only
	reliable if ( bNetDirty && bNetOwner && (Role == ROLE_Authority) )
		BankBalance, PendingPaycheck, bPaycheckReady, GroupLevel;

	// Wallet is replicated to all clients so the admin dashboard can inspect any player
	reliable if ( bNetDirty && (Role == ROLE_Authority) )
		Wallet;

	reliable if ( Role == ROLE_Authority )
		ClientRPNotify, ClientRPChat, ClientOpenMenu, ClientCloseMenu,
		ClientOpenAdminMenu, ClientCloseAdminMenu, ClientOpenSpawnMenu,
		ClientOpenArmoryMenu, ClientOpenShopMenu, ClientOpenDEFCONMenu,
		ClientToggleNoclip, ClientForceSyncIdentity, ClientForceWeapon;

	// Client -> server requests
	reliable if ( Role < ROLE_Authority )
		ServerRequestFaction, ServerToggleDuty, ServerRPEmote, ServerLocalSay,
		ServerListFactions, ServerListRanks, ServerRPStatus,
		ServerAdminSetRank, ServerAdminSetFaction, ServerAdminGiveMoney, ServerAdminBroadcast,
		ServerMenuPick, ServerRadio, ServerPay, ServerBank, ServerAdminAction,
		ServerAdminMenuToggle, ServerAdminMenuAction, ServerReceiveChat,
		ServerSteamFallback, ServerRequestSpawnMenu,
		ServerSpawnWeapon, ServerSpawnWeaponPickup, ServerSetSkin, ServerSpawnProp,
		ServerClearProps, ServerArmoryResupply, ServerShopBuy, ServerInteractClosed,
		ServerUpdateDEFCON, ServerInteractWithTarget, ServerRespawnMe;
}


///////////////////////////////////////////////////////////////////////////////
// STARTUP
///////////////////////////////////////////////////////////////////////////////
simulated function PostBeginPlay()
{
	Super.PostBeginPlay();
	MaxNotices = Clamp(MaxNotices, 1, 8);
	NoticeLifetime = FMax(1.0, NoticeLifetime);
	LocalChatRadius = FMax(64.0, LocalChatRadius);
	MenuTimeout = FMax(3.0, MenuTimeout);
	InteractRadius = FMax(64.0, InteractRadius);
	PayRadius = FMax(64.0, PayRadius);
	ChatMaxLength = Clamp(ChatMaxLength, 32, 256);
	MaxChatLogLines = Clamp(MaxChatLogLines, 1, 128);
	ChatLogLifetime = FMax(60.0, ChatLogLifetime);
}

// Fallback HUD if the game type fails to push HUDType; normally MilRPGameInfo
// already specifies MilRP.MilRPHUD.
function SpawnDefaultHUD()
{
	myHUD = spawn(class'MilRPHUD', self);
}


///////////////////////////////////////////////////////////////////////////////
// ECONOMY (server side, called by MilRPGameInfo)
// The HUD detects deltas by comparing Wallet against its own cached copy, so
// no PostNetReceive/bNetNotify plumbing is required here.
///////////////////////////////////////////////////////////////////////////////
function SetWallet(int NewAmount)
{
	if (Role == ROLE_Authority)
		Wallet = NewAmount;
}

function SetBank(int NewAmount)
{
	if (Role == ROLE_Authority)
		BankBalance = NewAmount;
}

function SetPaycheck(int Amount, bool bReady)
{
	if (Role == ROLE_Authority)
	{
		PendingPaycheck = Amount;
		bPaycheckReady = bReady;
	}
}


///////////////////////////////////////////////////////////////////////////////
// HELPERS
///////////////////////////////////////////////////////////////////////////////
function MilRPGameInfo GetRPGame()
{
	return MilRPGameInfo(Level.Game);
}

simulated function MilRPGameReplicationInfo GetRPGRI()
{
	return MilRPGameReplicationInfo(GameReplicationInfo);
}

simulated function MilRPPlayerReplicationInfo GetRPPRI()
{
	return MilRPPlayerReplicationInfo(PlayerReplicationInfo);
}

simulated function MilRPWorld GetRPWorld()
{
	local MilRPWorld W;

	foreach DynamicActors(class'MilRPWorld', W)
		return W;
	return None;
}

simulated function bool IsOnDuty()
{
	local MilRPPlayerReplicationInfo PRI;

	PRI = GetRPPRI();
	return (PRI != None && PRI.bOnDuty);
}

// Resolves a faction argument that may be an index or a (partial) name/tag.
function int ResolveFactionArg(string Arg)
{
	local MilRPGameReplicationInfo GRI;
	local int i;
	local string Needle;

	GRI = GetRPGRI();
	if (GRI == None || Arg == "")
		return -1;

	Needle = Caps(Arg);
	if (Needle == string(int(Needle)) && int(Needle) >= 0 && int(Needle) < GRI.FactionCount)
		return int(Needle);

	for (i = 0; i < GRI.FactionCount; i++)
		if (Caps(GRI.FactionTags[i]) == Needle)
			return i;
	for (i = 0; i < GRI.FactionCount; i++)
		if (InStr(Caps(GRI.FactionNames[i]), Needle) >= 0)
			return i;
	return -1;
}

function int ResolveRankArg(string Arg)
{
	local MilRPGameReplicationInfo GRI;
	local int i;
	local string Needle;

	GRI = GetRPGRI();
	if (GRI == None || Arg == "")
		return -1;

	Needle = Caps(Arg);
	if (Needle == string(int(Needle)) && int(Needle) >= 0 && int(Needle) < GRI.RankCount)
		return int(Needle);

	for (i = 0; i < GRI.RankCount; i++)
		if (InStr(Caps(GRI.RankTitles[i]), Needle) >= 0)
			return i;
	return -1;
}

// Sends Msg to every player whose view target is within Radius of Origin.
function BroadcastLocal(vector Origin, float Radius, PlayerReplicationInfo SenderPRI, string Msg, name Type)
{
	local Controller C;
	local Actor Ref;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (MilRPPlayer(C) == None)
			continue;
		Ref = C.Pawn;
		if (Ref == None)
			Ref = PlayerController(C).ViewTarget;
		if (Ref == None)
			Ref = C;
		if (VSize(Ref.Location - Origin) <= Radius)
			MilRPPlayer(C).ClientRPChat(SenderPRI, Msg, Type);
	}
}


///////////////////////////////////////////////////////////////////////////////
// PLAYER COMMANDS (console: "joinfaction usa", "duty", "me salutes", ...)
// Each exec runs on the client and forwards to the server RPC below it.
///////////////////////////////////////////////////////////////////////////////
exec function JoinFaction(string FactionArg)
{
	ServerRequestFaction(FactionArg);
}

exec function RequestFaction(int FactionID)
{
	ServerRequestFaction(string(FactionID));
}

exec function ToggleDuty()
{
	ServerToggleDuty();
}

exec function Duty()
{
	ServerToggleDuty();
}

exec function Me(string Msg)
{
	if (Msg != "")
		ServerRPEmote(0, Msg);
}

exec function DoEmote(string Msg)
{
	if (Msg != "")
		ServerRPEmote(1, Msg);
}

exec function L(string Msg)
{
	if (Msg != "")
		ServerLocalSay(Msg);
}

exec function LocalSay(string Msg)
{
	if (Msg != "")
		ServerLocalSay(Msg);
}

exec function Factions()
{
	ServerListFactions();
}

exec function RanksList()
{
	ServerListRanks();
}

exec function RPStatus()
{
	ServerRPStatus();
}

// Chat / slash command entry point.  Bound to the native Talk prompt (B key).
// The server-side ServerReceiveChat does all parsing and routing.
// Chat / slash command entry point.  Bound to the native Talk prompt (B key).
// Client-only menu commands (pick / close) are handled locally; everything else
// is passed to the server-side ServerReceiveChat for parsing and routing.
exec function Say(string Msg)
{
	local string Cmd, Arg;
	local int Space;

	if (Msg == "")
		return;

	if (Left(Msg, 1) == "/")
	{
		Space = InStr(Msg, " ");
		if (Space < 0)
		{
			Cmd = Caps(Mid(Msg, 1));
			Arg = "";
		}
		else
		{
			Cmd = Caps(Mid(Msg, 1, Space - 1));
			Arg = Mid(Msg, Space + 1);
		}

		// Client-only menu commands.
		if (Cmd == "PICK" || Cmd == "SELECT")
		{
			if (Arg != "" && Arg == string(int(Arg)))
				PickMenu(int(Arg));
		}
		else if (Cmd == "CLOSE")
		{
			CloseMenuCmd();
		}
		else if (Cmd == "RESETMENU" || Cmd == "RESETMENUS" || Cmd == "RESETPANEL")
		{
			ResetMenuState();
		}
		else if (Cmd == "ADMIN")
		{
			LocalOpenAdminMenu();
			ServerReceiveChat(Msg);
		}
		else
		{
			// Everything else (slash chat, duty, join, admin, etc.) goes to the server.
			ServerReceiveChat(Msg);
		}
	}
	else
	{
		// Plain proximity chat.
		ServerReceiveChat(Msg);
	}
}


///////////////////////////////////////////////////////////////////////////////
// SERVER RPCs - player
///////////////////////////////////////////////////////////////////////////////
function ServerRequestFaction(string FactionArg)
{
	local MilRPGameInfo Game;
	local MilRPPlayerReplicationInfo PRI;
	local int FactionID;
	local string FailReason;

	Game = GetRPGame();
	if (Game == None)
		return;

	FactionID = ResolveFactionArg(FactionArg);
	if (FactionID < 0)
	{
		ClientRPNotify("Invalid faction. Use /join [1-" $ Game.Factions.Length $ "] or see /factions.");
		return;
	}

	PRI = GetRPPRI();
	if (PRI == None)
	{
		ClientRPNotify(Game.FailInvalidFaction);
		return;
	}

	if (!Game.RequestFaction(self, FactionID, FailReason))
	{
		ClientRPNotify(FailReason);
		return;
	}

	// Equip the new faction's default duty kit immediately.
	if (Pawn != None && Pawn.Health > 0)
	{
		if (Game.IsCombatantFaction(FactionID))
			Game.SetDutyInternal(self, PRI, true, true);
		else
			Game.SetDutyInternal(self, PRI, false, true);
	}

	ClientRPNotify("You have joined the " $ Game.Factions[FactionID].Name $ ".");
}

function ServerToggleDuty()
{
	local MilRPGameInfo Game;
	local MilRPPlayerReplicationInfo PRI;
	local string FailReason;

	Game = GetRPGame();
	PRI = GetRPPRI();
	if (Game == None || PRI == None)
		return;

	if (!Game.RequestDuty(self, !PRI.bOnDuty, FailReason))
		ClientRPNotify(FailReason);
}

// Mode 0 = /me (first person action), 1 = /do (environment description)
function ServerRPEmote(byte Mode, string Msg)
{
	local vector Origin;
	local string Line;

	if (Msg == "" || PlayerReplicationInfo == None)
		return;
	Msg = Left(Msg, 200);

	if (Pawn != None)
		Origin = Pawn.Location;
	else
		Origin = Location;

	if (Mode == 0)
		Line = MePrefix $ PlayerReplicationInfo.PlayerName @ Msg;
	else
		Line = DoPrefix $ Msg @ "((" $ PlayerReplicationInfo.PlayerName $ "))";

	BroadcastLocal(Origin, LocalChatRadius, PlayerReplicationInfo, Line, 'Event');
}

function ServerLocalSay(string Msg)
{
	local vector Origin;

	if (Msg == "" || PlayerReplicationInfo == None)
		return;
	Msg = Left(Msg, 200);

	if (Pawn != None)
		Origin = Pawn.Location;
	else
		Origin = Location;

	BroadcastLocal(Origin, LocalChatRadius, PlayerReplicationInfo,
		LocalPrefix $ PlayerReplicationInfo.PlayerName $ ": " $ Msg, 'Event');
}


///////////////////////////////////////////////////////////////////////////////
// CHAT / SLASH COMMAND ROUTER (server-side)
///////////////////////////////////////////////////////////////////////////////
// Parses the first character of the line.  Plain text goes to proximity chat;
// leading slash commands are stripped and routed to the matching mod function.
function ServerReceiveChat(string Msg)
{
	local string Cmd, Arg;
	local int Space;

	if (Msg == "" || PlayerReplicationInfo == None)
		return;
	Msg = Left(Msg, ChatMaxLength);

	if (Left(Msg, 1) == "/")
	{
		Space = InStr(Msg, " ");
		if (Space < 0)
		{
			Cmd = Caps(Mid(Msg, 1));
			Arg = "";
		}
		else
		{
			Cmd = Caps(Mid(Msg, 1, Space - 1));
			Arg = Mid(Msg, Space + 1);
		}

		switch (Cmd)
		{
			case "DUTY":					ToggleDuty();									break;
			case "JOIN":
			case "FACTION":
			case "JOINFACTION":			if (Arg != "") JoinFaction(Arg);					break;
			case "CMDS":
		case "COMMANDS":
		case "HELP":					ServerListCommands();							break;
		case "FACTIONS":				Factions();										break;
			case "RANKS":					RanksList();									break;
			case "STATUS":					RPStatus();										break;
			case "SETRANK":					SetRankCmd(Arg);									break;
			case "SETFACTION":				SetFactionCmd(Arg);									break;
			case "SETSPAWN":				if (Arg != "") SetSpawnCmd(Arg);									break;
			case "GIVEMONEY":				GiveMoneyCmd(Arg);									break;
			case "ANNOUNCE":				Announce(Arg);									break;
			case "PAY":					if (Arg != "") Pay(Arg);							break;
			case "WITHDRAW":
			case "WD":					if (Arg != "" && Arg == string(int(Arg))) Withdraw(int(Arg)); break;
			case "DEPOSIT":
			case "DP":					if (Arg != "" && Arg == string(int(Arg))) Deposit(int(Arg));	break;
			case "TRANSFER":
			case "TR":					if (Arg != "") Transfer(Arg);							break;
			case "KICK":					if (Arg != "") Kick(Arg);								break;
			case "BAN":					if (Arg != "") Ban(Arg);								break;
			case "WARN":					if (Arg != "") WarnPlayer(Arg);							break;
			case "FINE":					if (Arg != "") Fine(Arg);								break;
			case "FREEZE":					if (Arg != "") Freeze(Arg);								break;
			case "UNFREEZE":
			case "THAW":					if (Arg != "") UnFreeze(Arg);								break;
			case "GOTO":					if (Arg != "") GotoPlayer(Arg);							break;
			case "BRING":					if (Arg != "") BringPlayer(Arg);							break;
			case "SLAP":					if (Arg != "") Slap(Arg);							break;
			case "CLEARPROPS":
		case "CLEARPROP":
		case "CLEARSANDBOX":							ServerClearProps();							break;
		case "POS":					Pos();											break;
			case "ALERT":
			case "DEFCON":				if (Arg != "" && Arg == string(int(Arg))) SetAlert(int(Arg));	break;
			case "ADMIN":					ServerAdminMenuToggle();									break;
			case "ADDSTAFF":				if (Arg != "") AddStaffCmd(Arg);									break;
		case "REASON":					if (Arg != "") { AdminMenuReason = Arg; ClientRPNotify("Admin reason set: " $ Arg); } else { AdminMenuReason = "Admin menu"; ClientRPNotify("Admin reason reset."); } break;
		case "NOCLIP":
		case "FLY":					ServerAdminAction("noclip", "", 0, "");								break;
		case "ME":					if (Arg != "") ServerRPEmote(0, Arg);						break;
			case "DO":					if (Arg != "") ServerRPEmote(1, Arg);						break;
			case "F":
			case "FACTIONCHAT":			if (Arg != "") ServerFactionChat(Arg);						break;
			case "A":
			case "ADMINCHAT":			if (Arg != "") ServerAdminChat(Arg);						break;
			case "L":
			case "LOCAL":
			case "SAY":				if (Arg != "") ServerLocalSay(Arg);							break;
			case "MYNAME":				if (Arg != "") MyNameCmd(Arg);							break;
			case "STEAMFALLBACK":			if (Arg != "") ServerSteamFallback(Arg);							break;
			default:
				// Unknown slash: still echo it as local chat for visibility.
				ServerLocalSay(Msg);
				break;
		}
	}
	else
	{
		// Plain proximity chat.
		ServerLocalSay(Msg);
	}
}

function ServerFactionChat(string Msg)
{
	local Controller C;
	local MilRPPlayerReplicationInfo SPRI, CPRI;
	local string Line;

	if (Msg == "" || PlayerReplicationInfo == None)
		return;
	SPRI = GetRPPRI();
	if (SPRI == None || SPRI.FactionID == 255)
	{
		ClientRPNotify("You are not in a faction.");
		return;
	}

	Msg = Left(Msg, ChatMaxLength);
	Line = FactionChatPrefix $ PlayerReplicationInfo.PlayerName $ ": " $ Msg;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (MilRPPlayer(C) == None)
			continue;
		CPRI = MilRPPlayer(C).GetRPPRI();
		if (CPRI == None)
			continue;
		if (CPRI.FactionID == SPRI.FactionID)
			MilRPPlayer(C).ClientRPChat(PlayerReplicationInfo, Line, 'TeamSay');
	}
}

function ServerAdminChat(string Msg)
{
	local Controller C;
	local MilRPGameInfo Game;
	local string Line;

	Game = GetRPGame();
	if (Game == None)
		return;
	if (!Game.IsAdmin(self))
	{
		ClientRPNotify(Game.FailNotAdmin);
		return;
	}
	if (Msg == "" || PlayerReplicationInfo == None)
		return;

	Msg = Left(Msg, ChatMaxLength);
	Line = AdminChatPrefix $ PlayerReplicationInfo.PlayerName $ ": " $ Msg;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (MilRPPlayer(C) == None)
			continue;
		if (Game.IsAdmin(C))
			MilRPPlayer(C).ClientRPChat(PlayerReplicationInfo, Line, 'TeamSay');
	}
}

// /cmds - dumps every operational slash command into the chat log.
function ServerListCommands()
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None)
		return;

	ClientRPChat(None, "=== MilRP Commands ===", 'Event');
	ClientRPChat(None, "  /duty - toggle on/off duty", 'Event');
	ClientRPChat(None, "  /join <faction> - join faction (id, tag, or name)", 'Event');
	ClientRPChat(None, "  /factions - list factions", 'Event');
	ClientRPChat(None, "  /ranks - list ranks", 'Event');
	ClientRPChat(None, "  /status - show your RP status", 'Event');
	ClientRPChat(None, "  /myname <name> - set RP name", 'Event');
	ClientRPChat(None, "  /pay <player> <amount> - hand cash to a player", 'Event');
	ClientRPChat(None, "  /withdraw|/wd <amt>, /deposit|/dp <amt>, /transfer|/tr <player> <amt>", 'Event');
	ClientRPChat(None, "  /me <action>, /do <action> - roleplay emotes", 'Event');
	ClientRPChat(None, "  /f <msg> faction chat, /l <msg> local say", 'Event');
	if (Game.IsAdmin(self))
	{
		ClientRPChat(None, "--- Staff ---", 'Event');
		ClientRPChat(None, "  /admin - admin control board, F2 = spawn menu", 'Event');
		ClientRPChat(None, "  /givemoney <amount> or <player> <amount>", 'Event');
		ClientRPChat(None, "  /setrank <player> <rank>, /setfaction <player> <faction>", 'Event');
		ClientRPChat(None, "  /setspawn <faction> - save faction spawn at your position", 'Event');
		ClientRPChat(None, "  /kick /ban /warn /fine /freeze /unfreeze /slap <player>", 'Event');
		ClientRPChat(None, "  /goto /bring <player>, /pos - coords, /alert <0-4>", 'Event');
		ClientRPChat(None, "  /a <msg> admin chat, /announce <msg> broadcast", 'Event');
		ClientRPChat(None, "  /noclip|/fly, /clearprops, /reason <text>, /addstaff", 'Event');
	}
}

function ServerListFactions()
{
	local MilRPGameInfo Game;
	local int i;
	local string Line;

	Game = GetRPGame();
	if (Game == None)
		return;

	ClientRPChat(None, FactionListHeader, 'Event');
	for (i = 0; i < Game.Factions.Length; i++)
	{
		Line = "  " $ i $ ". [" $ Game.Factions[i].Tag $ "] " $ Game.Factions[i].Name;
		if (Game.MaxFactionSize > 0)
			Line = Line @ "(" $ Game.CountFactionMembers(i) $ "/" $ Game.MaxFactionSize $ ")";
		else
			Line = Line @ "(" $ Game.CountFactionMembers(i) $ ")";
		ClientRPChat(None, Line, 'Event');
	}
}

function ServerListRanks()
{
	local MilRPGameInfo Game;
	local int i;

	Game = GetRPGame();
	if (Game == None)
		return;

	ClientRPChat(None, RankListHeader, 'Event');
	for (i = 0; i < Game.Ranks.Length; i++)
		ClientRPChat(None, "  " $ i $ ". " $ Game.Ranks[i].Title @ "(" $ Game.Ranks[i].MinScore $ ")", 'Event');
}

function ServerRPStatus()
{
	local MilRPGameInfo Game;
	local MilRPPlayerReplicationInfo PRI;
	local string S, FactionName, RankTitle, DutyText;

	Game = GetRPGame();
	PRI = GetRPPRI();
	if (Game == None || PRI == None)
		return;

	if (PRI.FactionID < Game.Factions.Length)
		FactionName = Game.Factions[PRI.FactionID].Name;
	else
		FactionName = NoFactionText;
	if (PRI.Rank < Game.Ranks.Length)
		RankTitle = Game.Ranks[PRI.Rank].Title;
	if (PRI.bOnDuty)
		DutyText = DutyOnText;
	else
		DutyText = DutyOffText;

	S = StatusFormat;
	ReplaceText(S, "%f", FactionName);
	ReplaceText(S, "%r", RankTitle);
	ReplaceText(S, "%d", DutyText);
	ReplaceText(S, "%a", string(Game.GetWallet(self)));
	ReplaceText(S, "%b", string(Game.GetBank(self)));
	ReplaceText(S, "%s", string(int(PRI.Score)));
	ClientRPNotify(S);
}


///////////////////////////////////////////////////////////////////////////////
// ADMIN COMMANDS
// Console: setrank <player> <rank>, setfaction <player> <faction>,
//          givemoney <player> <amount>, announce <text>
// Authorisation happens in MilRPGameInfo.IsAdmin() (PRI.bAdmin via AdminLogin).
///////////////////////////////////////////////////////////////////////////////
exec function SetRankCmd(string Args)
{
	local string Target, RankArg;

	if (!SplitFirstWord(Args, Target, RankArg))
		return;
	ServerAdminSetRank(Target, RankArg);
}

exec function SetRank(string TargetName, string RankArg)
{
	ServerAdminSetRank(TargetName, RankArg);
}

exec function SetFactionCmd(string Args)
{
	local string Target, FactionArg;

	if (!SplitFirstWord(Args, Target, FactionArg))
		return;
	ServerAdminSetFaction(Target, FactionArg);
}

exec function SetFaction(string TargetName, string FactionArg)
{
	ServerAdminSetFaction(TargetName, FactionArg);
}

// /setspawn <faction id or tag>: save current position as that faction's base.
function SetSpawnCmd(string Arg)
{
	local MilRPGameInfo Game;
	local int FactionID;

	Game = GetRPGame();
	if (Game == None)
		return;
	if (!Game.IsAdmin(self))
	{
		ClientRPNotify(Game.FailNotAdmin);
		return;
	}

	FactionID = ResolveFactionArg(Arg);
	if (FactionID < 0)
	{
		ClientRPNotify("Invalid faction. Use /setspawn <id|tag>.");
		return;
	}

	Game.SetFactionSpawn(self, FactionID);
}

exec function GiveMoneyCmd(string Args)
{
	local string Target, AmountArg;

	if (!SplitFirstWord(Args, Target, AmountArg))
		return;
	if (AmountArg == "")
	{
		// Single numeric arg: self-grant ("/givemoney 5000").
		if (Target != string(int(Target)))
		{
			ClientRPNotify("Usage: /givemoney <amount> or /givemoney <player> <amount>");
			return;
		}
		ServerAdminGiveMoney(PlayerReplicationInfo.PlayerName, int(Target));
		return;
	}
	ServerAdminGiveMoney(Target, int(AmountArg));
}

exec function GiveMoney(string TargetName, int Amount)
{
	ServerAdminGiveMoney(TargetName, Amount);
}

exec function Announce(string Msg)
{
	if (Msg != "")
		ServerAdminBroadcast(Msg);
}

// "alpha beta gamma" -> First="alpha", Rest="beta gamma". False if no split.
simulated function bool SplitFirstWord(string S, out string First, out string Rest)
{
	local int Space;

	Space = InStr(S, " ");
	if (Space < 0)
	{
		First = S;
		Rest = "";
		return (S != "");
	}
	First = Left(S, Space);
	Rest = Mid(S, Space + 1);
	return (First != "" && Rest != "");
}

function ServerAdminSetRank(string TargetName, string RankArg)
{
	local MilRPGameInfo Game;
	local int RankID;

	Game = GetRPGame();
	if (Game == None)
		return;
	if (!Game.IsAdmin(self))
	{
		ClientRPNotify(Game.FailNotAdmin);
		return;
	}
	RankID = ResolveRankArg(RankArg);
	if (RankID < 0)
	{
		ClientRPNotify("Unknown rank '" $ RankArg $ "'");
		return;
	}
	if (!Game.AdminSetRank(self, TargetName, RankID))
		ClientRPNotify("No player matching '" $ TargetName $ "'");
}

function ServerAdminSetFaction(string TargetName, string FactionArg)
{
	local MilRPGameInfo Game;
	local int FactionID;

	Game = GetRPGame();
	if (Game == None)
		return;
	if (!Game.IsAdmin(self))
	{
		ClientRPNotify(Game.FailNotAdmin);
		return;
	}
	FactionID = ResolveFactionArg(FactionArg);
	if (FactionID < 0)
	{
		ClientRPNotify(Game.FailInvalidFaction);
		return;
	}
	if (!Game.AdminSetFaction(self, TargetName, FactionID))
		ClientRPNotify("No player matching '" $ TargetName $ "'");
}

function ServerAdminGiveMoney(string TargetName, int Amount)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None || Amount == 0)
		return;
	if (!Game.IsAdmin(self))
	{
		ClientRPNotify(Game.FailNotAdmin);
		return;
	}
	if (!Game.AdminGiveCurrency(self, TargetName, Amount))
		ClientRPNotify("No player matching '" $ TargetName $ "'");
}

function ServerAdminBroadcast(string Msg)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None || Msg == "")
		return;
	Game.AdminBroadcast(self, Left(Msg, 120));
}


///////////////////////////////////////////////////////////////////////////////
// CLIENT RPCs
///////////////////////////////////////////////////////////////////////////////
// Direct HUD toast + console echo for this player only.
simulated function ClientRPNotify(string Message)
{
	local RPNotice N;

	if (Message == "")
		return;

	N.Text = Message;
	N.Time = Level.TimeSeconds;
	Notices[Notices.Length] = N;
	while (Notices.Length > MaxNotices)
		Notices.Remove(0, 1);

	if (Player != None && Player.Console != None)
		Player.Console.Message(Message, 6.0);
	if (bPlayNoticeSound)
		PlayBeepSound();
}

// Chat-style line (roleplay emotes, lists). Goes through the normal HUD
// message path so it appears in the chat area like regular Say text.
simulated function ClientRPChat(PlayerReplicationInfo SenderPRI, string Message, name Type)
{
	local RPChatLine L;

	if (Message == "")
		return;

	// Always feed the in-HUD chat log.
	L.Sender = SenderPRI;
	L.Text = Message;
	L.Type = Type;
	L.Time = Level.TimeSeconds;
	ChatLog[ChatLog.Length] = L;
	while (ChatLog.Length > MaxChatLogLines)
		ChatLog.Remove(0, 1);
}

// Drops expired toasts; called by the HUD each frame.
simulated function PruneNotices()
{
	while (Notices.Length > 0 && Level.TimeSeconds - Notices[0].Time > NoticeLifetime)
		Notices.Remove(0, 1);
}

// Drops old chat log lines; called by the HUD each frame.
simulated function PruneChatLog()
{
	while (ChatLog.Length > 0 && Level.TimeSeconds - ChatLog[0].Time > ChatLogLifetime)
		ChatLog.Remove(0, 1);
}


///////////////////////////////////////////////////////////////////////////////
// INTERACTIVE CHAT OVERLAY
///////////////////////////////////////////////////////////////////////////////
// True while the native chat prompt is open.  Player.Console.bTyping does not
// exist in this Postal 2 build; the engine sets this controller's bIsTyping
// via the Typing() function whenever the prompt opens/closes.
simulated function bool IsTyping()
{
	// The native chat prompt and the graphical admin menu both need to freeze
	// player input / looking so the overlay can capture keys cleanly.
	return bIsTyping || bShowAdminMenu;
}

// Freeze camera while the native chat prompt is open.
function UpdateRotation(float DeltaTime, float maxPitch)
{
	if (IsTyping())
		return;

	Super.UpdateRotation(DeltaTime, maxPitch);
}

// Freeze movement while the native chat prompt is open.
state PlayerWalking
{
	function BeginState()
	{
		Super.BeginState();
		if (Pawn != None)
			Pawn.SetPhysics(PHYS_Walking);
		if (PlayerReplicationInfo != None)
		{
			PlayerReplicationInfo.bIsSpectator = false;
			PlayerReplicationInfo.bOnlySpectator = false;
		}
		bBehindView = false;
	}

	function PlayerMove(float DeltaTime)
	{
		if (IsTyping())
		{
			if (Pawn != None)
			{
				Pawn.Acceleration = vect(0,0,0);
				Pawn.Velocity = vect(0,0,0);
			}
			bFire = 0;
			bAltFire = 0;
			return;
		}

		Super.PlayerMove(DeltaTime);
	}
}

// Mouse wheel scrolls the chat history while the prompt is open.
exec function NextWeapon()
{
	if (IsTyping())
	{
		ChatScrollUp();
		return;
	}

	Super.NextWeapon();
}

exec function PrevWeapon()
{
	if (IsTyping())
	{
		ChatScrollDown();
		return;
	}

	Super.PrevWeapon();
}

exec function WeaponZoomIn()
{
	if (IsTyping())
		return;

	Super.WeaponZoomIn();
}

exec function WeaponZoomOut()
{
	if (IsTyping())
		return;

	Super.WeaponZoomOut();
}

// Scroll older messages into view.
simulated function ChatScrollUp()
{
	local int MaxOffset;

	MaxOffset = ChatLog.Length - 1;
	if (MaxOffset < 0)
		MaxOffset = 0;
	ChatScrollOffset = Clamp(ChatScrollOffset + 1, 0, MaxOffset);
}

// Scroll back toward the most recent messages.
simulated function ChatScrollDown()
{
	ChatScrollOffset = FMax(ChatScrollOffset - 1, 0);
}

///////////////////////////////////////////////////////////////////////////////
// INTERACTION MENU
///////////////////////////////////////////////////////////////////////////////
// Server opens a menu on the owning client. Packed format: Title|Opt1|Opt2...
function ServerOpenMenu(MilRPInteractPoint Source, string Packed)
{
	local string Parts[9];
	local int i, Count;
	local string Tmp;

	if (Packed == "")
		return;

	Count = 0;
	Tmp = Packed;
	while (Tmp != "" && Count < 9)
	{
		i = InStr(Tmp, "|");
		if (i < 0)
		{
			Parts[Count] = Tmp;
			Tmp = "";
		}
		else
		{
			Parts[Count] = Left(Tmp, i);
			Tmp = Mid(Tmp, i + 1);
		}
		Count++;
	}
	if (Count == 0)
		return;

	CurrentMenu.Title = Parts[0];
	CurrentMenu.Count = Count - 1;
	CurrentMenu.Source = Source;
	CurrentMenu.OpenTime = Level.TimeSeconds;
	for (i = 0; i < CurrentMenu.Count && i < 8; i++)
		CurrentMenu.Options[i] = Parts[i + 1];

	ClientOpenMenu(Packed);
}

simulated function ClientOpenMenu(string Packed)
{
	local string Parts[9];
	local int i, Count;
	local string Tmp;

	bMenuOpen = true;

	Count = 0;
	Tmp = Packed;
	while (Tmp != "" && Count < 9)
	{
		i = InStr(Tmp, "|");
		if (i < 0)
		{
			Parts[Count] = Tmp;
			Tmp = "";
		}
		else
		{
			Parts[Count] = Left(Tmp, i);
			Tmp = Mid(Tmp, i + 1);
		}
		Count++;
	}

	if (Count > 0)
	{
		CurrentMenu.Title = Parts[0];
		CurrentMenu.Count = Count - 1;
		for (i = 0; i < CurrentMenu.Count && i < 8; i++)
			CurrentMenu.Options[i] = Parts[i + 1];
	}
}

function CloseMenu()
{
	bMenuOpen = false;
	CurrentMenu.Count = 0;
	CurrentMenu.Source = None;
	ClientCloseMenu();
}

simulated function ClientCloseMenu()
{
	bMenuOpen = false;
}

simulated function CheckMenuTimeout()
{
	if (bMenuOpen && Level.TimeSeconds - CurrentMenu.OpenTime > MenuTimeout)
		ClientCloseMenu();
}

exec function PickMenu(int Option)
{
	if (!bMenuOpen || CurrentMenu.Source == None || Option < 1 || Option > CurrentMenu.Count)
	{
		ClientRPNotify("No menu open or invalid option.");
		return;
	}
	ServerMenuPick(Option - 1);
}

exec function CloseMenuCmd()
{
	CloseMenu();
}

// Emergency escape hatch (/resetmenu): forcefully tears down every client-side
// interaction and restores a clean walking state so 'E' look-at traces can
// never be softlocked by a lingering menu flag.
simulated function ResetMenuState()
{
	if (ActiveArmoryMenu != None)
		ActiveArmoryMenu.CloseMenu();
	if (ActiveShopMenu != None)
		ActiveShopMenu.CloseMenu();
	if (ActiveDEFCONMenu != None)
		ActiveDEFCONMenu.CloseMenu();
	if (ActiveSpawnMenu != None)
	{
		ActiveSpawnMenu.Master.RemoveInteraction(ActiveSpawnMenu);
		ActiveSpawnMenu = None;
	}
	if (ActiveAdminInteraction != None)
	{
		ActiveAdminInteraction.Master.RemoveInteraction(ActiveAdminInteraction);
		ActiveAdminInteraction = None;
	}

	bShowAdminMenu = false;
	bMenuOpen = false;
	CurrentMenu.Count = 0;
	CurrentMenu.Source = None;
	bIsTyping = false;
	ChatScrollOffset = 0;

	// Server-side pointer cleanup (fires the client->server RPC).
	ServerInteractClosed();

	if (Pawn != None)
		GotoState('PlayerWalking');

	ClientRPChat(None, "[System] All administrative and interaction menus have been forcefully reset.", 'Event');
}

function ServerMenuPick(int Option)
{
	local string Feedback;

	if (CurrentMenu.Source == None || Option < 0 || Option >= CurrentMenu.Count)
		return;

	if (CurrentMenu.Source.HandleSelection(self, Option, Feedback))
	{
		if (Feedback != "")
			ClientRPNotify(Feedback);
	}
	else
		ClientRPNotify(Feedback);

	CloseMenu();
}


///////////////////////////////////////////////////////////////////////////////
// RADIO
///////////////////////////////////////////////////////////////////////////////
exec function Radio(string Msg)
{
	if (Msg != "")
		ServerRadio(0, Msg);
}

exec function Command(string Msg)
{
	if (Msg != "")
		ServerRadio(1, Msg);
}

exec function AdminRadio(string Msg)
{
	if (Msg != "")
		ServerRadio(2, Msg);
}

function ServerRadio(int Channel, string Msg)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None || Msg == "")
		return;
	Game.RadioMessage(self, Channel, Msg);
}


///////////////////////////////////////////////////////////////////////////////
// ECONOMY COMMANDS
///////////////////////////////////////////////////////////////////////////////
exec function Pay(string Args)
{
	local string Target, AmountS;

	if (!SplitFirstWord(Args, Target, AmountS))
		return;
	ServerPay(Target, int(AmountS));
}

function ServerPay(string TargetName, int Amount)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None || Amount <= 0 || TargetName == "")
		return;
	Game.PayPlayer(self, TargetName, Amount);
}

exec function Withdraw(int Amount)
{
	ServerBank("withdraw", Amount, "");
}

exec function Deposit(int Amount)
{
	ServerBank("deposit", Amount, "");
}

exec function Transfer(string Args)
{
	local string Target, AmountS;

	if (!SplitFirstWord(Args, Target, AmountS))
		return;
	ServerBank("transfer", int(AmountS), Target);
}

function ServerBank(string Action, int Amount, string Target)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None)
		return;
	Game.HandleBank(self, Action, Amount, Target);
}


///////////////////////////////////////////////////////////////////////////////
// ADMIN / MODERATION COMMANDS
///////////////////////////////////////////////////////////////////////////////
exec function Kick(string Args)
{
	local string Target, Reason;

	if (!SplitFirstWord(Args, Target, Reason))
		Reason = "";
	ServerAdminAction("kick", Target, 0, Reason);
}

exec function Ban(string Args)
{
	local string Target, Reason;

	if (!SplitFirstWord(Args, Target, Reason))
		Reason = "";
	ServerAdminAction("ban", Target, 0, Reason);
}

function AddStaffCmd(string Args)
{
	local string Name, LevelStr, S;
	local int i, Level;
	local MilRPGameInfo Game;

	S = Args;
	Level = -1;
	LevelStr = "";

	// Last token is the group level; the remainder is the player name.
	for (i = Len(S) - 1; i >= 0; i--)
		if (Mid(S, i, 1) == " ")
		{
			Name = Left(S, i);
			LevelStr = Right(S, Len(S) - i - 1);
			break;
		}

	if (Name == "" || LevelStr == "")
	{
		ClientRPNotify("Usage: /addstaff <PlayerName> <GroupLevel 0-4>");
		return;
	}

	Level = int(LevelStr);
	if (LevelStr != string(Level) || Level < 0 || Level > 4)
	{
		ClientRPNotify("Invalid group level.  Use 0-4.");
		return;
	}

	Game = GetRPGame();
	if (Game == None)
		return;

	Game.AddStaff(self, Name, Level);
}

function MyNameCmd(string NewName)
{
	local string OldName;
	local MilRPGameInfo Game;

	if (NewName == "")
		return;

	if (PlayerReplicationInfo == None)
		return;

	OldName = PlayerReplicationInfo.PlayerName;
	PlayerReplicationInfo.PlayerName = NewName;

	Game = GetRPGame();
	if (Game != None)
		Game.Broadcast(self, OldName $ " is now known as " $ NewName);

	ClientRPNotify("You are now known as " $ NewName);
}

exec function WarnPlayer(string Args)
{
	local string Target, Reason;

	if (!SplitFirstWord(Args, Target, Reason))
		Reason = "";
	ServerAdminAction("warn", Target, 0, Reason);
}

exec function Fine(string Args)
{
	local string Target, Rest, AmountS, Reason;
	local int Space;

	if (!SplitFirstWord(Args, Target, Rest))
		return;
	Space = InStr(Rest, " ");
	if (Space < 0)
	{
		AmountS = Rest;
		Reason = "";
	}
	else
	{
		AmountS = Left(Rest, Space);
		Reason = Mid(Rest, Space + 1);
	}
	ServerAdminAction("fine", Target, int(AmountS), Reason);
}

exec function Freeze(string Target)
{
	ServerAdminAction("freeze", Target, 0, "");
}

exec function UnFreeze(string Target)
{
	ServerAdminAction("unfreeze", Target, 0, "");
}

exec function Slap(string Target)
{
	if (Target != "")
		ServerAdminAction("slap", Target, 0, "");
}

exec function SteamFallback(string NewName)
{
	if (NewName == "" || PlayerReplicationInfo == None)
		return;
	PlayerReplicationInfo.PlayerName = NewName;
	ServerSteamFallback(NewName);
}

exec function GotoPlayer(string Target)
{
	ServerAdminAction("goto", Target, 0, "");
}

exec function BringPlayer(string Target)
{
	ServerAdminAction("bring", Target, 0, "");
}

exec function Pos()
{
	ServerAdminAction("pos", "", 0, "");
}

exec function SetAlert(int NewLevel)
{
	ServerAdminAction("alert", "", NewLevel, "");
}

// -----------------------------------------------------------------------------
// GRAPHICAL ADMIN MENU
// -----------------------------------------------------------------------------
// Default reason for menu actions; can be edited with /reason <text>.
exec function Reason(string Args)
{
	AdminMenuReason = Args;
	if (AdminMenuReason == "")
		AdminMenuReason = "Admin menu";
}

// The chat slash command /admin calls ServerAdminMenuToggle directly from
// ServerReceiveChat so it does not collide with the native exec function 'Admin'.

function ServerAdminMenuToggle()
{
	local MilRPGameInfo G;

	G = GetRPGame();
	if (G == None)
		return;
	if (!G.CheckPermission(self, 1))
	{
		ClientRPNotify("You need Moderator clearance or higher to use the admin menu.");
		return;
	}
	if (bShowAdminMenu)
		ClientCloseAdminMenu();
	else
		ClientOpenAdminMenu();
}

simulated function ClientOpenAdminMenu()
{
	if (!IsInState('PlayerWalking')
		&& !IsInState('PlayerHelicoptering')
		&& !IsInState('PlayerFlying'))
		return;
	if (Player == None || Player.InteractionMaster == None)
		return;

	SelectedPlayerIndex = 0;
	SelectedActionIndex = 0;
	if (AdminMenuReason == "")
		AdminMenuReason = "Admin menu";
	ClientRPNotify("Admin menu open.  Left-click to select/execute, Right-click/Esc to close.");
	Player.InteractionMaster.AddInteraction("MilRP.MilRPAdminInteraction", Player);

	if (bNoclip && Pawn != None)
	{
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		Pawn.Velocity.Z = 0;
	}
}

simulated function LocalOpenAdminMenu()
{
	if (Role < ROLE_Authority)
		ClientOpenAdminMenu();
}

simulated function ClientToggleNoclip(bool bEnabled)
{
	bNoclip = bEnabled;
	bCheatFlying = bEnabled;

	if (Pawn == None)
		return;

	Pawn.Velocity = vect(0,0,0);
	Pawn.Acceleration = vect(0,0,0);

	if (bEnabled)
	{
		Pawn.SetCollision(false, false, false);
		Pawn.bCollideWorld = false;
		GotoState('PlayerHelicoptering');
	}
	else
	{
		Pawn.SetCollision(true, true, true);
		Pawn.bCollideWorld = true;
		Pawn.SetPhysics(PHYS_Walking);
		GotoState('PlayerWalking');
	}
}

// Server -> client authoritative weapon flush. In this engine Pawn.Weapon is
// NOT replicated to the owner - the client is authoritative for its own
// weapon and only obeys Weapon.ClientWeaponSet, which is gated by
// SwitchPriority() (RifleWeapon AutoSwitchPriority=8 beats nearly every
// purchase). Running the canonical PendingWeapon/PutDown/ChangedWeapon swap
// on the client itself bypasses that priority gate entirely; the client then
// confirms back to the server through its own ServerChangedWeapon path.
simulated function ClientForceWeapon(Weapon W)
{
	if (Pawn == None || W == None || Pawn.Weapon == W)
		return;
	// Clean-state reset: a stalled PutDown/PendingClientWeaponSet on the
	// previously purchased gun is what glued hands to the first weapon
	// bought. Snap it back to Idle so the new switch can proceed fresh.
	Pawn.PendingWeapon = None;
	if (Pawn.Weapon != None)
		Pawn.Weapon.GotoState('Idle');
	Pawn.PendingWeapon = W;
	if (Pawn.Weapon == None || !Pawn.Weapon.PutDown())
		Pawn.ChangedWeapon();
}

// Server -> client identity sync for Steam fallback override.
simulated function ClientForceSyncIdentity(string NewName)
{
	if (PlayerReplicationInfo != None)
		PlayerReplicationInfo.PlayerName = NewName;
}

function ServerSteamFallback(string NewName)
{
	if (NewName == "" || PlayerReplicationInfo == None)
		return;
	PlayerReplicationInfo.PlayerName = NewName;
	ClientForceSyncIdentity(NewName);
	ClientRPNotify("Identity forced to: " $ NewName);
}

simulated function ClientCloseAdminMenu()
{
	bShowAdminMenu = false;
	if (bNoclip)
	{
		bCheatFlying = true;
		GotoState('PlayerHelicoptering');
	}
	else
		GotoState('PlayerWalking');
}

simulated function ClientOpenSpawnMenu()
{
	if (Player == None || Player.InteractionMaster == None)
		return;
	Player.InteractionMaster.AddInteraction("MilRP.MilRPSpawnMenu", Player);
}

function ServerRequestSpawnMenu()
{
	if (GetRPGame() == None || !GetRPGame().CheckPermission(self, 4))
	{
		ClientRPNotify("You need admin clearance.");
		return;
	}
	ClientOpenSpawnMenu();
}

exec function SpawnMenu()
{
	if (ActiveSpawnMenu != None)
	{
		ActiveSpawnMenu.Master.RemoveInteraction(ActiveSpawnMenu);
		ActiveSpawnMenu = None;
	}
	else
	{
		ServerRequestSpawnMenu();
	}
}

///////////////////////////////////////////////////////////////////////////////
// ARMORY / SHOP GUI PIPELINE
// Locker.UsedBy (server) validates, stores ActiveInteractPoint, then pushes a
// ClientOpen*Menu RPC. The interaction buttons fire the Server* RPCs below.
///////////////////////////////////////////////////////////////////////////////
simulated function ClientOpenArmoryMenu(string PackedKit)
{
	if (Player == None || Player.InteractionMaster == None)
		return;
	if (ActiveArmoryMenu != None)
	{
		ActiveArmoryMenu.SetKit(PackedKit);
		return;
	}
	Player.InteractionMaster.AddInteraction("MilRP.MilRPArmoryInteraction", Player);
	if (ActiveArmoryMenu != None)
		ActiveArmoryMenu.SetKit(PackedKit);
}

simulated function ClientOpenShopMenu(string PackedCatalog)
{
	if (Player == None || Player.InteractionMaster == None)
		return;
	if (ActiveShopMenu != None)
	{
		ActiveShopMenu.SetCatalog(PackedCatalog);
		return;
	}
	Player.InteractionMaster.AddInteraction("MilRP.MilRPShopInteraction", Player);
	if (ActiveShopMenu != None)
		ActiveShopMenu.SetCatalog(PackedCatalog);
}

simulated function ClientOpenDEFCONMenu()
{
	if (Player == None || Player.InteractionMaster == None)
		return;
	if (ActiveDEFCONMenu != None)
		return;
	Player.InteractionMaster.AddInteraction("MilRP.MilRPDEFCONInteraction", Player);
}

///////////////////////////////////////////////////////////////////////////////
// SCOREBOARD (Tab)
// Tab is bound to `Scoreboard` in User.ini/DefUser.ini. The bound exec only
// fires on key press; the MilRPScoreboardMenu interaction itself listens for
// the IK_Tab release event to know when the key is let go, so hold-to-view
// needs no per-frame polling. Pressing Tab again while the board is open
// also toggles it closed.
///////////////////////////////////////////////////////////////////////////////
exec function Scoreboard()
{
	if (ActiveScoreboard != None)
		CloseScoreboard();
	else
		OpenScoreboard();
}

simulated function OpenScoreboard()
{
	if (ActiveScoreboard != None)
		return;
	if (Player == None || Player.InteractionMaster == None)
		return;
	Player.InteractionMaster.AddInteraction("MilRP.MilRPScoreboardMenu", Player);
}

simulated function CloseScoreboard()
{
	if (ActiveScoreboard == None)
		return;
	ActiveScoreboard.Master.RemoveInteraction(ActiveScoreboard);
	ActiveScoreboard = None;
}

// F1 is bound to the native ShowScores command, which has no script body in
// xMpPlayer - our exec shadows it outright. Toggling our own interaction
// (never myHUD.bShowScores) keeps the engine's native score input path from
// ever engaging: no frag board, no eaten mouse clicks, and the right-click
// cursor works on the F1 path too.
exec function ShowScores()
{
	if (ActiveScoreboard != None)
		CloseScoreboard();
	else
		OpenScoreboard();
}

// DEFCON console threat button. Authorisation is re-checked server-side;
// SetAlertLevel broadcasts the change and pushes it to every MilRPSiren.
function ServerUpdateDEFCON(int NewLevel)
{
	local MilRPGameInfo G;

	G = GetRPGame();
	if (G == None || !G.CheckPermission(self, 2))
	{
		ClientRPNotify("You need Admin clearance to change DEFCON.");
		return;
	}
	G.SetAlertLevel(self, byte(Clamp(NewLevel, 0, 5)));
}

function ServerArmoryResupply()
{
	local MilRPArmoryLocker Locker;

	Locker = MilRPArmoryLocker(ActiveInteractPoint);
	if (Locker == None)
		return;
	Locker.DoRestock(self);
}

// 'E' key entry point. Bound via User.ini/DefUser.ini (E=Interact) because
// the engine's native exec Use() is a hardcoded C++ path that cannot be
// overridden client-side. On a network client we run the look-at trace
// locally against the client's own copy of the world: a solid
// (bBlockActors) interact point can never appear in Pawn.TouchingActors, so
// we resolve the aimed-at target here and ship the exact actor reference to
// the server over a reliable RPC. Listen-server/standalone hosts skip the
// RPC and go straight to ServerUse.
exec function Interact()
{
	local Vector Start, End, Hit, HitNormal;
	local Actor HitA;
	local MilRPInteractPoint Pt;

	// Dead/dying/spectating players treat E (and any interaction key) as an
	// instant respawn request. Unlike Fire/Enter, our custom exec has no
	// native input path that reaches the server, so it routes through a
	// dedicated reliable RPC instead.
	if (Pawn == None || Pawn.Health <= 0 || IsInState('Dead') || IsInState('Dying')
		|| IsInState('Spectating') || IsInState('PlayerWaiting') || IsInState('WaitingForPawn'))
	{
		ServerRespawnMe();
		return;
	}

	if (Role < ROLE_Authority && Pawn != None)
	{
		Start = Pawn.Location + (vect(0,0,1) * Pawn.BaseEyeHeight);
		End = Start + Vector(Rotation) * UseTraceRange();
		HitA = Trace(Hit, HitNormal, End, Start, true);
		Pt = MilRPInteractPoint(HitA);
		if (Pt != None)
		{
			ServerInteractWithTarget(Pt);
			return;
		}
	}
	ServerUse();
}

// Reliable client -> server handshake carrying the exact interact point the
// client traced. Re-validated server-side against the use radius before the
// point's UsedBy gate runs (which applies its own faction/rank/duty rules).
function ServerInteractWithTarget(MilRPInteractPoint TargetPoint)
{
	if (TargetPoint == None || Pawn == None)
		return;
	if (VSize(TargetPoint.Location - Pawn.Location) > TargetPoint.UseRadius + 256.0)
		return;
	TargetPoint.UsedBy(Pawn);
}

// The native ServerUse only consults Pawn.TouchingActors, which never lists
// blocking colliders. This forward look-at trace lets SOLID interact points
// (bBlockActors crates) fire UsedBy on 'E'.
function float UseTraceRange()
{
	return FMax(InteractRadius, 256.0);
}

function ServerUse()
{
	local Vector Start, End, Hit, HitNormal;
	local Actor HitA;
	local MilRPInteractPoint Pt;

	if (Pawn != None)
	{
		Start = Pawn.Location + (vect(0,0,1) * Pawn.BaseEyeHeight);
		End = Start + Vector(Rotation) * UseTraceRange();
		HitA = Pawn.Trace(Hit, HitNormal, End, Start, true);
		Pt = MilRPInteractPoint(HitA);
		if (Pt != None)
		{
			Pt.UsedBy(Pawn);
			return;
		}
	}
	Super.ServerUse();
}

// E pressed while dead/spectating. ServerRestartPlayer is not a client ->
// server replicated function in this engine (and no-ops on NM_Client), so
// the dead-state respawn request needs its own reliable RPC. Server-side we
// only honor it when the player genuinely has no living pawn.
function ServerRespawnMe()
{
	if (Pawn != None && Pawn.Health > 0)
		return;
	if (Level.Game != None)
		Level.Game.RestartPlayer(self);
}

// Records a shop-purchased inventory class so MilRPGameInfo.RemoveLoadout
// never strips it during duty/faction transitions.
function MarkPurchased(class<Inventory> C)
{
	local int i;

	if (C == None)
		return;
	for (i = 0; i < PurchasedItems.Length; i++)
		if (PurchasedItems[i] == C)
			return;
	PurchasedItems[PurchasedItems.Length] = C;
}

function bool OwnsPurchased(class<Inventory> C)
{
	local int i;

	for (i = 0; i < PurchasedItems.Length; i++)
		if (PurchasedItems[i] == C)
			return true;
	return false;
}

function ServerShopBuy(int Index)
{
	local MilRPShopLocker Shop;

	Shop = MilRPShopLocker(ActiveInteractPoint);
	if (Shop == None)
		return;
	Shop.DoPurchase(self, Index);
}

function ServerInteractClosed()
{
	ActiveInteractPoint = None;
}

function ServerSpawnWeapon(string ClassName)
{
	if (GetRPGame() == None || !GetRPGame().CheckPermission(self, 4))
		return;
	if (Pawn == None)
		return;
	GetRPGame().GiveLoadout(Pawn, ClassName);
}

function ServerSetSkin(string MeshName, string SkinName)
{
	local Mesh NewMesh;
	local Texture NewSkin;

	if (GetRPGame() == None || !GetRPGame().CheckPermission(self, 4))
		return;
	if (Pawn == None)
		return;

	NewMesh = Mesh(DynamicLoadObject(MeshName, class'Mesh'));
	if (NewMesh != None)
		Pawn.LinkMesh(NewMesh);
	NewSkin = Texture(DynamicLoadObject(SkinName, class'Texture'));
	if (NewSkin != None)
		Pawn.Skins[0] = NewSkin;
}

// Two-stage placement solver: forward crosshair trace, then a straight
// down-trace from that point to snap onto real floor geometry. Returns the
// floor-snapped location and a level (zero-pitch/roll) rotation.
function bool ComputeGroundSpawn(class<Actor> AC, out vector OutLoc, out rotator OutRot)
{
	local Vector Start, End, Hit, HitNormal;
	local Vector FloorHit, FloorNormal, DownEnd;
	local Actor HitActor, FloorActor;
	local float SpawnHeight;
	local bool bBottomPivot, bUprightStation;

	if (Pawn == None || AC == None)
		return false;

	// Shop/siren/desk meshes pivot at the bottom face - skip the half-height
	// lift so they sit flush on the floor instead of hovering.
	bBottomPivot = (AC == class'MilRPShopLocker'
		|| AC == class'MilRPSiren' || AC == class'MilRPDEFCONConsole'
		|| AC == class'MilRPCapturePoint');

	// Interactive stations ignore the player's camera yaw entirely - they
	// always spawn level and facing world-north so they can never land on
	// their backs or clip sideways into the floor.
	bUprightStation = (AC == class'MilRPArmoryLocker' || AC == class'MilRPShopLocker'
		|| AC == class'MilRPDEFCONConsole' || AC == class'MilRPCapturePoint');

	Start = Pawn.Location + (vect(0,0,1) * Pawn.BaseEyeHeight);
	End = Start + Vector(Rotation) * 5000.0;
	HitActor = Pawn.Trace(Hit, HitNormal, End, Start, true);

	if (HitActor == Pawn)
	{
		Start = Start + Vector(Rotation) * 150.0;
		HitActor = Pawn.Trace(Hit, HitNormal, End, Start, true);
	}
	if (HitActor == None)
		Hit = End;

	// Stage 2: drop straight down from the forward point to find the floor.
	DownEnd = Hit;
	DownEnd.Z -= 2000.0;
	FloorActor = Trace(FloorHit, FloorNormal, DownEnd, Hit, false);

	SpawnHeight = AC.default.CollisionHeight;
	if (SpawnHeight <= 0.0)
		SpawnHeight = 45.0;

	if (FloorActor != None)
	{
		// Snapped to physical ground - rest the actor on top of the surface.
		OutLoc = FloorHit;
		if (AC == class'MilRPArmoryLocker')
			OutLoc.Z += 32.0; // center-pivoted ammo box: half-height lift
		else if (!bBottomPivot)
			OutLoc.Z += (SpawnHeight + 2.0);
	}
	else
	{
		// No floor found - fall back to the forward hit surface offset.
		OutLoc = Hit + (HitNormal * (AC.default.CollisionRadius + 15.0));
		if (AC == class'MilRPArmoryLocker')
			OutLoc.Z += 32.0;
		else if (HitNormal.Z > 0.5 && !bBottomPivot)
			OutLoc.Z += (SpawnHeight + 2.0);
	}

	// The lightpole flag mesh pivots a little above its base - trim the Z so
	// the pole lands flush on the floor instead of floating.
	if (AC == class'MilRPCapturePoint')
		OutLoc.Z -= 16.0;

	if (bUprightStation)
	{
		// Hardcoded zero-rotator: stations always stand perfectly upright,
		// snapped flush to the floor - no extra height lift.
		OutRot.Pitch = 0;
		OutRot.Yaw = 0;
		OutRot.Roll = 0;
	}
	else
	{
		OutRot.Pitch = 0;
		OutRot.Yaw = Rotation.Yaw;
		OutRot.Roll = 0;
	}

	return true;
}

function ServerSpawnWeaponPickup(string ClassName)
{
	local Vector FinalLocation;
	local Pickup NewPickup;
	local class<Pickup> PC;
	local rotator FlatRotation;

	if (GetRPGame() == None || !GetRPGame().CheckPermission(self, 4))
		return;
	if (Pawn == None)
		return;

	if (ClassName ~= "Inventory.PistolWeaponSS")
		PC = class'Inventory.PistolPickup';
	else if (ClassName ~= "Inventory.ShotGunWeaponSS")
		PC = class'Inventory.ShotGunPickup';
	else if (ClassName ~= "Inventory.MachineGunWeaponSS")
		PC = class'Inventory.MachineGunPickup';
	else if (ClassName ~= "Inventory.RifleWeaponSS")
		PC = class'Inventory.RiflePickup';
	else if (ClassName ~= "Inventory.GrenadeWeaponSS")
		PC = class'Inventory.GrenadePickup';
	else if (ClassName ~= "Inventory.MolotovWeaponSS")
		PC = class'Inventory.MolotovPickup';
	else if (ClassName ~= "Inventory.LauncherWeaponSS")
		PC = class'Inventory.LauncherPickup';
	else if (ClassName ~= "Inventory.BatonWeaponSS")
		PC = class'Inventory.BatonPickup';
	else if (ClassName ~= "Inventory.ScissorsWeaponSS")
		PC = class'Inventory.ScissorsPickup';
	else if (ClassName ~= "Inventory.ShovelWeaponSS")
		PC = class'Inventory.ShovelPickup';
	else if (ClassName ~= "Inventory.CowHeadWeaponSS")
		PC = class'Inventory.CowHeadPickup';
	else if (ClassName ~= "Inventory.MrDKNadeWeaponSS")
		PC = class'Inventory.MrDKNadePickup';
	else if (ClassName ~= "EDStuff.MP5Weapon")
		PC = class'EDStuff.MP5Pickup';
	else
		return;

	if (!ComputeGroundSpawn(PC, FinalLocation, FlatRotation))
		return;

	NewPickup = Spawn(PC, None,, FinalLocation, FlatRotation);
	if (NewPickup == None)
		return;

	NewPickup.Tag = 'GmodSpawned';
}

function ServerSpawnProp(string ClassName, string MeshPath)
{
	local class<Actor> AC;
	local Vector FinalLocation;
	local Actor SpawnedActor;
	local Pawn SpawnedPawn;
	local Controller C;
	local rotator FlatRotation;
	local StaticMesh SM;
	local MilRPInteractPoint Pt;
	local MilRPSiren Sir;
	local MilRPWorld W;

	if (GetRPGame() == None || !GetRPGame().CheckPermission(self, 4))
		return;
	if (Pawn == None)
		return;

	AC = class<Actor>(DynamicLoadObject(ClassName, class'Class'));
	if (AC == None)
		return;

	if (!ComputeGroundSpawn(AC, FinalLocation, FlatRotation))
		return;

	SpawnedActor = Spawn(AC, None,, FinalLocation, FlatRotation);
	if (SpawnedActor == None)
		return;

	// Optional static-mesh override (MoveableStaticMeshActor prop spawning).
	if (MeshPath != "")
	{
		SM = StaticMesh(DynamicLoadObject(MeshPath, class'StaticMesh'));
		if (SM != None)
		{
			SpawnedActor.SetStaticMesh(SM);
			SpawnedActor.SetDrawType(DT_StaticMesh);
		}
	}

	// Register spawned interact points into MilRPWorld so the HUD prompt and
	// radius checks see them exactly like map-placed points; sirens join the
	// DEFCON broadcast list the same way.
	Pt = MilRPInteractPoint(SpawnedActor);
	Sir = MilRPSiren(SpawnedActor);
	if (Pt != None || Sir != None)
	{
		W = GetRPWorld();
		if (W != None)
		{
			if (Pt != None)
			{
				Pt.RegisterWorld(W);
				W.Points[W.Points.Length] = Pt;
			}
			if (Sir != None)
			{
				W.Sirens[W.Sirens.Length] = Sir;
				if (W.RPGame != None && W.RPGame.RPGRI != None)
					Sir.SetAlertLevel(W.RPGame.RPGRI.AlertLevel);
			}
		}
	}

	SpawnedPawn = Pawn(SpawnedActor);
	SpawnedActor.Tag = 'GmodSpawned';
	if (SpawnedPawn != None && SpawnedPawn.Controller == None && SpawnedPawn.ControllerClass != None)
	{
		C = Spawn(SpawnedPawn.ControllerClass);
		if (C != None)
			C.Possess(SpawnedPawn);
	}
}

function ServerClearProps()
{
	local Actor A;

	if (GetRPGame() == None || !GetRPGame().CheckPermission(self, 4))
		return;

	foreach AllActors(class'Actor', A, 'GmodSpawned')
	{
		if (A != None)
			A.Destroy();
	}
}

// Keyboard navigation, client-side.
exec function AdminMenuUp()
{
	local GameReplicationInfo GRI;
	local int MaxIdx;

	if (!bShowAdminMenu)
		return;

	if (bAdminMenuActionFocus)
		SelectedActionIndex = Max(0, SelectedActionIndex - 2);
	else
	{
		GRI = self.GameReplicationInfo;
		MaxIdx = 0;
		if (GRI != None)
			MaxIdx = GRI.PRIArray.Length - 1;
		SelectedPlayerIndex = Max(0, SelectedPlayerIndex - 1);
	}
}

exec function AdminMenuDown()
{
	local GameReplicationInfo GRI;
	local int MaxIdx;

	if (!bShowAdminMenu)
		return;

	if (bAdminMenuActionFocus)
		SelectedActionIndex = Min(9, SelectedActionIndex + 2);
	else
	{
		GRI = self.GameReplicationInfo;
		MaxIdx = 0;
		if (GRI != None)
			MaxIdx = GRI.PRIArray.Length - 1;
		SelectedPlayerIndex = Min(MaxIdx, SelectedPlayerIndex + 1);
	}
}

exec function AdminMenuLeft()
{
	if (!bShowAdminMenu)
		return;

	if (bAdminMenuActionFocus)
	{
		if ((SelectedActionIndex % 2) == 0)
			bAdminMenuActionFocus = false;
		else
			SelectedActionIndex--;
	}
}

exec function AdminMenuRight()
{
	if (!bShowAdminMenu)
		return;

	if (!bAdminMenuActionFocus)
		bAdminMenuActionFocus = true;
	else if ((SelectedActionIndex % 2) == 0)
		SelectedActionIndex = Min(9, SelectedActionIndex + 1);
}

exec function AdminMenuSelect()
{
	local string TargetName;
	local GameReplicationInfo GRI;

	if (!bShowAdminMenu)
		return;

	GRI = self.GameReplicationInfo;
	if (GRI == None || SelectedPlayerIndex < 0 || SelectedPlayerIndex >= GRI.PRIArray.Length)
		return;

	TargetName = GRI.PRIArray[SelectedPlayerIndex].PlayerName;
	ServerAdminMenuAction(TargetName, SelectedActionIndex, AdminMenuReason);
}

function ServerAdminMenuAction(string TargetName, int ActionIndex, string Reason)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None)
		return;
	if (Reason == "")
		Reason = "Admin menu";

	switch (ActionIndex)
	{
		case 0:  Game.AdminAction(self, "kick",    TargetName, 0, Reason); break;
		case 1:  Game.AdminAction(self, "ban",     TargetName, 0, Reason); break;
		case 2:  Game.AdminAction(self, "warn",    TargetName, 0, Reason); break;
		case 3:  Game.AdminAction(self, "freeze",  TargetName, 0, Reason); break;
		case 4:  Game.AdminAction(self, "goto",    TargetName, 0, Reason); break;
		case 5:  Game.AdminAction(self, "bring",   TargetName, 0, Reason); break;
		case 6:  Game.AdminAction(self, "alert",   "",         3, Reason); break;
		case 7:  Game.AdminAction(self, "lockdown","",         0, Reason); break;
		case 8:  Game.AdminAction(self, "noclip",  "",         0, Reason); break;
		case 9:  Game.AdminAction(self, "slap",    TargetName, 0, Reason); break;
	}
}

function ServerAdminAction(string Action, string Target, int Amount, string Reason)
{
	local MilRPGameInfo Game;

	Game = GetRPGame();
	if (Game == None)
		return;
	Game.AdminAction(self, Action, Target, Amount, Reason);
}


///////////////////////////////////////////////////////////////////////////////
// CLIENT HUD HELPERS
///////////////////////////////////////////////////////////////////////////////
// Returns the interact point the player can currently use: radius scan via
// MilRPWorld first, then a forward look-at trace for spawned/solid points.
simulated function MilRPInteractPoint GetNearbyPoint()
{
	local MilRPWorld W;
	local MilRPInteractPoint Pt;
	local Actor HitA;
	local Vector Start, End, Hit, HitNormal;

	foreach DynamicActors(class'MilRPWorld', W)
		if (W != None)
			break;
	if (W != None)
		Pt = W.FindPointFor(Pawn, InteractRadius);

	// Look-at trace fallback: covers spawned points missing from MilRPWorld
	// and solid (bBlockActors) crates that can never enter TouchingActors.
	if (Pt == None && Pawn != None)
	{
		Start = Pawn.Location + (vect(0,0,1) * Pawn.BaseEyeHeight);
		End = Start + Vector(Rotation) * UseTraceRange();
		HitA = Pawn.Trace(Hit, HitNormal, End, Start, true);
		Pt = MilRPInteractPoint(HitA);
	}

	return Pt;
}

simulated function string GetNearbyPointLabel()
{
	local MilRPInteractPoint Pt;

	Pt = GetNearbyPoint();
	if (Pt == None)
		return "";
	return Pt.PointLabel;
}


///////////////////////////////////////////////////////////////////////////////
// TICK / FREEZE
///////////////////////////////////////////////////////////////////////////////
event PlayerTick(float DeltaTime)
{
	local MilRPPlayerReplicationInfo PRI;

	Super.PlayerTick(DeltaTime);

	PRI = GetRPPRI();
	if (PRI != None && PRI.bFrozen && Pawn != None)
	{
		Pawn.Velocity = vect(0,0,0);
		Pawn.Acceleration = vect(0,0,0);
		bFire = 0;
		bAltFire = 0;
	}

	CheckMenuTimeout();
	PruneChatLog();

	// Reset chat scroll when the native prompt closes; keep the player frozen
	// while the prompt is active, even in non-walking states.
	if (IsTyping())
	{
		if (Pawn != None)
		{
			Pawn.Acceleration = vect(0,0,0);
			Pawn.Velocity = vect(0,0,0);
		}
		bFire = 0;
		bAltFire = 0;
	}
	else
	{
		ChatScrollOffset = 0;
	}
}

// If the player dies while the chat prompt is open, snap scroll back to real-time.
function PawnDied(Pawn P)
{
	if (P == Pawn)
		ChatScrollOffset = 0;

	PurchasedItems.Length = 0;
	bNoclip = false;
	ClientToggleNoclip(false);
	Super.PawnDied(P);
}

///////////////////////////////////////////////////////////////////////////////
// RESPAWN HELPERS
///////////////////////////////////////////////////////////////////////////////
// Pressing Enter (ActivateItem) while dead or spectating instantly respawns.
exec function ActivateItem()
{
	if (Pawn == None || (Pawn != None && Pawn.Health <= 0))
	{
		ServerRespawnMe();
		return;
	}

	Super.ActivateItem();
}

// Never draw the "Press to join the match!" startup overlay.
function PlayStartupMessage(byte StartupStage)
{
	// In a persistent RP world there is no pre-match waiting screen.
}

// Pressing Fire while spectating switches view by default; override it to respawn.
// Prevent the engine from pushing this player into the GameEnded state when a
// match would normally finish.  MilRPGameInfo never ends the match, but these
// guards also stop any stray client/server RPCs from locking the player out.
function GameHasEnded()
{
	// never enter GameEnded
}

simulated function ClientGameEnded()
{
	// never enter GameEnded on the client
}

// Joiners must never be stuck on the "Press to join the match!" screen.  If
// the engine still puts us here, click-through and fire both force a spawn.
auto state PlayerWaiting
{
	ignores SeePlayer, HearNoise, NotifyBump, TakeDamage, PhysicsVolumeChange, NextWeapon, PrevWeapon, SwitchToBestWeapon;

	function BeginState()
	{
		Super.BeginState();
		bFrozen = false;
		if (PlayerReplicationInfo != None)
		{
			PlayerReplicationInfo.bIsSpectator = false;
			PlayerReplicationInfo.bOnlySpectator = false;
		}
		SetPhysics(PHYS_None);
	}

	function ServerRestartPlayer()
	{
		if (Level.Game != None)
			Level.Game.RestartPlayer(self);
	}

	exec function Fire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function AltFire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function Interact()
	{
		ServerRespawnMe();
	}

	exec function Jump(optional float F)
	{
		// swallow the jump to avoid any default spectator behavior
	}
}

state Spectating
{
	ignores ThrowPowerup, Suicide, CheckMapReminder;

	// No background countdown may move the player back into the match.
	function Timer()
	{
		SetTimer(0.0, false);
	}

	function BeginState()
	{
		bFrozen = false;
		SetTimer(0.0, false);
	}

	exec function Fire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function AltFire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function Interact()
	{
		ServerRespawnMe();
	}
}

// Player is looking at their dead body.  Strip the freeze timers and any
// round-ending callbacks; only an explicit Fire/Enter respawns them.
state Dead
{
	ignores ThrowPowerup, Suicide, CheckMapReminder;

	function BeginState()
	{
		Super.BeginState();
		// The native dead-flow pins myHUD.bShowScores and its score input
		// path swallows clicks; release both so the world and our respawn
		// keys stay live under the corpse cam.
		if (MyHUD != None)
			MyHUD.bShowScores = false;
		bFrozen = false;
		SetTimer(0.0, false);
		WaitDelay = 0;
	}

	function Timer()
	{
		SetTimer(0.0, false);
	}

	function ServerReStartGame()
	{
		// Disabled: this would call Level.Game.RestartGame() and reload the map.
	}

	function ServerRestartPlayer()
	{
		if (Level.Game != None)
			Level.Game.RestartPlayer(self);
	}

	exec function Fire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function AltFire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function Interact()
	{
		ServerRespawnMe();
	}

	exec function GameOverRestart(optional float F)
	{
		// single-player only, but block it here as well
	}
}

// Transient death-cam state some engine paths use before Dead. Same rule:
// any fire/interact key becomes an instant respawn request.
state Dying
{
	ignores ThrowPowerup, Suicide, CheckMapReminder;

	function BeginState()
	{
		if (MyHUD != None)
			MyHUD.bShowScores = false;
	}

	exec function Fire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function AltFire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function Interact()
	{
		ServerRespawnMe();
	}
}

// If the engine ever tries to enter GameEnded, immediately thaw the player so
// they can respawn, and block the map-restart path entirely.
state GameEnded
{
	ignores ThrowPowerup, Suicide, CheckMapReminder;

	function BeginState()
	{
		Super.BeginState();
		bFrozen = false;
		SetTimer(0.0, false);
		// MpPlayer.GameEnded.Timer() forces myHUD.bShowScores every tick to
		// pin the native scoreboard; we kill the timer above and release the
		// flag here so its input mask can't eat our respawn clicks.
		if (MyHUD != None)
			MyHUD.bShowScores = false;
	}

	function Timer()
	{
		SetTimer(0.0, false);
	}

	function ServerReStartGame()
	{
		// Disabled: never reload the map.
	}

	function ServerRestartPlayer()
	{
		if (Level.Game != None)
			Level.Game.RestartPlayer(self);
	}

	exec function Fire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function AltFire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function Interact()
	{
		ServerRespawnMe();
	}
}

// The WaitingForPawn state normally spams AskForPawn() every 0.2s.  We only
// want a manual respawn, so disable that background request loop.
state WaitingForPawn
{
	function PlayerTick(float DeltaTime)
	{
		Global.PlayerTick(DeltaTime);
		SetTimer(0.0, false);
	}

	function Timer()
	{
		SetTimer(0.0, false);
	}

	function BeginState()
	{
		bFrozen = false;
		SetTimer(0.0, false);
		if (MyHUD != None)
			MyHUD.bShowScores = false;
	}

	// Dead -> WaitingForPawn strips the Dead state's respawn keys; rebind
	// them here so clicking or pressing E always revives.
	exec function Fire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function AltFire(optional float F)
	{
		ServerRespawnMe();
	}

	exec function Interact()
	{
		ServerRespawnMe();
	}

	function LongClientAdjustPosition
	(
		float TimeStamp,
		name newState,
		EPhysics newPhysics,
		float NewLocX,
		float NewLocY,
		float NewLocZ,
		float NewVelX,
		float NewVelY,
		float NewVelZ,
		Actor NewBase,
		float NewFloorX,
		float NewFloorY,
		float NewFloorZ
	)
	{
		// Refuse any server command that would force us into GameEnded.
		if (newState == 'GameEnded')
			return;
		Super.LongClientAdjustPosition(TimeStamp, newState, newPhysics,
			NewLocX, NewLocY, NewLocZ, NewVelX, NewVelY, NewVelZ,
			NewBase, NewFloorX, NewFloorY, NewFloorZ);
	}
}

///////////////////////////////////////////////////////////////////////////////
// TEXT CHAT
///////////////////////////////////////////////////////////////////////////////
// In-game chat is handled by the native 'Talk'/'Say' prompt (bound to B).
// Non-slash text falls through to ServerReceiveChat -> ServerLocalSay and is
// rendered in the HUD chat log.  Slash commands are handled by the Say exec.


///////////////////////////////////////////////////////////////////////////////
// ADMIN MENU INPUT STATE
///////////////////////////////////////////////////////////////////////////////
// Global fallback execs so players can bind arrow keys / Enter / Escape to
// these aliases in User.ini even if the automatic DefUser.ini is not applied.
exec function MenuUp()    { if (bShowAdminMenu) AdminMenuUp(); }
exec function MenuDown()  { if (bShowAdminMenu) AdminMenuDown(); }
exec function MenuLeft()  { if (bShowAdminMenu) AdminMenuLeft(); }
exec function MenuRight() { if (bShowAdminMenu) AdminMenuRight(); }
exec function MenuEnter() { if (bShowAdminMenu) AdminMenuSelect(); }
exec function MenuClose() { if (bShowAdminMenu) ServerAdminMenuToggle(); }

state AdminMenuOpen
{
	// Freeze all standard gameplay movement / actions while the board is open.
	ignores PlayerMove, UpdateRotation, Fire, AltFire, Use;

	// Movement-key fallbacks (useful if the player keeps WASD bound while in-menu).
	exec function MoveForward()  { AdminMenuUp(); }
	exec function MoveBackward() { AdminMenuDown(); }
	exec function StrafeLeft()   { AdminMenuLeft(); }
	exec function StrafeRight()  { AdminMenuRight(); }

	// Look/arrow-key fallbacks for the second binding layer.
	exec function LookUp()       { if (bShowAdminMenu) AdminMenuUp(); }
	exec function LookDown()     { if (bShowAdminMenu) AdminMenuDown(); }

	// Action and close bindings.
	exec function Talking()      { if (bShowAdminMenu) AdminMenuSelect(); }
	exec function Jump(optional float F) { if (bShowAdminMenu) ServerAdminMenuToggle(); }
}


defaultproperties
{
	LocalChatRadius=1280.0
	NoticeLifetime=6.0
	MaxNotices=4
	bPlayNoticeSound=true
	MenuTimeout=30.0
	InteractRadius=128.0
	PayRadius=256.0
	MaxBankBalance=1000000

	MePrefix="* "
	DoPrefix="** "
	LocalPrefix="[Local] "
	WalletLabel="Wallet"
	FactionListHeader="Factions (use /join <id|tag> or /joinfaction <id|tag>):"
	RankListHeader="Ranks (title / RP score required):"
	StatusFormat="%f | %r | %d | Wallet $%a | Bank $%b | RP %s"
	DutyOnText="ON DUTY"
	DutyOffText="OFF DUTY"
	NoFactionText="No faction"
	MenuHint="Type /pick <number> or /close"
	RadioPrefix="[RADIO] "
	CommandPrefix="[COMMAND] "
	AdminPrefix="[ADMIN] "
	PayPrefix="[PAY] "
	BankLabel="Bank"

	PlayerReplicationInfoClass=class'MilRP.MilRPPlayerReplicationInfo'

	ChatMaxLength=128
	MaxChatLogLines=50
	ChatLogLifetime=300.0
	VoiceChatPrompt="Use a third-party voice server for team comms."

	ChatPrefix="[Chat] "
	EmotePrefix="* "
	DoEmotePrefix="** "
	FactionChatPrefix="[Faction] "
	AdminChatPrefix="[Admin] "
}
