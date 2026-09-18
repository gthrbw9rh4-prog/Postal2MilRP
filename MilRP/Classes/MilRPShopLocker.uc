///////////////////////////////////////////////////////////////////////////////
// MilRPShopLocker.uc
//
// Quartermaster supply crate. Pressing USE opens the mouse-driven
// MilRPShopInteraction catalog screen; [PURCHASE ITEM] routes back here
// through MilRPPlayer.ServerShopBuy -> DoPurchase, which charges the Wallet
// and issues the item into the pawn's inventory.
//
// Catalog is tuned in System\MilRP.ini under [MilRP.MilRPShopLocker]:
//   ShopInventory(0)=(WeaponClassPath="EDStuff.MP5Weapon",ItemName="MP5",Price=1500,RankLock=2)
//
// Per-instance filtering:
//   [MilRP.MilRPWorld] Placeables -> Extra="<ShopInventory index or ItemName>"
//   restricts this crate to that single item; empty Extra shows the full list.
///////////////////////////////////////////////////////////////////////////////
class MilRPShopLocker extends MilRPInteractPoint
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
struct ShopItemDef
{
	var string	WeaponClassPath;	// full engine class path (e.g. "EDStuff.MP5Weapon")
	var string	ItemName;			// visual label / selector name
	var int		Price;				// wallet cash cost
	var int		RankLock;			// minimum rank index required to buy
};

var config array<ShopItemDef>	ShopInventory;

var() int		TargetFactionID;		// owning faction id (255 = any faction)
var() int		MinimumRankRequired;	// locker-level minimum rank index
var() int		ShopItemIndex;			// catalog index used when Extra filters by index


///////////////////////////////////////////////////////////////////////////////
// INITIALISATION
///////////////////////////////////////////////////////////////////////////////
function PostBeginPlay()
{
	Super.PostBeginPlay();

	// The base PostBeginPlay sizes the cylinder to UseRadius for touch
	// detection; 'E' now routes through MilRPPlayer.ServerUse's look-at
	// trace, so shrink the cylinder to the solid body footprint instead.
	SetCollisionSize(60.0, CollisionHeight);

	if (MinimumRankRequired > RankRequired)
		RankRequired = MinimumRankRequired;
}

function RegisterWorld(MilRPWorld W)
{
	Super.RegisterWorld(W);
	TargetFactionID = PointFaction;
}


///////////////////////////////////////////////////////////////////////////////
// STOCK SELECTION / CATALOG PACKING
///////////////////////////////////////////////////////////////////////////////
function int ResolveShopIndex()
{
	local int i;
	local string Wanted;

	Wanted = Trim(ExtraConfig);
	if (Wanted != "")
	{
		// Numeric Extra = direct catalog index.
		if (Wanted == string(int(Wanted)))
			return int(Wanted);

		// Otherwise match against the configured ItemName.
		for (i = 0; i < ShopInventory.Length; i++)
			if (ShopInventory[i].ItemName ~= Wanted)
				return i;
	}

	return ShopItemIndex;
}

// Maps a UI row index back to a ShopInventory index, honoring the
// single-item filter when ExtraConfig names one entry.
function int MapCatalogIndex(int UIIndex)
{
	local int Idx;

	if (Trim(ExtraConfig) != "")
	{
		Idx = ResolveShopIndex();
		if (Idx >= 0 && Idx < ShopInventory.Length)
		{
			if (UIIndex == 0)
				return Idx;
			return -1;
		}
	}
	return UIIndex;
}

// "Name~Price~Rank|Name~Price~Rank|..."
function string PackCatalog()
{
	local int i, Idx;
	local string S;

	if (Trim(ExtraConfig) != "")
	{
		Idx = ResolveShopIndex();
		if (Idx >= 0 && Idx < ShopInventory.Length)
			return ShopInventory[Idx].ItemName $ "~" $ ShopInventory[Idx].Price $ "~" $ ShopInventory[Idx].RankLock;
	}

	for (i = 0; i < ShopInventory.Length && i < 16; i++)
	{
		if (S != "")
			S = S $ "|";
		S = S $ ShopInventory[i].ItemName $ "~" $ ShopInventory[i].Price $ "~" $ ShopInventory[i].RankLock;
	}
	return S;
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
// ACCESS GATE (server-side; shared by UsedBy and DoPurchase)
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
		FailReason = "Shop offline.";
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
			FailReason = "Access Denied: this shop belongs to " $ GRI.GetFactionName(TargetFactionID) $ ".";
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
		FailReason = "Cannot purchase while dead or spectating.";
		return false;
	}
	return true;
}


