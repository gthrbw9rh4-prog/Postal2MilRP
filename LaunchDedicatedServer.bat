@echo off
rem ===========================================================================
rem  LaunchDedicatedServer.bat - Postal 2 MilRP dedicated server bootstrap.
rem
rem  Boots a headless UCC server with the MilRP game type and the standard
rem  Postal 2 multiplayer ports so the engine can announce itself to the
rem  global Steam in-game server list (see [IpDrv.MasterServerUplink] and
rem  bLANServer=False in your Postal2.ini).
rem
rem  Forward UDP 7777 (game) and UDP 7778 (query) on your router, then run.
rem ===========================================================================
title Postal 2 Military Roleplay Dedicated Server

rem --- Paths ---------------------------------------------------------------
rem  Point this at whichever install hosts your server binaries. The POSTed
rem  SDK dir ships System\UCC.exe; retail POSTAL2Complete\System does not.
set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor\System"

rem --- Server settings -----------------------------------------------------
set "MAP=MPDGT-Asylum"
set "GAME=MilRP.MilRPGameInfo"
set "PORT=7777"
set "QPORT=7778"
set "VAC=1"

echo [MilRP] Launching Dedicated Server onto the Steam Master List...
echo [MilRP] Dir   : %GAME_DIR%
echo [MilRP] Map   : %MAP%   Game: %GAME%
echo [MilRP] Ports : game UDP %PORT%, query UDP %QPORT% (forward both on your router)

cd /d "%GAME_DIR%" || (echo [MilRP] GAME_DIR not found. & pause & exit /b 1)

UCC.exe server %MAP%?Game=%GAME%?VAC=%VAC%?Port=%PORT%?QueryPort=%QPORT% -log=server.log
