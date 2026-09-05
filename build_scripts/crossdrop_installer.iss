; Inno Setup Script fuer CrossDrop Windows Installer (.exe)
[Setup]
AppName=CrossDrop
AppVersion=1.3.0
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
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""CrossDrop"" dir=in action=allow program=""{app}\crossdrop.exe"" enable=yes"; Flags: runhidden
Filename: "{app}\crossdrop.exe"; Description: "{cm:LaunchProgram,CrossDrop}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""CrossDrop"""; Flags: runhidden
