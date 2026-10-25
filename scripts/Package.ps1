param([string]$Version='0.2.0-preview.1',[string]$OutputRoot,[string]$PowerShellRuntime)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$PowerShellRuntime){$PowerShellRuntime=Join-Path $root '.work\runtime\pwsh'}
if(!(Test-Path (Join-Path $PowerShellRuntime 'pwsh.exe'))){throw '先运行 scripts/Fetch-Runtime.ps1 获取已校验的 PowerShell 7 运行环境'}
$name='ShuniangGuard-'+$Version+'-win-x64'
if(!$OutputRoot){$OutputRoot=Join-Path $root 'artifacts\release'}
$out=Join-Path $OutputRoot $name
if(Test-Path $out){throw 'Choose a fresh version/output directory; release builds never overwrite a prior bundle'}
New-Item -ItemType Directory -Path $out,(Join-Path $out 'app\vendor\dsh-pet\assets'),(Join-Path $out 'app\dist\guard') -Force | Out-Null
Copy-Item (Join-Path $root 'node_modules\electron\dist') (Join-Path $out 'runtime') -Recurse
Copy-Item $PowerShellRuntime (Join-Path $out 'pwsh') -Recurse
Copy-Item (Join-Path $root 'dist\ShuniangSetupHost.exe') $out
Copy-Item (Join-Path $root 'dist\setup.cjs') (Join-Path $out 'app\dist')
foreach($part in 'assets','docs'){Copy-Item (Join-Path $root $part) (Join-Path $out 'app') -Recurse}
New-Item -ItemType Directory -Path (Join-Path $out 'app\scripts') -Force | Out-Null
foreach($file in 'build.mjs','Build-Guard.ps1','Install-Guard.ps1','Update-Guard.ps1','Restore-Guard.ps1','Package.ps1','Publish-GitHub.ps1','Backup-ClaudeNetworkGuard.ps1','Build-NetworkGuard.ps1','Test-ClaudeNetworkGuard.ps1','Install-ClaudeNetworkGuard.ps1','Refresh-ClaudeNetworkGuard.ps1','Remove-ClaudeNetworkGuard.ps1'){Copy-Item (Join-Path $root ('scripts\'+$file)) (Join-Path $out 'app\scripts')}
foreach($file in 'Install-Standalone.ps1','Uninstall-Standalone.ps1','Build-Installer.ps1','Fetch-Runtime.ps1'){Copy-Item (Join-Path $root ('scripts\'+$file)) (Join-Path $out 'app\scripts')}
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
@('@echo off','start "" "%~dp0runtime\electron.exe" "%~dp0app\src\main.cjs" --setup') | Set-Content (Join-Path $out '配置向导.cmd') -Encoding ascii
@('书娘守护 · 独立安装预发布版','普通用户请下载 Setup.exe，双击安装后按中文向导操作。','ZIP 解压后可双击「配置向导.cmd」；无需 Node.js、PowerShell 或旧保护器。','启用系统保护需一次管理员确认；不覆盖其他保护器，不会打开 Claude。','仅支持 Windows x64、FlClash、Windows 商店版 Claude；要求独立节点配置。','详见 app\README.md。源代码：https://github.com/Eclipse017/ShuniangGuard','全新机器系统服务安装、真实 Claude 客户端兼容性未实测；不是零泄漏或防封号保证。') | Set-Content (Join-Path $out '先读我.txt') -Encoding utf8
$manifest=Get-ChildItem -LiteralPath $out -File -Recurse | ForEach-Object{[pscustomobject]@{path=$_.FullName.Substring($out.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}}
$manifest | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $out 'manifest.json') -Encoding utf8
$zip=$out+'.zip'
Compress-Archive -LiteralPath $out -DestinationPath $zip -CompressionLevel Optimal
$hash=Get-FileHash $zip
$setup=Join-Path $OutputRoot ('ShuniangGuard-'+$Version+'-Setup.exe')
& (Join-Path $PSScriptRoot 'Build-Installer.ps1') -Payload $zip -Output $setup
$setupHash=(Get-FileHash -LiteralPath $setup).Hash
@(($hash.Hash+'  '+[IO.Path]::GetFileName($zip)),($setupHash+'  '+[IO.Path]::GetFileName($setup))) | Set-Content (Join-Path (Split-Path $out) 'SHA256SUMS.txt') -Encoding ascii
[pscustomobject]@{Directory=$out;Zip=$zip;Setup=$setup;Files=$manifest.Count;SHA256=$hash.Hash;SetupSHA256=$setupHash}|ConvertTo-Json
