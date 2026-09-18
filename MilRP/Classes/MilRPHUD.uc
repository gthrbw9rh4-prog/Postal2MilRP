///////////////////////////////////////////////////////////////////////////////
// MilRPHUD.uc
//
// Roleplay overlay on top of the stock multiplayer HUD (MpHUD). Three
// elements, all purely client-side and driven only by already-replicated data:
//
//   1. Dashboard (top-right): faction, rank, duty badge, wallet, paycheck timer.
//      Sources: local MilRPPlayerReplicationInfo, MilRPPlayer.Wallet,
//      MilRPGameReplicationInfo tables.
//   2. Base broadcast feed (top-centre): the 6-slot ring buffer in
//      MilRPGameReplicationInfo. New lines are detected via BroadcastSerial,
//      time-stamped locally and faded out - no extra network traffic.
//   3. Notices (lower-centre): toasts queued by MilRPPlayer.ClientRPNotify.
//
// All positions are fractions of the (16:10 normalised) canvas so the layout
// survives any resolution; text goes through FontInfo.DrawTextEx which picks a
// resolution-appropriate font and draws the drop shadow for us.
///////////////////////////////////////////////////////////////////////////////
class MilRPHUD extends MpHUD
	config(MilRP);


///////////////////////////////////////////////////////////////////////////////
// CONFIGURATION
///////////////////////////////////////////////////////////////////////////////
// --- Dashboard
var config bool		bShowDashboard;
var config float	DashRightPX;			// right edge, fraction of width
var config float	DashTopPY;				// top edge, fraction of height
var config float	DashMinWidthPX;			// minimum panel width, fraction of width
var config float	DashPaddingPX;			// inner padding, fraction of width
var config int		DashFontSize;			// FontInfo size 0..3
var config bool		bShowPaycheckTimer;
var config bool		bShowWalletDelta;
var config float	WalletFlashDuration;	// seconds the +/-$ delta stays visible

// --- Broadcast feed
var config bool		bShowBroadcastFeed;
var config float	FeedCenterPX;
var config float	FeedTopPY;
var config float	FeedWidthPX;
var config int		FeedMaxLines;			// 1..6
var config int		FeedFontSize;
var config float	FeedLineLifetime;		// seconds before a line starts fading
var config float	FeedFadeDuration;		// seconds spent fading
var config bool		bFeedAlwaysShowHeader;

// --- Notices
var config bool		bShowNotices;
var config float	NoticeCenterPX;
var config float	NoticeBottomPY;			// bottom edge of the newest notice
var config int		NoticeFontSize;
var config float	NoticeFadeDuration;

// --- Alert banner
var config bool			bShowAlertBanner;
var config float		AlertBannerTopPY;

// --- Interaction prompt
var config bool			bShowInteractPrompt;
var config float		InteractPromptPY;

// --- In-world menu
var config bool			bShowMenu;
var config float		MenuCenterPX;
var config float		MenuTopPY;
var config float		MenuWidthPX;
var config int			MenuFontSize;

// --- Chat log + input
var config bool			bShowChatLog;
var config float		ChatLogLeftPX;
var config float		ChatLogBottomPY;
var config float		ChatLogWidthPX;
var config int			ChatLogMaxVisible;
var config int			ChatLogFontSize;
var config color		ChatLogColor;

// --- Interactive chat menu
var config int			ChatMenuMaxVisible;
var config float		ChatMenuBottomPY;
var config float		ChatMenuHeight;

// Used in place of the stock P2HUD.UltraWideOffsetX, which does not exist in
// the ShareThePain retail build.
var float				UltraWideOffsetX;

// --- Colours
var config color	PanelColor;				// background fill
var config color	PanelBorderColor;
var config color	LabelColor;				// dim labels
var config color	ValueColor;				// primary text
var config color	OnDutyColor;
var config color	OffDutyColor;
var config color	MoneyColor;
var config color	GainColor;
var config color	LossColor;
var config color	FeedHeaderColor;
var config color	FeedTextColor;
var config color	NoticeColor;
var config color	AlertColor;

// Localized labels (MilRP.int)
var localized string	DashOnDuty;
var localized string	DashOffDuty;
var localized string	DashNoFaction;
var localized string	DashPayIn;				// "PAY IN"
var localized string	DashRP;					// "RP"
var localized string	FeedHeader;				// "BASE COMMAND"
var localized string	CurrencySymbol;			// "$"


///////////////////////////////////////////////////////////////////////////////
// RUNTIME (client only)
///////////////////////////////////////////////////////////////////////////////
var int			CachedWallet;
var bool		bWalletCached;
var int			WalletDelta;
var float		WalletDeltaTime;

var byte		LastFeedSerial;
var bool		bFeedSerialValid;
var float		FeedStamp[6];			// Level.TimeSeconds each ring slot was last written

var float		LineH;					// measured text height for the dash font this frame
var float		BorderPS;				// border thickness in pixels this frame
var float		StatusBoxRight;			// right edge of the dashboard status box this frame
var float		StatusBoxBottom;		// bottom edge of the dashboard status box this frame


///////////////////////////////////////////////////////////////////////////////
// INIT
///////////////////////////////////////////////////////////////////////////////
simulated function PostBeginPlay()
{
	local int i;

	Super.PostBeginPlay();

	DashFontSize = Clamp(DashFontSize, 0, 3);
	FeedFontSize = Clamp(FeedFontSize, 0, 3);
	NoticeFontSize = Clamp(NoticeFontSize, 0, 3);
	FeedMaxLines = Clamp(FeedMaxLines, 1, 6);
	FeedLineLifetime = FMax(1.0, FeedLineLifetime);
	FeedFadeDuration = FMax(0.1, FeedFadeDuration);
	NoticeFadeDuration = FMax(0.1, NoticeFadeDuration);
	WalletFlashDuration = FMax(0.5, WalletFlashDuration);

	for (i = 0; i < 6; i++)
		FeedStamp[i] = -1000.0;
}


