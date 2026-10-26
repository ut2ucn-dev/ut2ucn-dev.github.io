; The Windows installer of Stemik Admin (Inno Setup 6). CI builds it after
; `flutter build windows` (.github/workflows/mobile.yml):
;   iscc /DAppVersion=2.0.<run> mobile\windows\installer\stemik_admin.iss
; and publishes dist\stemik-admin-setup.exe with the release.
;
; Installed for the current user (no administrator rights needed), into
; %LOCALAPPDATA%\Programs\Stemik Admin. Running a newer installer over it
; closes the app, updates it and keeps the sign-in and the data (those
; live in %APPDATA%, not next to the program).

#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#define AppExe "stemik_admin.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Identifies the app for updates and uninstalling; never change.
AppId={{B3179B1C-3EF1-466A-8662-707AF738E9B0}
AppName=Stemik Admin
AppVersion={#AppVersion}
AppVerName=Stemik Admin {#AppVersion}
AppPublisher=Stemik
AppPublisherURL=https://ut2ucn-dev.github.io/
VersionInfoVersion={#AppVersion}
VersionInfoCompany=Stemik
VersionInfoDescription=Stemik Admin Setup
VersionInfoProductName=Stemik Admin
VersionInfoProductVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 Stemik
DefaultDirName={autopf}\Stemik Admin
DefaultGroupName=Stemik Admin
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\..\..\dist
OutputBaseFilename=stemik-admin-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=Stemik Admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; What an older version left that this one no longer ships.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The app id (as in windows/runner/main.cpp) ties the taskbar button and
; the notifications to this shortcut.
Name: "{autoprograms}\Stemik Admin"; Filename: "{app}\{#AppExe}"; AppUserModelID: "StemikStudio.StemikAdmin"
Name: "{autodesktop}\Stemik Admin"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon; AppUserModelID: "StemikStudio.StemikAdmin"

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Stemik Admin}"; Flags: nowait postinstall skipifsilent
