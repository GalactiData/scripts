@echo off
REM ---------------------------------------------------------------------------
REM Launcher for Get-SystemInventory.ps1 - for users not familiar with PowerShell.
REM Double-click this file. It collects a hardware/software inventory of this
REM machine and saves it as an HTML report in the same folder, then opens the
REM report. No administrator rights are needed and nothing is changed on the
REM machine. Send the generated .html file to your IT contact.
REM ---------------------------------------------------------------------------

REM The .ps1 must sit next to this file. If it is missing, the zip was probably
REM not extracted first.
if not exist "%~dp0Get-SystemInventory.ps1" (
    echo ERROR: Get-SystemInventory.ps1 was not found next to this file.
    echo.
    echo If you opened this from inside a zip file, extract the whole zip
    echo to a folder first, then run this file from the extracted folder.
    echo.
    pause
    exit /b 1
)

set "REPORT=%~dp0SystemInventory_%COMPUTERNAME%.html"

echo Collecting system inventory... this can take a minute or two.
echo.

REM -ExecutionPolicy Bypass covers restrictive policies and the
REM downloaded-from-internet block on the extracted .ps1.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-SystemInventory.ps1" -Format HTML -OutputPath "%REPORT%"
set "EXITCODE=%errorlevel%"

echo.
if exist "%REPORT%" (
    echo Report saved to:
    echo   %REPORT%
    echo.
    echo Opening the report now. Send that file to your IT contact.
    start "" "%REPORT%"
) else (
    echo The report was not created ^(exit code %EXITCODE%^). Review any
    echo messages above before closing this window.
)
pause
exit /b %EXITCODE%
