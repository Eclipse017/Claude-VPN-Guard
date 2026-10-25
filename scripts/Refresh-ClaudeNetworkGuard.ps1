$ErrorActionPreference='Stop'
$root='C:\Program Files\ClaudeNetworkGuard'
$data='C:\ProgramData\ClaudeNetworkGuard'
$mutex=[Threading.Mutex]::new($false,'Global\ClaudeNetworkGuardReconcile')
$held=$false
try {
  $held=$mutex.WaitOne(0)
  if(-not $held){exit 0}
  $temporary=Join-Path $data ('status.'+$PID+'.tmp')
  & (Join-Path $root 'ClaudeNetworkGuard.exe') apply (Join-Path $root 'policy.json') $temporary
  $code=$LASTEXITCODE
  $result=Get-Content -LiteralPath $temporary -Raw|ConvertFrom-Json
  $result|Add-Member -NotePropertyName CheckedAt -NotePropertyValue (Get-Date -Format o)
  $result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $temporary
  $status=Join-Path $data 'status.json'
  if(Test-Path $status){[IO.File]::Replace($temporary,$status,$null)}else{[IO.File]::Move($temporary,$status)}
  exit $code
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
