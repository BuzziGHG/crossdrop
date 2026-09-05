; Inno Setup Script fuer CrossDrop Windows Installer (.exe)
[Setup]
AppName=CrossDrop
AppVersion=1.0.1
DefaultDirName={autopf}\CrossDrop
DefaultGroupName=CrossDrop
OutputDir=.
OutputBaseFilename=CrossDrop-Windows-Setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no

[Files]
Source: "..\client\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CrossDrop"; Filename: "{app}\crossdrop.exe"
Name: "{group}\CrossDrop deinstallieren"; Filename: "{uninstallexe}"
Name: "{autodesktop}\CrossDrop"; Filename: "{app}\crossdrop.exe"

[Run]
Filename: "{app}\crossdrop.exe"; Description: "{cm:LaunchProgram,CrossDrop}"; Flags: nowait postinstall skipifsilent