///////////////////////////////////////////////////////////////////////////////
// USETRIGGER HOOK - opens the shop GUI
///////////////////////////////////////////////////////////////////////////////
function UsedBy(Pawn user)
{
	local MilRPPlayer RPO;
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
	if (ShopInventory.Length == 0)
	{
		RPO.ClientRPNotify("Shop has no stock configured.");
		return;
	}

	RPO.ActiveInteractPoint = self;
	RPO.ClientOpenShopMenu(PackCatalog());
	LastUseTime = Level.TimeSeconds;
}


///////////////////////////////////////////////////////////////////////////////
// SERVER RPC ENTRY - [PURCHASE ITEM] button
///////////////////////////////////////////////////////////////////////////////
function DoPurchase(MilRPPlayer RPO, int UIIndex)
{
	local MilRPPlayerReplicationInfo PRI;
	local MilRPGameReplicationInfo GRI;
	local MilRPGameInfo Game;
	local ShopItemDef It;
	local string Reason;
	local int Idx;
	local class<Inventory> InvClass, GrantedClass;
	local class<Pickup> PickClass;
	local Pickup Pk;
	local Inventory NewInv, Existing;
	local Weapon LiveWeapon;
	local KevlarInv ArmorInv;
	local bool bAdminBypass;

	if (RPO == None)
		return;
	if (!CheckAccess(RPO, Reason))
	{
		RPO.ClientRPNotify(Reason);
		return;
	}

	Game = GetGame();
	PRI = RPO.GetRPPRI();
	GRI = RPO.GetRPGRI();
	// Supreme admin rule: staff issue items free of charge with no rank lock.
	bAdminBypass = Game.CheckPermission(RPO, 2);
	Idx = MapCatalogIndex(UIIndex);
	if (Idx < 0 || Idx >= ShopInventory.Length)
	{
		RPO.ClientRPNotify("Shop crate misconfigured.");
		return;
	}
	It = ShopInventory[Idx];

	if (!bAdminBypass && It.RankLock > PRI.Rank)
	{
		if (GRI != None)
			RPO.ClientRPNotify("Access Denied: requires rank " $ GRI.GetRankTitle(It.RankLock) $ ".");
		else
			RPO.ClientRPNotify("Access Denied: requires rank " $ It.RankLock $ ".");
		return;
	}
	if (It.WeaponClassPath == "")
	{
		RPO.ClientRPNotify("Item unavailable.");
		return;
	}

	// Resolve through the game mutator so single-player names remap onto
	// their ShareThePain (*WeaponSS) multiplayer classes.
	if (Game.BaseMutator != None)
		InvClass = Game.BaseMutator.GetInventoryClass(It.WeaponClassPath);
	else
		InvClass = class<Inventory>(DynamicLoadObject(It.WeaponClassPath, class'Class'));
	if (InvClass == None)
	{
		RPO.ClientRPNotify("Item unavailable.");
		return;
	}

	// Already-owned non-weapon items cannot be re-bought; already-owned
	// weapons convert the purchase into an ammunition resupply, and
	// already-owned armor converts into a fresh AddArmor top-up.
	Existing = RPO.Pawn.FindInventoryType(InvClass);
	if (Existing != None && Weapon(Existing) == None && KevlarInv(Existing) == None)
	{
		if (It.ItemName != "")
			RPO.ClientRPNotify("You already carry " $ It.ItemName $ ".");
		else
			RPO.ClientRPNotify("You already carry this item.");
		return;
	}

	// Authoritative wallet deduction; notifies on insufficient funds.
	// Admins skip the charge entirely - items are issued for free.
	if (!bAdminBypass && !Game.TryCharge(RPO, It.Price, "shop_purchase"))
	{
		RPO.ClientRPNotify("Insufficient funds: need $" $ It.Price $ ".");
		return;
	}

	if (Existing != None)
	{
		// Ammo resupply for a weapon they already carry, or an armor
		// refresh for a vest they already own.
		LiveWeapon = Weapon(Existing);
		if (LiveWeapon != None && LiveWeapon.AmmoType != None)
			LiveWeapon.AmmoType.AddAmmo(LiveWeapon.AmmoType.MaxAmmo);
		ArmorInv = KevlarInv(Existing);
		if (ArmorInv != None)
			ArmorInv.Activate(); // native AddArmor top-up
	}
	else
	{
		// Sticky-weapon reset: clear any stale server-side weapon pointers
		// before granting. A leftover PendingWeapon from a previous purchase
		// is what snapped the second buy back to the first gun selected.
		RPO.Pawn.PendingWeapon = None;

		// Native pickup delivery: spawn the item's pickup wrapper inside the
		// pawn's collision cylinder and force its Touch, so the grant runs
		// the exact same code as walking over a map pickup (SpawnCopy ->
		// GiveTo -> PickupFunction -> AnnouncePickup). That registers the
		// weapon's replicated HUD icon slot and ammo pools natively - which
		// direct Spawn+GiveTo never did, leaving blank hotbar icons.
		PickClass = InvClass.default.PickupClass;
		if (PickClass != None)
			Pk = Spawn(PickClass, , , RPO.Pawn.Location + vect(0,0,4.0));
		if (Pk != None)
		{
			GrantedClass = Pk.InventoryType;
			Pk.Touch(RPO.Pawn);
			if (GrantedClass != None)
				NewInv = RPO.Pawn.FindInventoryType(GrantedClass);
			if (NewInv == None)
				NewInv = RPO.Pawn.FindInventoryType(InvClass);
		}
		if (NewInv == None)
		{
			// Fallback: direct attach if the pickup wrapper failed to grant.
			NewInv = Spawn(InvClass, RPO.Pawn);
			if (NewInv == None)
			{
				if (!bAdminBypass)
					Game.AddCurrency(RPO, It.Price, "shop_refund");
				RPO.ClientRPNotify("Item issue failed: " $ It.ItemName $ ".");
				return;
			}
			NewInv.GiveTo(RPO.Pawn);

			// Armor items (KevlarInv/BodyArmorInv) are not Weapons - in the
			// fallback path Activate() runs the native P2Pawn.AddArmor grant.
			// (The pickup path already ran its own PickupFunction grant.)
			ArmorInv = KevlarInv(NewInv);
			if (ArmorInv != None)
				ArmorInv.Activate();
		}

		// Top off ammo on the granted weapon instance.
		LiveWeapon = Weapon(NewInv);
		if (LiveWeapon != None && LiveWeapon.AmmoType != None)
			LiveWeapon.AmmoType.AmmoAmount = LiveWeapon.AmmoType.MaxAmmo;
	}

	// Canonical engine weapon switch (same sequence as SwitchWeapon): set
	// PendingWeapon, ask the current weapon to lower itself via PutDown -
	// its finish event completes the swap. ChangedWeapon only fires
	// immediately when there is no current weapon to put down.
	if (LiveWeapon != None && RPO.Pawn.Weapon != LiveWeapon)
	{
		RPO.Pawn.PendingWeapon = LiveWeapon;
		if (RPO.Pawn.Weapon == None || !RPO.Pawn.Weapon.PutDown())
			RPO.Pawn.ChangedWeapon();
		// Authoritative network flush: Pawn.Weapon is not replicated to the
		// owner in this engine and the native ClientWeaponSet RPC is gated
		// by SwitchPriority (rifle=8), so the server->client ClientForceWeapon
		// RPC performs the same swap on the client, breaking the stasis.
		RPO.ClientForceWeapon(LiveWeapon);
	}

	// Record the purchase so duty/faction loadout transitions never strip it.
	RPO.MarkPurchased(InvClass);

	RPO.Pawn.PlaySound(Sound'WeaponSounds.weapon_pickup', SLOT_Interface, 1.0);
	if (bAdminBypass)
		RPO.ClientRPNotify("Issued " $ It.ItemName $ " (admin - no charge).");
	else if (It.ItemName != "")
		RPO.ClientRPNotify("Purchased " $ It.ItemName $ " for $" $ It.Price $ ".");
	else
		RPO.ClientRPNotify("Purchased " $ It.WeaponClassPath $ " for $" $ It.Price $ ".");

	if (World != None && !bAdminBypass)
		World.Logf("ECONOMY", RPO.PlayerReplicationInfo.PlayerName $ " | shop | " $ -It.Price $ " | " $ It.WeaponClassPath);
}


///////////////////////////////////////////////////////////////////////////////
// DEFAULTS
///////////////////////////////////////////////////////////////////////////////
defaultproperties
{
	TargetFactionID=255
	MinimumRankRequired=0
	ShopItemIndex=0
	PointLabel="Press USE to buy"
	MenuTitle="Quartermaster"
	bOffDutyOk=true

	DrawType=DT_StaticMesh
	StaticMesh=StaticMesh'Zo_BaseMeshes.zo_base_opencrate'
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
	CollisionHeight=60.000000

	ShopInventory(0)=(WeaponClassPath="Inventory.PistolWeaponSS",ItemName="Pistol",Price=250,RankLock=0)
	ShopInventory(1)=(WeaponClassPath="Inventory.ShotGunWeaponSS",ItemName="Shotgun",Price=800,RankLock=1)
	ShopInventory(2)=(WeaponClassPath="EDStuff.MP5Weapon",ItemName="MP5",Price=1500,RankLock=2)
	ShopInventory(3)=(WeaponClassPath="Inventory.BodyArmorInv",ItemName="Kevlar Vest",Price=400,RankLock=0)
}
