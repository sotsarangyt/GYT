# GYT installer / updater for MetaTrader 5 (Windows)
# - downloads the latest GYT files from GitHub (main branch)
# - copies them into every MT5 terminal data folder on this PC
# - compiles them with that terminal's MetaEditor (attached EAs reload automatically)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base  = 'https://raw.githubusercontent.com/sotsarangyt/GYT/main'
$files = @(
    @{ Url = "$base/MQL5/Experts/GYT/GYT_MultiEngine.mq5"; Rel = 'Experts\GYT\GYT_MultiEngine.mq5' },
    @{ Url = "$base/MQL5/Scripts/GYT/GYT_DataExport.mq5";  Rel = 'Scripts\GYT\GYT_DataExport.mq5' }
)
$quiet = $false

function Say($msg, $color = 'Gray') { if (-not $quiet) { Write-Host $msg -ForegroundColor $color } }

Say '==================================================' Cyan
Say '  GYT Multi-Engine installer for MetaTrader 5' Cyan
Say '==================================================' Cyan

# 1. download
$tmp = Join-Path $env:TEMP 'GYT_install'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
foreach ($f in $files) {
    $f.Local = Join-Path $tmp (Split-Path $f.Rel -Leaf)
    Invoke-WebRequest -UseBasicParsing -Uri ("{0}?t={1}" -f $f.Url, [DateTime]::UtcNow.Ticks) -OutFile $f.Local
    Say ("Downloaded  {0}" -f (Split-Path $f.Rel -Leaf)) Green
}

# 2. find MT5 terminals
$root = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
if (-not (Test-Path $root)) { throw "No MetaTrader 5 data folder found in $root. Start MT5 once, then run this again." }
$terms = Get-ChildItem -Path $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'MQL5\Experts') }
if (-not $terms) { throw 'No MetaTrader 5 terminal found on this PC.' }

$okCount = 0
foreach ($t in $terms) {
    $originFile = Join-Path $t.FullName 'origin.txt'
    $install = $null
    if (Test-Path $originFile) { $install = (Get-Content -Path $originFile -Raw).Trim() }
    $editor = $null
    if ($install) {
        foreach ($n in 'metaeditor64.exe', 'MetaEditor64.exe', 'metaeditor.exe') {
            $c = Join-Path $install $n
            if (Test-Path $c) { $editor = $c; break }
        }
    }
    Say ''
    Say ("Terminal: {0}" -f ($(if ($install) { $install } else { $t.Name }))) Yellow

    foreach ($f in $files) {
        $dest = Join-Path $t.FullName ("MQL5\" + $f.Rel)
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -Force -Path $f.Local -Destination $dest
        if (-not $editor) { Say '  copied, but MetaEditor not found: compile manually (F7)' Red; continue }

        $log = [IO.Path]::ChangeExtension($dest, '.log')
        if (Test-Path $log) { Remove-Item -Force $log }
        Start-Process -FilePath $editor -ArgumentList ('/compile:"{0}"' -f $dest), ('/log:"{0}"' -f $log) -Wait -WindowStyle Hidden
        $result = if (Test-Path $log) { (Get-Content -Path $log -Raw) } else { '' }
        $summary = ($result -split "`r?`n" | Where-Object { $_ -match 'error' -and $_ -match 'warning' } | Select-Object -Last 1)
        if ($result -match '(?m)\b0 errors?\b' -or $result -match 'Result:\s*0 errors') {
            Say ("  OK   {0}  {1}" -f (Split-Path $f.Rel -Leaf), $summary) Green
            $okCount++
        } else {
            Say ("  FAIL {0}  {1}" -f (Split-Path $f.Rel -Leaf), $summary) Red
            Say ("       log: {0}" -f $log) Red
        }
    }
}

Say ''
if ($okCount -gt 0) {
    Say 'Done. EAs already on a chart reload automatically with the new version.' Green
    Say 'Check the GYT panel on your XAUUSD chart: it must show the new version number.' Green
} else {
    Say 'Nothing compiled successfully. Send a screenshot of this window to Claude.' Red
}
