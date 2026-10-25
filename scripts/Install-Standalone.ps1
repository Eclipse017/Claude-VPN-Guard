param([Parameter(Mandatory)][string]$PolicyPath,[Parameter(Mandatory)][string]$ResultPath,[string]$FixtureRoot)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Write-Result($value){$value|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ResultPath -Encoding utf8}
function Assert-Policy($policy){
 if($policy.schema -ne 1 -or !$policy.enrolled -or $policy.nodeDigest -notmatch '^[a-f0-9]{64}$' -or @($policy.allowedExitIps).Count -lt 1){throw '请先完成中文配置向导中的出口检查'}
 $u=[Uri]$policy.controller
 if($u.Scheme -ne 'http' -or $u.Host -ne '127.0.0.1' -or $u.UserInfo -or $u.AbsolutePath -ne '/'){throw '控制接口必须是本机 127.0.0.1'}
}
function Decision($legacy,$foreign){if($legacy -or $foreign){throw '检测到其他 Claude 保护程序；本版不会覆盖。请先通过原保护程序的卸载或恢复功能处理。'}}
$dest='C:\Program Files\ShuniangGuard';$data='C:\ProgramData\ShuniangGuard'
$network='C:\Program Files\ClaudeNetworkGuard';$networkData='C:\ProgramData\ClaudeNetworkGuard'
$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe'
$gate='"C:\Program Files\ShuniangGuard\ShuniangGuard.exe" --intercept'
$changed=$false;$createdNetwork=$false;$previous=$null;$previousActive=$false;$madeNetworkDirectory=$false
try {
 if($PSVersionTable.PSVersion.Major -lt 7){throw '随包 PowerShell 7 运行环境不可用'}
 $policy=Get-Content -LiteralPath $PolicyPath -Raw|ConvertFrom-Json
 Assert-Policy $policy
 if($FixtureRoot){
  # Shared preflight and actual file copy/ACL-free fixture. No HKLM, service, task, VPN, or Claude access.
  if(Test-Path $FixtureRoot){throw '测试目录必须不存在'}
  Decision $false $false
  New-Item -ItemType Directory -Path $FixtureRoot|Out-Null
  foreach($name in 'ShuniangGuard.exe','sensor.cjs','node.exe'){Copy-Item (Join-Path $root ('dist\guard\'+$name)) $FixtureRoot}
  Copy-Item -LiteralPath $PolicyPath -Destination (Join-Path $FixtureRoot 'policy.json')
  $rejected=$false;try{Decision $true $false}catch{$rejected=$true}
  if(!$rejected){throw '旧保护冲突检查未拒绝'}
  Write-Result @{status='PASS';fixture=$true;legacyDependency=$false;foreignGuardRejected=$true;systemChanged=$false;claudeStarted=$false};exit 0
 }
 if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '启用系统保护需要确认 Windows 管理员提示'}
 if(Get-Process Claude -ErrorAction SilentlyContinue){throw '请先自行关闭 Claude，再启用保护；安装器不会替你打开或关闭 Claude'}
 $old=Get-ScheduledTask -TaskName ClaudeVpnGuard -ErrorAction SilentlyContinue
 $debugger=Get-ItemPropertyValue -LiteralPath $key -Name Debugger -ErrorAction SilentlyContinue
 if((Get-ItemPropertyValue -LiteralPath $key -Name UseFilter -ErrorAction SilentlyContinue) -eq 1){throw '存在按路径过滤的启动保护；本版不会覆盖'}
 Decision (!!$old) (!!$debugger -and $debugger -ne $gate)
 if(Test-Path (Join-Path $data 'standalone-install.json')){$previous=Get-Content (Join-Path $data 'standalone-install.json') -Raw|ConvertFrom-Json}
 if($previous -and $previous.owner -ne 'ShuniangGuard-standalone-v2'){throw '保护安装标记不属于本程序'}
 $previousActive=!!($previous -and $previous.state -eq 'active')
 if((Test-Path $dest) -and !$previous){throw '检测到旧版书娘保护目录；本版不会直接覆盖，请先备份并迁移'}
 if((Get-ScheduledTask ShuniangGuard -ErrorAction SilentlyContinue) -and !$previous){throw '保护任务名称被其他安装占用'}
 $otherTask=Get-ScheduledTask AIAppVpnGuard -ErrorAction SilentlyContinue
 $otherXml=if($otherTask){Export-ScheduledTask AIAppVpnGuard}else{''}
 $otherPids=@(Get-Process AIAppVpnGuard -ErrorAction SilentlyContinue|ForEach-Object Id)
 $vpnPids=@(Get-Process FlClashCore -ErrorAction Stop|ForEach-Object Id)
 $configHash=(Get-FileHash -LiteralPath $policy.configPath).Hash
 # Recheck independently inside the elevated installer; no client is started.
 $json=& (Join-Path $root 'dist\guard\node.exe') (Join-Path $root 'dist\guard\sensor.cjs') --once --policy $PolicyPath
 if($LASTEXITCODE -ne 0 -or !($json|ConvertFrom-Json).allowed){throw '安装前节点、出口地区或分流复检未通过'}
 $backup=Join-Path $env:ProgramData ('ShuniangGuardBackups\standalone-'+(Get-Date -Format yyyyMMdd-HHmmss))
 New-Item -ItemType Directory -Path $backup -Force|Out-Null
 & icacls.exe $backup /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'|Out-Null
 if($LASTEXITCODE -ne 0){throw '备份权限设置失败'}
 if($previousActive){Copy-Item $dest (Join-Path $backup 'program') -Recurse;Copy-Item (Join-Path $data 'policy.json') (Join-Path $backup 'policy.json')}
 New-Item -ItemType Directory -Path $dest,$data -Force|Out-Null
 & icacls.exe $data /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'|Out-Null
 if($LASTEXITCODE -ne 0){throw '保护状态权限设置失败'}
 $changed=$true
 if(!$previousActive){@{owner='ShuniangGuard-standalone-v2';state='preparing';createdNetwork=$false}|ConvertTo-Json|Set-Content (Join-Path $data 'standalone-install.json')}
 if($previousActive){Stop-ScheduledTask ShuniangGuard;Start-Sleep -Milliseconds 700;Get-CimInstance Win32_Process -Filter "Name='node.exe'"|Where-Object {$_.ExecutablePath -eq (Join-Path $dest 'node.exe')}|ForEach-Object{Stop-Process -Id $_.ProcessId -Force}}
 foreach($name in 'ShuniangGuard.exe','sensor.cjs','node.exe'){Copy-Item (Join-Path $root ('dist\guard\'+$name)) (Join-Path $dest $name) -Force}
 Copy-Item -LiteralPath $PolicyPath -Destination (Join-Path $data 'policy.json') -Force
 $changed=$true
 New-Item $key -Force|Out-Null
 New-ItemProperty $key -Name Debugger -Value $gate -PropertyType String -Force|Out-Null
 New-ItemProperty $key -Name ShuniangGuardOwner -Value v1 -PropertyType String -Force|Out-Null
 # Network service is independent; an existing reviewed installation is reused, never removed.
 $service=Get-CimInstance Win32_Service -Filter "Name='ClaudeNetworkGuard'"
 if($service){if($service.PathName -ne '"C:\Program Files\ClaudeNetworkGuard\ClaudeNetworkGuard.exe" --service' -or $service.State -ne 'Running'){throw '现有网络保护不是预期版本或未运行'}}
 else {
  if(Test-Path $network){throw '存在未登记的网络保护目录，请先检查原安装'}
  New-Item -ItemType Directory -Path $network,$networkData -Force|Out-Null
  $madeNetworkDirectory=$true
  & icacls.exe $networkData /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'|Out-Null
  if($LASTEXITCODE -ne 0){throw '网络状态权限设置失败'}
  Copy-Item (Join-Path $root 'dist\network\ClaudeNetworkGuard.exe') $network
  $cfg=@{Schema=1;AdapterName='FlClash';AdapterDescription='Meta Tunnel';PackageSid='S-1-15-2-3557520199-3666692283-3112367039-3524159787-2791857073-3163583606-3692855932';PackageRoots=@('C:\Program Files\WindowsApps','D:\WindowsApps');TestPrograms=@();TestMode=$false;DenyAllNonLoopback=$false}
  $cfg|ConvertTo-Json -Depth 4|Set-Content (Join-Path $network 'policy.json')
  New-Service -Name ClaudeNetworkGuard -BinaryPathName '"C:\Program Files\ClaudeNetworkGuard\ClaudeNetworkGuard.exe" --service' -DisplayName 'Claude 专属网络保护' -StartupType Automatic -DependsOn BFE|Out-Null
  $createdNetwork=$true
  & (Join-Path $network 'ClaudeNetworkGuard.exe') apply (Join-Path $network 'policy.json') (Join-Path $data 'network-install.json')
  if($LASTEXITCODE -ne 0){throw '网络规则安装失败，请确认已安装 Windows 商店版 Claude'}
  Start-Service ClaudeNetworkGuard
 }
 $action=New-ScheduledTaskAction -Execute (Join-Path $dest 'ShuniangGuard.exe') -Argument '--monitor'
 $principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
 Register-ScheduledTask -TaskName ShuniangGuard -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $principal -Settings $settings -Force|Out-Null
 Start-ScheduledTask ShuniangGuard
 $ready=$false
 for($i=0;$i -lt 90;$i++){Start-Sleep -Milliseconds 500;try{$s=Get-Content (Join-Path $data 'status.json') -Raw|ConvertFrom-Json;if($s.allowed -and @($s.checks).Count -eq 15){$ready=$true;break}}catch{}}
 if(!$ready){throw '保护后台未能就绪，安装保持失败关闭'}
 if((Get-FileHash -LiteralPath $policy.configPath).Hash -ne $configHash){throw 'VPN 配置在安装期间被修改'}
 if(($vpnPids -join ',') -ne (@(Get-Process FlClashCore|ForEach-Object Id) -join ',')){throw 'VPN 核心进程发生变化'}
 if($otherTask -and (Export-ScheduledTask AIAppVpnGuard) -ne $otherXml){throw '其他应用保护任务发生变化'}
 if(($otherPids -join ',') -ne (@(Get-Process AIAppVpnGuard -ErrorAction SilentlyContinue|ForEach-Object Id) -join ',')){throw '其他应用保护进程发生变化'}
 $record=@{owner='ShuniangGuard-standalone-v2';state='active';createdNetwork=($createdNetwork -or ($previous -and $previous.createdNetwork));backup=$backup;installedAt=(Get-Date -Format o);claudeStarted=$false}
 $record|ConvertTo-Json|Set-Content (Join-Path $data 'standalone-install.json')
 Write-Result @{status='PASS';message='保护已启用，Claude 未启动';claudeStarted=$false;checks=15;legacyDependency=$false;otherGuardsUnchanged=$true}
}catch{
 $message=$_.Exception.Message
 if($changed){
  Stop-ScheduledTask ShuniangGuard -ErrorAction SilentlyContinue
  Get-CimInstance Win32_Process -Filter "Name='node.exe'"|Where-Object {$_.ExecutablePath -eq (Join-Path $dest 'node.exe')}|ForEach-Object{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
  if(!$previousActive){Unregister-ScheduledTask ShuniangGuard -Confirm:$false -ErrorAction SilentlyContinue;if((Get-ItemPropertyValue $key Debugger -ErrorAction SilentlyContinue) -eq $gate){Remove-ItemProperty $key -Name Debugger -ErrorAction SilentlyContinue;Remove-ItemProperty $key -Name ShuniangGuardOwner -ErrorAction SilentlyContinue};@{owner='ShuniangGuard-standalone-v2';state='failed';createdNetwork=$false}|ConvertTo-Json|Set-Content (Join-Path $data 'standalone-install.json')}
  else {Get-CimInstance Win32_Process -Filter "Name='node.exe'"|Where-Object {$_.ExecutablePath -eq (Join-Path $dest 'node.exe')}|ForEach-Object{Stop-Process -Id $_.ProcessId -Force};Get-ChildItem (Join-Path $backup 'program')|Copy-Item -Destination $dest -Force;Copy-Item (Join-Path $backup 'policy.json') (Join-Path $data 'policy.json') -Force;Start-ScheduledTask ShuniangGuard}
 }
 if($createdNetwork){
  Stop-Service ClaudeNetworkGuard -ErrorAction SilentlyContinue
  & (Join-Path $network 'ClaudeNetworkGuard.exe') remove (Join-Path $network 'policy.json') (Join-Path $data 'network-failed-rollback.json')
  if($LASTEXITCODE -ne 0){
   Start-Service ClaudeNetworkGuard -ErrorAction SilentlyContinue
   @{owner='ShuniangGuard-standalone-v2';state='failed';createdNetwork=$true}|ConvertTo-Json|Set-Content (Join-Path $data 'standalone-install.json')
   Write-Result @{status='FAILED';message=($message+'；网络回滚未完成，服务与恢复记录保留，请重试或卸载');claudeStarted=$false;protectionEnabled=$false};exit 1
  }
  Remove-Service ClaudeNetworkGuard -ErrorAction SilentlyContinue
 }
 if($madeNetworkDirectory -and !(Get-Service ClaudeNetworkGuard -ErrorAction SilentlyContinue)){
  # Only files created by this attempt; fixed absolute directory, no recursive removal.
  foreach($file in 'ClaudeNetworkGuard.exe','policy.json'){Remove-Item -LiteralPath (Join-Path $network $file) -ErrorAction SilentlyContinue}
  if(@(Get-ChildItem -LiteralPath $network -Force).Count -eq 0){Remove-Item -LiteralPath $network}
 }
 Write-Result @{status='FAILED';message=$message;claudeStarted=$false;protectionEnabled=$false};exit 1
}
