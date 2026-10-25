$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){throw 'PowerShell 7 required'}
if(!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator permission required'}
$data='C:\ProgramData\ShuniangGuard';$record=Get-Content (Join-Path $data 'install.json') -Raw | ConvertFrom-Json
$key='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Claude.exe'
$expected='"C:\Program Files\ShuniangGuard\ShuniangGuard.exe" --intercept'
if((Get-ItemPropertyValue $key -Name Debugger) -ne $expected){throw 'IFEO changed by another program; refusing overwrite'}
Stop-ScheduledTask -TaskName ShuniangGuard
Unregister-ScheduledTask -TaskName ShuniangGuard -Confirm:$false
if($record.OldDebugger){Set-ItemProperty $key -Name Debugger -Value $record.OldDebugger}else{Remove-ItemProperty $key -Name Debugger}
Remove-ItemProperty $key -Name ShuniangGuardOwner -ErrorAction SilentlyContinue
if($record.HadShortcut -and (Get-FileHash $record.Shortcut).Hash -eq $record.ProtectedShortcutHash){Copy-Item (Join-Path $record.BackupRoot 'Claude.before.lnk') $record.Shortcut -Force}
if($record.OldTaskEnabled){Enable-ScheduledTask ClaudeVpnGuard | Out-Null;Start-ScheduledTask ClaudeVpnGuard}
'Original Claude guard restored. Other application guards unchanged. Files and backups retained. No Claude launched.'
