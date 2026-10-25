param([Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$ProbeDirectory,[string]$PhysicalInterface='以太网')
$ErrorActionPreference='Stop'
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Test-ClaudeNetworkGuard.ps1') -OutputDirectory $OutputDirectory -ProbeDirectory $ProbeDirectory -PhysicalInterface $PhysicalInterface