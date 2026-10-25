param([string]$Payload,[string]$Output)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$Output){$Output=Join-Path $root 'dist\ShuniangSetupHost.exe'}
$compiler='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/r:System.Windows.Forms.dll','/r:System.Drawing.dll','/r:System.Core.dll','/r:Microsoft.CSharp.dll','/r:System.Web.Extensions.dll','/r:System.IO.Compression.dll',('/out:'+$Output))
if($Payload){$arguments+=('/resource:'+$Payload+',payload.zip')}
& $compiler @arguments (Join-Path $root 'src\Installer.cs')
if($LASTEXITCODE -ne 0){throw '安装器构建失败'}