///////////////////////////////////////////////////////////////////////////////
// MASTER DRAW
///////////////////////////////////////////////////////////////////////////////
simulated function DrawHUD(Canvas Canvas)
{
	local MilRPPlayerReplicationInfo PRI;
	local MilRPGameReplicationInfo GRI;
	local MilRPPlayer RPOwner;
	local bool bNativeScores;

	// Suppress the native frag scoreboard inside Super.DrawHUD - the MilRP
	// roleplay board replaces it below whenever the engine asks for the
	// scoreboard or our Tab interaction is alive.
	bNativeScores = bShowScores;
	bShowScores = false;
	Super.DrawHUD(Canvas);
	bShowScores = bNativeScores;

	if (bHideHUD || IsMatchIntroRunning() || PlayerOwner == None || MyFont == None)
		return;

	RPOwner = MilRPPlayer(PlayerOwner);
	PRI = MilRPPlayerReplicationInfo(PlayerOwner.PlayerReplicationInfo);
	GRI = MilRPGameReplicationInfo(PlayerOwner.GameReplicationInfo);
	if (PRI == None || GRI == None)
		return;

	// The roleplay scoreboard takes over the whole overlay while it is up.
	if (bShowScores || (RPOwner != None && RPOwner.ActiveScoreboard != None))
	{
		DrawScoreboardMenu(Canvas, RPOwner, GRI);
		return;
	}

	// Cheap per-frame measurements shared by all panels
	Canvas.Font = MyFont.GetFont(DashFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", BorderPS, LineH);
	BorderPS = FMax(1.0, CanvasHeight / 480.0);

	UpdateFeedStamps(GRI);
	UpdateWalletDelta(RPOwner);

	if (bShowBroadcastFeed)
		DrawBroadcastFeed(Canvas, GRI);
	if (bShowAlertBanner)
		DrawAlertBanner(Canvas, GRI);
	if (bShowDashboard && !PRI.bOnlySpectator)
		DrawDashboard(Canvas, PRI, GRI, RPOwner);
	if (bShowMenu && RPOwner != None && RPOwner.bMenuOpen)
		DrawMenu(Canvas, RPOwner);
	if (bShowInteractPrompt && RPOwner != None
		&& RPOwner.ActiveArmoryMenu == None && RPOwner.ActiveShopMenu == None
		&& RPOwner.ActiveDEFCONMenu == None)
	{
		DrawInteractPrompt(Canvas, RPOwner);
		DrawCaptureMeter(Canvas, RPOwner, GRI);
	}
	if (bShowNotices && RPOwner != None)
		DrawNotices(Canvas, RPOwner);
	if (bShowChatLog && RPOwner != None)
		DrawChatLog(Canvas, RPOwner);
	if (RPOwner != None && RPOwner.IsTyping())
		DrawChatMenu(Canvas, RPOwner);
	if (RPOwner != None && RPOwner.ActiveAdminInteraction != None)
		DrawAdminMenu(Canvas, RPOwner);
	if (RPOwner != None && RPOwner.ActiveSpawnMenu != None)
		RPOwner.ActiveSpawnMenu.Draw(Canvas);
	if (RPOwner != None && RPOwner.ActiveArmoryMenu != None)
		DrawArmoryMenu(Canvas, RPOwner);
	if (RPOwner != None && RPOwner.ActiveShopMenu != None)
		DrawShopMenu(Canvas, RPOwner);
	if (RPOwner != None && RPOwner.ActiveDEFCONMenu != None)
		DrawDEFCONMenu(Canvas, RPOwner, GRI);
}


///////////////////////////////////////////////////////////////////////////////
// STATE TRACKING
///////////////////////////////////////////////////////////////////////////////
// Stamp every ring slot written since the last frame so each line can fade
// independently even if several arrived in the same replication update.
simulated function UpdateFeedStamps(MilRPGameReplicationInfo GRI)
{
	local int Delta, j, Idx;

	if (!bFeedSerialValid)
	{
		// First sight of the GRI: treat existing lines as fresh so late joiners
		// see the recent history instead of an empty feed.
		bFeedSerialValid = true;
		LastFeedSerial = GRI.BroadcastSerial;
		for (j = 0; j < 6; j++)
			if (GRI.BroadcastLines[j] != "")
				FeedStamp[j] = Level.TimeSeconds;
		return;
	}

	if (GRI.BroadcastSerial == LastFeedSerial)
		return;

	Delta = (int(GRI.BroadcastSerial) - int(LastFeedSerial) + 256) % 256;
	Delta = Min(Delta, 6);
	for (j = 0; j < Delta; j++)
	{
		Idx = (int(GRI.BroadcastCursor) - 1 - j + 12) % 6;
		FeedStamp[Idx] = Level.TimeSeconds;
	}
	LastFeedSerial = GRI.BroadcastSerial;
}

simulated function UpdateWalletDelta(MilRPPlayer RPOwner)
{
	if (RPOwner == None)
		return;
	if (!bWalletCached)
	{
		CachedWallet = RPOwner.Wallet;
		bWalletCached = true;
		return;
	}
	if (RPOwner.Wallet != CachedWallet)
	{
		WalletDelta = RPOwner.Wallet - CachedWallet;
		WalletDeltaTime = Level.TimeSeconds;
		CachedWallet = RPOwner.Wallet;
	}
}


///////////////////////////////////////////////////////////////////////////////
// DASHBOARD
///////////////////////////////////////////////////////////////////////////////
simulated function DrawDashboard(Canvas Canvas, MilRPPlayerReplicationInfo PRI, MilRPGameReplicationInfo GRI, MilRPPlayer RPOwner)
{
	local string FactionLine, RankLine, DutyLine, MoneyLine, BankLine, PayLine, RPLine, DeltaLine;
	local float X, Y, W, H, Pad, XL, YL, RightX, InnerRight, StripeW;
	local float LineW, MaxW;
	local color FactionTint, DutyColor;
	local int SecondsLeft;

	Pad = DashPaddingPX * CanvasWidth;
	StripeW = FMax(2.0, Pad * 0.5);

	// --- Compose text ------------------------------------------------------
	if (PRI.HasFaction() && GRI.IsValidFaction(PRI.FactionID))
	{
		FactionLine = "[" $ GRI.GetFactionTag(PRI.FactionID) $ "] " $ GRI.GetFactionName(PRI.FactionID);
		FactionTint = GRI.GetFactionColor(PRI.FactionID);
	}
	else
	{
		FactionLine = DashNoFaction;
		FactionTint = OffDutyColor;
	}

	RankLine = GRI.GetRankTitle(PRI.Rank);
	if (RankLine == "")
		RankLine = "-";

	if (PRI.bOnDuty)
	{
		DutyLine = DashOnDuty;
		DutyColor = OnDutyColor;
	}
	else
	{
		DutyLine = DashOffDuty;
		DutyColor = OffDutyColor;
	}

	if (RPOwner != None)
	{
		MoneyLine = CurrencySymbol $ FormatMoney(RPOwner.Wallet);
		BankLine = "Bank " $ CurrencySymbol $ FormatMoney(RPOwner.BankBalance);
	}
	else
	{
		MoneyLine = CurrencySymbol $ "0";
		BankLine = "Bank " $ CurrencySymbol $ "0";
	}

	RPLine = DashRP @ string(int(PRI.Score));

	if (bShowPaycheckTimer && GRI.PaycheckInterval > 0)
	{
		SecondsLeft = GRI.NextPaycheckTime - GRI.ElapsedTime;
		if (SecondsLeft < 0)
			SecondsLeft = 0;
		PayLine = DashPayIn @ FormatClock(SecondsLeft);
	}

	if (bShowWalletDelta && WalletDelta != 0 && Level.TimeSeconds - WalletDeltaTime < WalletFlashDuration)
	{
		if (WalletDelta > 0)
			DeltaLine = "+" $ CurrencySymbol $ FormatMoney(WalletDelta);
		else
			DeltaLine = "-" $ CurrencySymbol $ FormatMoney(-WalletDelta);
	}

	// --- Measure -----------------------------------------------------------
	Canvas.Font = MyFont.GetFont(DashFontSize, true, CanvasWidth);
	MaxW = DashMinWidthPX * CanvasWidth;

	Canvas.StrLen(FactionLine, XL, YL);					MaxW = FMax(MaxW, XL);
	Canvas.StrLen(RankLine $ "    " $ DutyLine, XL, YL);	MaxW = FMax(MaxW, XL);
	Canvas.StrLen(MoneyLine $ "    " $ PayLine, XL, YL);	MaxW = FMax(MaxW, XL);
	Canvas.StrLen(BankLine, XL, YL);					MaxW = FMax(MaxW, XL);
	Canvas.StrLen(RPLine $ "    " $ DeltaLine, XL, YL);	MaxW = FMax(MaxW, XL);

	W = MaxW + Pad * 2;
	H = LineH * 1.7 + LineH * 4 + Pad * 2 + LineH * 0.3;
	RightX = UltraWideOffsetX + DashRightPX * CanvasWidth;
	X = RightX - W;
	Y = DashTopPY * CanvasHeight;

	// Publish the status box rect so DrawInteractPrompt can anchor its [E]
	// badge directly underneath the faction/status panel.
	StatusBoxRight = RightX;
	StatusBoxBottom = Y + H;

	// --- Framed window: shadow, charcoal fill, faction-tinted border -------
	DrawMenuFrame(Canvas, X, Y, W, H,
		Canvas.MakeColor(20, 23, 28, 235),
		FadeColor(FactionTint, 1.0));

	// Header band: dark steel bar, faction accent stripe + rule, faction
	// name in the faction's own colour.
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(34, 38, 46, 245);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, LineH * 1.7);
	Canvas.DrawColor = FactionTint;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', FMax(3.0, StripeW), LineH * 1.7);
	Canvas.DrawColor.A = 170;
	Canvas.SetPos(X, Y + LineH * 1.7 - FMax(1.0, BorderPS));
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, FMax(1.0, BorderPS));

	// --- Text --------------------------------------------------------------
	X += Pad;
	Y += (LineH * 1.7 - LineH) * 0.5;
	InnerRight = RightX - Pad;

	// line 1: faction header (tinted)
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + FMax(3.0, StripeW) + Pad * 0.5, Y, FactionLine, DashFontSize, true, EJ_Left, FactionTint);
	Y = DashTopPY * CanvasHeight + LineH * 1.7 + Pad;

	// line 2: rank ....... duty badge
	MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, RankLine, DashFontSize, true, EJ_Left, ValueColor);
	Canvas.StrLen(DutyLine, LineW, YL);
	DrawBadge(Canvas, InnerRight - LineW - Pad * 0.5, Y, LineW + Pad, LineH, DutyColor);
	MyFont.DrawTextEx(Canvas, CanvasWidth, InnerRight, Y, DutyLine, DashFontSize, true, EJ_Right, ValueColor);
	Y += LineH;

	// line 3: wallet ....... paycheck countdown
	MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, MoneyLine, DashFontSize, true, EJ_Left, MoneyColor);
	if (PayLine != "")
		MyFont.DrawTextEx(Canvas, CanvasWidth, InnerRight, Y, PayLine, DashFontSize, true, EJ_Right, LabelColor);
	Y += LineH;

	// line 4: bank
	MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, BankLine, DashFontSize, true, EJ_Left, MoneyColor);
	Y += LineH;

	// line 5: RP score ....... wallet delta flash
	MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, RPLine, DashFontSize, true, EJ_Left, LabelColor);
	if (DeltaLine != "")
	{
		if (WalletDelta > 0)
			MyFont.DrawTextEx(Canvas, CanvasWidth, InnerRight, Y, DeltaLine, DashFontSize, true, EJ_Right,
				FadeColor(GainColor, 1.0 - (Level.TimeSeconds - WalletDeltaTime) / WalletFlashDuration));
		else
			MyFont.DrawTextEx(Canvas, CanvasWidth, InnerRight, Y, DeltaLine, DashFontSize, true, EJ_Right,
				FadeColor(LossColor, 1.0 - (Level.TimeSeconds - WalletDeltaTime) / WalletFlashDuration));
	}
}


///////////////////////////////////////////////////////////////////////////////
// BROADCAST FEED
///////////////////////////////////////////////////////////////////////////////
simulated function DrawBroadcastFeed(Canvas Canvas, MilRPGameReplicationInfo GRI)
{
	local int Age, Idx, Shown, i;
	local string Line;
	local float Alpha, X, Y, W, H, Pad, XL, YL, FeedLineH;
	local string Lines[6];
	local float Alphas[6];

	Canvas.Font = MyFont.GetFont(FeedFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, FeedLineH);
	Pad = DashPaddingPX * CanvasWidth * 0.75;

	// Collect visible lines newest-first, then render oldest at the top so the
	// feed reads like a log that scrolls upward.
	for (Age = 0; Age < FeedMaxLines; Age++)
	{
		Line = GRI.GetBroadcastLine(Age);
		if (Line == "")
			continue;
		Idx = (int(GRI.BroadcastCursor) - 1 - Age + 12) % 6;
		Alpha = FeedAlpha(FeedStamp[Idx]);
		if (Alpha <= 0.0)
			continue;
		Lines[Shown] = Line;
		Alphas[Shown] = Alpha;
		Shown++;
	}

	if (Shown == 0 && !bFeedAlwaysShowHeader)
		return;

	W = FeedWidthPX * CanvasWidth;
	X = UltraWideOffsetX + FeedCenterPX * CanvasWidth - W * 0.5;
	Y = FeedTopPY * CanvasHeight;
	H = Pad * 2 + FeedLineH * (Shown + 1) + FeedLineH * 0.25;

	DrawPanel(Canvas, X, Y, W, H);

	// header bar
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = FeedHeaderColor;
	Canvas.DrawColor.A = 90;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, FeedLineH + Pad);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + Pad * 0.5, FeedHeader, FeedFontSize, true, EJ_Center, FeedHeaderColor);
	Y += FeedLineH + Pad + FeedLineH * 0.25;

	// body, oldest first
	for (i = Shown - 1; i >= 0; i--)
	{
		Canvas.Font = MyFont.GetFont(FeedFontSize, true, CanvasWidth);
		Canvas.StrLen(Lines[i], XL, YL);
		if (XL > W - Pad * 2)
			Lines[i] = ClipToWidth(Canvas, Lines[i], W - Pad * 2);
		MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad, Y, Lines[i], FeedFontSize, true, EJ_Left, FadeColor(FeedTextColor, Alphas[i]));
		Y += FeedLineH;
	}
}

simulated function float FeedAlpha(float Stamp)
{
	local float Age;

	Age = Level.TimeSeconds - Stamp;
	if (Age < 0.0)
		return 1.0;
	if (Age <= FeedLineLifetime)
		return 1.0;
	if (Age >= FeedLineLifetime + FeedFadeDuration)
		return 0.0;
	return 1.0 - (Age - FeedLineLifetime) / FeedFadeDuration;
}


///////////////////////////////////////////////////////////////////////////////
// NOTICES
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
// ALERT BANNER
///////////////////////////////////////////////////////////////////////////////
simulated function DrawAlertBanner(Canvas Canvas, MilRPGameReplicationInfo GRI)
{
	local string Line;
	local float W, H, X, Y, XL, YL;
	local color C;

	// Banner only rides the screen for real alert states: level >= 3 is
	// DEFCON 2 (Ready) and DEFCON 1 (Lockdown). Peacetime/Vigilance/
	// Round-Clock are normal conditions and show no banner.
	if (GRI == None || GRI.AlertLevel < 3)
		return;

	// GetAlertName() already returns the full "DEFCON n - name" string.
	Line = GRI.GetAlertName();
	if (GRI.bLockdown)
		Line = Line $ " - LOCKDOWN";

	Canvas.Font = MyFont.GetFont(FeedFontSize, true, CanvasWidth);
	Canvas.StrLen(Line, XL, YL);
	W = FMin(XL + CanvasWidth * 0.04, CanvasWidth * 0.8);
	H = YL + CanvasHeight * 0.015;
	X = UltraWideOffsetX + CanvasWidth * 0.5 - W * 0.5;
	Y = AlertBannerTopPY * CanvasHeight;
	C = GRI.GetAlertColor();
	C.A = 140;

	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = C;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + H * 0.5 - YL * 0.5, Line, FeedFontSize, true, EJ_Center, GRI.GetAlertColor());
}


