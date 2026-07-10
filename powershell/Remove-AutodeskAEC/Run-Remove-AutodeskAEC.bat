@echo off
REM ---------------------------------------------------------------------------
REM Launcher for Remove-AutodeskAEC.ps1 - for users not familiar with PowerShell.
REM Double-click this file. It asks for administrator rights (UAC prompt), then
REM runs the removal script in full mode (-All). The script still shows a
REM complete preview of everything it will remove and requires typing YES
REM before anything is touched.
REM ---------------------------------------------------------------------------

REM The .ps1 must sit next to this file. If it is missing, the zip was probably
REM not extracted first.
if not exist "%~dp0Remove-AutodeskAEC.ps1" (
    echo ERROR: Remove-AutodeskAEC.ps1 was not found next to this file.
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-AutodeskAEC.ps1" -All
set "EXITCODE=%errorlevel%"

echo.
if not "%EXITCODE%"=="0" (
    echo The script finished with exit code %EXITCODE%. Review the log file
    echo shown above before closing this window.
)
pause
exit /b %EXITCODE%
