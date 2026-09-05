@echo off
chcp 65001 >nul
echo =======================================================================
echo          CrossDrop: Automatischer GitHub-Upload & Cloud-Build
echo =======================================================================
echo.

REM 1. Prüfen, ob Git vorhanden ist
where git >nul 2>nul
if %errorlevel% neq 0 (
    echo [HINWEIS] Git ist noch nicht installiert.
    echo Bitte laden Sie kurz Git herunter: https://git-scm.com/download/win
    echo Oder installieren Sie 'GitHub Desktop': https://desktop.github.com
    echo.
    pause
    exit /b 1
)

cd /d "%~dp0"

echo 1. Initialisiere Git Repository...
if not exist ".git" (
    git init
    git branch -M main
)

echo 2. Fuege alle Projektdateien hinzu...
git add .

echo 3. Erstelle initialen Commit...
git commit -m "CrossDrop v1.0.0: Windows .exe, Linux .deb, Android .apk mit automatischem VPN"

echo.
echo =======================================================================
echo Geben Sie nun die HTTPS-URL Ihres GitHub-Repositories ein.
echo Beispiel: https://github.com/IhrBenutzername/crossdrop.git
echo =======================================================================
set /p REPO_URL="Repository URL: "

if "%REPO_URL%"=="" (
    echo Keine URL eingegeben. Abbruch.
    pause
    exit /b 1
)

echo.
echo 4. Setze Remote Origin...
git remote remove origin 2>nul
git remote add origin %REPO_URL%

echo 5. Pushe zu GitHub...
git push -u origin main

if %errorlevel% equ 0 (
    echo.
    echo =======================================================================
    echo   ERFOLGREICH ZU GITHUB HOCHGELADEN! 🎉
    echo =======================================================================
    echo.
    echo GitHub Actions baut nun VOLLAUTOMATISCH im Hintergrund:
    echo   1. Windows 10/11 (.exe) -> CrossDrop-Windows-x64.zip
    echo   2. Debian / Linux (.deb) -> crossdrop_1.0.0_amd64.deb
    echo   3. Android (.apk)        -> crossdrop-release.apk
    echo.
    echo Oeffnen Sie in Ihrem Browser:
    echo   %REPO_URL%/releases
    echo.
    echo In ca. 3-5 Minuten finden Sie dort alle drei fertigen Installationsdateien
    echo direkt als 1-Klick-Download!
    echo =======================================================================
) else (
    echo.
    echo [FEHLER] Push zu GitHub fehlgeschlagen.
    echo Bitte pruefen Sie, ob Sie bei GitHub eingeloggt sind und die URL stimmt.
)

echo.
pause
