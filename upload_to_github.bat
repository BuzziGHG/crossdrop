@echo off
setlocal
set "PATH=C:\Program Files\Git\cmd;%LOCALAPPDATA%\Programs\Git\cmd;%PATH%"

echo =======================================================================
echo          CrossDrop: Upload zu https://github.com/BuzziGHG/crossdrop
echo =======================================================================
echo.

cd /d "%~dp0"

echo 1. Setze Remote Origin...
git remote remove origin 2>nul
git remote add origin https://github.com/BuzziGHG/crossdrop.git

echo 2. Pushe zu GitHub...
git push -u origin main

if %errorlevel% equ 0 (
    echo.
    echo =======================================================================
    echo   ERFOLGREICH ZU GITHUB HOCHGELADEN!
    echo =======================================================================
    echo.
    echo GitHub Actions baut nun VOLLAUTOMATISCH:
    echo   1. Windows 10/11 (.exe)  - CrossDrop-Windows-x64.zip
    echo   2. Debian / Linux (.deb) - crossdrop_1.0.0_amd64.deb
    echo   3. Android (.apk)        - crossdrop-release.apk
    echo.
    echo Oeffnen Sie in Ihrem Browser:
    echo   https://github.com/BuzziGHG/crossdrop/releases
    echo.
    echo In ca. 3-5 Minuten finden Sie dort alle drei fertigen Dateien!
    echo =======================================================================
) else (
    echo.
    echo [HINWEIS] Bitte fuehren Sie zuerst 'anmelden_und_hochladen.bat' aus.
)

echo.
pause