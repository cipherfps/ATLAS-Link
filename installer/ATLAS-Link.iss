#define MyAppName "ATLAS Link"
#define MyAppPublisher "cipher"
#define MyAppURL "https://github.com/cipherfps/ATLAS-Link"

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#ifndef SourceDir
  #error SourceDir define is required.
#endif

#ifndef ExecutableName
  #define ExecutableName "ATLAS Link.exe"
#endif

#ifndef OutputDir
  #error OutputDir define is required.
#endif

#ifndef OutputBaseFilename
  #define OutputBaseFilename "ATLAS Link Setup"
#endif

#ifndef SetupIconFile
  #define SetupIconFile ""
#endif

[Setup]
AppId={{A28DB5CE-E9A2-4E14-A78A-E1298A0A6B55}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
UninstallDisplayName={#MyAppName}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\ATLAS Link
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#ExecutableName}
CloseApplications=yes
CloseApplicationsFilter={#ExecutableName},atlas_link_flutter.exe
RestartApplications=no
#if SetupIconFile != ""
SetupIconFile={#SetupIconFile}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "defenderexclusions"; Description: "Add {#MyAppName} DLL folder to Windows Defender exclusions (Recommended)"; GroupDescription: "Security:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#ExecutableName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function PowerShellQuoted(const Value: string): string;
begin
  Result := Value;
  StringChangeEx(Result, '''', '''''', True);
end;

procedure ApplyDefenderExclusions;
var
  ScriptPath: string;
  ScriptContent: string;
  PowerShellExe: string;
  Params: string;
  ResultCode: Integer;
begin
  if WizardSilent then
    Exit;

  ScriptPath := ExpandConstant('{tmp}\atlas-link-defender-exclusions.ps1');
  ScriptContent :=
    '$ErrorActionPreference = ''Stop'''#13#10 +
    '$Host.UI.RawUI.WindowTitle = ''ATLAS Link - Defender Exclusions'''#13#10 +
    'Write-Host ''ATLAS Link setup: adding Windows Defender exclusions...'''#13#10 +
    'Write-Host ''This window will close automatically.'''#13#10 +
    'try {'#13#10 +
    '  $paths = @('#13#10 +
    '    ''' +
    PowerShellQuoted(ExpandConstant('{app}\data\flutter_assets\assets\dlls')) +
    ''''#13#10 +
    '  )'#13#10 +
    '  $existing = @((Get-MpPreference).ExclusionPath)'#13#10 +
    '  foreach ($rawPath in $paths) {'#13#10 +
    '    if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }'#13#10 +
    '    $fullPath = [System.IO.Path]::GetFullPath($rawPath)'#13#10 +
    '    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null'#13#10 +
    '    $normalized = $fullPath.TrimEnd(''\'').ToLowerInvariant()'#13#10 +
    '    $already = $false'#13#10 +
    '    foreach ($existingPath in $existing) {'#13#10 +
    '      if ($null -eq $existingPath) { continue }'#13#10 +
    '      $existingNormalized = $existingPath.TrimEnd(''\'').ToLowerInvariant()'#13#10 +
    '      if ($existingNormalized -eq $normalized) { $already = $true; break }'#13#10 +
    '    }'#13#10 +
    '    if (-not $already) {'#13#10 +
    '      Add-MpPreference -ExclusionPath $fullPath'#13#10 +
    '      $existing += $fullPath'#13#10 +
    '    }'#13#10 +
    '  }'#13#10 +
    '  Write-Host ''Done.'''#13#10 +
    '  Start-Sleep -Milliseconds 1200'#13#10 +
    '  exit 0'#13#10 +
    '} catch {'#13#10 +
    '  Write-Host '''''#13#10 +
    '  Write-Host ''Failed to apply Windows Defender exclusions.'''#13#10 +
    '  Write-Host $_'#13#10 +
    '  Start-Sleep -Seconds 6'#13#10 +
    '  exit 1'#13#10 +
    '}'#13#10;

  if not SaveStringToFile(ScriptPath, ScriptContent, False) then begin
    MsgBox(
      'Unable to prepare the Windows Defender exclusion script.',
      mbError,
      MB_OK
    );
    Exit;
  end;

  PowerShellExe := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not FileExists(PowerShellExe) then
    PowerShellExe := 'powershell';

  Params := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "' + ScriptPath + '"';
  if not ShellExec(
    'runas',
    PowerShellExe,
    Params,
    '',
    SW_SHOWNORMAL,
    ewWaitUntilTerminated,
    ResultCode
  ) then begin
    MsgBox(
      'Windows Defender exclusions were not applied. You can rerun setup later to apply them.',
      mbInformation,
      MB_OK
    );
    Exit;
  end;

  if ResultCode <> 0 then
    MsgBox(
      'Windows Defender exclusions were not applied (exit code ' + IntToStr(ResultCode) + '). You can rerun setup later to apply them.',
      mbInformation,
      MB_OK
    );
end;

procedure _TaskKillImage(const ImageName: string);
var
  ResultCode: Integer;
begin
  if (ImageName = '') then
    Exit;

  // Best-effort termination. Ignore failures if the process isn't running.
  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/IM "' + ImageName + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
  Exec(
    ExpandConstant('{sys}\taskkill.exe'),
    '/F /T /IM "' + ImageName + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // Apply before extracting files so Defender doesn't quarantine DLLs during install.
  if (CurStep = ssInstall) and WizardIsTaskSelected('defenderexclusions') then
    ApplyDefenderExclusions;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    _TaskKillImage('{#ExecutableName}');
    // Older builds used this name; close it too so uninstall/deletion works.
    if CompareText('{#ExecutableName}', 'atlas_link_flutter.exe') <> 0 then
      _TaskKillImage('atlas_link_flutter.exe');
  end;
end;
