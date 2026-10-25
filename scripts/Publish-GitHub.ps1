param([switch]$CreateRepository,[string]$ReleaseZip,[string]$Tag='v0.1.0-preview.2')
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
  $body=@{tag_name=$Tag;name='书娘守护 '+$Tag;prerelease=$true;draft=$false;body="Windows x64 预发布版。下载 ZIP 后先使用「预览书娘.cmd」。互动、策略反例及离线启动探针已验证；未启动真实 Claude 测试。保护安装需管理员权限与本机独立策略。请先阅读 README 和验证边界。`n`n基于 PC2005-cloud/dsh-pet，保留 MIT 署名；书娘图集为本项目 AI 生成素材。不包含任何用户 VPN 配置、凭据或原程序备份。"}|ConvertTo-Json
  $release=Invoke-RestMethod -Method Post -Uri 'https://api.github.com/repos/Eclipse017/ShuniangGuard/releases' -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body))
  $upload=$release.upload_url -replace '\{.*\}$',''
  foreach($file in @($ReleaseZip,(Join-Path (Split-Path $ReleaseZip) 'SHA256SUMS.txt'))){
   $url=$upload+'?name='+[Uri]::EscapeDataString([IO.Path]::GetFileName($file))
   $asset=Invoke-RestMethod -Method Post -Uri $url -Headers $headers -ContentType 'application/octet-stream' -InFile $file
   [pscustomobject]@{asset=$asset.name;size=$asset.size;url=$asset.browser_download_url}|ConvertTo-Json
  }
  [pscustomobject]@{release=$release.html_url;prerelease=$release.prerelease}|ConvertTo-Json
 }
}finally{$credential.Clear();$lines=$null;$headers=$null}
