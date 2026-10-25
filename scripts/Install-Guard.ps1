param([Parameter(Mandatory=$true)][string]$PolicyPath,[string]$BackupRoot)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(!$admin){throw 'Run this script with PowerShell 7 as Administrator. It never opens Claude.'}
if($PSVersionTable.PSVersion.Major -lt 7){throw 'PowerShell 7 required'}
if(Get-Process -Name Claude -ErrorAction SilentlyContinue){throw 'Claude is already running. Installation cancelled without touching it.'}
$dest='C:\Program Files\ShuniangGuard';$data='C:\ProgramData\ShuniangGuard';$task='ShuniangGuard'
$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe'
$oldTask=Get-ScheduledTask -TaskName ClaudeVpnGuard -ErrorAction Stop
$oldExecutable='C:\Program Files\ClaudeVpnGuard\ClaudeVpnGuard.exe'
if($oldTask.Actions.Execute -ne $oldExecutable -or $oldTask.Actions.Arguments -ne '--monitor'){throw 'Old guard task differs from reviewed version'}
if(Test-Path -LiteralPath $dest){throw 'Installation already exists; use the documented update procedure'}
$baseline=Get-ItemProperty -LiteralPath $key
$oldDebugger=$baseline.Debugger
$expected='"'+$oldExecutable+'" --blocked'
if($oldDebugger -and $oldDebugger -ne $expected){throw 'Foreign Claude IFEO debugger detected'}
if(!$BackupRoot){$BackupRoot=Join-Path $env:ProgramData ('ShuniangGuardBackups\'+(Get-Date -Format yyyyMMdd-HHmmss))}
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
Export-ScheduledTask -TaskName ClaudeVpnGuard | Set-Content (Join-Path $BackupRoot 'ClaudeVpnGuard.task.xml') -Encoding utf8
Export-ScheduledTask -TaskName AIAppVpnGuard -ErrorAction SilentlyContinue | Set-Content (Join-Path $BackupRoot 'AIAppVpnGuard.task.xml') -Encoding utf8
& reg.exe export 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe' (Join-Path $BackupRoot 'before-IFEO.reg') /y | Out-Null
Copy-Item -LiteralPath 'C:\Program Files\ClaudeVpnGuard' -Destination (Join-Path $BackupRoot 'old-installed') -Recurse
$desktop=[Environment]::GetFolderPath('Desktop');$link=Join-Path $desktop 'Claude.lnk';$savedLink=Join-Path $BackupRoot 'Claude.before.lnk'
if(Test-Path -LiteralPath $link){Copy-Item -LiteralPath $link -Destination $savedLink}
$otherHashes=@(Get-ChildItem 'C:\Program Files\AIAppVpnGuard' -File -Recurse | Get-FileHash | Select-Object Path,Hash)
$otherTaskBefore=Export-ScheduledTask -TaskName AIAppVpnGuard
$otherPids=@(Get-Process AIAppVpnGuard -ErrorAction Stop | ForEach-Object Id)
$record=[ordered]@{BackupRoot=$BackupRoot;OldTaskEnabled=$oldTask.Settings.Enabled;OldDebugger=$oldDebugger;Shortcut=$link;HadShortcut=(Test-Path $savedLink);OtherGuardPids=$otherPids;OtherGuardHashes=$otherHashes;InstalledAt=(Get-Date -Format o)}
$record | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $BackupRoot 'rollback.json') -Encoding utf8
$switched=$false
try {
 New-Item -ItemType Directory -Path $dest,$data -Force | Out-Null
 & icacls.exe $data /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
 if($LASTEXITCODE -ne 0){throw 'State ACL setup failed'}
 foreach($name in 'ShuniangGuard.exe','sensor.cjs','node.exe'){
  $source=Join-Path $root ('dist\guard\'+$name);Copy-Item -LiteralPath $source -Destination $dest
  if((Get-FileHash $source).Hash -ne (Get-FileHash (Join-Path $dest $name)).Hash){throw 'Copy verification failed'}
 }
 Copy-Item -LiteralPath $PolicyPath -Destination (Join-Path $data 'policy.json')
 # Exercise Windows IFEO and the debug/detach path with a harmless, uniquely named executable.
 $verify=Join-Path $data 'verify';New-Item -ItemType Directory $verify -Force | Out-Null
 Copy-Item (Join-Path $root 'dist\guard\ShuniangGuardTest.exe'),(Join-Path $root 'dist\guard\ShuniangGuardProbe.exe') $verify
 $probeKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\ShuniangGuardProbe.exe'
 if(Test-Path $probeKey){throw 'Probe IFEO key already exists'}
 $probe=Join-Path $verify 'ShuniangGuardProbe.exe';$tester=Join-Path $verify 'ShuniangGuardTest.exe';$marker=Join-Path $verify 'probe-ran.txt'
 try {
  New-Item -Path $probeKey -Force | Out-Null
  New-ItemProperty $probeKey -Name Debugger -Value ('"'+$tester+'" --probe-block') -PropertyType String | Out-Null
  $p=Start-Process -FilePath $probe -PassThru -WindowStyle Hidden
  if(!$p.WaitForExit(10000)){throw 'Blocked fixture timed out'}
  if(Test-Path $marker){throw 'IFEO failed to block fixture'}
  Set-ItemProperty $probeKey -Name Debugger -Value ('"'+$tester+'" --probe-allow')
  $p=Start-Process -FilePath $probe -PassThru -WindowStyle Hidden
  if(!$p.WaitForExit(10000)){throw 'Allowed fixture timed out'}
  for($i=0;$i -lt 30 -and !(Test-Path $marker);$i++){Start-Sleep -Milliseconds 100}
  if(!(Test-Path $marker)){throw 'IFEO debug-detach failed to allow fixture'}
 }finally{if(Test-Path $probeKey){Remove-Item -LiteralPath $probeKey}}
 # Fixed migration boundary: only this existing Claude task and Claude.exe IFEO are changed.
 Disable-ScheduledTask -TaskName ClaudeVpnGuard | Out-Null
 Stop-ScheduledTask -TaskName ClaudeVpnGuard
 for($i=0;$i -lt 40 -and (Get-Process ClaudeVpnGuard -ErrorAction SilentlyContinue);$i++){Start-Sleep -Milliseconds 100}
 if(Get-Process ClaudeVpnGuard -ErrorAction SilentlyContinue){throw 'Old Claude guard did not exit'}
 $switched=$true
 $gate='"'+(Join-Path $dest 'ShuniangGuard.exe')+'" --intercept'
 Set-ItemProperty -LiteralPath $key -Name Debugger -Value $gate
 New-ItemProperty -LiteralPath $key -Name ShuniangGuardOwner -Value 'v1' -PropertyType String -Force | Out-Null
 $action=New-ScheduledTaskAction -Execute (Join-Path $dest 'ShuniangGuard.exe') -Argument '--monitor'
 $principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
 Register-ScheduledTask -TaskName $task -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Settings $settings -Description 'Claude-only persistent launch gate; no automatic Claude launch.' | Out-Null
 Start-ScheduledTask -TaskName $task
 $statusFile=Join-Path $data 'status.json'
 for($i=0;$i -lt 60 -and !(Test-Path $statusFile);$i++){Start-Sleep -Milliseconds 250}
 if(!(Test-Path $statusFile)){throw 'New monitor did not publish state'}
 $shell=New-Object -ComObject WScript.Shell;$shortcut=$shell.CreateShortcut($link)
 $shortcut.TargetPath=Join-Path $dest 'ShuniangGuard.exe';$shortcut.Arguments='--launch';$shortcut.WorkingDirectory=$dest;$shortcut.Description='书娘守护：节点与分流通过后才允许启动';$shortcut.Save()
 $record.ProtectedShortcutHash=(Get-FileHash $link).Hash
 $record | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $data 'install.json') -Encoding utf8
 foreach($entry in $otherHashes){if((Get-FileHash -LiteralPath $entry.Path).Hash -ne $entry.Hash){throw 'Other application guard files changed'}}
 if((Export-ScheduledTask -TaskName AIAppVpnGuard) -ne $otherTaskBefore){throw 'Other application guard task changed'}
 if(Compare-Object $otherPids @(Get-Process AIAppVpnGuard | ForEach-Object Id)){throw 'Other application guard restarted'}
 if((Get-ItemPropertyValue $key -Name Debugger) -ne $gate){throw 'Permanent IFEO not installed'}
 [ordered]@{status='PASS';claudeLaunched=$false;offlineProbeBlocked=$true;offlineProbeAllowed=$true;otherAppGuardUnchanged=$true;otherAppGuardPids=$otherPids;guardState=(Get-Content $statusFile -Raw | ConvertFrom-Json);backup=$BackupRoot} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $BackupRoot 'install-result.json') -Encoding utf8
}catch{
 $failure=$_.Exception.Message
 if($switched){
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
  if($oldDebugger){Set-ItemProperty $key -Name Debugger -Value $oldDebugger}else{Remove-ItemProperty $key -Name Debugger -ErrorAction SilentlyContinue}
  Remove-ItemProperty $key -Name ShuniangGuardOwner -ErrorAction SilentlyContinue
  if(Test-Path $savedLink){Copy-Item $savedLink $link -Force}
 }
 if($record.OldTaskEnabled){Enable-ScheduledTask -TaskName ClaudeVpnGuard | Out-Null;Start-ScheduledTask -TaskName ClaudeVpnGuard}
 @{status='FAILED';message=$failure;claudeLaunched=$false;oldGuardRestored=$true} | ConvertTo-Json | Set-Content (Join-Path $BackupRoot 'install-result.json') -Encoding utf8
 throw
}
