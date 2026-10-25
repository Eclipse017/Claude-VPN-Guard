# Removes only this component's service and WFP provider. Does not import a whole-machine firewall backup.
$ErrorActionPreference='Stop'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){throw 'Run this rollback in administrator PowerShell 7.'}
$root='C:\Program Files\ClaudeNetworkGuard'
$data='C:\ProgramData\ClaudeNetworkGuard'
$service=Get-CimInstance Win32_Service -Filter "Name='ClaudeNetworkGuard'"
if($service){
  if($service.PathName -ne '"C:\Program Files\ClaudeNetworkGuard\ClaudeNetworkGuard.exe" --service'){throw 'Service ownership changed; refusing to remove it.'}
  Set-Service -Name 'ClaudeNetworkGuard' -StartupType Disabled
  Stop-Service -Name 'ClaudeNetworkGuard'
}
$mutex=[Threading.Mutex]::new($false,'Global\ClaudeNetworkGuardReconcile')
$held=$false
try {
  $held=$mutex.WaitOne(30000)
  if(-not $held){throw 'Reconciler busy; retry after it finishes. Existing filters were retained.'}
  # Close the integrated startup gate immediately; do not leave a recent PASS after removal.
  $temporary=Join-Path $data 'status.removing.tmp'
  @{Status='REMOVING';FailClosed=$true;FilterCount=0;CheckedAt=([DateTime]::UtcNow.ToString('o'));Reason='Network protection rollback in progress'}|ConvertTo-Json|Set-Content -LiteralPath $temporary
  $status=Join-Path $data 'status.json'
  if(Test-Path $status){[IO.File]::Replace($temporary,$status,$null)}else{[IO.File]::Move($temporary,$status)}
  & (Join-Path $root 'ClaudeNetworkGuard.exe') remove (Join-Path $root 'policy.json') (Join-Path $data 'rollback-result.json')
  if($LASTEXITCODE -ne 0){throw (Get-Content (Join-Path $data 'rollback-result.json') -Raw)}
  if($service){Remove-Service -Name 'ClaudeNetworkGuard'}
  Get-Content (Join-Path $data 'rollback-result.json')
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
# Keep program files, evidence, and backups for recovery and inspection.
