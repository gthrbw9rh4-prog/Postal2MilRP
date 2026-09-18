///////////////////////////////////////////////////////////////////////////////
// MilRPATMPaymaster.uc
//
// Combined ATM and paymaster. Supports:
//   - withdraw/deposit/transfer from bank account
//   - collect a pending physical paycheck
//
// The bank balance is server-authoritative and persisted with the player record.
///////////////////////////////////////////////////////////////////////////////
class MilRPATMPaymaster extends MilRPInteractPoint;


var int				LastAmount;


function int BuildMenu(MilRPPlayer RPO, out string Options[8])
{
	local MilRPGameInfo Game;

	Game = GetGame();
	if (Game == None)
		return 0;

	MenuTitle = "ATM / Paymaster";
	Options[0] = "1. Withdraw $100";
	Options[1] = "2. Deposit $100";
	Options[2] = "3. Collect paycheck";
	Options[3] = "4. Check balance";
	return 4;
}

function bool HandleSelection(MilRPPlayer RPO, int Index, out string Feedback)
{
	local MilRPGameInfo Game;
	local int Bank;

	Game = GetGame();
	if (Game == None)
	{
		Feedback = "Terminal offline.";
		return false;
	}

	Bank = Game.GetBank(RPO);

	switch (Index)
	{
		case 0:
			if (Game.BankTransfer(RPO, -100))
			{
				Game.AddCurrency(RPO, 100, "atm_withdraw");
				Feedback = "Withdrew $100. Wallet: $" $ Game.GetWallet(RPO) $ " Bank: $" $ Game.GetBank(RPO);
			}
			else
				Feedback = "Insufficient bank funds.";
			return true;

		case 1:
			if (Game.TryCharge(RPO, 100, "atm_deposit"))
			{
				Game.BankTransfer(RPO, 100);
				Feedback = "Deposited $100. Wallet: $" $ Game.GetWallet(RPO) $ " Bank: $" $ Game.GetBank(RPO);
			}
			else
				Feedback = "Insufficient wallet funds.";
			return true;

		case 2:
			Feedback = Game.CollectPaycheck(RPO);
			return true;

		case 3:
			Feedback = "Wallet: $" $ Game.GetWallet(RPO) $ " | Bank: $" $ Bank;
			return true;
	}

	Feedback = "Invalid option.";
	return false;
}


defaultproperties
{
	PointLabel="Press USE for ATM"
	MenuTitle="ATM"
	bOffDutyOk=true
}