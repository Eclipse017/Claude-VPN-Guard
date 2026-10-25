param([Parameter(Mandatory)][string]$AuditDirectory,[string]$FlClashConfigPath)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$dest='C:\Program Files\ClaudeNetworkGuard'
$data='C:\ProgramData\ClaudeNetworkGuard'
$created=$false
$applied=$false
try {
  if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator PowerShell 7 is required.'}
  $audit=Get-Content -LiteralPath (Join-Path $AuditDirectory 'audit-result.json') -Raw|ConvertFrom-Json
  $test=Get-Content -LiteralPath (Join-Path $AuditDirectory 'test-result.json') -Raw|ConvertFrom-Json
  if($audit.Status -ne 'PASS' -or $test.Status -ne 'PASS'){throw 'Successful backup/audit and live harmless-probe tests are required.'}
  if((Test-Path $dest) -or (Test-Path $data) -or (Get-Service -Name 'ClaudeNetworkGuard' -ErrorAction SilentlyContinue)){throw 'Existing installation; refusing to overwrite.'}
  if(Get-Process -Name 'Claude' -ErrorAction SilentlyContinue){throw 'Claude is already running. Refusing to change its networking during an active session.'}
  if(-not $FlClashConfigPath){
    $guardPolicy=Join-Path $env:ProgramData 'ShuniangGuard\policy.json'
    if(Test-Path $guardPolicy){$FlClashConfigPath=(Get-Content $guardPolicy -Raw|ConvertFrom-Json).configPath}
    if(-not $FlClashConfigPath){$FlClashConfigPath=Join-Path $env:APPDATA 'com.follow\clash\config.yaml'}
  }
  $clash=[IO.Path]::GetFullPath($FlClashConfigPath)
  $hash=(Get-FileHash -LiteralPath $clash).Hash
  $before=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -in @('FlClash.exe','FlClashCore.exe','AIAppVpnGuard.exe','ShuniangGuard.exe','ClaudeVpnGuard.exe')}|Select-Object Name,ProcessId,CreationDate)
  $before|ConvertTo-Json|Set-Content (Join-Path $AuditDirectory 'install-processes-before.json')
  $profiles=@(Get-NetFirewallProfile -PolicyStore ActiveStore)
  if(@($profiles|Where-Object {$_.Enabled -ne 'True'}).Count){throw 'A Windows firewall profile is disabled; review separately.'}
  New-Item -ItemType Directory -Path $dest,$data|Out-Null
  $created=$true
  & icacls.exe $data /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'|Out-Null
  if($LASTEXITCODE -ne 0){throw 'Could not secure status directory.'}
  $payload=@(
    @{Source=(Join-Path $workspace 'dist\network\ClaudeNetworkGuard.exe');Name='ClaudeNetworkGuard.exe'},
    @{Source=(Join-Path $workspace 'scripts\Refresh-ClaudeNetworkGuard.ps1');Name='Refresh-ClaudeNetworkGuard.ps1'},
    @{Source=(Join-Path $workspace 'scripts\Remove-ClaudeNetworkGuard.ps1');Name='Remove-ClaudeNetworkGuard.ps1'},
    @{Source=(Join-Path $workspace 'docs\CLAUDE-NETWORK-GUARD.md');Name='README.md'}
  )
  foreach($p in $payload){Copy-Item -LiteralPath $p.Source -Destination (Join-Path $dest $p.Name);if((Get-FileHash -LiteralPath $p.Source).Hash -ne (Get-FileHash -LiteralPath (Join-Path $dest $p.Name)).Hash){throw 'Installed payload hash mismatch.'}}
  $cfg=[ordered]@{Schema=1;AdapterName='FlClash';AdapterDescription='Meta Tunnel';PackageSid='S-1-15-2-3557520199-3666692283-3112367039-3524159787-2791857073-3163583606-3692855932';PackageRoots=@('C:\Program Files\WindowsApps','D:\WindowsApps');TestPrograms=@();TestMode=$false;DenyAllNonLoopback=$false}
  $config=Join-Path $dest 'policy.json'
  $cfg|ConvertTo-Json -Depth 4|Set-Content $config
  & (Join-Path $dest 'ClaudeNetworkGuard.exe') status $config (Join-Path $AuditDirectory 'production-before.json')
  if($LASTEXITCODE -ne 0){throw 'Unable to inspect WFP provider.'}
  $state=Get-Content (Join-Path $AuditDirectory 'production-before.json') -Raw|ConvertFrom-Json
  if(@($state.Filters).Count){throw 'Preexisting WFP ownership found; refusing to replace.'}
  # Auto-start association is required for BFE to enable a persistent provider after reboot.
  New-Service -Name 'ClaudeNetworkGuard' -BinaryPathName '"C:\Program Files\ClaudeNetworkGuard\ClaudeNetworkGuard.exe" --service' -DisplayName 'Claude application network protection' -StartupType Automatic -DependsOn BFE -Description 'Claude-only persistent WFP blocking; no Claude launches or VPN changes.'|Out-Null
  # Once apply is attempted, any failure rolls back only this newly-created provider.
  $applied=$true
  & (Join-Path $dest 'ClaudeNetworkGuard.exe') apply $config (Join-Path $AuditDirectory 'production-applied.json')
  if($LASTEXITCODE -ne 0){throw (Get-Content (Join-Path $AuditDirectory 'production-applied.json') -Raw)}
  $appliedState=Get-Content (Join-Path $AuditDirectory 'production-applied.json') -Raw|ConvertFrom-Json
  if($appliedState.FailClosed){throw 'Approved TUN was unavailable during installation.'}
  & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -File (Join-Path $dest 'Refresh-ClaudeNetworkGuard.ps1')
  if($LASTEXITCODE -ne 0){throw 'Installed reconciliation failed.'}
  Start-Service -Name 'ClaudeNetworkGuard'
  & sc.exe failure ClaudeNetworkGuard reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-File (Join-Path $AuditDirectory 'service-recovery.txt')
  if($LASTEXITCODE -ne 0){throw 'Service recovery configuration failed.'}
  Start-Sleep -Seconds 2
  $service=Get-CimInstance Win32_Service -Filter "Name='ClaudeNetworkGuard'"
  if($service.State -ne 'Running' -or $service.StartMode -ne 'Auto'){throw 'Installed service not ready.'}
  $service|Select-Object Name,State,StartMode,StartName,PathName|ConvertTo-Json|Set-Content (Join-Path $AuditDirectory 'service.json')
  if((Get-FileHash -LiteralPath $clash).Hash -ne $hash){throw 'FlClash config changed concurrently; inspect before delivery.'}
  $after=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -in @('FlClash.exe','FlClashCore.exe','AIAppVpnGuard.exe','ShuniangGuard.exe','ClaudeVpnGuard.exe')}|Select-Object Name,ProcessId,CreationDate)
  if(Compare-Object ($before|ForEach-Object {"$($_.Name)|$($_.ProcessId)|$($_.CreationDate)"}) ($after|ForEach-Object {"$($_.Name)|$($_.ProcessId)|$($_.CreationDate)"})){throw 'An existing guard or proxy process changed during installation.'}
  $manifest=@(Get-ChildItem -LiteralPath $dest -File|ForEach-Object{[ordered]@{Name=$_.Name;SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
  $result=[ordered]@{Status='PASS';Time=(Get-Date -Format o);AuditDirectory=$AuditDirectory;FilterCount=$appliedState.FilterCount;Programs=$appliedState.Programs;ClaudeStarted=$false;VPNStopped=$false;FlClashConfigUnchanged=$true;ExistingProcessesUnchanged=$true;Payload=$manifest}
  $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $data 'install.json')
  $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $AuditDirectory 'install-result.json')
} catch {
  $errorText=$_.ToString()
  if($applied){
    $s=Get-Service -Name 'ClaudeNetworkGuard' -ErrorAction SilentlyContinue
    if($s){Set-Service -Name 'ClaudeNetworkGuard' -StartupType Disabled;Stop-Service -Name 'ClaudeNetworkGuard';Remove-Service -Name 'ClaudeNetworkGuard'}
    & (Join-Path $dest 'ClaudeNetworkGuard.exe') remove (Join-Path $dest 'policy.json') (Join-Path $AuditDirectory 'install-failure-rollback.json')
  }
  @{Status='FAILED';Error=$errorText;Time=(Get-Date -Format o);CreatedDirectories=$created}|ConvertTo-Json|Set-Content (Join-Path $AuditDirectory 'install-result.json')
  exit 1
}
