# if have permission issue run this first 
# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# or
# powershell -ExecutionPolicy Bypass -File D:\restore.ps1

param(
    [string]$SourceRoot = "F:\Users\Spencer",
    [string]$DestRoot = "D:\SSD_Backup\Spencer",
    [string]$LogFile = "D:\SSD_Backup\backup_v7.log",
    [int]$CopyTimeoutMs = 4000,
    [int]$ScanRootTimeoutMs = 20000,
    [int]$ScanSubTimeoutMs = 5000
)

function Write-Log($level, $path) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$level] $path"
    Write-Host $line
    $line | Out-File $LogFile -Append -Encoding utf8
}

New-Item -Force -ItemType Directory -Path $DestRoot | Out-Null
Write-Log "START" "=== $(Get-Date) ==="

$ExcludeDirs = @("ATV Manuals", "CH 13 Truist OBPP Payments_files", "Dell Transfer", "SD")
$ExcludeFiles = @("*.download", "*.crdownload", "*.tmp", "*.part", "*.avi", ".thumbdata*")

function Test-Excluded($path) {
    if ([string]::IsNullOrWhiteSpace($path)) { return $true }
    foreach ($d in $ExcludeDirs) { if ($path -like "*\$d\*" -or $path.EndsWith("\$d")) { return $true } }
    $fn = [System.IO.Path]::GetFileName($path)
    foreach ($f in $ExcludeFiles) { if ($fn -like $f) { return $true } }
    return $false
}

$WorkerScript = Join-Path $env:TEMP "backup_worker.ps1"
@'
param([string]$Mode,[string]$Src,[string]$Dst,[string]$OutFile)
try {
    if ($Mode -eq "copy") {
        $dir = Split-Path $Dst -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Force -ItemType Directory -Path $dir | Out-Null }
        Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
        "OK" | Out-File $OutFile -Encoding utf8
    } elseif ($Mode -eq "scan") {
        Get-ChildItem -LiteralPath $Src -Force -ErrorAction SilentlyContinue |
            ForEach-Object { "$($_.PSIsContainer)|$($_.FullName)" } |
            Out-File $OutFile -Encoding utf8
    }
} catch { "ERR" | Out-File $OutFile -Encoding utf8 }
'@ | Set-Content -LiteralPath $WorkerScript -Encoding utf8 -Force

function Invoke-WithTimeout($mode, $src, $dst, $timeoutMs) {
    $outFile = Join-Path $env:TEMP ("scan_" + [guid]::NewGuid().ToString() + ".txt")
    if (Test-Path $outFile) { Remove-Item $outFile -Force }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $escSrc = $src -replace '"','""'
    $escDst = if ($dst) { $dst -replace '"','""' } else { "" }
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$WorkerScript`" -Mode $mode -Src `"$escSrc`" -Dst `"$escDst`" -OutFile `"$outFile`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)

    $exited = $p.WaitForExit($timeoutMs)
    if (-not $exited) {
        try { $p.Kill() } catch {}
        Start-Sleep -Milliseconds 200
        if (Test-Path $outFile) { Remove-Item $outFile -Force }
        return $null
    }

    if (Test-Path $outFile) {
        $content = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        return $content
    }
    return ""
}

function Copy-File-Safe($srcFile, $dstFile) {
    if (Test-Excluded $srcFile) { return }
    if (Test-Path -LiteralPath $dstFile) { return }
    $result = Invoke-WithTimeout "copy" $srcFile $dstFile $CopyTimeoutMs
    if ($null -eq $result) { Write-Log "SKIP-TIMEOUT" $srcFile }
    elseif ($result -match "OK") { Write-Log "OK" $srcFile }
    else { Write-Log "SKIP-FAIL" $srcFile }
}

function Copy-Tree-Robust($relativePath) {
    $srcRoot = Join-Path $SourceRoot $relativePath
    if (!(Test-Path -LiteralPath $srcRoot)) { return }
    Write-Log "FOLDER" "=== $relativePath ==="
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($srcRoot)
    while ($queue.Count -gt 0) {
        $curDir = $queue.Dequeue()
        if (Test-Excluded $curDir) { Write-Log "SKIP-DIR" $curDir; continue }
        Write-Log "SCAN" $curDir
        $timeout = if ($curDir -eq $srcRoot) { $ScanRootTimeoutMs } else { $ScanSubTimeoutMs }
        $raw = Invoke-WithTimeout "scan" $curDir $null $timeout
        if ($null -eq $raw) { Write-Log "SKIP-DIR-TIMEOUT ${timeout}ms" $curDir; continue }
        foreach ($line in ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne "" })) {
            if ($line.StartsWith("ERR")) { continue }
            $parts = $line.Split('|', 2)
            if ($parts.Count -lt 2) { continue }
            $isDir = $false; try { $isDir = [bool]::Parse($parts[0]) } catch { continue }
            $full = $parts[1]
            if ($isDir) { $queue.Enqueue($full) }
            else {
                $rel = $full.Substring($SourceRoot.Length).TrimStart('\','/')
                $dstFile = Join-Path $DestRoot $rel
                Copy-File-Safe $full $dstFile
            }
        }
    }
}

$list = @("Pictures\Bebop Flights")
foreach ($p in $list) { Copy-Tree-Robust $p }
Write-Log "DONE" "All done"
