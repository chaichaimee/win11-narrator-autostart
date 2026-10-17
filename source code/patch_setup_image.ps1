# Called by boot_narrator.bat. Patches a MOUNTED Windows Setup image (boot.wim index 2).
# Prints one fact per line. Ends with a RESULT line. Also saves C:\boot_diag.txt for troubleshooting.
param([Parameter(Mandatory=$true)][string]$Mount)
$ErrorActionPreference = 'Stop'
$sys32 = Join-Path $Mount 'Windows\System32'
if (-not (Test-Path (Join-Path $sys32 'Narrator.exe'))) {
    throw "Narrator.exe is not inside this image. Wrong index? Expected the Windows Setup image (index 2)."
}

# 1. Helper that starts Narrator once, after the audio service is running. It logs to X:\narrator_log.txt.
$helper = @'
@echo off
rem Started detached. Never blocks Setup. Log: X:\narrator_log.txt
echo %time% helper started>>X:\narrator_log.txt
for %%d in (C D E F G H I J K L M) do if exist %%d:\autounattend.xml echo %time% autounattend.xml found on %%d:>>X:\narrator_log.txt
if exist "%SystemRoot%\Temp\narrator.started" goto already
md "%SystemRoot%\Temp" 2>nul
echo started>"%SystemRoot%\Temp\narrator.started"
set /a n=0
:wait
sc query audiosrv >X:\narrator_sc.txt 2>&1
find "RUNNING" X:\narrator_sc.txt >nul && goto go
set /a n+=1
if %n% GEQ 30 goto go
ping -n 2 127.0.0.1 >nul
goto wait
:go
echo %time% audio wait finished after %n% tries>>X:\narrator_log.txt
type X:\narrator_sc.txt>>X:\narrator_log.txt
start "" "%SystemRoot%\System32\Narrator.exe"
echo %time% Narrator start issued>>X:\narrator_log.txt
ping -n 8 127.0.0.1 >nul
tasklist 2>>X:\narrator_log.txt | find /i "narrator" >>X:\narrator_log.txt
echo %time% helper finished>>X:\narrator_log.txt
exit /b 0
:already
echo %time% already started, exiting>>X:\narrator_log.txt
exit /b 0
'@
[IO.File]::WriteAllText((Join-Path $sys32 'start_narrator.cmd'), ($helper -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
Write-Host "Helper written: Windows\System32\start_narrator.cmd"

$detached = 'start "" /min X:\Windows\System32\cmd.exe /c X:\Windows\System32\start_narrator.cmd'
$launchIni = 'X:\Windows\System32\cmd.exe, /c ' + $detached
$ini = Join-Path $sys32 'winpeshl.ini'
$snc = Join-Path $sys32 'startnet.cmd'
$result = ''

# 2. Undo the winpeshl.ini that an earlier version of this script CREATED on media that had none.
if (Test-Path $ini) {
    $norm = @([IO.File]::ReadAllLines($ini) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($norm.Count -eq 4 -and $norm[0] -eq '[LaunchApps]' -and $norm[1] -ieq 'X:\Windows\System32\wpeinit.exe' -and $norm[2] -like '*start_narrator.cmd*' -and $norm[3] -ieq '%SYSTEMDRIVE%\sources\setup.exe') {
        Remove-Item $ini -Force
        Write-Host "Removed the winpeshl.ini created by an earlier version. Image is back to its original start layout."
    }
}

# 3. Add Narrator start where Setup really starts from.
if (Test-Path $ini) {
    $lines = [IO.File]::ReadAllLines($ini)
    Write-Host "winpeshl.ini BEFORE:"; $lines | ForEach-Object { Write-Host "  $_" }
    if ($lines -match 'start_narrator') {
        Write-Host "winpeshl.ini already patched."
    } else {
        $out = New-Object System.Collections.Generic.List[string]
        $done = $false
        foreach ($l in $lines) {
            if (-not $done -and $l -match 'setup(_old)?\.exe') { $out.Add($launchIni); $done = $true }
            $out.Add($l)
        }
        if (-not $done) { throw "No setup.exe line found in winpeshl.ini. Not changing it. Review it by hand." }
        [IO.File]::WriteAllLines($ini, $out, [Text.Encoding]::ASCII)
        Write-Host "winpeshl.ini AFTER:"; [IO.File]::ReadAllLines($ini) | ForEach-Object { Write-Host "  $_" }
    }
    $result = 'Narrator is started from winpeshl.ini'
}
elseif (Test-Path $snc) {
    $lines = [IO.File]::ReadAllLines($snc)
    Write-Host "No winpeshl.ini in this image. Found startnet.cmd:"; $lines | ForEach-Object { Write-Host "  $_" }
    if ($lines -match 'start_narrator') {
        Write-Host "startnet.cmd already patched."
    } else {
        $out = New-Object System.Collections.Generic.List[string]
        $at = 0
        if ($lines.Count -gt 0 -and $lines[0].Trim() -ieq '@echo off') { $out.Add($lines[0]); $at = 1 }
        $out.Add($detached)
        for ($i = $at; $i -lt $lines.Count; $i++) { $out.Add($lines[$i]) }
        [IO.File]::WriteAllLines($snc, $out, [Text.Encoding]::ASCII)
        Write-Host "startnet.cmd AFTER:"; [IO.File]::ReadAllLines($snc) | ForEach-Object { Write-Host "  $_" }
    }
    $result = 'Narrator is started from startnet.cmd. Also relies on autounattend.xml. Verify on a real boot.'
}
else {
    Write-Host "No winpeshl.ini and no startnet.cmd in this image. Not creating either, so Setup start is unchanged."
    $result = 'boot.wim not changed for start-up. Narrator relies on autounattend.xml (windowsPE pass). Verify on a real boot.'
}

# 4. Diagnostics. Uses a COPY of the SYSTEM hive, so the image itself is not touched.
$diag = 'C:\boot_diag.txt'
$ErrorActionPreference = 'Continue'
try {
    $d = New-Object System.Collections.Generic.List[string]
    $d.Add("boot.wim index 2 diagnostics, " + (Get-Date))
    $d.Add("--- files in the image root ---")
    Get-ChildItem -Force $Mount | ForEach-Object { $d.Add($_.Name) }
    $d.Add("--- System32 files named *.ini, start*, winpe*, wpeinit*, utilman*, narrator*, setup* ---")
    Get-ChildItem $sys32 -File | Where-Object { $_.Name -match '\.ini$|^start|^winpe|^wpeinit|^utilman|^narrator|^setup' } | ForEach-Object { $d.Add("$($_.Name)  $($_.Length)") }
    $d.Add("--- startnet.cmd ---")
    if (Test-Path $snc) { [IO.File]::ReadAllLines($snc) | ForEach-Object { $d.Add($_) } } else { $d.Add("(missing)") }
    $hive = Join-Path $env:TEMP 'bootsys_copy'
    Copy-Item (Join-Path $sys32 'config\SYSTEM') $hive -Force
    & reg.exe load HKLM\ZBOOTSYS $hive | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $d.Add("--- registry: SYSTEM\Setup ---")
        $q = @(& reg.exe query HKLM\ZBOOTSYS\Setup /s 2>&1 | ForEach-Object { "$_" })
        $q | ForEach-Object { $d.Add($_) }
        $d.Add("--- registry: Audiosrv ---")
        @(& reg.exe query HKLM\ZBOOTSYS\ControlSet001\Services\Audiosrv /v Start 2>&1 | ForEach-Object { "$_" }) | ForEach-Object { $d.Add($_) }
        foreach ($line in $q) { if ($line -match 'CmdLine|SetupType|SystemSetupInProgress') { Write-Host ("Setup registry: " + $line.Trim()) } }
        [gc]::Collect()
        & reg.exe unload HKLM\ZBOOTSYS | Out-Null
    } else {
        $d.Add("Could not load a copy of the SYSTEM hive.")
    }
    Remove-Item $hive -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllLines($diag, $d)
    Write-Host "Diagnostics saved to $diag"
} catch {
    Write-Host "Diagnostics skipped: $($_.Exception.Message)"
}
Write-Host "RESULT: $result"
