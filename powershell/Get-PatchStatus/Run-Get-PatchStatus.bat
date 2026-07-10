@echo off
REM ---------------------------------------------------------------------------
REM Launcher for Get-PatchStatus.ps1 - for users not familiar with PowerShell.
REM Double-click this file. It reports when this machine was last patched,
REM whether updates are waiting to be installed, and whether a reboot is
REM pending. Nothing is installed or changed on the machine and no
REM administrator rights are needed.
REM ---------------------------------------------------------------------------

REM The .ps1 must sit next to this file. If it is missing, the zip was probably
REM not extracted first.
if not exist "%~dp0Get-PatchStatus.ps1" (
    echo ERROR: Get-PatchStatus.ps1 was not found next to this file.
    echo.
    echo If you opened this from inside a zip file, extract the whole zip
    echo to a folder first, then run this file from the extracted folder.
    echo.
    pause
    exit /b 1
)

echo Checking patch status... the Windows Update search can take a minute.
echo.

REM -ExecutionPolicy Bypass covers restrictive policies and the
REM downloaded-from-internet block on the extracted .ps1.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-PatchStatus.ps1"
set "EXITCODE=%errorlevel%"

echo.
echo Done. Review the status above ^(0 = OK, 1 = attention, 2 = critical^).
pause
exit /b %EXITCODE%
