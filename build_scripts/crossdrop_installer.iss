; Inno Setup Script fuer CrossDrop Windows Installer (.exe)
[Setup]
AppName=CrossDrop
AppVersion=1.0.0
DefaultDirName={autopf}\CrossDrop
DefaultGroupName=CrossDrop
OutputDir=.
OutputBaseFilename=CrossDrop-Setup-1.0.0
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "..\client\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CrossDrop"; Filename: "{app}\crossdrop.exe"
Name: "{autodesktop}\CrossDrop"; Filename: "{app}\crossdrop.exe"

[Run]
Filename: "{app}\crossdrop.exe"; Description: "{cm:LaunchProgram,CrossDrop}"; Flags: nowait postinstall skipifsilent
