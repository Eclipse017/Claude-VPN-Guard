param([Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$ProbeDirectory,[string]$PhysicalInterface='以太网')
$ErrorActionPreference='Stop'
$out=$OutputDirectory
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe=Join-Path $ProbeDirectory 'ClaudeNetworkGuard.exe'
$probe=Join-Path $ProbeDirectory 'ClaudeNetworkProbe.exe'
$config=Join-Path $out 'test-policy.json'
$results=New-Object System.Collections.Generic.List[object]
function Guard([string]$mode,[string]$file) {
  & $exe $mode $config (Join-Path $out $file)
  if($LASTEXITCODE -ne 0){throw (Get-Content (Join-Path $out $file) -Raw)}
  return Get-Content (Join-Path $out $file) -Raw | ConvertFrom-Json
}
function Probe([string]$name,[string]$mode,[string]$ip,[int]$port,[int]$interface,[string]$bind) {
  $path=Join-Path $out ($name+'.json')
  $p=Start-Process -FilePath $probe -ArgumentList @($mode,$ip,$port,$interface,$bind,('"'+$path+'"')) -WindowStyle Hidden -PassThru
  if(-not $p.WaitForExit(15000)){Stop-Process -Id $p.Id;throw 'Synthetic probe exceeded timeout'}
  $r=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  $results.Add([pscustomobject]@{Test=$name;Result=$r})
  return $r
}
try {
  $cfg=[ordered]@{Schema=1;AdapterName='FlClash';AdapterDescription='Meta Tunnel';PackageSid=$null;PackageRoots=@();TestPrograms=@($probe);TestMode=$true;DenyAllNonLoopback=$false}
  $cfg | ConvertTo-Json -Depth 4 | Set-Content $config
  $state=Guard 'status' 'test-before.json'
  if($state.Filters.Count){throw 'Existing test filters found; inspect before replacing.'}
  $tun=Get-NetAdapter -Name 'FlClash'
  $physical=Get-NetAdapter -Name $PhysicalInterface
  $v4=Get-NetIPAddress -InterfaceIndex $physical.ifIndex -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '169.254.*'} | Select-Object -First 1 -ExpandProperty IPAddress
  $r=Probe 'control-tun-tcp' 'tcp' '1.1.1.1' 443 0 '-'
  if($r.Status -ne 'CONNECTED'){throw 'Control TUN connection failed; no blocking policy applied.'}
  $r=Probe 'control-physical-tcp' 'tcp' '1.1.1.1' 443 $physical.ifIndex $v4
  $r=Probe 'control-physical-udp' 'udp' '1.1.1.1' 443 $physical.ifIndex $v4
  $r=Probe 'control-physical-v6-udp' 'udp' ('fe80::1%'+$physical.ifIndex) 443 $physical.ifIndex '-'
  $active=Guard 'apply' 'test-apply.json'
  $idempotent=Guard 'apply' 'test-idempotent.json'
  if($idempotent.Changed){throw 'Idempotent reconciliation unexpectedly changed filters'}
  $r=Probe 'protected-tun-tcp' 'tcp' '1.1.1.1' 443 0 '-'
  if($r.Status -ne 'CONNECTED'){throw 'TUN compatibility test failed'}
  $r=Probe 'protected-proxy-https' 'proxy' '127.0.0.1' 7890 0 '-'
  if($r.Status -ne 'CONNECTED'){throw 'Local proxy HTTPS test failed'}
  $r=Probe 'protected-physical-tcp' 'tcp' '1.1.1.1' 443 $physical.ifIndex $v4
  if($r.NativeError -ne 10013){throw 'Expected WSAEACCES for direct TCP'}
  $r=Probe 'protected-physical-udp' 'udp' '1.1.1.1' 443 $physical.ifIndex $v4
  $r=Probe 'protected-physical-v6-udp' 'udp' ('fe80::1%'+$physical.ifIndex) 443 $physical.ifIndex '-'
  # UDP send() can succeed while WFP asynchronously discards its packet. Require actual
  # kernel CLASSIFY_DROP evidence tied to OUR newly-created filter IDs, not a timeout.
  Start-Sleep -Seconds 1
  $eventsPath=Join-Path $out 'probe-drop-events.xml'
  & netsh.exe wfp show netevents ('file='+$eventsPath) ('appid='+$probe) timewindow=30 | Out-File (Join-Path $out 'probe-drop-events-export.txt')
  if($LASTEXITCODE -ne 0){throw 'Cannot read kernel filtering evidence'}
  [xml]$events=Get-Content -LiteralPath $eventsPath -Raw
  $ownedIds=@($active.Filters.Id|ForEach-Object {"$_"})
  foreach($version in @('FWP_IP_VERSION_V4','FWP_IP_VERSION_V6')) {
    $matches=@($events.netEvents.item|Where-Object {
      $_.type -eq 'FWPM_NET_EVENT_TYPE_CLASSIFY_DROP' -and $_.header.ipProtocol -eq '17' -and $_.header.ipVersion -eq $version -and $_.header.remotePort -eq '443' -and
      @($_.internalFields.terminatingFiltersInfo.item|Where-Object {$_.actionType -eq 'FWP_ACTION_BLOCK' -and $_.filterId -in $ownedIds}).Count -gt 0
    })
    if($matches.Count -lt 1){throw ('No owned WFP UDP drop evidence for '+$version)}
    $results.Add([pscustomobject]@{Test=('kernel-udp-drop-'+$version);Result=[pscustomobject]@{Status='BLOCK_CONFIRMED';Events=$matches.Count;Evidence='probe-drop-events.xml'}})
  }
  # Simulate no approved interface for THIS PROBE ONLY. Actual VPN/routes remain untouched.
  $cfg.DenyAllNonLoopback=$true
  $cfg|ConvertTo-Json -Depth 4|Set-Content $config
  Guard 'apply' 'test-no-interface-apply.json'|Out-Null
  $r=Probe 'missing-interface-tcp' 'tcp' '1.1.1.1' 443 0 '-'
  if($r.NativeError -ne 10013){throw 'Fail-closed test failed'}
  $r=Probe 'missing-interface-proxy-https' 'proxy' '127.0.0.1' 7890 0 '-'
  if($r.Status -ne 'CONNECTED'){throw 'Proxy must remain usable without TUN selection'}
  Guard 'remove' 'test-removed.json' | Out-Null
  $r=Probe 'rollback-tun-tcp' 'tcp' '1.1.1.1' 443 0 '-'
  if($r.Status -ne 'CONNECTED'){throw 'Probe rollback failed'}
  @{Status='PASS';ClaudeStarted=$false;VpnStopped=$false;Results=$results} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'test-result.json')
} catch {
  @{Status='FAILED';Error=$_.ToString();Results=$results} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'test-result.json')
} finally {
  if(Test-Path $config){& $exe 'remove' $config (Join-Path $out 'test-cleanup.json')}
}
