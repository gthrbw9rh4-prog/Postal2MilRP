@echo off
REM LaunchDedicated.bat
REM Starts a true dedicated Postal 2: MilRP server in a text console.
REM NOTE: must run the retail build-5100 Postal2.exe from
REM POSTAL2Complete\System. The SDK's POSTAL2Editor\System\UCC.exe is
REM engine version 1409 and only announces to 333networks - modern
REM clients reject it with a "latest Postal2 update" protocol error.
REM (Retail has no ucc.exe; Postal2.exe hosts the 'server' commandlet.)
cd /d "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"

Postal2.exe server MPDGT-Asylum?Game=MilRP.MilRPGameInfo?VAC=1?Port=7777?QueryPort=7778 -log=server.log
