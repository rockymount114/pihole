# performance_nosleep.ps1 - Windows 10 Home safe
# Run as Administrator

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Right-click PowerShell -> Run as Administrator" -ForegroundColor Red
  exit 1
}

Write-Host "=== Setting High Performance + No Sleep ===" -ForegroundColor Cyan

# 1. Activate High Performance plan (works on Home)
$highPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
powercfg /setactive $highPerf
Write-Host "Active plan set to High Performance"

# 2. No sleep/hibernate on AC and Battery
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 30
powercfg /change disk-timeout-ac 0
powercfg /change disk-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0

# 3. Disable hibernate file (frees space, prevents backup interruption)
powercfg /hibernate off

# 4. Battery performance: high perf even on battery + disable USB selective suspend (critical for old E: USB)
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bbe5a8ab8a 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bbe5a8ab8a 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100

# 5. Disable USB selective suspend (prevents old E: USB disconnecting during copy)
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bbe5a8ab8a 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bbe5a8ab8a 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
# Apply
powercfg /setactive SCHEME_CURRENT

# 6. Lid close = Do nothing (laptops)
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0

Write-Host "=== Done - Verify ===" -ForegroundColor Green
powercfg /getactivescheme
powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String "Current"

Write-Host "Now run your backup_v7.ps1 - it won't sleep" -ForegroundColor Cyan