///////////////////////////////////////////////////////////////////////////////
// INTERACTION PROMPT
///////////////////////////////////////////////////////////////////////////////
simulated function DrawInteractPrompt(Canvas Canvas, MilRPPlayer RPOwner)
{
	local string Label;
	local float XL, YL, X, Y;
	local float IconS, IX, IY;
	local MilRPInteractPoint Pt;

	if (RPOwner == None)
		return;
	Pt = RPOwner.GetNearbyPoint();
	if (Pt == None)
		return;
	Label = Pt.PointLabel;
	if (Label == "")
		return;

	Canvas.Font = MyFont.GetFont(NoticeFontSize, true, CanvasWidth);
	Canvas.StrLen(Label, XL, YL);
	X = UltraWideOffsetX + CanvasWidth * 0.5 - XL * 0.5;
	Y = InteractPromptPY * CanvasHeight;

	MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, "[USE] " $ Label, NoticeFontSize, true, EJ_Left, NoticeColor);

	// Graphical [USE] icon block anchored to the status/faction dashboard:
	// the badge hangs directly under the panel's right edge, aligned with
	// the other status indicators. Falls back to the old right-edge position
	// when the dashboard isn't being drawn (e.g. spectating).
	IconS = YL * 3.2;
	if (StatusBoxRight > 0.0)
	{
		IX = StatusBoxRight - IconS;
		IY = StatusBoxBottom + BorderPS * 4.0;
	}
	else
	{
		IX = UltraWideOffsetX + CanvasWidth - IconS - CanvasWidth * 0.03;
		IY = CanvasHeight * 0.5 - IconS * 0.5;
	}

	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(30, 60, 30, 220);
	Canvas.SetPos(IX, IY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', IconS, IconS);
	// Crisp border so the badge reads as a framed widget, not a raw block.
	Canvas.DrawColor = Canvas.MakeColor(120, 200, 120, 255);
	Canvas.SetPos(IX, IY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', IconS, BorderPS);
	Canvas.SetPos(IX, IY + IconS - BorderPS);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', IconS, BorderPS);
	Canvas.SetPos(IX, IY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, IconS);
	Canvas.SetPos(IX + IconS - BorderPS, IY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, IconS);
	// Always draw the letter "E" - never depends on an optional icon texture
	// resolving client-side, so the widget can never render as an empty box.
	MyFont.DrawTextEx(Canvas, CanvasWidth, IX + IconS * 0.5, IY + IconS * 0.5 - YL * 0.7,
		"E", MenuFontSize + 1, true, EJ_Center, Canvas.MakeColor(255, 255, 255, 255));
	MyFont.DrawTextEx(Canvas, CanvasWidth, IX + IconS * 0.5, IY + IconS + YL * 0.2,
		"USE", NoticeFontSize, true, EJ_Center, LabelColor);
}


///////////////////////////////////////////////////////////////////////////////
// TERRITORY CAPTURE METER
// Localized widget under the crosshair whenever the pawn stands inside a
// MilRPCapturePoint radius. Shows the zone name, current holder, and a
// faction-coloured progress bar while a capture is in flight.
///////////////////////////////////////////////////////////////////////////////
simulated function DrawCaptureMeter(Canvas Canvas, MilRPPlayer RPOwner, MilRPGameReplicationInfo GRI)
{
	local MilRPCapturePoint CP, Best;
	local float D, BestD;
	local float W, H, X, Y, Pad, XL, YL, BarW, BarH, FillW;
	local string OwnerName, Head, ProgressLabel;
	local color OwnerColor, Accent;

	if (RPOwner == None || RPOwner.Pawn == None || GRI == None)
		return;

	// Nearest capture zone whose radius contains the pawn.
	BestD = 1000000.0;
	foreach DynamicActors(class'MilRPCapturePoint', CP)
	{
		if (CP == None)
			continue;
		D = VSize(CP.Location - RPOwner.Pawn.Location);
		if (D <= CP.CaptureRadius && D < BestD)
		{
			Best = CP;
			BestD = D;
		}
	}
	if (Best == None)
		return;

	Canvas.Font = MyFont.GetFont(NoticeFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, YL);
	Pad = BorderPS * 6.0;
	W = CanvasWidth * 0.34;
	H = YL * 2.4 + Pad * 2.0 + BorderPS * 5.0;
	X = UltraWideOffsetX + CanvasWidth * 0.5 - W * 0.5;
	Y = CanvasHeight * 0.60;

	// Owner label + accent colour follow the capturing faction while a
	// capture is in flight, otherwise the current holder.
	if (Best.CurrentOwnerID != 255)
	{
		OwnerName = GRI.GetFactionName(Best.CurrentOwnerID);
		OwnerColor = GRI.GetFactionColor(Best.CurrentOwnerID);
	}
	else
	{
		OwnerName = "Neutral";
		OwnerColor = Canvas.MakeColor(170, 170, 170, 255);
	}

	if (Best.CapturingFactionID != 255)
		Accent = GRI.GetFactionColor(Best.CapturingFactionID);
	else
		Accent = OwnerColor;

	// Framed body matching the dashboard/badge chrome.
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(18, 20, 24, 210);
	Canvas.SetPos(X + BorderPS * 2.0, Y + BorderPS * 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);
	Canvas.DrawColor = Canvas.MakeColor(22, 24, 30, 235);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);
	Canvas.DrawColor = Canvas.MakeColor(Accent.R, Accent.G, Accent.B, 255);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BorderPS);
	Canvas.SetPos(X, Y + H - BorderPS);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BorderPS);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, H);
	Canvas.SetPos(X + W - BorderPS, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, H);

	Head = Best.ZoneName $ "  |  " $ OwnerName;
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + Pad * 0.6,
		Head, NoticeFontSize, true, EJ_Center, OwnerColor);

	// Progress bar: dark trough, faction-coloured fill, percentage label.
	BarW = W - Pad * 2.0;
	BarH = YL * 0.8;
	FillW = BarW * float(Best.CaptureProgress) / 100.0;
	Canvas.DrawColor = Canvas.MakeColor(10, 10, 14, 255);
	Canvas.SetPos(X + Pad, Y + Pad + YL * 1.2);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BarW, BarH);
	if (FillW > 0.0)
	{
		Canvas.DrawColor = Canvas.MakeColor(Accent.R, Accent.G, Accent.B, 235);
		Canvas.SetPos(X + Pad, Y + Pad + YL * 1.2);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', FillW, BarH);
	}
	// Thin trough outline.
	Canvas.DrawColor = Canvas.MakeColor(90, 90, 100, 255);
	Canvas.SetPos(X + Pad, Y + Pad + YL * 1.2);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BarW, BorderPS);
	Canvas.SetPos(X + Pad, Y + Pad + YL * 1.2 + BarH - BorderPS);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BarW, BorderPS);
	Canvas.SetPos(X + Pad, Y + Pad + YL * 1.2);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, BarH);
	Canvas.SetPos(X + Pad + BarW - BorderPS, Y + Pad + YL * 1.2);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, BarH);

	if (Best.CapturingFactionID != 255)
		ProgressLabel = "CAPTURING " $ Best.CaptureProgress $ "%";
	else
		ProgressLabel = "SECURE";
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + Pad * 1.1 + YL * 1.2 + BarH * 0.5 - YL * 0.5,
		ProgressLabel, NoticeFontSize, true, EJ_Center, Canvas.MakeColor(255, 255, 255, 255));
}


///////////////////////////////////////////////////////////////////////////////
// IN-WORLD MENU
///////////////////////////////////////////////////////////////////////////////
simulated function DrawMenu(Canvas Canvas, MilRPPlayer RPOwner)
{
	local int i;
	local string Line;
	local float W, H, X, Y, XL, YL, LineH, Pad;
	local color C;

	if (RPOwner == None || !RPOwner.bMenuOpen || RPOwner.CurrentMenu.Count == 0)
		return;

	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, LineH);
	Pad = DashPaddingPX * CanvasWidth;

	W = MenuWidthPX * CanvasWidth;
	H = LineH * (RPOwner.CurrentMenu.Count + 2) + Pad * 2;
	X = UltraWideOffsetX + MenuCenterPX * CanvasWidth - W * 0.5;
	Y = MenuTopPY * CanvasHeight;

	DrawPanel(Canvas, X, Y, W, H);

	C = ValueColor;
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad, Y + Pad, RPOwner.CurrentMenu.Title, MenuFontSize, true, EJ_Left, C);
	Y += LineH + Pad;

	for (i = 0; i < RPOwner.CurrentMenu.Count && i < 8; i++)
	{
		Line = RPOwner.CurrentMenu.Options[i];
		Canvas.StrLen(Line, XL, YL);
		if (XL > W - Pad * 2)
			Line = ClipToWidth(Canvas, Line, W - Pad * 2);
		MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad, Y, Line, MenuFontSize, true, EJ_Left, LabelColor);
		Y += LineH;
	}
}


///////////////////////////////////////////////////////////////////////////////
// NOTICES
///////////////////////////////////////////////////////////////////////////////
simulated function DrawNotices(Canvas Canvas, MilRPPlayer RPOwner)
{
	local int i;
	local float Y, XL, YL, NoticeLineH, Alpha, Age, Pad, CenterX;
	local string Line;

	RPOwner.PruneNotices();
	if (RPOwner.Notices.Length == 0)
		return;

	Canvas.Font = MyFont.GetFont(NoticeFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, NoticeLineH);
	Pad = DashPaddingPX * CanvasWidth * 0.5;
	CenterX = UltraWideOffsetX + NoticeCenterPX * CanvasWidth;

	// newest at the bottom, stacking upward
	Y = NoticeBottomPY * CanvasHeight - NoticeLineH;
	for (i = RPOwner.Notices.Length - 1; i >= 0; i--)
	{
		Age = Level.TimeSeconds - RPOwner.Notices[i].Time;
		Alpha = 1.0;
		if (RPOwner.NoticeLifetime - Age < NoticeFadeDuration)
			Alpha = FClamp((RPOwner.NoticeLifetime - Age) / NoticeFadeDuration, 0.0, 1.0);
		if (Alpha <= 0.0)
			continue;

		Line = RPOwner.Notices[i].Text;
		Canvas.StrLen(Line, XL, YL);
		if (XL > CanvasWidth * 0.6)
			Line = ClipToWidth(Canvas, Line, CanvasWidth * 0.6);
		Canvas.StrLen(Line, XL, YL);

		DrawPanelAlpha(Canvas, CenterX - XL * 0.5 - Pad, Y - Pad * 0.25, XL + Pad * 2, NoticeLineH + Pad * 0.5, Alpha);
		MyFont.DrawTextEx(Canvas, CanvasWidth, CenterX, Y, Line, NoticeFontSize, true, EJ_Center, FadeColor(NoticeColor, Alpha));
		Y -= NoticeLineH + Pad;
	}
}


///////////////////////////////////////////////////////////////////////////////
// CHAT LOG
///////////////////////////////////////////////////////////////////////////////
simulated function DrawChatLog(Canvas Canvas, MilRPPlayer RPOwner)
{
	local int i, Start, Count;
	local float X, Y, W, LineH, XL, YL, Pad, Alpha, Age;
	local string Line;

	RPOwner.PruneChatLog();
	if (RPOwner.ChatLog.Length == 0)
		return;

	Count = Clamp(RPOwner.ChatLog.Length - RPOwner.ChatScrollOffset, 0, ChatLogMaxVisible);
	Start = RPOwner.ChatLog.Length - RPOwner.ChatScrollOffset - Count;

	Canvas.Font = MyFont.GetFont(ChatLogFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, LineH);
	Pad = DashPaddingPX * CanvasWidth;
	W = ChatLogWidthPX * CanvasWidth;
	X = UltraWideOffsetX + ChatLogLeftPX * CanvasWidth;
	Y = ChatLogBottomPY * CanvasHeight - Count * LineH;

	// Dark backing panel.
	DrawPanelAlpha(Canvas, X - Pad, Y - Pad, W + Pad * 2, Count * LineH + Pad * 2, 0.75);

	for (i = 0; i < Count; i++)
	{
		Line = RPOwner.ChatLog[Start + i].Text;
		Canvas.StrLen(Line, XL, YL);
		if (XL > W)
			Line = ClipToWidth(Canvas, Line, W);

		Age = Level.TimeSeconds - RPOwner.ChatLog[Start + i].Time;
		if (Age >= RPOwner.ChatLogLifetime - 5.0)
			Alpha = FClamp(1.0 - (Age - (RPOwner.ChatLogLifetime - 5.0)) / 5.0, 0.0, 1.0);
		else
			Alpha = 1.0;

		MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, Line, ChatLogFontSize, true, EJ_Left, FadeColor(ChatLogColor, Alpha));
		Y += LineH;
	}
}


