$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$out=Join-Path $root 'dist\guard'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /nowarn:0649 /target:winexe /platform:x64 /optimize+ /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $out 'ShuniangGuard.exe')) (Join-Path $root 'src\Guard.cs')
if($LASTEXITCODE -ne 0){throw 'Guard compilation failed'}
& $csc /nologo /nowarn:0649 /target:exe /platform:x64 /define:TEST_PROBE /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll ('/out:'+(Join-Path $out 'ShuniangGuardTest.exe')) (Join-Path $root 'src\Guard.cs')
if($LASTEXITCODE -ne 0){throw 'Test harness compilation failed'}
& $csc /nologo /target:exe /platform:x64 ('/out:'+(Join-Path $out 'ShuniangGuardProbe.exe')) (Join-Path $root 'src\Probe.cs')
if($LASTEXITCODE -ne 0){throw 'Probe compilation failed'}
Copy-Item (Get-Command node.exe).Source (Join-Path $out 'node.exe') -Force
& (Join-Path $out 'ShuniangGuardTest.exe') --self-test
if($LASTEXITCODE -ne 0){throw 'Guard unit test failed'}
