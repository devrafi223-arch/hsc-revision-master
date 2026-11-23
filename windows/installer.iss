; HSC Revision Master — Windows installer (Inno Setup 6).
; Built in CI after `flutter build windows --release`:
;   iscc /DAppVersion=<version from pubspec.yaml> windows\installer.iss
; Produces installer-output\HSC-Revision-Master-Setup-<version>.exe —
; a normal setup.exe (per-user install, Start menu + optional desktop
; shortcut, launch after install). NOT portable: no zip is shipped.
#define MyAppName "HSC Revision Master"
#ifndef MyAppVersion
  #define MyAppVersion "3.0.10"
#endif
#define MyAppExe "hsc_revision_master.exe"

[Setup]
AppId={{3F2A1B4C-7D8E-4A1B-9C2D-5E6F7A8B9C0D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Rafi
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=installer-output
OutputBaseFilename=HSC-Revision-Master-Setup-{#MyAppVersion}
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExe}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
