@echo off
chcp 65001 >nul
set "PATH=%LOCALAPPDATA%\Programs\Git\cmd;%PATH%"

echo =======================================================================
echo     CrossDrop: 1-Klick GitHub-Anmeldung & Upload
echo =======================================================================
echo.
echo Schritt 1: GitHub-Autorisierung im Browser...
echo (Es oeffnet sich gleich Ihr Browser, wo Sie nur auf "Authorize" klicken)
echo.
call gh auth login -h github.com -p https -w
call gh auth setup-git

echo.
echo Schritt 2: Lade Projekt zu https://github.com/BuzziGHG/crossdrop hoch...
echo.
cd /d "%~dp0"
git remote remove origin 2>nul
git remote add origin https://github.com/BuzziGHG/crossdrop.git
git push -u origin main

if %errorlevel% equ 0 (
    echo.
    echo =======================================================================
    echo   HERZLICHEN GLUECKWUNSCH! DER UPLOAD WAR ERFOLGREICH! 🎉
    echo =======================================================================
    echo.
    echo GitHub Actions hat soeben gestartet und baut VOLLAUTOMATISCH:
    echo   1. Windows 10/11 (.exe)  -> CrossDrop-Windows-x64.zip
    echo   2. Debian / Linux (.deb) -> crossdrop_1.0.0_amd64.deb
    echo   3. Android (.apk)        -> crossdrop-release.apk
    echo.
    echo Besuchen Sie jetzt:
    echo   https://github.com/BuzziGHG/crossdrop/releases
    echo.
    echo In ca. 3-5 Minuten sind alle 3 Installationsdateien fertig gebaut!
    echo =======================================================================
) else (
    echo.
    echo [HINWEIS] Falls der Push fehlgeschlagen ist, pruefen Sie bitte,
    echo ob Sie bei GitHub angemeldet sind.
)

echo.
pause
