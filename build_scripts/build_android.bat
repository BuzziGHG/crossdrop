@echo off
echo ============================================================
echo   [CrossDrop] Baue Android Release (.apk)
echo ============================================================

cd /d "%~dp0..\client"

echo 1. Fuehre Flutter Build fuer Android APK aus...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo [FEHLER] Android APK Build ist fehlgeschlagen.
    pause
    exit /b %errorlevel%
)

echo 2. Kopiere APK in Ausgabeverzeichnis...
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "%~dp0crossdrop-release.apk"

echo ============================================================
echo   ERFOLG: Die Android APK befindet sich in:
echo   %~dp0crossdrop-release.apk
echo ============================================================
pause
