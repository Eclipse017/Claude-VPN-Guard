param([string]$BackupRoot)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){throw 'PowerShell 7 required'}
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator permission required'}
if(Get-Process Claude -ErrorAction SilentlyContinue){throw 'Claude is running; update cancelled without touching it'}
$root=Split-Path $PSScriptRoot -Parent
$dest='C:\Program Files\ShuniangGuard';$data='C:\ProgramData\ShuniangGuard'
$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe'
$gate='"C:\Program Files\ShuniangGuard\ShuniangGuard.exe" --intercept'
$task=Get-ScheduledTask -TaskName ShuniangGuard
if($task.Actions.Execute -ne (Join-Path $dest 'ShuniangGuard.exe') -or $task.Actions.Arguments -ne '--monitor'){throw 'Unexpected guard task'}
if((Get-ItemPropertyValue $key Debugger) -ne $gate){throw 'Unexpected IFEO owner'}
if(!$BackupRoot){$BackupRoot=Join-Path $env:ProgramData ('ShuniangGuardBackups\update-'+(Get-Date -Format yyyyMMdd-HHmmss))}
if(Test-Path -LiteralPath $BackupRoot){throw 'Update backup must be a new directory'}
$names=@('ShuniangGuard.exe','sensor.cjs','node.exe')
foreach($name in $names){if(!(Test-Path (Join-Path $root ('dist\guard\'+$name)))){throw 'Build first'}}
New-Item -ItemType Directory -Path $BackupRoot | Out-Null
foreach($name in $names){Copy-Item -LiteralPath (Join-Path $dest $name) -Destination $BackupRoot}
$otherHashes=@(Get-ChildItem 'C:\Program Files\AIAppVpnGuard' -File -Recurse | Get-FileHash)
$otherTask=Export-ScheduledTask -TaskName AIAppVpnGuard
$otherPids=@(Get-Process AIAppVpnGuard | ForEach-Object Id)
function Stop-OwnedGuard {
 Stop-ScheduledTask -TaskName ShuniangGuard
 for($i=0;$i -lt 50 -and (Get-Process ShuniangGuard -ErrorAction SilentlyContinue);$i++){Start-Sleep -Milliseconds 100}
 if(Get-Process ShuniangGuard -ErrorAction SilentlyContinue){throw 'Guard did not stop'}
 # Task termination can leave its child alive. Match both its protected image and sensor path.
 Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
  $_.ExecutablePath -eq (Join-Path $dest 'node.exe') -and $_.CommandLine -like '*"C:\Program Files\ShuniangGuard\sensor.cjs"*'
 } | ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop}
}
try {
 Stop-OwnedGuard
 foreach($name in $names){
  $source=Join-Path $root ('dist\guard\'+$name);Copy-Item -LiteralPath $source -Destination (Join-Path $dest $name) -Force
  if((Get-FileHash $source).Hash -ne (Get-FileHash (Join-Path $dest $name)).Hash){throw 'Installed hash mismatch'}
 }
 # The permanent IFEO remains in place throughout the update; no client is launched.
 $started=[DateTime]::UtcNow;Start-ScheduledTask -TaskName ShuniangGuard
 $ready=$false
 for($i=0;$i -lt 60;$i++){
  Start-Sleep -Milliseconds 250
  $s=Get-Content (Join-Path $data 'status.json') -Raw | ConvertFrom-Json
  $checked=if($s.checkedAt -is [DateTime]){$s.checkedAt}else{[DateTime]::Parse($s.checkedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
  if($s.monitor -and $checked.ToUniversalTime() -gt $started){$ready=$true;break}
 }
 if(!$ready){throw 'Updated monitor heartbeat missing'}
 if((Get-ItemPropertyValue $key Debugger) -ne $gate){throw 'Permanent gate changed'}
 foreach($entry in $otherHashes){if((Get-FileHash $entry.Path).Hash -ne $entry.Hash){throw 'Other guard file changed'}}
 if((Export-ScheduledTask -TaskName AIAppVpnGuard) -ne $otherTask){throw 'Other guard task changed'}
 if(Compare-Object $otherPids @(Get-Process AIAppVpnGuard | ForEach-Object Id)){throw 'Other guard restarted'}
 [ordered]@{status='PASS';claudeLaunched=$false;permanentGatePreserved=$true;otherAppGuardUnchanged=$true;hashes=@($names | ForEach-Object {Get-FileHash (Join-Path $dest $_) | Select-Object Path,Hash})} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $BackupRoot 'update-result.json') -Encoding utf8
}catch{
 $failure=$_.Exception.Message
 Stop-OwnedGuard
 foreach($name in $names){Copy-Item -LiteralPath (Join-Path $BackupRoot $name) -Destination (Join-Path $dest $name) -Force}
 Start-ScheduledTask -TaskName ShuniangGuard
 @{status='FAILED';reason=$failure;oldVersionRestored=$true;claudeLaunched=$false} | ConvertTo-Json | Set-Content (Join-Path $BackupRoot 'update-result.json')
 throw
}
