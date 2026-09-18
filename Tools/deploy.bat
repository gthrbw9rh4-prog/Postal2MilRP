@echo off
rem ===========================================================================
rem  MilRP deploy script - force-kills lingering engine processes to release
rem  file locks, then installs MilRP.u/.ini/.int into the retail game.
rem
rem  Usage:
rem    deploy.bat                 (uses RETAIL_DIR below)
rem    deploy.bat "D:\Games\Postal 2 Complete"
rem ===========================================================================
setlocal

set "REPO=%~dp0.."
if not "%~1"=="" set "RETAIL_DIR=%~1"
if "%RETAIL_DIR%"=="" set "RETAIL_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete"
set "RSYS=%RETAIL_DIR%\System"

echo [MilRP] Retail dir : %RETAIL_DIR%

rem --- 1. Kill any running engine processes holding MilRP.u open ---
taskkill /F /IM Postal2.exe >nul 2>&1
taskkill /F /IM ucc.exe >nul 2>&1
taskkill /F /IM Postal2Editor.exe >nul 2>&1

rem --- 2. Deploy ---
if not exist "%REPO%\System\MilRP.u" (
    echo [MilRP] No compiled MilRP.u in repo System - run make.bat first.
    exit /b 1
)
copy /y "%REPO%\System\MilRP.u"   "%RSYS%\MilRP.u"   >nul
copy /y "%REPO%\System\MilRP.ini" "%RSYS%\MilRP.ini" >nul
copy /y "%REPO%\System\MilRP.int" "%RSYS%\MilRP.int" >nul

echo [MilRP] DEPLOYED -^> "%RSYS%"
exit /b 0
