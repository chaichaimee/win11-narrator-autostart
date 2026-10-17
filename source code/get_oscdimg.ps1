# Downloads oscdimg.exe the same way Tiny11Builder does: from Microsoft's symbol server,
# accepted only if the SHA-256 matches the exact approved binary. Called by make_small_iso.bat.
param([Parameter(Mandatory=$true)][string]$Dest)
$ErrorActionPreference = 'Stop'
$url = 'https://msdl.microsoft.com/download/symbols/oscdimg.exe/688CABB065000/oscdimg.exe'
$sha = '2000160B2C5044691B2F9A0AC308E5207F273D4880A572457AF16D05886BA861'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $dir = Split-Path $Dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $tmp = "$Dest.download"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Write-Host "Downloading oscdimg.exe from the Microsoft symbol server. Please wait."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $tmp -UserAgent 'Microsoft-Symbol-Server/10.0.0.0' -UseBasicParsing
    $got = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash
    if ($got -ne $sha) {
        Remove-Item $tmp -Force
        throw "SHA-256 check failed. The file was rejected and deleted. Got $got"
    }
    Move-Item -Path $tmp -Destination $Dest -Force
    Write-Host "OK: oscdimg.exe saved to $Dest and SHA-256 verified."
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
