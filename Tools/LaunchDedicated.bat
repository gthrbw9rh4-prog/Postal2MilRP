@echo off
REM LaunchDedicated.bat
REM Starts a true dedicated Postal 2: MilRP server in a text console.
REM NOTE: UCC.exe only ships inside the POSTed SDK dir, not the retail
REM POSTAL2Editor\System folder - cd to the SDK install or the exe
REM will not resolve.
cd /d "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor\System"

ucc server MPDGT-Asylum.fuk?Game=MilRP.MilRPGameInfo -ini=Postal2.ini
