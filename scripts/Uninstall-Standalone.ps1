param([Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
$data='C:\ProgramData\ShuniangGuard';$dest='C:\Program Files\ShuniangGuard'
$marker=Join-Path $data 'standalone-install.json'
$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe'
$gate='"C:\Program Files\ShuniangGuard\ShuniangGuard.exe" --intercept'
try {
 if(!(Test-Path -LiteralPath $marker)){@{status='PASS';message='本应用没有安装系统保护，现有保护已保留'}|ConvertTo-Json|Set-Content $ResultPath;exit 0}
 $record=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
 if($record.owner -ne 'ShuniangGuard-standalone-v2'){throw '保护归属不匹配，已停止卸载'}
 if(Get-Process Claude -ErrorAction SilentlyContinue){throw '请自行关闭 Claude 后重试卸载'}
 $debugger=Get-ItemPropertyValue -LiteralPath $key -Name Debugger -ErrorAction SilentlyContinue
 if($debugger -and $debugger -ne $gate){throw 'Claude 启动入口已被其他程序接管，未修改'}
 $task=Get-ScheduledTask ShuniangGuard -ErrorAction SilentlyContinue
 if($task -and ($task.Actions.Execute -ne (Join-Path $dest 'ShuniangGuard.exe') -or $task.Actions.Arguments -ne '--monitor')){throw '任务归属不匹配'}
 if($record.createdNetwork){
  $service=Get-CimInstance Win32_Service -Filter "Name='ClaudeNetworkGuard'"
  if($service -and $service.PathName -ne '"C:\Program Files\ClaudeNetworkGuard\ClaudeNetworkGuard.exe" --service'){throw '网络服务已变更，已停止卸载'}
  if($service){Stop-Service ClaudeNetworkGuard}
  & 'C:\Program Files\ClaudeNetworkGuard\ClaudeNetworkGuard.exe' remove 'C:\Program Files\ClaudeNetworkGuard\policy.json' (Join-Path $data 'uninstall-network.json')
  if($LASTEXITCODE -ne 0){if($service){Start-Service ClaudeNetworkGuard};throw '网络规则移除失败，已保留启动保护'}
  if($service){Remove-Service ClaudeNetworkGuard}
  # Fixed owned filenames only. Keep protected audit records in ProgramData.
  foreach($name in 'ClaudeNetworkGuard.exe','policy.json'){Remove-Item -LiteralPath (Join-Path 'C:\Program Files\ClaudeNetworkGuard' $name) -ErrorAction SilentlyContinue}
  if(@(Get-ChildItem -LiteralPath 'C:\Program Files\ClaudeNetworkGuard' -Force).Count -eq 0){Remove-Item -LiteralPath 'C:\Program Files\ClaudeNetworkGuard'}
 }
 if($task){Stop-ScheduledTask ShuniangGuard;Unregister-ScheduledTask ShuniangGuard -Confirm:$false}
 Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -in @((Join-Path $dest 'node.exe'),(Join-Path $dest 'ShuniangGuard.exe'))}|ForEach-Object{Stop-Process -Id $_.ProcessId -Force}
 if($debugger -eq $gate){Remove-ItemProperty -LiteralPath $key -Name Debugger;Remove-ItemProperty -LiteralPath $key -Name ShuniangGuardOwner -ErrorAction SilentlyContinue}
 $record.state='uninstalled';$record.createdNetwork=$false;$record|ConvertTo-Json|Set-Content -LiteralPath $marker
 @{status='PASS';otherGuardsRetained=$true;claudeStarted=$false;message='本应用系统保护已移除；恢复资料保留在 ProgramData'}|ConvertTo-Json|Set-Content $ResultPath
}catch{@{status='FAILED';message=$_.Exception.Message;claudeStarted=$false}|ConvertTo-Json|Set-Content $ResultPath;exit 1}
