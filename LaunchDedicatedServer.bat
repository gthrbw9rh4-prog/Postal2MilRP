@echo off
rem ===========================================================================
rem  LaunchDedicatedServer.bat - Postal 2 MilRP dedicated server bootstrap.
rem
rem  Runs a true headless server (console only, no game window, no Steam
rem  session lock) so you can launch your own client alongside it.
rem
rem  IMPORTANT: use System\UCC.exe (the headless console binary), NOT
rem  Postal2.exe. `Postal2.exe server` boots the full client engine, opens a
rem  "Postal2 (Running)" window and holds your Steam profile, blocking a
rem  second client on this machine. The retail install ships no UCC.exe -
rem  copy it once from the POSTed SDK (or ShareThePain\System) into
rem  POSTAL2Complete\System. The version string comes from the engine DLLs,
rem  so the copied launcher still reports the modern protocol.
rem
rem  Forward UDP 7777 (game) and UDP 7778 (query) on your router, then run.
rem ===========================================================================
title Postal 2 Military Roleplay Dedicated Server

rem --- Paths ---------------------------------------------------------------
set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"
set "SDK_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor\System"

rem --- Server settings -----------------------------------------------------
set "MAP=MPDGT-Asylum"
set "GAME=MilRP.MilRPGameInfo"
set "PORT=7777"
set "QPORT=7778"
set "VAC=1"

echo [MilRP] Launching headless dedicated server (console only, no window)...
echo [MilRP] Dir   : %GAME_DIR%
echo [MilRP] Map   : %MAP%   Game: %GAME%
echo [MilRP] Ports : game UDP %PORT%, query UDP %QPORT% (forward both on your router)

rem  NOTE: this script intentionally avoids parenthesized if-blocks - the
rem  install paths contain "(x86)", which breaks cmd's block parsing when
rem  the variables expand inside a (...) group. goto labels are used instead.

if exist "%GAME_DIR%\Postal2.exe" goto DIR_OK
echo [MilRP] GAME_DIR not found - edit the GAME_DIR variable at the top.
pause
exit /b 1

:DIR_OK
cd /d "%GAME_DIR%"

rem  Auto-install the headless launcher from the SDK if it is missing.
if exist "UCC.exe" goto RUN_UCC
if not exist "%SDK_DIR%\UCC.exe" goto NO_UCC
echo [MilRP] Copying UCC.exe from the POSTed SDK ...
copy /y "%SDK_DIR%\UCC.exe" "UCC.exe" >nul
goto RUN_UCC

:NO_UCC
echo [MilRP] UCC.exe not found - falling back to Postal2.exe.
echo [MilRP] Warning - Postal2.exe opens a client window and holds your
echo [MilRP] Steam session. Install UCC.exe for a true headless server.
Postal2.exe server %MAP%?Game=%GAME%?VAC=%VAC%?Port=%PORT%?QueryPort=%QPORT% -log=server.log
goto END

:RUN_UCC
rem  UE2 parses absolute exe paths containing "(x86)" incorrectly - run the
rem  relative name from the cd'd System dir.
UCC.exe server %MAP%?Game=%GAME%?VAC=%VAC%?Port=%PORT%?QueryPort=%QPORT% -log=server.log

:END
echo.
echo [MilRP] Server process exited. See server.log in the game System dir.
pause