///////////////////////////////////////////////////////////////////////////////
// INTERACTIVE CHAT MENU
///////////////////////////////////////////////////////////////////////////////
simulated function DrawChatMenu(Canvas Canvas, MilRPPlayer RPOwner)
{
	local int i, Start, Count;
	local float X, Y, W, LineH, XL, YL, Pad;
	local float MenuX, MenuY, MenuW, MenuH;
	local string Line;

	RPOwner.PruneChatLog();

	Canvas.Font = MyFont.GetFont(ChatLogFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, LineH);
	Pad = DashPaddingPX * CanvasWidth;
	W = ChatLogWidthPX * CanvasWidth;
	X = UltraWideOffsetX + ChatLogLeftPX * CanvasWidth;

	Count = Clamp(RPOwner.ChatLog.Length - RPOwner.ChatScrollOffset, 0, ChatMenuMaxVisible);
	Start = RPOwner.ChatLog.Length - RPOwner.ChatScrollOffset - Count;

	// Background panel that extends from the chat log area up to the menu top.
	MenuH = ChatMenuHeight * CanvasHeight;
	MenuY = ChatMenuBottomPY * CanvasHeight - MenuH;
	MenuX = X - Pad;
	MenuW = W + Pad * 2;
	DrawPanelAlpha(Canvas, MenuX, MenuY, MenuW, MenuH, 0.9);

	Y = ChatMenuBottomPY * CanvasHeight - Pad - LineH;
	for (i = 0; i < Count; i++)
	{
		Line = RPOwner.ChatLog[Start + Count - 1 - i].Text;
		Canvas.StrLen(Line, XL, YL);
		if (XL > W)
			Line = ClipToWidth(Canvas, Line, W);

		MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, Line, ChatLogFontSize, true, EJ_Left, ChatLogColor);
		Y -= LineH;
	}

	// Prompt area at the very bottom of the menu.
	Y = ChatMenuBottomPY * CanvasHeight - LineH - Pad * 0.5;
	MyFont.DrawTextEx(Canvas, CanvasWidth, X, Y, "Say:", ChatLogFontSize, true, EJ_Left, LabelColor);
}


///////////////////////////////////////////////////////////////////////////////
// ADMIN MENU
///////////////////////////////////////////////////////////////////////////////
simulated function DrawAdminMenu(Canvas Canvas, MilRPPlayer RPOwner)
{
	local GameReplicationInfo GRI;
	local PlayerReplicationInfo PRI;
	local MilRPPlayerReplicationInfo SelRPPRI;
	local MilRPPlayer TargetPlayer;
	local float X, Y, W, H, Pad, ListX, ListY, ListW, RightX, RightW, RowH, BtnW, BtnH, XL, YL;
	local float PanelTop, PanelBottom;
	local float MX, MY;
	local int Idx, Row, Col, HoverPlayer, HoverAction;
	local color SelColor;
	local string ActionNames[10];
	local string Label, Faction, Rank, Cash, Footer;

	ActionNames[0] = "[Kick]";
	ActionNames[1] = "[Ban]";
	ActionNames[2] = "[Warn]";
	ActionNames[3] = "[Freeze]";
	ActionNames[4] = "[Goto]";
	ActionNames[5] = "[Bring]";
	ActionNames[6] = "[Set DEFCON 3]";
	ActionNames[7] = "[Toggle Lockdown]";
	ActionNames[8] = "[Noclip]";
	ActionNames[9] = "[Slap]";

	GRI = PlayerOwner.GameReplicationInfo;
	if (GRI == None)
		return;

	// Main panel: centered, translucent grey.
	W = CanvasWidth * 0.80;
	H = CanvasHeight * 0.80;
	X = (CanvasWidth - W) * 0.5;
	Y = (CanvasHeight - H) * 0.5;
	PanelTop = Y;
	PanelBottom = Y + H;
	Pad = FMax(DashPaddingPX * CanvasWidth * 0.5, YL * 0.6);

	DrawMenuFrame(Canvas, X, Y, W, H, PanelColor, PanelBorderColor);
	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, YL);
	RowH = YL * 2.2;

	// Live mouse coordinates from the interaction
	MX = RPOwner.ActiveAdminInteraction.MouseX;
	MY = RPOwner.ActiveAdminInteraction.MouseY;

	// Command header band behind the board title.
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(38, 44, 60, 240);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, RowH + Pad);
	Canvas.DrawColor = Canvas.MakeColor(115, 95, 160, 255);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', FMax(4.0, BorderPS * 2.0), RowH + Pad);
	Canvas.DrawColor.A = 170;
	Canvas.SetPos(X, Y + RowH + Pad - FMax(1.0, BorderPS));
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, FMax(1.0, BorderPS));

	// Title.
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + Pad, "ADMIN CONTROL BOARD", MenuFontSize + 1, true, EJ_Center, ValueColor);

	// Left: player list.
	ListW = W * 0.38;
	RightX = X + ListW + Pad * 2;
	ListX = X + Pad;
	ListY = Y + Pad * 2 + RowH * 2;

	MyFont.DrawTextEx(Canvas, CanvasWidth, ListX, Y + Pad * 2 + RowH, "ONLINE PLAYERS", MenuFontSize, true, EJ_Left, LabelColor);
	Y = ListY;

	// Mouse-driven player highlight
	HoverPlayer = -1;
	if (GRI.PRIArray.Length > 0 && MX >= ListX && MX <= ListX + ListW && MY >= ListY && MY <= ListY + GRI.PRIArray.Length * RowH)
	{
		HoverPlayer = Clamp(int((MY - ListY) / RowH), 0, GRI.PRIArray.Length - 1);
		RPOwner.SelectedPlayerIndex = HoverPlayer;
	}

	for (Idx = 0; Idx < GRI.PRIArray.Length; Idx++)
	{
		PRI = GRI.PRIArray[Idx];
		if (PRI == None)
			continue;
		if (Idx == RPOwner.SelectedPlayerIndex)
		{
			DrawBadge(Canvas, X + Pad, Y + Idx * RowH, ListW - Pad * 2, RowH, OnDutyColor);
			SelColor = ValueColor;
		}
		else
			SelColor = LabelColor;
		MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad * 2, Y + Idx * RowH + RowH * 0.1, PRI.PlayerName, MenuFontSize, true, EJ_Left, SelColor);
	}

	// Right: action grid (2 columns x 5 rows) so long text stays safely bounded.
	MyFont.DrawTextEx(Canvas, CanvasWidth, RightX, Y - RowH, "ACTIONS", MenuFontSize, true, EJ_Left, LabelColor);
	RightW = X + W - Pad - RightX;
	BtnW = (RightW - Pad) / 2.0;
	BtnH = RowH * 1.9;

	// Mouse-driven action highlight
	HoverAction = -1;
	if (MX >= RightX && MX <= RightX + RightW && MY >= Y && MY <= Y + 5 * (BtnH + Pad))
	{
		Col = Clamp(int((MX - RightX) / (BtnW + Pad)), 0, 1);
		Row = Clamp(int((MY - Y) / (BtnH + Pad)), 0, 4);
		HoverAction = Row * 2 + Col;
		RPOwner.SelectedActionIndex = HoverAction;
	}

	// Capture the selected player's replicated freeze state for the freeze badge.
	SelRPPRI = None;
	if (RPOwner.SelectedPlayerIndex >= 0
		&& RPOwner.SelectedPlayerIndex < GRI.PRIArray.Length)
		SelRPPRI = MilRPPlayerReplicationInfo(GRI.PRIArray[RPOwner.SelectedPlayerIndex]);

	for (Idx = 0; Idx < 10; Idx++)
	{
		Row = Idx / 2;
		Col = Idx % 2;
		if (Idx == RPOwner.SelectedActionIndex)
		{
			DrawBadge(Canvas, RightX + Col * (BtnW + Pad), Y + Row * (BtnH + Pad), BtnW, BtnH, OnDutyColor);
			SelColor = ValueColor;
		}
		else
			SelColor = LabelColor;

		// Dynamic badges for freeze and noclip.
		Label = ActionNames[Idx];
		if (Idx == 3 && SelRPPRI != None)
		{
			if (SelRPPRI.bFrozen)
				Label = "[Freeze: YES]";
			else
				Label = "[Freeze: NO]";
		}
		else if (Idx == 8)
		{
			if (RPOwner.bNoclip && RPOwner.IsInState('PlayerHelicoptering'))
				Label = "[Noclip: ON]";
			else
				Label = "[Noclip: OFF]";
		}

		MyFont.DrawTextEx(Canvas, CanvasWidth,
			RightX + Col * (BtnW + Pad) + BtnW * 0.5,
			Y + Row * (BtnH + Pad) + BtnH * 0.5 - YL * 0.5,
			Label, MenuFontSize, true, EJ_Center, SelColor);
	}

	// Footer: selected player identity + full RP inspection pane.
	if (SelRPPRI != None)
	{
		TargetPlayer = MilRPPlayer(GRI.PRIArray[RPOwner.SelectedPlayerIndex].Owner);
		Faction = SelRPPRI.GetFactionName();
		Rank = SelRPPRI.GetRankTitle();
		if (Faction == "")
			Faction = "None";
		if (Rank == "")
			Rank = "Civilian";
		if (TargetPlayer != None)
			Cash = "Wallet $" $ string(TargetPlayer.Wallet);
		else
			Cash = "Wallet $0";

		Footer = "Selected: " $ SelRPPRI.PlayerName $ " | Net IP: " $ SelRPPRI.NetSignature
			$ " | Faction: " $ Faction $ " | Rank: " $ Rank $ " | " $ Cash;
		MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad, PanelBottom - Pad * 2 - YL,
			Footer, ChatLogFontSize, true, EJ_Left, LabelColor);
	}
	else
	{
		MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad, PanelBottom - Pad * 2 - YL,
			"No player selected",
			ChatLogFontSize, true, EJ_Left, LabelColor);
	}

	// Mouse hint.
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, PanelBottom - Pad * 3 - YL * 2,
		"Left click = select / execute     Right click / Esc = close",
		ChatLogFontSize, true, EJ_Center, LabelColor);

	// Draw cursor from the interaction's live coordinates.
	Canvas.SetPos(MX, MY);
	Canvas.Style = 5;
	Canvas.DrawColor = Canvas.MakeColor(255, 255, 255, 255);
	Canvas.DrawTile(Texture'UWindow.Icons.MouseCursor', 20, 20, 0, 0, 32, 32);

	// Sync the interaction's hit-box layout so clicks match this exact frame.
	if (RPOwner.ActiveAdminInteraction != None)
	{
		RPOwner.ActiveAdminInteraction.ListX = ListX;
		RPOwner.ActiveAdminInteraction.ListY = ListY;
		RPOwner.ActiveAdminInteraction.ListW = ListW;
		RPOwner.ActiveAdminInteraction.ListH = GRI.PRIArray.Length * RowH;
		RPOwner.ActiveAdminInteraction.ActionX = RightX;
		RPOwner.ActiveAdminInteraction.ActionY = Y;
		RPOwner.ActiveAdminInteraction.ActionW = RightW;
		RPOwner.ActiveAdminInteraction.ActionH = BtnH + Pad;
		RPOwner.ActiveAdminInteraction.RowH = RowH;
		RPOwner.ActiveAdminInteraction.Pad = Pad;
		RPOwner.ActiveAdminInteraction.BtnW = BtnW;
		RPOwner.ActiveAdminInteraction.BtnH = BtnH;
	}
}


