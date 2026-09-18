@echo off
REM Launch a local listen-server for the Postal 2: MilRP game type.
REM Uses a relative executable name to avoid the UE2 command-line parser bug with
REM paths containing "(x86)".
REM
REM This script runs the main retail POSTAL2Complete\System\Postal2.exe, which
REM loads the compatible 5 MB Engine.u and the MilRP package.
REM
REM Usage:
REM   LaunchServer.bat [map] [game] [options]

set "GAME_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"
set "MAP=MPDGT-Asylum.fuk"
set "GAME=MilRP.MilRPGameInfo"
set "LISTEN=?Listen"

if not "%~1"=="" set "MAP=%~1"
if not "%~2"=="" set "GAME=%~2"

cd /d "%GAME_DIR%" || exit /b 1

Postal2.exe %MAP%?Game=%GAME%%LISTEN% -ini=Postal2.ini
