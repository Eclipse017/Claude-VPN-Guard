param([string]$OutputRoot)
$ErrorActionPreference='Stop'
if(!$OutputRoot){$OutputRoot=Join-Path (Split-Path $PSScriptRoot -Parent) '.work\runtime'}
New-Item -ItemType Directory -Path $OutputRoot -Force|Out-Null
$archive=Join-Path $OutputRoot 'PowerShell-7.6.8-win-x64.zip'
if(!(Test-Path $archive)){Invoke-WebRequest 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.8/PowerShell-7.6.8-win-x64.zip' -OutFile $archive}
if((Get-FileHash $archive).Hash -ne 'B9F074F923C499B51EC99D313DA8E9AE90D17A9F3ADF00C73D6189F34D908528'){throw 'PowerShell 发布包哈希不匹配'}
$target=Join-Path $OutputRoot 'pwsh'
if(!(Test-Path $target)){Expand-Archive -LiteralPath $archive -DestinationPath $target}
if((Get-AuthenticodeSignature (Join-Path $target 'pwsh.exe')).Status -ne 'Valid'){throw 'PowerShell Microsoft 签名无效'}
Write-Output 'PASS: PowerShell 7.6.8 archive hash and Microsoft signature verified'