// Olive-drab tactical crate screen for MilRPArmoryInteraction.
simulated function DrawArmoryMenu(Canvas Canvas, MilRPPlayer RPOwner)
{
	local float X, Y, W, H, Pad, RowH, XL, YL;
	local float ListX, ListY, ListW, RightX, BtnW, BtnH, BtnY, CloseY, SecY;
	local float MX, MY;
	local int i;
	local MilRPArmoryInteraction AI;
	local bool bHoverRestock, bHoverClose;

	AI = RPOwner.ActiveArmoryMenu;
	if (AI == None)
		return;

	W = CanvasWidth * 0.60;
	H = CanvasHeight * 0.60;
	X = (CanvasWidth - W) * 0.5;
	Y = (CanvasHeight - H) * 0.5;
	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, YL);
	Pad = FMax(DashPaddingPX * CanvasWidth * 0.5, YL * 0.6);
	RowH = YL * 2.2;

	MX = AI.MouseX;
	MY = AI.MouseY;

	// Framed olive-drab window: drop shadow, fill, crisp border.
	DrawMenuFrame(Canvas, X, Y, W, H,
		Canvas.MakeColor(24, 28, 20, 235), Canvas.MakeColor(100, 112, 78, 255));

	// Header band with olive accent stripe.
	DrawMenuHeader(Canvas, X, Y, W, RowH + Pad, "ARMORY STORAGE CRATE",
		Canvas.MakeColor(58, 68, 44, 245), Canvas.MakeColor(150, 170, 95, 255), Canvas.MakeColor(225, 230, 205, 255));

	// Left column: issued kit, with a section rule under the label. SecY is
	// the section-label band; ListY drops a full glyph height below it.
	ListX = X + Pad;
	SecY = Y + RowH + Pad * 2.0;
	ListY = SecY + YL + Pad;
	ListW = W * 0.5 - Pad;
	MyFont.DrawTextEx(Canvas, CanvasWidth, ListX, SecY,
		"ISSUED EQUIPMENT", MenuFontSize, true, EJ_Left, Canvas.MakeColor(165, 175, 145, 255));
	Canvas.DrawColor = Canvas.MakeColor(80, 90, 60, 200);
	Canvas.SetPos(ListX, SecY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);

	// Inset manifest pane: dark sunken box + thin border so an empty kit
	// reads as an empty manifest rather than dead space.
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(14, 17, 12, 220);
	Canvas.SetPos(ListX, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, Y + H - Pad - YL - Pad - ListY);
	Canvas.DrawColor = Canvas.MakeColor(70, 80, 55, 220);
	Canvas.SetPos(ListX, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);
	Canvas.SetPos(ListX, Y + H - Pad - YL - Pad);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);
	Canvas.SetPos(ListX, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, Y + H - Pad - YL - Pad - ListY);
	Canvas.SetPos(ListX + ListW, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, Y + H - Pad - YL - Pad - ListY);

	for (i = 0; i < AI.KitCount; i++)
		MyFont.DrawTextEx(Canvas, CanvasWidth, ListX + Pad, ListY + Pad + i * RowH + RowH * 0.1,
			"- " $ AI.KitLines[i], MenuFontSize, true, EJ_Left, ValueColor);
	if (AI.KitCount == 0)
		MyFont.DrawTextEx(Canvas, CanvasWidth, ListX + ListW * 0.5, ListY + (Y + H - Pad - YL - Pad - ListY) * 0.5,
			"(no kit configured)", MenuFontSize, true, EJ_Center, LabelColor);

	// Vertical divider between the manifest and the action column.
	Canvas.DrawColor = Canvas.MakeColor(70, 80, 55, 200);
	Canvas.SetPos(ListX + ListW + Pad * 1.5, SecY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, Y + H - Pad - YL - Pad - SecY);

	// Right column: section header + bordered restock + close buttons.
	BtnW = W * 0.35;
	BtnH = RowH * 1.9;
	RightX = X + W - BtnW - Pad;
	MyFont.DrawTextEx(Canvas, CanvasWidth, RightX, SecY,
		"SUPPLY ACTIONS", MenuFontSize, true, EJ_Left, Canvas.MakeColor(165, 175, 145, 255));
	Canvas.DrawColor = Canvas.MakeColor(80, 90, 60, 200);
	Canvas.SetPos(RightX, SecY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BtnW, 1.0);
	BtnY = ListY;

	bHoverRestock = (MX >= RightX && MX <= RightX + BtnW && MY >= BtnY && MY <= BtnY + BtnH);
	DrawMenuButton(Canvas, RightX, BtnY, BtnW, BtnH, "[RESTOCK MUNITIONS]", bHoverRestock,
		Canvas.MakeColor(55, 75, 40, 235), Canvas.MakeColor(90, 130, 60, 245),
		Canvas.MakeColor(120, 145, 85, 255), Canvas.MakeColor(240, 240, 220, 255));

	CloseY = BtnY + BtnH + Pad;
	bHoverClose = (MX >= RightX && MX <= RightX + BtnW && MY >= CloseY && MY <= CloseY + BtnH);
	DrawMenuButton(Canvas, RightX, CloseY, BtnW, BtnH, "[CLOSE]", bHoverClose,
		Canvas.MakeColor(80, 45, 40, 235), Canvas.MakeColor(140, 60, 50, 245),
		Canvas.MakeColor(150, 85, 75, 255), Canvas.MakeColor(240, 220, 210, 255));

	// Footer rule + hint.
	Canvas.DrawColor = Canvas.MakeColor(70, 78, 55, 200);
	Canvas.SetPos(X + Pad, Y + H - Pad - YL - Pad * 0.5);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W - Pad * 2.0, 1.0);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + H - Pad - YL,
		"Esc or Right-click to close", ChatLogFontSize, true, EJ_Center, LabelColor);

	// Cursor.
	Canvas.SetPos(MX, MY);
	Canvas.Style = 5;
	Canvas.DrawColor = Canvas.MakeColor(255, 255, 255, 255);
	Canvas.DrawTile(Texture'UWindow.Icons.MouseCursor', 20, 20, 0, 0, 32, 32);

	// Sync the interaction's hit-box layout so clicks match this exact frame.
	AI.PanelX = X; AI.PanelY = Y; AI.PanelW = W; AI.PanelH = H;
	AI.ListX = ListX; AI.ListY = ListY; AI.ListW = ListW;
	AI.RowH = RowH; AI.Pad = Pad;
	AI.BtnX = RightX; AI.BtnY = BtnY; AI.BtnW = BtnW; AI.BtnH = BtnH;
	AI.CloseX = RightX; AI.CloseY = CloseY;
}


// Gunmetal quartermaster catalog screen for MilRPShopInteraction.
simulated function DrawShopMenu(Canvas Canvas, MilRPPlayer RPOwner)
{
	local float X, Y, W, H, Pad, RowH, XL, YL;
	local float ListX, ListY, ListW, DX, BtnW, BtnH, BtnY, CloseY, SecY;
	local float MX, MY, IY;
	local int i;
	local MilRPShopInteraction SI;
	local bool bHoverBuy, bHoverClose, bHover;
	local color RowColor;

	SI = RPOwner.ActiveShopMenu;
	if (SI == None)
		return;

	W = CanvasWidth * 0.65;
	H = CanvasHeight * 0.65;
	X = (CanvasWidth - W) * 0.5;
	Y = (CanvasHeight - H) * 0.5;
	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, YL);
	Pad = FMax(DashPaddingPX * CanvasWidth * 0.5, YL * 0.6);
	RowH = YL * 2.2;

	MX = SI.MouseX;
	MY = SI.MouseY;

	// Framed gunmetal window: drop shadow, fill, crisp border.
	DrawMenuFrame(Canvas, X, Y, W, H,
		Canvas.MakeColor(22, 24, 30, 235), Canvas.MakeColor(82, 92, 120, 255));

	// Header band with steel-blue accent stripe.
	DrawMenuHeader(Canvas, X, Y, W, RowH + Pad, "QUARTERMASTER SUPPLY",
		Canvas.MakeColor(45, 52, 68, 245), Canvas.MakeColor(95, 140, 220, 255), Canvas.MakeColor(215, 220, 235, 255));
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W - Pad, Y + Pad * 0.9,
		"Wallet: $" $ RPOwner.Wallet, MenuFontSize, true, EJ_Right, MoneyColor);

	// Left column: catalog rows. SecY is the section-label band (clears the
	// header band); ListY drops a full glyph height below label + rule.
	ListX = X + Pad;
	SecY = Y + RowH + Pad * 2.0;
	ListY = SecY + YL + Pad;
	ListW = W * 0.55 - Pad;
	MyFont.DrawTextEx(Canvas, CanvasWidth, ListX, SecY,
		"CATALOG", MenuFontSize, true, EJ_Left, Canvas.MakeColor(150, 160, 180, 255));
	Canvas.DrawColor = Canvas.MakeColor(75, 85, 110, 200);
	Canvas.SetPos(ListX, SecY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);

	// Inset catalog pane behind the rows (matches the armory manifest pane).
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(14, 16, 20, 220);
	Canvas.SetPos(ListX - Pad * 0.5, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW + Pad, Y + H - Pad - YL - Pad - ListY);
	Canvas.DrawColor = Canvas.MakeColor(70, 78, 100, 220);
	Canvas.SetPos(ListX - Pad * 0.5, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW + Pad, 1.0);
	Canvas.SetPos(ListX - Pad * 0.5, Y + H - Pad - YL - Pad);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW + Pad, 1.0);
	Canvas.SetPos(ListX - Pad * 0.5, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, Y + H - Pad - YL - Pad - ListY);
	Canvas.SetPos(ListX - Pad * 0.5 + ListW + Pad, ListY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, Y + H - Pad - YL - Pad - ListY);

	for (i = 0; i < SI.ItemCount; i++)
	{
		IY = ListY + i * RowH;
		bHover = (MX >= ListX && MX <= ListX + ListW && MY >= IY && MY <= IY + RowH);
		if (i == SI.SelectedIndex)
		{
			// Selected row: solid highlight + left accent stripe.
			Canvas.DrawColor = Canvas.MakeColor(60, 75, 110, 235);
			Canvas.SetPos(ListX - Pad * 0.5, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW + Pad, RowH);
			Canvas.DrawColor = Canvas.MakeColor(95, 140, 220, 255);
			Canvas.SetPos(ListX - Pad * 0.5, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', FMax(3.0, BorderPS), RowH);
		}
		else if (bHover)
		{
			Canvas.DrawColor = Canvas.MakeColor(45, 55, 80, 220);
			Canvas.SetPos(ListX - Pad * 0.5, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW + Pad, RowH);
		}
		if (i == SI.SelectedIndex)
			RowColor = Canvas.MakeColor(255, 215, 100, 255);
		else if (bHover)
			RowColor = Canvas.MakeColor(230, 235, 255, 255);
		else
			RowColor = Canvas.MakeColor(200, 200, 210, 255);
		MyFont.DrawTextEx(Canvas, CanvasWidth, ListX + Pad * 0.5, IY + RowH * 0.1,
			SI.ItemNames[i] $ "  ($" $ SI.ItemPrices[i] $ ")", MenuFontSize, true, EJ_Left, RowColor);
		if (SI.ItemRanks[i] > 0)
			MyFont.DrawTextEx(Canvas, CanvasWidth, ListX + ListW, IY + RowH * 0.1,
				"[R:" $ SI.ItemRanks[i] $ "]", MenuFontSize, true, EJ_Right, Canvas.MakeColor(200, 160, 120, 255));
	}
	if (SI.ItemCount == 0)
		MyFont.DrawTextEx(Canvas, CanvasWidth, ListX, ListY,
			"(crate empty)", MenuFontSize, true, EJ_Left, LabelColor);

	// Right column: framed detail box + purchase buttons.
	DX = X + W * 0.58;
	BtnW = X + W - Pad - DX;
	BtnH = RowH * 1.9;
	// Buttons sit below the full details block (name + price + rank line)
	// so the readout can never render behind the buttons.
	BtnY = ListY + Pad * 0.5 + RowH * 1.6 + YL + Pad;

	MyFont.DrawTextEx(Canvas, CanvasWidth, DX, SecY,
		"DETAILS", MenuFontSize, true, EJ_Left, Canvas.MakeColor(150, 160, 180, 255));
	Canvas.DrawColor = Canvas.MakeColor(75, 85, 110, 200);
	Canvas.SetPos(DX, SecY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BtnW, 1.0);

	if (SI.SelectedIndex >= 0 && SI.SelectedIndex < SI.ItemCount)
	{
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX, ListY + Pad * 0.5,
			SI.ItemNames[SI.SelectedIndex], MenuFontSize, true, EJ_Left, Canvas.MakeColor(230, 230, 240, 255));
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX, ListY + Pad * 0.5 + RowH * 0.8,
			"Price: $" $ SI.ItemPrices[SI.SelectedIndex], MenuFontSize, true, EJ_Left, MoneyColor);
		if (SI.ItemRanks[SI.SelectedIndex] > 0)
			MyFont.DrawTextEx(Canvas, CanvasWidth, DX, ListY + Pad * 0.5 + RowH * 1.6,
				"Requires rank " $ SI.ItemRanks[SI.SelectedIndex], MenuFontSize, true, EJ_Left, Canvas.MakeColor(220, 170, 120, 255));
	}
	else
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX, ListY + Pad * 0.5,
			"Select an item.", MenuFontSize, true, EJ_Left, LabelColor);

	bHoverBuy = (MX >= DX && MX <= DX + BtnW && MY >= BtnY && MY <= BtnY + BtnH);
	DrawMenuButton(Canvas, DX, BtnY, BtnW, BtnH, "[PURCHASE ITEM]", bHoverBuy,
		Canvas.MakeColor(35, 75, 40, 235), Canvas.MakeColor(60, 120, 60, 245),
		Canvas.MakeColor(95, 160, 95, 255), Canvas.MakeColor(230, 240, 225, 255));

	CloseY = BtnY + BtnH + Pad;
	bHoverClose = (MX >= DX && MX <= DX + BtnW && MY >= CloseY && MY <= CloseY + BtnH);
	DrawMenuButton(Canvas, DX, CloseY, BtnW, BtnH, "[CLOSE]", bHoverClose,
		Canvas.MakeColor(80, 45, 40, 235), Canvas.MakeColor(140, 60, 50, 245),
		Canvas.MakeColor(150, 85, 75, 255), Canvas.MakeColor(240, 220, 210, 255));

	// Footer rule + hint.
	Canvas.DrawColor = Canvas.MakeColor(70, 78, 100, 200);
	Canvas.SetPos(X + Pad, Y + H - Pad - YL - Pad * 0.5);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W - Pad * 2.0, 1.0);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + H - Pad - YL,
		"Esc or Right-click to close", ChatLogFontSize, true, EJ_Center, LabelColor);

	// Cursor.
	Canvas.SetPos(MX, MY);
	Canvas.Style = 5;
	Canvas.DrawColor = Canvas.MakeColor(255, 255, 255, 255);
	Canvas.DrawTile(Texture'UWindow.Icons.MouseCursor', 20, 20, 0, 0, 32, 32);

	// Sync the interaction's hit-box layout so clicks match this exact frame.
	SI.PanelX = X; SI.PanelY = Y; SI.PanelW = W; SI.PanelH = H;
	SI.ListX = ListX; SI.ListY = ListY; SI.ListW = ListW;
	SI.RowH = RowH; SI.Pad = Pad;
	SI.BtnX = DX; SI.BtnY = BtnY; SI.BtnW = BtnW; SI.BtnH = BtnH;
	SI.CloseX = DX; SI.CloseY = CloseY;
}


