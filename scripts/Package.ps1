param([string]$Version='0.1.0-preview.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$name='ShuniangGuard-'+$Version+'-win-x64'
$out=Join-Path $root ('artifacts\release\'+$name)
if(Test-Path $out){throw 'Choose a fresh version/output directory; release builds never overwrite a prior bundle'}
New-Item -ItemType Directory -Path $out,(Join-Path $out 'app\vendor\dsh-pet\assets'),(Join-Path $out 'app\dist\guard') -Force | Out-Null
Copy-Item (Join-Path $root 'node_modules\electron\dist') (Join-Path $out 'runtime') -Recurse
foreach($part in 'assets','docs'){Copy-Item (Join-Path $root $part) (Join-Path $out 'app') -Recurse}
New-Item -ItemType Directory -Path (Join-Path $out 'app\scripts') -Force | Out-Null
foreach($file in 'build.mjs','Build-Guard.ps1','Install-Guard.ps1','Update-Guard.ps1','Restore-Guard.ps1','Package.ps1','Publish-GitHub.ps1','Backup-ClaudeNetworkGuard.ps1','Build-NetworkGuard.ps1','Test-ClaudeNetworkGuard.ps1','Install-ClaudeNetworkGuard.ps1','Refresh-ClaudeNetworkGuard.ps1','Remove-ClaudeNetworkGuard.ps1'){Copy-Item (Join-Path $root ('scripts\'+$file)) (Join-Path $out 'app\scripts')}
# Only reviewed desktop/launch-guard source files; unrelated workspace subprojects are excluded.
New-Item -ItemType Directory -Path (Join-Path $out 'app\src') -Force | Out-Null
Get-ChildItem (Join-Path $root 'src') -File | Copy-Item -Destination (Join-Path $out 'app\src')
Copy-Item (Join-Path $root 'src\network') (Join-Path $out 'app\src') -Recurse
Copy-Item (Join-Path $root 'dist\network') (Join-Path $out 'app\dist') -Recurse
New-Item -ItemType Directory -Path (Join-Path $out 'app\licenses') -Force | Out-Null
foreach($dependency in 'yaml','zod'){Copy-Item (Join-Path $root ('node_modules\'+$dependency+'\LICENSE')) (Join-Path $out ('app\licenses\'+$dependency+'-LICENSE.txt'))}
foreach($file in 'README.md','NOTICE.md','LICENSE','policy.example.json','package.json','package-lock.json'){Copy-Item (Join-Path $root $file) (Join-Path $out 'app')}
Copy-Item (Join-Path $root 'vendor\dsh-pet\lib') (Join-Path $out 'app\vendor\dsh-pet') -Recurse
Copy-Item (Join-Path $root 'vendor\dsh-pet\runtime') (Join-Path $out 'app\vendor\dsh-pet') -Recurse
foreach($file in 'LICENSE','package.json'){Copy-Item (Join-Path $root ('vendor\dsh-pet\'+$file)) (Join-Path $out 'app\vendor\dsh-pet')}
# Assets allowlist: none of the upstream videos, sounds, fonts or images enter the release.
Copy-Item (Join-Path $root 'vendor\dsh-pet\assets\config.jsonc') (Join-Path $out 'app\vendor\dsh-pet\assets')
foreach($file in 'ShuniangGuard.exe','ShuniangGuardTest.exe','ShuniangGuardProbe.exe','sensor.cjs','node.exe'){Copy-Item (Join-Path $root ('dist\guard\'+$file)) (Join-Path $out 'app\dist\guard')}
$nodeLicense=Join-Path (Split-Path (Get-Command node.exe).Source -Parent) 'LICENSE'
if(Test-Path $nodeLicense){Copy-Item $nodeLicense (Join-Path $out 'app\dist\guard\NODE-LICENSE.txt')}
@('@echo off','start "" "%~dp0runtime\electron.exe" "%~dp0app\src\main.cjs" --preview') | Set-Content (Join-Path $out '预览书娘.cmd') -Encoding ascii
@('@echo off','start "" "%~dp0runtime\electron.exe" "%~dp0app\src\main.cjs"') | Set-Content (Join-Path $out '书娘守护.cmd') -Encoding ascii
@('书娘守护 · 预发布版','先双击「预览书娘.cmd」体验。预览模式绝不启动 Claude。','保护后台需要单独安装，配置未通过时保持锁定。','详见 app\README.md。源代码：https://github.com/Eclipse017/ShuniangGuard','未启动真实 Claude 进行测试；不是零泄漏或防封号保证。') | Set-Content (Join-Path $out '先读我.txt') -Encoding utf8
$manifest=Get-ChildItem -LiteralPath $out -File -Recurse | ForEach-Object{[pscustomobject]@{path=$_.FullName.Substring($out.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}}
$manifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $out 'manifest.json') -Encoding utf8
$zip=$out+'.zip'
Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal
$hash=Get-FileHash $zip
($hash.Hash+'  '+[IO.Path]::GetFileName($zip)) | Set-Content (Join-Path (Split-Path $out) 'SHA256SUMS.txt') -Encoding ascii
[pscustomobject]@{Directory=$out;Zip=$zip;Files=$manifest.Count;SHA256=$hash.Hash}|ConvertTo-Json
