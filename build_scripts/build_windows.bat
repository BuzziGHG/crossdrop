@echo off
echo ============================================================
echo   [CrossDrop] Baue Windows 10/11 Release (.exe)
echo ============================================================

cd /d "%~dp0..\client"

echo 1. Fuehre Flutter Build fuer Windows aus...
call flutter build windows --release
if %errorlevel% neq 0 (
    echo [FEHLER] Flutter Build fuer Windows ist fehlgeschlagen.
    pause
    exit /b %errorlevel%
)

echo 2. Erstelle Ausgabeordner...
set OUTDIR=%~dp0dist-windows
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo 3. Kopiere Release-Dateien...
xcopy /E /I /Y "build\windows\x64\runner\Release\*" "%OUTDIR%\"

echo ============================================================
echo   ERFOLG: Die Windows-Anwendung (.exe) befindet sich in:
echo   %OUTDIR%\crossdrop.exe
echo ============================================================
pause
