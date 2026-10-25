$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'dist\network'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$csc='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
foreach($name in @('ClaudeNetworkGuard','ClaudeNetworkProbe')) {
  & $csc /nologo /target:exe /platform:x64 /optimize+ /r:System.Web.Extensions.dll /r:System.ServiceProcess.dll ("/out:"+(Join-Path $out ($name+'.exe'))) (Join-Path $root ('src\network\'+$name+'.cs'))
  if($LASTEXITCODE -ne 0){throw "Build failed: $name"}
}
Get-ChildItem -LiteralPath $out -Filter '*.exe' | Get-FileHash | Select-Object Path,Hash | ConvertTo-Json