// Dark steel DEFCON control board for MilRPDEFCONInteraction.
simulated function DrawDEFCONMenu(Canvas Canvas, MilRPPlayer RPOwner, MilRPGameReplicationInfo GRI)
{
	local float X, Y, W, H, Pad, RowH, XL, YL;
	local float ListX, ListY, ListW, DX, BtnW, BtnH, CloseY, StatusH;
	local float MX, MY, IY, StripeW, TitleY, TitleH, HeadY;
	local int i, CurBtn, Mins, Secs;
	local MilRPDEFCONInteraction DI;
	local bool bHover, bHoverClose;
	local color BtnColor, TxtColor;
	local string BtnLabel, TimeStr;

	DI = RPOwner.ActiveDEFCONMenu;
	if (DI == None)
		return;

	W = CanvasWidth * 0.62;
	H = CanvasHeight * 0.55;
	X = (CanvasWidth - W) * 0.5;
	Y = (CanvasHeight - H) * 0.5;
	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, YL);
	Pad = FMax(DashPaddingPX * CanvasWidth * 0.5, YL * 0.6);
	RowH = YL * 2.2;

	MX = DI.MouseX;
	MY = DI.MouseY;

	// Dark steel window: drop shadow, fill, brass border.
	DrawMenuFrame(Canvas, X, Y, W, H,
		Canvas.MakeColor(28, 30, 36, 235), Canvas.MakeColor(125, 108, 62, 255));

	// Caution-striped accent across the top: alternating yellow/black bands.
	StripeW = FMax(12.0, W / 40.0);
	for (i = 0; i * StripeW < W; i++)
	{
		if (i % 2 == 0)
			Canvas.DrawColor = Canvas.MakeColor(220, 180, 40, 255);
		else
			Canvas.DrawColor = Canvas.MakeColor(25, 25, 25, 255);
		Canvas.SetPos(X + i * StripeW, Y);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', StripeW, BorderPS * 4.0);
	}

	// Title band: measured at its own font size so the column headers below
	// can be spaced clear of both the hazard stripe and the title glyphs.
	TitleY = Y + BorderPS * 4.0 + Pad * 0.5;
	Canvas.Font = MyFont.GetFont(MenuFontSize + 1, true, CanvasWidth);
	Canvas.StrLen("DEFCON CONTROL TERMINAL", XL, TitleH);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad, TitleY,
		"DEFCON CONTROL TERMINAL", MenuFontSize + 1, true, EJ_Left, Canvas.MakeColor(230, 200, 90, 255));

	// Column header row sits a full title-height below the title - the old
	// single-Pad offset let the headers bleed into the title text.
	HeadY = TitleY + TitleH + Pad * 0.6;

	// Which button reflects the live server level (2->0, 3->1, >=4->2).
	if (GRI != None)
	{
		if (GRI.AlertLevel <= 2)
			CurBtn = 0;
		else if (GRI.AlertLevel == 3)
			CurBtn = 1;
		else
			CurBtn = 2;
	}
	else
		CurBtn = -1;

	// Left column: three threat-level buttons. StatusH measures the right
	// status pane's real content height (4 label+value blocks); BtnH is then
	// solved so the left button column and the right status+close column
	// bottom-align exactly.
	ListX = X + Pad;
	ListY = HeadY + YL + Pad;
	ListW = W * 0.55 - Pad;
	StatusH = Pad * 1.2 + YL * 9.8;
	BtnH = (StatusH - Pad) * 0.5;

	MyFont.DrawTextEx(Canvas, CanvasWidth, ListX, HeadY,
		"THREAT CONDITION", MenuFontSize, true, EJ_Left, Canvas.MakeColor(160, 165, 175, 255));
	Canvas.DrawColor = Canvas.MakeColor(85, 85, 95, 200);
	Canvas.SetPos(ListX, HeadY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);

	for (i = 0; i < 3; i++)
	{
		IY = ListY + i * (BtnH + Pad);
		bHover = (MX >= ListX && MX <= ListX + ListW && MY >= IY && MY <= IY + BtnH);

		switch (i)
		{
			case 0:
				BtnColor = Canvas.MakeColor(35, 70, 35, 235);
				if (bHover) BtnColor = Canvas.MakeColor(50, 110, 50, 235);
				if (CurBtn == 0) BtnColor = Canvas.MakeColor(45, 140, 45, 255);
				BtnLabel = "DEFCON 3 - NORMAL CONDITION";
				break;
			case 1:
				BtnColor = Canvas.MakeColor(85, 70, 25, 235);
				if (bHover) BtnColor = Canvas.MakeColor(140, 115, 40, 235);
				if (CurBtn == 1) BtnColor = Canvas.MakeColor(190, 155, 40, 255);
				BtnLabel = "DEFCON 2 - ELEVATED ALERT";
				break;
			default:
				BtnColor = Canvas.MakeColor(80, 30, 28, 235);
				if (bHover) BtnColor = Canvas.MakeColor(140, 45, 40, 235);
				if (CurBtn == 2) BtnColor = Canvas.MakeColor(200, 50, 45, 255);
				BtnLabel = "DEFCON 1 - TACTICAL LOCKDOWN";
				break;
		}

		Canvas.DrawColor = BtnColor;
		Canvas.SetPos(ListX, IY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, BtnH);

		// Thin dark edge on every button for definition.
		Canvas.DrawColor = Canvas.MakeColor(15, 15, 18, 255);
		Canvas.SetPos(ListX, IY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);
		Canvas.SetPos(ListX, IY + BtnH - 1.0);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);
		Canvas.SetPos(ListX, IY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, BtnH);
		Canvas.SetPos(ListX + ListW - 1.0, IY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, BtnH);

		// Bright edge on the active level.
		if (CurBtn == i)
		{
			Canvas.DrawColor = Canvas.MakeColor(255, 255, 255, 255);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, BorderPS);
			Canvas.SetPos(ListX, IY + BtnH - BorderPS);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, BorderPS);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, BtnH);
			Canvas.SetPos(ListX + ListW - BorderPS, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, BtnH);
		}

		TxtColor = Canvas.MakeColor(235, 235, 230, 255);
		MyFont.DrawTextEx(Canvas, CanvasWidth, ListX + ListW * 0.5, IY + BtnH * 0.5 - YL * 0.5,
			BtnLabel, MenuFontSize, true, EJ_Center, TxtColor);
	}

	// Right column: live server status readout.
	DX = X + W * 0.58;
	BtnW = X + W - Pad - DX;

	MyFont.DrawTextEx(Canvas, CanvasWidth, DX, HeadY,
		"SERVER STATUS", MenuFontSize, true, EJ_Left, Canvas.MakeColor(160, 165, 175, 255));
	Canvas.DrawColor = Canvas.MakeColor(85, 85, 95, 200);
	Canvas.SetPos(DX, HeadY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BtnW, 1.0);

	// Status pane sized to its real content: top pad + 4 label/value blocks.
	DrawPanelAlpha(Canvas, DX, ListY, BtnW, StatusH, 0.9);

	IY = ListY + Pad * 0.6;
	if (GRI != None)
	{
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
			"THREAT TIER", ChatLogFontSize, true, EJ_Left, LabelColor);
		IY += YL;
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
			GRI.GetAlertName(), MenuFontSize, true, EJ_Left, GRI.GetAlertColor());
		IY += YL * 1.6;

		MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
			"LOCKDOWN", ChatLogFontSize, true, EJ_Left, LabelColor);
		IY += YL;
		if (GRI.bLockdown)
			MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
				"ENGAGED - base sealed", MenuFontSize, true, EJ_Left, Canvas.MakeColor(230, 80, 70, 255));
		else
			MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
				"Standby", MenuFontSize, true, EJ_Left, ValueColor);
		IY += YL * 1.6;

		Mins = GRI.ElapsedTime / 60;
		Secs = GRI.ElapsedTime % 60;
		if (Secs < 10)
			TimeStr = "T+" $ Mins $ ":0" $ Secs;
		else
			TimeStr = "T+" $ Mins $ ":" $ Secs;
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
			"SERVER TIME", ChatLogFontSize, true, EJ_Left, LabelColor);
		IY += YL;
		MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
			TimeStr, MenuFontSize, true, EJ_Left, ValueColor);
		IY += YL * 1.6;

		MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
			"SIREN NETWORK", ChatLogFontSize, true, EJ_Left, LabelColor);
		IY += YL;
		if (GRI.AlertLevel >= 4)
			MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
				"KLAXON ACTIVE", MenuFontSize, true, EJ_Left, Canvas.MakeColor(230, 80, 70, 255));
		else if (GRI.AlertLevel == 3)
			MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
				"Alert tone loop", MenuFontSize, true, EJ_Left, Canvas.MakeColor(220, 180, 60, 255));
		else
			MyFont.DrawTextEx(Canvas, CanvasWidth, DX + Pad * 0.5, IY,
				"Silent", MenuFontSize, true, EJ_Left, ValueColor);
	}

	// [CLOSE] under the status box; bottom-aligns with the left column.
	CloseY = ListY + StatusH + Pad;
	bHoverClose = (MX >= DX && MX <= DX + BtnW && MY >= CloseY && MY <= CloseY + BtnH);
	DrawMenuButton(Canvas, DX, CloseY, BtnW, BtnH, "[CLOSE]", bHoverClose,
		Canvas.MakeColor(80, 45, 40, 235), Canvas.MakeColor(140, 60, 50, 245),
		Canvas.MakeColor(150, 85, 75, 255), Canvas.MakeColor(240, 220, 210, 255));

	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + H - Pad - YL,
		"Esc or Right-click to close", ChatLogFontSize, true, EJ_Center, LabelColor);

	// Cursor.
	Canvas.SetPos(MX, MY);
	Canvas.Style = 5;
	Canvas.DrawColor = Canvas.MakeColor(255, 255, 255, 255);
	Canvas.DrawTile(Texture'UWindow.Icons.MouseCursor', 20, 20, 0, 0, 32, 32);

	// Sync the interaction's hit-box layout so clicks match this exact frame.
	DI.PanelX = X; DI.PanelY = Y; DI.PanelW = W; DI.PanelH = H;
	DI.ListX = ListX; DI.ListY = ListY; DI.ListW = ListW;
	DI.RowH = RowH; DI.Pad = Pad;
	DI.BtnW = BtnW; DI.BtnH = BtnH;
	DI.CloseX = DX; DI.CloseY = CloseY;
}


