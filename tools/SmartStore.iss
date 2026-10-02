#ifndef AppVersion
  #error AppVersion must be supplied by build_installer.ps1
#endif
#ifndef BuildDir
  #error BuildDir must be supplied by build_installer.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build_installer.ps1
#endif
#ifndef AppIconFile
  #error AppIconFile must be supplied by build_installer.ps1
#endif

#define AppName "SmartStore"

[Setup]
AppId={{65B67709-6AA3-4B7A-A8F6-6B71F331920A}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=SmartStore
DefaultDirName={localappdata}\Programs\SmartStore
DefaultGroupName=SmartStore
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
CloseApplicationsFilter=smart_store.exe
OutputDir={#OutputDir}
OutputBaseFilename=SmartStore-Setup-{#AppVersion}
SetupIconFile={#AppIconFile}
UninstallDisplayIcon={app}\smart_store.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp,*.pdb,updater.exe,user_data\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SmartStore"; Filename: "{app}\smart_store.exe"
Name: "{autodesktop}\SmartStore"; Filename: "{app}\smart_store.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\smart_store.exe"; Description: "Launch SmartStore"; Flags: postinstall nowait