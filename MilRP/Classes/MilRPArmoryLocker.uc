///////////////////////////////////////////////////////////////////////////////
// MilRPArmoryLocker.uc
//
// Faction-owned armory crate. Pressing USE opens the mouse-driven
// MilRPArmoryInteraction screen; the [RESTOCK MUNITIONS] button routes back
// here through MilRPPlayer.ServerArmoryResupply -> DoRestock.
//
// MilRPInteractPoint extends the engine UseTrigger, so ServerUse -> UsedBy
// fires on 'E' with no extra bindings.
//
// Placement:
//   [MilRP.MilRPWorld] Placeables -> ClassName="MilRP.MilRPArmoryLocker",
//   FactionID=<id> (255 = any), Extra="<min rank>" (optional).
///////////////////////////////////////////////////////////////////////////////
class MilRPArmoryLocker extends MilRPInteractPoint
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
var() int		TargetFactionID;		// owning faction id (255 = any faction)
var() int		MinimumRankRequired;	// minimum rank index allowed to resupply


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	Super.PostBeginPlay();

	// The center-pivoted mesh is lifted +32 at spawn; widen the cylinder so
	// the client's look-at trace reliably catches it at a comfortable
	// distance. (Cylinder is solid - the wide footprint also blocks walking.)
	UseRadius = 180.0;
	SetCollisionSize(180.0, CollisionHeight);

	// ExtraConfig may carry a numeric minimum rank for per-instance tuning.
	ParseExtraRank();
	if (MinimumRankRequired > RankRequired)
		RankRequired = MinimumRankRequired;
}

function RegisterWorld(MilRPWorld W)
{
	Super.RegisterWorld(W);

	// MilRPWorld sets PointFaction from the placement row; mirror it here.
	TargetFactionID = PointFaction;
	ParseExtraRank();
}

function ParseExtraRank()
{
	local string Tmp;
	local int Eq;

	Tmp = Trim(ExtraConfig);
	if (Tmp == "")
		return;

	Eq = InStr(Tmp, "=");
	if (Eq >= 0)
	{
		if (Left(Tmp, Eq) ~= "rank" || Left(Tmp, Eq) ~= "minrank")
			Tmp = Trim(Mid(Tmp, Eq + 1));
		else
			return;
	}
	if (Tmp != "" && Tmp == string(int(Tmp)))
		MinimumRankRequired = int(Tmp);
}

function string Trim(string S)
{
	while (Len(S) > 0 && (Left(S, 1) == " " || Left(S, 1) == "\t"))
		S = Mid(S, 1);
	while (Len(S) > 0 && (Right(S, 1) == " " || Right(S, 1) == "\t"))
		S = Left(S, Len(S) - 1);
	return S;
}