///////////////////////////////////////////////////////////////////////////////
// ROLEPLAY SCOREBOARD (Tab)
///////////////////////////////////////////////////////////////////////////////
// Framed dark-slate roster replacing the native frag scoreboard. Drawn while
// the MilRPScoreboardMenu interaction is alive (Tab held) or the legacy
// bShowScores flag is set (F1). All hitbox geometry is synced back to the
// interaction so its clicks always match the pixels on screen.
simulated function DrawScoreboardMenu(Canvas Canvas, MilRPPlayer RPOwner, MilRPGameReplicationInfo GRI)
{
	local float X, Y, W, H, Pad, RowH, XL, YL;
	local float ListX, ListY, ListW, SecY, TeleY, FootY, MX, MY, IY, DIY;
	local float ColX[5], ColW[5];
	local int i, Count, Drawn, Mins, Secs;
	local bool bAdmin, bMouseLive, bHover, bIsSelf;
	local MilRPScoreboardMenu SM;
	local PlayerReplicationInfo PRI;
	local MilRPPlayerReplicationInfo RPPRI;
	local MilRPPlayer OtherP;
	local color RowColor;
	local string WalletStr, TimeStr;

	SM = None;
	bMouseLive = false;
	MX = 0.0;
	MY = 0.0;
	if (RPOwner != None && RPOwner.ActiveScoreboard != None)
	{
		SM = RPOwner.ActiveScoreboard;
		bMouseLive = SM.bMouseActive;
		MX = SM.MouseX;
		MY = SM.MouseY;
	}

	// --- Centered slate window ------------------------------------------
	W = CanvasWidth * 0.78;
	H = CanvasHeight * 0.74;
	X = (CanvasWidth - W) * 0.5;
	Y = (CanvasHeight - H) * 0.5;
	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen("Xg", XL, YL);
	Pad = FMax(DashPaddingPX * CanvasWidth * 0.5, YL * 0.6);
	RowH = YL * 2.0;

	DrawMenuFrame(Canvas, X, Y, W, H,
		Canvas.MakeColor(24, 26, 33, 238), Canvas.MakeColor(92, 102, 128, 255));
	DrawMenuHeader(Canvas, X, Y, W, RowH + Pad, "SERVER SCOREBOARD",
		Canvas.MakeColor(40, 46, 60, 245), Canvas.MakeColor(95, 140, 220, 255), Canvas.MakeColor(215, 220, 235, 255));

	// --- Telemetry strip: server name | players | uptime | DEFCON --------
	TeleY = Y + RowH + Pad * 1.8;
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = Canvas.MakeColor(16, 18, 24, 235);
	Canvas.SetPos(X + Pad, TeleY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W - Pad * 2.0, YL + Pad);
	Canvas.DrawColor = Canvas.MakeColor(60, 68, 88, 220);
	Canvas.SetPos(X + Pad, TeleY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W - Pad * 2.0, 1.0);
	Canvas.SetPos(X + Pad, TeleY + YL + Pad - 1.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W - Pad * 2.0, 1.0);

	MyFont.DrawTextEx(Canvas, CanvasWidth, X + Pad * 1.5, TeleY + Pad * 0.4,
		GRI.ServerName, MenuFontSize, true, EJ_Left, Canvas.MakeColor(220, 225, 240, 255));

	Mins = GRI.ElapsedTime / 60;
	Secs = GRI.ElapsedTime % 60;
	if (Secs < 10)
		TimeStr = "T+" $ Mins $ ":0" $ Secs;
	else
		TimeStr = "T+" $ Mins $ ":" $ Secs;
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.55, TeleY + Pad * 0.4,
		"PLAYERS " $ GRI.PRIArray.Length $ "/" $ GRI.MaxSlots $ "   UPTIME " $ TimeStr,
		MenuFontSize, true, EJ_Left, LabelColor);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W - Pad * 1.5, TeleY + Pad * 0.4,
		GRI.GetAlertName(), MenuFontSize, true, EJ_Right, GRI.GetAlertColor());

	// --- Column headers --------------------------------------------------
	SecY = TeleY + YL + Pad * 2.2;
	ListX = X + Pad;
	ListW = W - Pad * 2.0;
	ColX[0] = ListX;
	ColW[0] = ListW * 0.16;							// ID / PING
	ColX[1] = ColX[0] + ColW[0];
	ColW[1] = ListW * 0.30;							// PLAYER NAME
	ColX[2] = ColX[1] + ColW[1];
	ColW[2] = ListW * 0.22;							// FACTION
	ColX[3] = ColX[2] + ColW[2];
	ColW[3] = ListW * 0.18;							// RANK
	ColX[4] = ColX[3] + ColW[3];
	ColW[4] = ListX + ListW - ColX[4];				// WALLET

	MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[0] + Pad * 0.5, SecY, "ID / PING", MenuFontSize, true, EJ_Left, Canvas.MakeColor(150, 160, 180, 255));
	MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[1] + Pad * 0.5, SecY, "PLAYER NAME", MenuFontSize, true, EJ_Left, Canvas.MakeColor(150, 160, 180, 255));
	MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[2] + Pad * 0.5, SecY, "FACTION", MenuFontSize, true, EJ_Left, Canvas.MakeColor(150, 160, 180, 255));
	MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[3] + Pad * 0.5, SecY, "RANK", MenuFontSize, true, EJ_Left, Canvas.MakeColor(150, 160, 180, 255));
	MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[4] + ColW[4] - Pad * 0.5, SecY, "WALLET", MenuFontSize, true, EJ_Right, Canvas.MakeColor(150, 160, 180, 255));
	Canvas.DrawColor = Canvas.MakeColor(75, 85, 110, 200);
	Canvas.SetPos(ListX, SecY + YL + 2.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, 1.0);

	// --- Roster rows -----------------------------------------------------
	ListY = SecY + YL + Pad;
	FootY = Y + H - Pad - YL - Pad * 0.5;
	Count = GRI.PRIArray.Length;
	Drawn = 0;
	bAdmin = (RPOwner != None && RPOwner.GroupLevel >= 2);
	if (SM != None)
		SM.HoveredIndex = -1;

	for (i = 0; i < Count; i++)
	{
		PRI = GRI.PRIArray[i];
		if (PRI == None)
			continue;
		IY = ListY + Drawn * RowH;
		if (IY + RowH > FootY - Pad)
			break;	// roster longer than the window: clip, never overflow

		RPPRI = MilRPPlayerReplicationInfo(PRI);
		bIsSelf = (RPOwner != None && PRI == RPOwner.PlayerReplicationInfo);
		bHover = bMouseLive && (SM != None && !SM.bDropOpen)
			&& MX >= ListX && MX <= ListX + ListW && MY >= IY && MY <= IY + RowH;
		if (bHover && SM != None)
			SM.HoveredIndex = i;

		// Row background: dropdown-selected > hovered > own-row accent.
		Canvas.Style = ERenderStyle.STY_Alpha;
		if (SM != None && SM.bDropOpen && i == SM.SelectedIndex)
		{
			Canvas.DrawColor = Canvas.MakeColor(60, 75, 110, 235);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, RowH);
			Canvas.DrawColor = Canvas.MakeColor(95, 140, 220, 255);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', FMax(3.0, BorderPS), RowH);
		}
		else if (bHover)
		{
			Canvas.DrawColor = Canvas.MakeColor(45, 55, 80, 220);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, RowH);
		}
		else if (bIsSelf)
		{
			Canvas.DrawColor = Canvas.MakeColor(38, 44, 56, 220);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', ListW, RowH);
			Canvas.DrawColor = Canvas.MakeColor(120, 130, 150, 255);
			Canvas.SetPos(ListX, IY);
			Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', FMax(3.0, BorderPS), RowH);
		}

		// ID / ping
		MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[0] + Pad * 0.5, IY + RowH * 0.1,
			"#" $ PRI.PlayerID $ "  " $ PRI.Ping $ "ms", MenuFontSize, true, EJ_Left, LabelColor);

		// Name
		if (bIsSelf)
			RowColor = Canvas.MakeColor(255, 215, 100, 255);
		else
			RowColor = ValueColor;
		MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[1] + Pad * 0.5, IY + RowH * 0.1,
			PRI.PlayerName, MenuFontSize, true, EJ_Left, RowColor);

		// Faction (colour-coded) + rank
		if (RPPRI != None && RPPRI.HasFaction())
			MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[2] + Pad * 0.5, IY + RowH * 0.1,
				GRI.GetFactionName(RPPRI.FactionID), MenuFontSize, true, EJ_Left,
				GRI.GetFactionColor(RPPRI.FactionID));
		else
			MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[2] + Pad * 0.5, IY + RowH * 0.1,
				"UNASSIGNED", MenuFontSize, true, EJ_Left, LabelColor);
		if (RPPRI != None && GRI.GetRankTitle(RPPRI.Rank) != "")
			MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[3] + Pad * 0.5, IY + RowH * 0.1,
				GRI.GetRankTitle(RPPRI.Rank), MenuFontSize, true, EJ_Left, ValueColor);
		else
			MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[3] + Pad * 0.5, IY + RowH * 0.1,
				"-", MenuFontSize, true, EJ_Left, LabelColor);

		// Wallet: always visible on your own row; other rows need admin
		// clearance (metagaming rule) or show a masked placeholder.
		if (bIsSelf || bAdmin)
		{
			OtherP = MilRPPlayer(PRI.Owner);
			if (OtherP != None)
				WalletStr = "$" $ OtherP.Wallet;
			else
				WalletStr = "-";
			MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[4] + ColW[4] - Pad * 0.5, IY + RowH * 0.1,
				WalletStr, MenuFontSize, true, EJ_Right, MoneyColor);
		}
		else
			MyFont.DrawTextEx(Canvas, CanvasWidth, ColX[4] + ColW[4] - Pad * 0.5, IY + RowH * 0.1,
				"---", MenuFontSize, true, EJ_Right, LabelColor);

		Drawn++;
	}

	// --- Admin action dropdown (anchored at the last click) --------------
	if (SM != None && SM.bDropOpen)
	{
		SM.DropHover = -1;
		Canvas.Style = ERenderStyle.STY_Alpha;
		Canvas.DrawColor = Canvas.MakeColor(30, 34, 44, 245);
		Canvas.SetPos(SM.DropX, SM.DropY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', SM.DropW, SM.DropH);
		Canvas.DrawColor = Canvas.MakeColor(110, 120, 145, 255);
		Canvas.SetPos(SM.DropX, SM.DropY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', SM.DropW, 1.0);
		Canvas.SetPos(SM.DropX, SM.DropY + SM.DropH - 1.0);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', SM.DropW, 1.0);
		Canvas.SetPos(SM.DropX, SM.DropY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, SM.DropH);
		Canvas.SetPos(SM.DropX + SM.DropW - 1.0, SM.DropY);
		Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', 1.0, SM.DropH);

		for (i = 0; i < 3; i++)	// NUM_DROP_ACTIONS rows: Slap / Freeze / Kick
		{
			DIY = SM.DropY + Pad + i * RowH;
			bHover = MX >= SM.DropX && MX <= SM.DropX + SM.DropW && MY >= DIY && MY <= DIY + RowH;
			if (bHover)
			{
				SM.DropHover = i;
				Canvas.DrawColor = Canvas.MakeColor(55, 65, 90, 235);
				Canvas.SetPos(SM.DropX + 1.0, DIY);
				Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', SM.DropW - 2.0, RowH);
			}
			switch (i)
			{
				case 0:		TimeStr = "[Slap]";		break;
				case 1:		TimeStr = "[Freeze]";	break;
				default:	TimeStr = "[Kick]";		break;
			}
			MyFont.DrawTextEx(Canvas, CanvasWidth, SM.DropX + SM.DropW * 0.5, DIY + RowH * 0.1,
				TimeStr, MenuFontSize, true, EJ_Center, Canvas.MakeColor(230, 230, 235, 255));
		}
	}

	// --- Footer ----------------------------------------------------------
	Canvas.DrawColor = Canvas.MakeColor(70, 78, 100, 200);
	Canvas.SetPos(X + Pad, FootY);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W - Pad * 2.0, 1.0);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, FootY + Pad * 0.5,
		"Press F1 or Hold TAB to view   -   Right-click for cursor   -   Click a row for admin actions",
		ChatLogFontSize, true, EJ_Center, LabelColor);

	// Free cursor only while it is unlocked via right-click.
	if (bMouseLive)
	{
		Canvas.SetPos(MX, MY);
		Canvas.Style = 5;
		Canvas.DrawColor = Canvas.MakeColor(255, 255, 255, 255);
		Canvas.DrawTile(Texture'UWindow.Icons.MouseCursor', 20, 20, 0, 0, 32, 32);
	}

	// Sync the interaction's hit-box layout so clicks match this exact frame.
	if (SM != None)
	{
		SM.PanelX = X; SM.PanelY = Y; SM.PanelW = W; SM.PanelH = H;
		SM.ListX = ListX; SM.ListY = ListY; SM.ListW = ListW;
		SM.RowH = RowH; SM.Pad = Pad;
		SM.ItemCount = Drawn;
	}
}


