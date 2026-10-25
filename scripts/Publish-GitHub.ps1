param([switch]$CreateRepository,[string]$ReleaseZip,[string]$SetupExe,[string]$ReleaseNotes,[string]$Tag='v0.2.0-preview.1')
$ErrorActionPreference='Stop'
$env:GIT_TERMINAL_PROMPT='0';$env:GCM_INTERACTIVE='never'
$lines=(@('protocol=https','host=github.com','') -join "`n") | git credential fill
$credential=@{};foreach($line in $lines){if($line -match '^([^=]+)=(.*)$'){$credential[$matches[1]]=$matches[2]}}
if(!$credential.password){throw 'GitHub authentication unavailable'}
$headers=@{Authorization='Bearer '+$credential.password;Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
try {
 $account=Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
 if($account.login -ne 'Eclipse017'){throw 'Unexpected GitHub account'}
 if($CreateRepository){
  $body=@{name='ShuniangGuard';description='书娘守护：基于 dsh-pet 的独立桌宠与 Claude 节点/分流启动检查';private=$false;auto_init=$false;has_wiki=$false}|ConvertTo-Json
  $repo=Invoke-RestMethod -Method Post -Uri 'https://api.github.com/user/repos' -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  [pscustomobject]@{url=$repo.html_url;visibility=$repo.visibility}|ConvertTo-Json
 }
 if($ReleaseZip){
  if(!$SetupExe -or !$ReleaseNotes){throw '发布需要安装程序与已核对的说明文件'}
  $body=@{tag_name=$Tag;name='书娘守护 '+$Tag;prerelease=$true;draft=$true;body=(Get-Content -LiteralPath $ReleaseNotes -Raw)}|ConvertTo-Json
  $release=Invoke-RestMethod -Method Post -Uri 'https://api.github.com/repos/Eclipse017/ShuniangGuard/releases' -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  $upload=$release.upload_url -replace '\{.*\}$',''
  foreach($file in @($SetupExe,$ReleaseZip,(Join-Path (Split-Path $ReleaseZip) 'SHA256SUMS.txt'))){
   $url=$upload+'?name='+[Uri]::EscapeDataString([IO.Path]::GetFileName($file))
   $asset=Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType 'application/octet-stream' -InFile $file
   $expected='sha256:'+((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant())
   if($asset.digest -ne $expected){throw ('GitHub 资源摘要不匹配：'+$asset.name)}
   [pscustomobject]@{asset=$asset.name;size=$asset.size;url=$asset.browser_download_url}|ConvertTo-Json
  }
  $release=Invoke-RestMethod -Method Patch -Uri $release.url -Headers $headers -ContentType 'application/json' -Body '{"draft":false}'
  [pscustomobject]@{release=$release.html_url;prerelease=$release.prerelease}|ConvertTo-Json
 }
}finally{$credential.Clear();$lines=$null;$headers=$null}
