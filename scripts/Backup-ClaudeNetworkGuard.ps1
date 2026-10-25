param([Parameter(Mandatory)][string]$OutputDirectory,[string]$FlClashConfigDirectory=(Join-Path $env:APPDATA 'com.follow\clash'))
# Read-only system audit. Does not start Claude or change VPN/firewall rules.
$ErrorActionPreference='Stop'
$out=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $out -Force | Out-Null
try {
  $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if(-not $admin){throw 'Administrator token is required for firewall backup and audit.'}
  Start-Transcript -LiteralPath (Join-Path $out 'audit.log') | Out-Null
  $backup=Join-Path $out 'backup'
  New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
  & icacls.exe $backup /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Unable to restrict backup access.'}
  # Grant the requesting user explicitly; configuration copies may contain proxy credentials.
  $owner=(Get-Acl -LiteralPath $out).Owner
  & icacls.exe $backup /grant:r ($owner+':(OI)(CI)F') | Out-Null
  if($LASTEXITCODE -ne 0){throw 'Unable to grant backup access.'}
  & netsh.exe advfirewall export (Join-Path $backup 'firewall-before.wfw') | Out-File (Join-Path $out 'firewall-export.txt')
  if($LASTEXITCODE -ne 0){throw 'Firewall export failed.'}
  $active=@(Get-NetFirewallRule -PolicyStore ActiveStore)
  $active | Export-Clixml -LiteralPath (Join-Path $backup 'active-rules.clixml')
  $snapshot=foreach($r in $active){
    $a=$r | Get-NetFirewallApplicationFilter
    $p=$r | Get-NetFirewallPortFilter
    $d=$r | Get-NetFirewallAddressFilter
    $i=$r | Get-NetFirewallInterfaceFilter
    [ordered]@{Name=$r.Name;DisplayName=$r.DisplayName;Enabled="$($r.Enabled)";Direction="$($r.Direction)";Action="$($r.Action)";Profile="$($r.Profile)";Program=$a.Program;Package=$a.Package;Protocol=$p.Protocol;LocalPort=$p.LocalPort;RemotePort=$p.RemotePort;RemoteAddress=$d.RemoteAddress;InterfaceAlias=$i.InterfaceAlias}
  }
  $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backup 'active-rules.json')
  @($snapshot | Where-Object {$_.DisplayName -match 'Claude|Anthropic|FlClash|Mihomo|Guard' -or $_.Program -match 'Claude|Anthropic|FlClash|Mihomo|Guard' -or ($_.Enabled -eq 'True' -and $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block')}) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'relevant-rules.json')
  Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name,@{n='Enabled';e={"$($_.Enabled)"}},@{n='DefaultInboundAction';e={"$($_.DefaultInboundAction)"}},@{n='DefaultOutboundAction';e={"$($_.DefaultOutboundAction)"}} | ConvertTo-Json | Set-Content (Join-Path $out 'profiles.json')
  $files=New-Object System.Collections.Generic.List[object]
  foreach($dir in @('C:\Program Files\ClaudeVpnGuard','C:\ProgramData\ClaudeVpnGuard','C:\Program Files\ShuniangGuard','C:\ProgramData\ShuniangGuard')) {
    if(Test-Path -LiteralPath $dir){
      $dest=Join-Path $backup ($dir.Replace(':','').Replace('\','_'))
      Copy-Item -LiteralPath $dir -Destination $dest -Recurse
      foreach($f in Get-ChildItem -LiteralPath $dir -Recurse -File){$files.Add([pscustomobject]@{Path=$f.FullName;Length=$f.Length;SHA256=(Get-FileHash -LiteralPath $f.FullName).Hash})}
    }
  }
    $clash=$FlClashConfigDirectory
  New-Item -ItemType Directory -Path (Join-Path $backup 'flclash') | Out-Null
  foreach($name in @('config.yaml','shared_preferences.json')) {
    $p=Join-Path $clash $name
    if(Test-Path $p){Copy-Item -LiteralPath $p -Destination (Join-Path $backup 'flclash');$files.Add([pscustomobject]@{Path=$p;Length=(Get-Item $p).Length;SHA256=(Get-FileHash -LiteralPath $p).Hash})}
  }
  # Do not copy the live SQLite database; no database edits are planned.
  $files | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $out 'source-manifest.json')
  foreach($name in @('ClaudeVpnGuard','ShuniangGuard','AIAppVpnGuard')) {
    $t=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if($t){Export-ScheduledTask -TaskName $name | Set-Content (Join-Path $backup ($name+'.task.xml'))}
  }
  & reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe' (Join-Path $backup 'Claude-IFEO.reg') /y | Out-File (Join-Path $out 'ifeo-export.txt')
  if($LASTEXITCODE -ne 0){throw 'Claude IFEO export failed.'}
  Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'Claude|Guard|FlClash'} | Select-Object Name,ProcessId,ExecutablePath,CreationDate | ConvertTo-Json | Set-Content (Join-Path $out 'processes-before.json')
  Get-NetAdapter | Select-Object Name,InterfaceDescription,InterfaceGuid,ifIndex,Status | ConvertTo-Json | Set-Content (Join-Path $out 'adapters.json')
  Get-NetIPAddress | Select-Object InterfaceAlias,InterfaceIndex,IPAddress,AddressFamily | ConvertTo-Json | Set-Content (Join-Path $out 'addresses.json')
  Get-NetRoute | Select-Object InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | ConvertTo-Json | Set-Content (Join-Path $out 'routes.json')
  $packages=@(Get-ChildItem 'C:\Program Files\WindowsApps','D:\WindowsApps' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)
  $inventory=foreach($p in $packages){[ordered]@{PackageDir=$p.FullName;Manifest=(Get-Content -LiteralPath (Join-Path $p.FullName 'AppxManifest.xml') -Raw);Executables=@(Get-ChildItem -LiteralPath $p.FullName -Filter '*.exe' -Recurse | Select-Object FullName,Length)}}
  $inventory | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out 'claude-packages.json')
  & netsh.exe wfp show state ('file='+ (Join-Path $backup 'wfp-before.xml')) | Out-File (Join-Path $out 'wfp-export.txt')
  if($LASTEXITCODE -ne 0){throw 'WFP state export failed.'}
  Get-ChildItem -LiteralPath $backup -Recurse -File | ForEach-Object {[pscustomobject]@{RelativePath=$_.FullName.Substring($backup.Length+1);Length=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash}} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $out 'backup-manifest.json')
  @{Status='PASS';Time=(Get-Date -Format o);FirewallRuleCount=$active.Count;ClaudeStarted=$false;VPNChanged=$false;RulesChanged=$false} | ConvertTo-Json | Set-Content (Join-Path $out 'audit-result.json')
} catch {
  @{Status='FAILED';Error=$_.ToString();Time=(Get-Date -Format o)} | ConvertTo-Json | Set-Content (Join-Path $out 'audit-result.json')
  exit 1
} finally {Stop-Transcript -ErrorAction SilentlyContinue | Out-Null}
