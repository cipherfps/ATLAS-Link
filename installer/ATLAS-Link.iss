#define MyAppName "ATLAS Link"
#define MyAppPublisher "cipherfps"
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

#ifndef VcRedistPath
  #define VcRedistPath ""
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
UsePreviousTasks=no
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma
SolidCompression=yes
; Enables native extraction of the downloaded backend .zip payloads
; (Flags: external extractarchive) during install.
ArchiveExtraction=full
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#ExecutableName}
CloseApplications=yes
CloseApplicationsFilter={#ExecutableName},atlas_link_flutter.exe
RestartApplications=no
DisableReadyMemo=yes
#if SetupIconFile != ""
SetupIconFile={#SetupIconFile}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
SelectTasksDesc=Which ATLAS Link setup options should be performed?
SelectTasksLabel2=Select the options you would like Setup to perform while installing ATLAS Link, then click Next.
ReadyLabel1=Setup is now ready to install ATLAS Link on your computer.
ReadyLabel2a=Click Install to continue with the installation, or click Back if you want to review any ATLAS Link setup options.
ReadyLabel2b=Click Install to continue with the installation.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "Additional options:"; Flags: unchecked

[Files]
; The embedded backend payloads are NOT bundled in the installer (keeps the
; setup small). Backends ticked on the additions page are downloaded to {tmp}
; in NextButtonClick and extracted here. skipifsourcedoesntexist lets the
; install proceed if a download was skipped or failed (the launcher can still
; install the backend later from the Backend tab).
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "data\flutter_assets\assets\backend\*"
; NeoniteV2 backend payload (neonite_v2\, node\, bin\atlas_neonitev2.exe)
Source: "{tmp}\neonitev2-backend.zip"; DestDir: "{app}\data\flutter_assets\assets\backend"; Flags: external extractarchive recursesubdirs ignoreversion skipifsourcedoesntexist; Check: WantNeonite
; LawinServer backend payload (lawinserver\, node\, bin\atlas_lawinserver.exe)
Source: "{tmp}\lawinserver-backend.zip"; DestDir: "{app}\data\flutter_assets\assets\backend"; Flags: external extractarchive recursesubdirs ignoreversion skipifsourcedoesntexist; Check: WantLawin
#if VcRedistPath != ""
Source: "{#VcRedistPath}"; DestDir: "{tmp}"; DestName: "vc_redist.x64.exe"; Flags: deleteafterinstall
#endif

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#ExecutableName}"; Tasks: desktopicon

[Run]
#if VcRedistPath != ""
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Check: NeedsVCRedist; Flags: runhidden waituntilterminated
#endif
Filename: "{sys}\msiexec.exe"; Parameters: "/i ""{tmp}\tailscale-setup.msi"" /quiet /norestart TS_UNATTENDEDMODE=always"; StatusMsg: "Installing Tailscale..."; Check: ShouldInstallTailscale; Flags: runhidden waituntilterminated
Filename: "{app}\{#ExecutableName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  NeoniteBackendUrl =
    'https://raw.githubusercontent.com/cipherfps/ATLAS-Link/main/backends/neonitev2-backend.zip';
  LawinBackendUrl =
    'https://raw.githubusercontent.com/cipherfps/ATLAS-Link/main/backends/lawinserver-backend.zip';
  TailscaleMsiUrl =
    'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi';

var
  DefenderOptionsPage: TWizardPage;
  DefenderIntroLabel: TNewStaticText;
  DefenderDetailsLabel: TNewStaticText;
  DefenderExclusionsCheckBox: TNewCheckBox;
  BackendOptionsPage: TWizardPage;
  BackendIntroLabel: TNewStaticText;
  BackendDetailsLabel: TNewStaticText;
  NeoniteCheckBox: TNewCheckBox;
  LawinCheckBox: TNewCheckBox;
  TailscaleOptionsPage: TWizardPage;
  TailscaleIntroLabel: TNewStaticText;
  TailscaleDetailsLabel: TNewStaticText;
  TailscaleCheckBox: TNewCheckBox;
  TailscaleInstallQueued: Boolean;
  BackendDownloadPage: TDownloadWizardPage;

function WantNeonite: Boolean;
begin
  Result := Assigned(NeoniteCheckBox) and NeoniteCheckBox.Checked;
end;

function WantLawin: Boolean;
begin
  Result := Assigned(LawinCheckBox) and LawinCheckBox.Checked;
end;

function WantEitherBackend: Boolean;
begin
  Result := WantNeonite or WantLawin;
end;

function TailscaleAlreadyInstalled: Boolean;
begin
  Result :=
    FileExists(ExpandConstant('{autopf}\Tailscale\tailscale.exe')) or
    FileExists(ExpandConstant('{pf32}\Tailscale\tailscale.exe'));
end;

function WantTailscale: Boolean;
begin
  Result := Assigned(TailscaleCheckBox) and TailscaleCheckBox.Checked;
end;

function WantTailscaleDownload: Boolean;
begin
  Result := WantTailscale and (not TailscaleAlreadyInstalled);
end;

function ShouldInstallTailscale: Boolean;
begin
  Result :=
    WantTailscale and
    (not TailscaleAlreadyInstalled) and
    FileExists(ExpandConstant('{tmp}\tailscale-setup.msi'));
end;

function IsVCRedistInstalled: Boolean;
var
  Installed: Cardinal;
begin
  Result :=
    RegQueryDWordValue(
      HKLM64,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed',
      Installed
    ) and (Installed = 1);

  if not Result then
    Result :=
      RegQueryDWordValue(
        HKLM,
        'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        'Installed',
        Installed
      ) and (Installed = 1);
end;

function NeedsVCRedist: Boolean;
begin
  Result := not IsVCRedistInstalled;
end;

function PowerShellQuoted(const Value: string): string;
begin
  Result := Value;
  StringChangeEx(Result, '''', '''''', True);
end;

function ShouldApplyDefenderExclusions: Boolean;
begin
  Result :=
    Assigned(DefenderExclusionsCheckBox) and
    DefenderExclusionsCheckBox.Checked;
end;

procedure InitializeWizard;
begin
  DefenderOptionsPage := CreateCustomPage(
    wpSelectDir,
    'Allow bundled DLL support',
    'ATLAS Link can add its helper DLL folder to Windows Defender exclusions.'
  );

  DefenderIntroLabel := TNewStaticText.Create(DefenderOptionsPage);
  DefenderIntroLabel.Parent := DefenderOptionsPage.Surface;
  DefenderIntroLabel.Left := 0;
  DefenderIntroLabel.Top := 0;
  DefenderIntroLabel.Width := DefenderOptionsPage.SurfaceWidth;
  DefenderIntroLabel.AutoSize := False;
  DefenderIntroLabel.WordWrap := True;
  DefenderIntroLabel.Font.Style := [fsBold];
  DefenderIntroLabel.Caption :=
    'ATLAS Link can use bundled DLLs for compatibility on natively supported versions.';
  WizardForm.AdjustLabelHeight(DefenderIntroLabel);

  DefenderDetailsLabel := TNewStaticText.Create(DefenderOptionsPage);
  DefenderDetailsLabel.Parent := DefenderOptionsPage.Surface;
  DefenderDetailsLabel.Left := 0;
  DefenderDetailsLabel.Top :=
    DefenderIntroLabel.Top + DefenderIntroLabel.Height + ScaleY(12);
  DefenderDetailsLabel.Width := DefenderOptionsPage.SurfaceWidth;
  DefenderDetailsLabel.AutoSize := False;
  DefenderDetailsLabel.WordWrap := True;
  DefenderDetailsLabel.Caption :=
    'Selecting the option below will add ATLAS Link''s bundled DLL folder to the Windows Defender exclusions list. This can help prevent Windows Security from quarantining required files during install or launch. If another antivirus is active, you may still need to add the exclusion there manually. Only enable this if you trust ATLAS Link. You can review the source code at https://github.com/cipherfps/ATLAS-Link and manage exclusions yourself later if you prefer.';
  WizardForm.AdjustLabelHeight(DefenderDetailsLabel);

  DefenderExclusionsCheckBox := TNewCheckBox.Create(DefenderOptionsPage);
  DefenderExclusionsCheckBox.Parent := DefenderOptionsPage.Surface;
  DefenderExclusionsCheckBox.Left := 0;
  DefenderExclusionsCheckBox.Top :=
    DefenderDetailsLabel.Top + DefenderDetailsLabel.Height + ScaleY(16);
  DefenderExclusionsCheckBox.Width := DefenderOptionsPage.SurfaceWidth;
  DefenderExclusionsCheckBox.Height := ScaleY(24);
  DefenderExclusionsCheckBox.Checked := True;
  DefenderExclusionsCheckBox.Caption :=
    'Add ATLAS Link''s bundled DLL folder to Windows Defender exclusions';

  BackendOptionsPage := CreateCustomPage(
    DefenderOptionsPage.ID,
    'Additional Backends',
    'Choose which embedded backends to install with ATLAS Link.'
  );

  BackendIntroLabel := TNewStaticText.Create(BackendOptionsPage);
  BackendIntroLabel.Parent := BackendOptionsPage.Surface;
  BackendIntroLabel.Left := 0;
  BackendIntroLabel.Top := 0;
  BackendIntroLabel.Width := BackendOptionsPage.SurfaceWidth;
  BackendIntroLabel.AutoSize := False;
  BackendIntroLabel.WordWrap := True;
  BackendIntroLabel.Font.Style := [fsBold];
  BackendIntroLabel.Caption :=
    'ATLAS Link can bundle NeoniteV2 and/or LawinServer so you can host a backend locally.';
  WizardForm.AdjustLabelHeight(BackendIntroLabel);

  BackendDetailsLabel := TNewStaticText.Create(BackendOptionsPage);
  BackendDetailsLabel.Parent := BackendOptionsPage.Surface;
  BackendDetailsLabel.Left := 0;
  BackendDetailsLabel.Top :=
    BackendIntroLabel.Top + BackendIntroLabel.Height + ScaleY(12);
  BackendDetailsLabel.Width := BackendOptionsPage.SurfaceWidth;
  BackendDetailsLabel.AutoSize := False;
  BackendDetailsLabel.WordWrap := True;
  BackendDetailsLabel.Caption :=
    'Selected backends are downloaded from GitHub during installation (an internet connection is required while installing), so the installer itself stays small. Leave both unchecked for the fastest install - you can download either backend later from the Backend tab inside ATLAS Link.';
  WizardForm.AdjustLabelHeight(BackendDetailsLabel);

  NeoniteCheckBox := TNewCheckBox.Create(BackendOptionsPage);
  NeoniteCheckBox.Parent := BackendOptionsPage.Surface;
  NeoniteCheckBox.Left := 0;
  NeoniteCheckBox.Top :=
    BackendDetailsLabel.Top + BackendDetailsLabel.Height + ScaleY(16);
  NeoniteCheckBox.Width := BackendOptionsPage.SurfaceWidth;
  NeoniteCheckBox.Height := ScaleY(24);
  NeoniteCheckBox.Checked := False;
  NeoniteCheckBox.Caption := 'Install NeoniteV2 backend';

  LawinCheckBox := TNewCheckBox.Create(BackendOptionsPage);
  LawinCheckBox.Parent := BackendOptionsPage.Surface;
  LawinCheckBox.Left := 0;
  LawinCheckBox.Top :=
    NeoniteCheckBox.Top + NeoniteCheckBox.Height + ScaleY(8);
  LawinCheckBox.Width := BackendOptionsPage.SurfaceWidth;
  LawinCheckBox.Height := ScaleY(24);
  LawinCheckBox.Checked := False;
  LawinCheckBox.Caption := 'Install LawinServer backend';

  TailscaleOptionsPage := CreateCustomPage(
    BackendOptionsPage.ID,
    'Network (Tailscale)',
    'Install Tailscale so you can use the ATLAS Link Network feature.'
  );

  TailscaleIntroLabel := TNewStaticText.Create(TailscaleOptionsPage);
  TailscaleIntroLabel.Parent := TailscaleOptionsPage.Surface;
  TailscaleIntroLabel.Left := 0;
  TailscaleIntroLabel.Top := 0;
  TailscaleIntroLabel.Width := TailscaleOptionsPage.SurfaceWidth;
  TailscaleIntroLabel.AutoSize := False;
  TailscaleIntroLabel.WordWrap := True;
  TailscaleIntroLabel.Font.Style := [fsBold];
  TailscaleIntroLabel.Caption :=
    'ATLAS Link''s Network feature uses Tailscale to connect you directly with friends.';
  WizardForm.AdjustLabelHeight(TailscaleIntroLabel);

  TailscaleDetailsLabel := TNewStaticText.Create(TailscaleOptionsPage);
  TailscaleDetailsLabel.Parent := TailscaleOptionsPage.Surface;
  TailscaleDetailsLabel.Left := 0;
  TailscaleDetailsLabel.Top :=
    TailscaleIntroLabel.Top + TailscaleIntroLabel.Height + ScaleY(12);
  TailscaleDetailsLabel.Width := TailscaleOptionsPage.SurfaceWidth;
  TailscaleDetailsLabel.AutoSize := False;
  TailscaleDetailsLabel.WordWrap := True;
  TailscaleDetailsLabel.Caption :=
    'The Network tab lets you join a shared private network and host or join games directly by IP with no port forwarding and no separate account or login required. Tailscale is a free, secure (WireGuard-based) tool that makes this possible. The official Tailscale installer is downloaded from tailscale.com and installed silently during setup (an internet connection is required). If Tailscale is already installed, this step is skipped automatically. You can also install it later from the Network tab inside ATLAS Link.';
  WizardForm.AdjustLabelHeight(TailscaleDetailsLabel);

  TailscaleCheckBox := TNewCheckBox.Create(TailscaleOptionsPage);
  TailscaleCheckBox.Parent := TailscaleOptionsPage.Surface;
  TailscaleCheckBox.Left := 0;
  TailscaleCheckBox.Top :=
    TailscaleDetailsLabel.Top + TailscaleDetailsLabel.Height + ScaleY(16);
  TailscaleCheckBox.Width := TailscaleOptionsPage.SurfaceWidth;
  TailscaleCheckBox.Height := ScaleY(24);
  TailscaleCheckBox.Checked := True;
  TailscaleCheckBox.Caption :=
    'Install Tailscale (recommended)';

  BackendDownloadPage :=
    CreateDownloadPage('Downloading components', 'Fetching the selected ATLAS Link components...', nil);
  BackendDownloadPage.ShowBaseNameInsteadOfUrl := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  // Download the selected backend payloads to {tmp} right after the user
  // commits to install (the Ready page). The [Files] section then extracts
  // whatever was downloaded. Failures are non-fatal so the rest of ATLAS Link
  // still installs; the missing backend can be downloaded later in-app.
  if CurPageID <> wpReady then
    Exit;
  if not (WantEitherBackend or WantTailscaleDownload) then
    Exit;

  BackendDownloadPage.Clear;
  if WantNeonite then
    BackendDownloadPage.Add(NeoniteBackendUrl, 'neonitev2-backend.zip', '');
  if WantLawin then
    BackendDownloadPage.Add(LawinBackendUrl, 'lawinserver-backend.zip', '');
  if WantTailscaleDownload then
    BackendDownloadPage.Add(TailscaleMsiUrl, 'tailscale-setup.msi', '');

  BackendDownloadPage.Show;
  try
    try
      BackendDownloadPage.Download;
    except
      if BackendDownloadPage.AbortedByUser then begin
        Result := False;
      end else begin
        SuppressibleMsgBox(
          'The selected backend(s) could not be downloaded right now:' + #13#10 +
          AddPeriod(GetExceptionMessage) + #13#10#13#10 +
          'Setup will continue. You can install the backend later from the Backend tab inside ATLAS Link.',
          mbInformation, MB_OK, IDOK);
        Result := True;
      end;
    end;
  finally
    BackendDownloadPage.Hide;
  end;
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

  Params := '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ScriptPath + '"';
  if not ShellExec(
    'open',
    PowerShellExe,
    Params,
    '',
    SW_HIDE,
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

procedure SuppressTailscaleAutostart;
begin
  // ATLAS Link drives Tailscale through its CLI and the background tailscaled
  // service, so the Tailscale tray/login GUI is unnecessary. Remove its
  // auto-start entry and close it so a fresh install never shows the Tailscale
  // setup/login window. (Only runs when ATLAS installed Tailscale itself.)
  DeleteFile(ExpandConstant('{commonstartup}\Tailscale.lnk'));
  DeleteFile(ExpandConstant('{userstartup}\Tailscale.lnk'));
  _TaskKillImage('tailscale-ipn.exe');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssInstall) then begin
    TailscaleInstallQueued :=
      WantTailscale and
      (not TailscaleAlreadyInstalled) and
      FileExists(ExpandConstant('{tmp}\tailscale-setup.msi'));
    // Apply before extracting files so Defender doesn't quarantine DLLs during install.
    if ShouldApplyDefenderExclusions then
      ApplyDefenderExclusions;
  end;
  // Runs after the silent Tailscale MSI has completed.
  if (CurStep = ssPostInstall) and TailscaleInstallQueued then
    SuppressTailscaleAutostart;
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
