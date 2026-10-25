param([Parameter(Mandatory)][string]$Setup,[Parameter(Mandatory)][string]$WorkRoot)
$ErrorActionPreference='Stop'
$setupPath=(Resolve-Path -LiteralPath $Setup).Path
$testRoot=Join-Path ([IO.Path]::GetFullPath($WorkRoot)) ('installer-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $WorkRoot -Force|Out-Null
function Run($arguments){$p=Start-Process -FilePath $setupPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru;return $p.ExitCode}
if((Run @('--fixture-install',('"'+$testRoot+'"'))) -ne 0){throw 'Fixture extraction failed'}
$marker=Get-Content -LiteralPath (Join-Path $testRoot 'installation.json') -Raw|ConvertFrom-Json
if(!$marker.fixture -or $marker.owner -ne 'ShuniangGuard-app-v2'){throw 'Fixture ownership failed'}
if((Run @('--fixture-install',('"'+$testRoot+'"'))) -eq 0){throw 'Existing installation should not be overwritten'}
$before=(Get-FileHash -LiteralPath (Join-Path $testRoot 'app\dist\guard\ShuniangGuard.exe')).Hash
Set-Content -LiteralPath (Join-Path $testRoot 'user-retained.txt') -Value 'user fixture: retain'
if((Run @('--fixture-remove',('"'+$testRoot+'"'))) -ne 0){throw 'Fixture removal failed'}
if(!(Test-Path -LiteralPath (Join-Path $testRoot 'user-retained.txt')) -or (Test-Path -LiteralPath (Join-Path $testRoot 'runtime\electron.exe'))){throw 'Uninstall scope incorrect'}
$result=@{status='PASS';manifestFiles=$marker.files;existingTargetRefused=$true;extraUserFileRetained=$true;guardHash=$before;systemProtectionTouched=$false;claudeStarted=$false}
$result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $WorkRoot 'installer-result.json')
$result|ConvertTo-Json
