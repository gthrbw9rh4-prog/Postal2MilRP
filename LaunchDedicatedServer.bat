@echo off
rem ===========================================================================
rem  LaunchDedicatedServer.bat - Postal 2 MilRP dedicated server bootstrap.
rem
rem  Runs the modern retail engine (Postal2.exe, build 5100, Steam-integrated)
rem  as a dedicated server. Do NOT use POSTAL2Editor\System\UCC.exe here - the
rem  SDK compiler binary is engine version 1409 and announces to 333networks,
rem  which modern clients reject with a "latest Postal2 update" protocol error.
rem
rem  Forward UDP 7777 (game) and UDP 7778 (query) on your router, then run.
rem ===========================================================================
title Postal 2 Military Roleplay Dedicated Server

rem --- Paths ---------------------------------------------------------------
rem  Must be the retail install's System dir (the only 5100 Steam binary).
set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"

rem --- Server settings -----------------------------------------------------
set "MAP=MPDGT-Asylum"
set "GAME=MilRP.MilRPGameInfo"
set "PORT=7777"
set "QPORT=7778"
set "VAC=1"

echo [MilRP] Launching Version 5100 Dedicated Server onto the official Steam Master List...
echo [MilRP] Dir   : %GAME_DIR%
echo [MilRP] Map   : %MAP%   Game: %GAME%
echo [MilRP] Ports : game UDP %PORT%, query UDP %QPORT% (forward both on your router)

cd /d "%GAME_DIR%" || (echo [MilRP] GAME_DIR not found. & pause & exit /b 1)

rem  UE2 parses absolute exe paths containing "(x86)" incorrectly - run the
rem  relative name from the cd'd System dir. Postal2.exe hosts the 'server'
rem  commandlet natively (no ucc.exe exists in this install).
Postal2.exe server %MAP%?Game=%GAME%?VAC=%VAC%?Port=%PORT%?QueryPort=%QPORT% -log=server.log
