@echo off
REM ---------------------------------------------------------------------------
REM Launcher for Clear-PrintQueue.ps1 - for users not familiar with PowerShell.
REM Double-click this file. It asks for administrator rights (UAC prompt), then
REM clears stuck print jobs from ALL printer queues by restarting the Print
REM Spooler. The script asks for confirmation before making changes.
REM ---------------------------------------------------------------------------

REM The .ps1 must sit next to this file. If it is missing, the zip was probably
REM not extracted first.
if not exist "%~dp0Clear-PrintQueue.ps1" (
    echo ERROR: Clear-PrintQueue.ps1 was not found next to this file.
    echo.
    echo If you opened this from inside a zip file, extract the whole zip
    echo to a folder first, then run this file from the extracted folder.
    echo.
    pause
    exit /b 1
)

REM Relaunch elevated if not already running as administrator.
net session >nul 2>&1
if not %errorlevel%==0 (
    echo Requesting administrator rights...
    powershell.exe -NoProfile -Command "Start-Process -FilePath \"%~f0\" -Verb RunAs"
    exit /b
)

REM -ExecutionPolicy Bypass covers restrictive policies and the
REM downloaded-from-internet block on the extracted .ps1.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clear-PrintQueue.ps1"
set "EXITCODE=%errorlevel%"

echo.
if not "%EXITCODE%"=="0" (
    echo The script finished with exit code %EXITCODE%. Review the log file
    echo shown above before closing this window.
)
pause
exit /b %EXITCODE%