///////////////////////////////////////////////////////////////////////////////
// ACCESS GATE (server-side; shared by UsedBy and DoRestock)
///////////////////////////////////////////////////////////////////////////////
function bool CheckAccess(MilRPPlayer RPO, out string FailReason)
{
	local MilRPPlayerReplicationInfo PRI;
	local MilRPGameReplicationInfo GRI;
	local MilRPGameInfo Game;

	Game = GetGame();
	PRI = RPO.GetRPPRI();
	GRI = RPO.GetRPGRI();
	FailReason = "";

	if (Game == None || PRI == None)
	{
		FailReason = "Armory offline.";
		return false;
	}
	// Admin testing override: skip faction/rank/duty/lockdown gates so staff
	// can open and test the GUI regardless of their character state.
	if (Game.CheckPermission(RPO, 2))
		return true;
	if (PRI.bFrozen)
	{
		FailReason = "You are frozen.";
		return false;
	}
	if (GRI != None && GRI.bLockdown && !bOffDutyOk)
	{
		FailReason = "Base lockdown is active.";
		return false;
	}
	if (TargetFactionID != 255 && PRI.FactionID != TargetFactionID)
	{
		if (GRI != None)
			FailReason = "Access Denied: this armory belongs to " $ GRI.GetFactionName(TargetFactionID) $ ".";
		else
			FailReason = "Access Denied: faction " $ TargetFactionID $ " only.";
		return false;
	}
	if (PRI.Rank < MinimumRankRequired)
	{
		if (GRI != None)
			FailReason = "Access Denied: requires rank " $ GRI.GetRankTitle(MinimumRankRequired) $ ".";
		else
			FailReason = "Access Denied: requires rank " $ MinimumRankRequired $ ".";
		return false;
	}
	if (!bOffDutyOk && !PRI.bOnDuty)
	{
		FailReason = "Access Denied: you must be on duty.";
		return false;
	}
	if (RPO.Pawn == None)
	{
		FailReason = "Cannot resupply while dead or spectating.";
		return false;
	}
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// USETRIGGER HOOK - opens the tactical GUI
///////////////////////////////////////////////////////////////////////////////
function UsedBy(Pawn user)
{
	local MilRPPlayer RPO;
	local MilRPPlayerReplicationInfo PRI;
	local MilRPGameInfo Game;
	local string Reason;

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
	if (!CheckAccess(RPO, Reason))
	{
		RPO.ClientRPNotify(Reason);
		return;
	}

	Game = GetGame();
	PRI = RPO.GetRPPRI();
	RPO.ActiveInteractPoint = self;
	if (Game != None && PRI != None && PRI.FactionID < Game.Factions.Length
		&& Game.IsCombatantFaction(PRI.FactionID))
		RPO.ClientOpenArmoryMenu(Game.Factions[PRI.FactionID].DutyLoadout);
	else if (Game != None)
		RPO.ClientOpenArmoryMenu(Game.OffDutyLoadout);
	else
		RPO.ClientOpenArmoryMenu("");

	LastUseTime = Level.TimeSeconds;
}


///////////////////////////////////////////////////////////////////////////////
// SERVER RPC ENTRY - [RESTOCK MUNITIONS] button
///////////////////////////////////////////////////////////////////////////////
function DoRestock(MilRPPlayer RPO)
{
	local MilRPGameInfo Game;
	local MilRPPlayerReplicationInfo PRI;
	local string Reason, Loadout;
	local array<string> Names;
	local int i;
	local Inventory NewInv, Inv;
	local class<Inventory> InvClass;
	local Weapon W;
	local Ammunition Am;

	if (RPO == None)
		return;
	if (!CheckAccess(RPO, Reason))
	{
		RPO.ClientRPNotify(Reason);
		return;
	}

	Game = GetGame();
	if (Game == None || RPO.Pawn == None)
		return;

	RPO.Pawn.PlaySound(Sound'WeaponSounds.weapon_pickup', SLOT_Interface, 1.0);

	// Re-issue the same kit the GUI advertised: faction duty loadout for
	// combatants, otherwise the off-duty set.
	PRI = RPO.GetRPPRI();
	if (PRI != None && PRI.FactionID < Game.Factions.Length
		&& Game.IsCombatantFaction(PRI.FactionID))
		Loadout = Game.Factions[PRI.FactionID].DutyLoadout;
	else
		Loadout = Game.OffDutyLoadout;

	// Explicit multiplayer attach for every missing kit piece: spawn
	// server-side, then GiveTo links it into the pawn's inventory chain and
	// replicates it to the client.
	class'MilRPGameInfo'.static.SplitLoadout(Loadout, Names);
	for (i = 0; i < Names.Length; i++)
	{
		if (Game.BaseMutator != None)
			InvClass = Game.BaseMutator.GetInventoryClass(Names[i]);
		else
			InvClass = class<Inventory>(DynamicLoadObject(Names[i], class'Class'));
		if (InvClass == None || RPO.Pawn.FindInventoryType(InvClass) != None)
			continue;
		NewInv = Spawn(InvClass, RPO.Pawn);
		if (NewInv == None)
			continue;
		NewInv.GiveTo(RPO.Pawn);
		W = Weapon(NewInv);
		if (W != None && W.AmmoType != None)
			W.AmmoType.AmmoAmount = W.AmmoType.MaxAmmo;
	}

	// Top off the ammo pools of everything already carried.
	for (Inv = RPO.Pawn.Inventory; Inv != None; Inv = Inv.Inventory)
	{
		Am = Ammunition(Inv);
		if (Am != None)
		{
			Am.AddAmmo(Am.MaxAmmo);
			continue;
		}
		W = Weapon(Inv);
		if (W != None && W.AmmoType != None)
			W.AmmoType.AddAmmo(W.AmmoType.MaxAmmo);
	}

	RPO.ClientRPNotify("Armory resupply complete.");
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	TargetFactionID=255
	MinimumRankRequired=0
	PointLabel="Press USE for armory"
	MenuTitle="Armory"
	bOffDutyOk=false

	DrawType=DT_StaticMesh
	// Compact green ammo crate - probe-verified mesh, sits flush via the
	// bottom-pivot rule, visually distinct from the shop's open crate.
	StaticMesh=StaticMesh'Zo_BaseMeshes.zo_base_ammocrate2'
	DrawScale=1.100000
	// Solid body: 'E' reaches UsedBy through MilRPPlayer.ServerUse's look-at
	// trace (bBlockZeroExtentTraces catches the crosshair line), so blocking
	// is safe again.
	bCollideActors=true
	bBlockActors=true
	bBlockPlayers=true
	bBlockZeroExtentTraces=true
	bBlockNonZeroExtentTraces=true
	UseRadius=150.000000
	CollisionRadius=60.000000
	CollisionHeight=50.000000
}
