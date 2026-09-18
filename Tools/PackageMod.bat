@echo off
setlocal EnableDelayedExpansion
rem ===========================================================================
rem  PackageMod.bat - bundles the compiled MilRP core into a clean,
rem  ready-to-zip distribution folder.
rem
rem  Default output is the client/workshop package: System\MilRP.u, MilRP.ini
rem  and MilRP.int ONLY - the files players need to auto-download when
rem  joining a server. Pass "full" as %3 to also include docs, launchers
rem  and the addon template for a server-operator distribution.
rem
rem  Usage:
rem    Tools\PackageMod.bat
rem    Tools\PackageMod.bat "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor" "C:\MyProjects\Postal2-MilRP-Workshop" client
rem    Tools\PackageMod.bat "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor" "C:\MyProjects\Postal2-MilRP-Distribution" full
rem ===========================================================================

for %%I in ("%~dp0..") do set "REPO=%%~fI"
if "%~1"=="" (
    set "POSTAL2_DIR=C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Editor"
) else (
    set "POSTAL2_DIR=%~1"
)

if "%~2"=="" (
    set "DIST=%REPO%-Workshop"
) else (
    set "DIST=%~2"
)

if "%~3"=="" (
    set "PKG_KIND=client"
) else (
    set "PKG_KIND=%~3"
)
set "P2SYS=%POSTAL2_DIR%\System"
set "TEMPLATE=C:\MyProjects\Postal2-MilRP-AddonTemplate"

echo [PackageMod] Source  : %REPO%
echo [PackageMod] Build   : %P2SYS%
echo [PackageMod] Output  : %DIST%  (%PKG_KIND%)

if not exist "%P2SYS%\MilRP.u" (
    echo [PackageMod] MilRP.u not found in "%P2SYS%". Build the core first with Tools\make.bat.
    exit /b 1
)

rem --- Clean distribution folder ---
if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%\System"

rem --- Core mod package (always) ---
copy /y "%P2SYS%\MilRP.u"   "%DIST%\System\MilRP.u"   >nul
copy /y "%REPO%\System\MilRP.ini" "%DIST%\System\MilRP.ini" >nul
copy /y "%REPO%\System\MilRP.int" "%DIST%\System\MilRP.int" >nul

rem --- Docs / launchers / addon template (server-operator package only) ---
if /i "%PKG_KIND%"=="full" (
    mkdir "%DIST%\AddonTemplate"
    copy /y "%REPO%\README.md"  "%DIST%\README.md"  >nul
    copy /y "%REPO%\SERVER_HOST_GUIDE.md" "%DIST%\SERVER_HOST_GUIDE.md" >nul
    copy /y "%REPO%\Tools\LaunchServer.bat" "%DIST%\LaunchServer.bat" >nul
    copy /y "%REPO%\LaunchDedicatedServer.bat" "%DIST%\LaunchDedicatedServer.bat" >nul
    robocopy "%TEMPLATE%" "%DIST%\AddonTemplate" /MIR /NJH /NJS /NDL /NFL >nul
    if errorlevel 8 (
        echo [PackageMod] robocopy failed while copying the addon template.
        exit /b 1
    )
)

echo [PackageMod] Distribution ready: %DIST%
echo [PackageMod] Contents:
dir /b /s "%DIST%" 2>nul | findstr /i /c:".u" /c:".ini" /c:".int" /c:"README" /c:"DISTRIBUTION" /c:"make.bat"
exit /b 0
