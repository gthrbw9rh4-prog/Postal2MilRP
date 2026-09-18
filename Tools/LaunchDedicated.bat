@echo off
REM LaunchDedicated.bat
REM Starts a true headless dedicated Postal 2: MilRP server (console only,
REM no game window, no Steam session lock - a second client can run beside
REM it). Uses System\UCC.exe, auto-copied from the POSTed SDK when missing.
REM Do NOT use Postal2.exe here: it opens a "Postal2 (Running)" window and
REM holds your Steam profile, blocking your own game client.
cd /d "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"

if not exist "UCC.exe" if exist "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor\System\UCC.exe" copy /y "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor\System\UCC.exe" "UCC.exe" >nul

UCC.exe server MPDGT-Asylum?Game=MilRP.MilRPGameInfo?VAC=1?Port=7777?QueryPort=7778 -log=server.log