///////////////////////////////////////////////////////////////////////////////
// DRAW PRIMITIVES
///////////////////////////////////////////////////////////////////////////////
simulated function DrawPanel(Canvas Canvas, float X, float Y, float W, float H)
{
	DrawPanelAlpha(Canvas, X, Y, W, H, 1.0);
}

simulated function DrawPanelAlpha(Canvas Canvas, float X, float Y, float W, float H, float Alpha)
{
	Canvas.Style = ERenderStyle.STY_Alpha;

	// fill
	Canvas.DrawColor = PanelColor;
	Canvas.DrawColor.A = byte(float(PanelColor.A) * Alpha);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);

	// 1px-ish border
	Canvas.DrawColor = PanelBorderColor;
	Canvas.DrawColor.A = byte(float(PanelBorderColor.A) * Alpha);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BorderPS);
	Canvas.SetPos(X, Y + H - BorderPS);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BorderPS);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, H);
	Canvas.SetPos(X + W - BorderPS, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BorderPS, H);
}

// Solid coloured pill behind the duty text.
simulated function DrawBadge(Canvas Canvas, float X, float Y, float W, float H, color C)
{
	Canvas.Style = ERenderStyle.STY_Alpha;
	Canvas.DrawColor = C;
	Canvas.DrawColor.A = 110;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);
}

// Window chrome shared by every interaction menu: soft drop shadow, solid
// fill, and a crisp border so panels pop off the gameplay scene.
simulated function DrawMenuFrame(Canvas Canvas, float X, float Y, float W, float H, color Fill, color Border)
{
	local float BW;

	Canvas.Style = ERenderStyle.STY_Alpha;
	BW = FMax(2.0, BorderPS);

	// Drop shadow offset down-right.
	Canvas.DrawColor = Canvas.MakeColor(0, 0, 0, 150);
	Canvas.SetPos(X + 5.0, Y + 6.0);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);

	// Fill.
	Canvas.DrawColor = Fill;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);

	// Crisp border frame.
	Canvas.DrawColor = Border;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BW);
	Canvas.SetPos(X, Y + H - BW);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BW);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BW, H);
	Canvas.SetPos(X + W - BW, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BW, H);
}

// Title band at the top of a menu window: solid bar, left accent stripe,
// thin underline rule, vertically-centred title text.
simulated function DrawMenuHeader(Canvas Canvas, float X, float Y, float W, float HeaderH, string Title, color BarColor, color Accent, color TitleColor)
{
	local float XL, YL, StripeW;

	Canvas.Style = ERenderStyle.STY_Alpha;
	StripeW = FMax(4.0, BorderPS * 2.0);

	Canvas.DrawColor = BarColor;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, HeaderH);

	Canvas.DrawColor = Accent;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', StripeW, HeaderH);

	Canvas.DrawColor = Accent;
	Canvas.DrawColor.A = 170;
	Canvas.SetPos(X, Y + HeaderH - FMax(1.0, BorderPS));
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, FMax(1.0, BorderPS));

	Canvas.Font = MyFont.GetFont(MenuFontSize + 1, true, CanvasWidth);
	Canvas.StrLen(Title, XL, YL);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + StripeW + YL * 0.8, Y + (HeaderH - YL) * 0.5,
		Title, MenuFontSize + 1, true, EJ_Left, TitleColor);
}

// Bordered action button: fill, crisp edge, centred label.
simulated function DrawMenuButton(Canvas Canvas, float X, float Y, float W, float H, string Label, bool bHover, color Base, color Hover, color Border, color TextC)
{
	local float XL, YL, BW;

	Canvas.Style = ERenderStyle.STY_Alpha;
	BW = FMax(1.0, BorderPS * 0.5);

	if (bHover)
		Canvas.DrawColor = Hover;
	else
		Canvas.DrawColor = Base;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, H);

	Canvas.DrawColor = Border;
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BW);
	Canvas.SetPos(X, Y + H - BW);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', W, BW);
	Canvas.SetPos(X, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BW, H);
	Canvas.SetPos(X + W - BW, Y);
	Canvas.DrawRect(Texture'Engine.WhiteSquareTexture', BW, H);

	Canvas.Font = MyFont.GetFont(MenuFontSize, true, CanvasWidth);
	Canvas.StrLen(Label, XL, YL);
	MyFont.DrawTextEx(Canvas, CanvasWidth, X + W * 0.5, Y + (H - YL) * 0.5,
		Label, MenuFontSize, true, EJ_Center, TextC);
}

simulated function color FadeColor(color C, float Alpha)
{
	Alpha = FClamp(Alpha, 0.0, 1.0);
	C.A = byte(float(C.A) * Alpha);
	return C;
}

// Truncates S with an ellipsis until it fits MaxW using the current Canvas.Font.
simulated function string ClipToWidth(Canvas Canvas, string S, float MaxW)
{
	local float XL, YL;

	Canvas.StrLen(S, XL, YL);
	while (XL > MaxW && Len(S) > 4)
	{
		S = Left(S, Len(S) - 4) $ "...";
		Canvas.StrLen(S, XL, YL);
	}
	return S;
}

// 1234567 -> "1,234,567"
simulated function string FormatMoney(int Amount)
{
	local string S, Result;
	local bool bNeg;
	local int Count;

	bNeg = (Amount < 0);
	if (bNeg)
		Amount = -Amount;
	S = string(Amount);

	while (Len(S) > 0)
	{
		Result = Right(S, 1) $ Result;
		S = Left(S, Len(S) - 1);
		Count++;
		if (Count % 3 == 0 && Len(S) > 0)
			Result = "," $ Result;
	}
	if (bNeg)
		Result = "-" $ Result;
	return Result;
}

// 275 -> "04:35"
simulated function string FormatClock(int Seconds)
{
	local int M, S;
	local string SM, SS;

	Seconds = Max(0, Seconds);
	M = Seconds / 60;
	S = Seconds % 60;
	SM = string(M);
	SS = string(S);
	if (M < 10)
		SM = "0" $ SM;
	if (S < 10)
		SS = "0" $ SS;
	return SM $ ":" $ SS;
}


defaultproperties
{
	// The stock MP frag/rank window overlaps our dashboard and is meaningless in RP.
	bHideOwnScore=true

	// --- Dashboard
	bShowDashboard=true
	DashRightPX=0.985
	DashTopPY=0.030
	DashMinWidthPX=0.20
	DashPaddingPX=0.008
	DashFontSize=0
	bShowPaycheckTimer=true
	bShowWalletDelta=true
	WalletFlashDuration=4.0

	// --- Feed
	bShowBroadcastFeed=true
	FeedCenterPX=0.5
	FeedTopPY=0.030
	FeedWidthPX=0.42
	FeedMaxLines=4
	FeedFontSize=0
	FeedLineLifetime=12.0
	FeedFadeDuration=2.5
	bFeedAlwaysShowHeader=false

	// --- Notices
	bShowNotices=true
	NoticeCenterPX=0.5
	NoticeBottomPY=0.78
	NoticeFontSize=0
	NoticeFadeDuration=1.0

	// --- Alert / prompt / menu
	bShowAlertBanner=true
	AlertBannerTopPY=0.120
	bShowInteractPrompt=true
	InteractPromptPY=0.700
	bShowMenu=true
	MenuCenterPX=0.500
	MenuTopPY=0.350
	MenuWidthPX=0.350
	MenuFontSize=0

	// --- Chat
	bShowChatLog=true
	ChatLogLeftPX=0.020
	ChatLogBottomPY=0.300
	ChatLogWidthPX=0.35
	ChatLogMaxVisible=8
	ChatLogFontSize=0
	ChatLogColor=(R=235,G=235,B=225,A=230)

	ChatMenuMaxVisible=12
	ChatMenuBottomPY=0.920
	ChatMenuHeight=0.300
	UltraWideOffsetX=0.0

	// --- Colours (olive-drab military palette)
	PanelColor=(R=18,G=24,B=16,A=170)
	PanelBorderColor=(R=120,G=140,B=90,A=200)
	LabelColor=(R=170,G=180,B=150,A=255)
	ValueColor=(R=235,G=235,B=225,A=255)
	OnDutyColor=(R=90,G=200,B=90,A=255)
	OffDutyColor=(R=150,G=150,B=150,A=255)
	MoneyColor=(R=220,G=200,B=90,A=255)
	GainColor=(R=120,G=230,B=120,A=255)
	LossColor=(R=230,G=110,B=100,A=255)
	FeedHeaderColor=(R=200,G=210,B=160,A=255)
	FeedTextColor=(R=225,G=230,B=210,A=255)
	NoticeColor=(R=255,G=240,B=200,A=255)
	AlertColor=(R=220,G=60,B=60,A=255)

	DashOnDuty="ON DUTY"
	DashOffDuty="OFF DUTY"
	DashNoFaction="UNASSIGNED - type /factions"
	DashPayIn="PAY IN"
	DashRP="RP"
	FeedHeader="BASE COMMAND"
	CurrencySymbol="$"
}
