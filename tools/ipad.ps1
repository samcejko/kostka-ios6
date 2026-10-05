# Helpers for talking to the jailbroken iPad over SSH (dot-source this file).
#   . .\tools\ipad.ps1
#   Invoke-IPad 'uname -a'
#   Install-IPadPackage -DebPath .\packages\run-1\com.samcejko.kostka_0.1.0_iphoneos-arm.deb
#   Invoke-Kostka 'kostka:probe?test=info' -WaitSeconds 2 ; Get-KostkaLog
#
# Kostka is installed as the DEB (into /Applications): an app outside the container sandbox may generate code
# (the Java VM's JIT) and keep its game files anywhere.

$script:IPadKey = Join-Path $env:USERPROFILE '.ssh\ipad_ios6'
$script:IPadDefaultHost = '192.168.137.17'
$script:IPadLocalCfg = Join-Path $PSScriptRoot 'local.json'
if (Test-Path $script:IPadLocalCfg) {
    try {
        $c = Get-Content $script:IPadLocalCfg -Raw | ConvertFrom-Json
        if ($c.ipad) { $script:IPadDefaultHost = $c.ipad }
    } catch {}
}

function Get-IPadSshArgs {
    # (keepalives end a session whose Wi-Fi link died instead of waiting for ever)
    @('-i', $script:IPadKey, '-oHostKeyAlgorithms=+ssh-rsa', '-oStrictHostKeyChecking=accept-new', '-oConnectTimeout=10', '-oBatchMode=yes', '-oLogLevel=ERROR',
      '-oServerAliveInterval=5', '-oServerAliveCountMax=4')
}

# Runs a command on the iPad and returns stdout+stderr as plain strings (never throws on stderr output).
function Invoke-IPad {
    param([Parameter(Mandatory = $true)][string]$Command, [string]$IPadHost = $script:IPadDefaultHost)
    $ErrorActionPreference = 'Continue'   # function-local: native stderr must not become a terminating error
    $sshArgs = Get-IPadSshArgs
    & ssh.exe @sshArgs "root@$IPadHost" $Command 2>&1 |
        ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }
}

function Copy-ToIPad {
    param([Parameter(Mandatory = $true)][string]$LocalPath, [Parameter(Mandatory = $true)][string]$RemotePath, [string]$IPadHost = $script:IPadDefaultHost)
    $ErrorActionPreference = 'Continue'
    $sshArgs = Get-IPadSshArgs
    & scp.exe -O @sshArgs $LocalPath "root@${IPadHost}:$RemotePath" 2>&1 |
        ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }
    if ($LASTEXITCODE -ne 0) { throw "scp failed for $LocalPath" }
}

function Copy-FromIPad {
    param([Parameter(Mandatory = $true)][string]$RemotePath, [Parameter(Mandatory = $true)][string]$LocalPath, [string]$IPadHost = $script:IPadDefaultHost)
    $ErrorActionPreference = 'Continue'
    $sshArgs = Get-IPadSshArgs
    & scp.exe -O @sshArgs -r "root@${IPadHost}:$RemotePath" $LocalPath 2>&1 |
        ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }
    if ($LASTEXITCODE -ne 0) { throw "scp failed for $RemotePath" }
}

# Installs the DEB into /Applications (an IPA would land in the sandboxed container: no JIT there)
function Install-IPadPackage {
    param([string]$IpaPath, [string]$DebPath, [string]$IPadHost = $script:IPadDefaultHost)
    if (-not $DebPath -and $IpaPath) {
        $found = Get-ChildItem (Join-Path (Split-Path $IpaPath) 'com.samcejko.kostka_*.deb') -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $DebPath = $found.FullName }
    }
    if (-not $DebPath -or -not (Test-Path $DebPath)) { throw "Kostka is installed from its DEB: pass -DebPath" }
    Invoke-IPad -IPadHost $IPadHost -Command 'killall Kostka 2>/dev/null; ipainstaller -u com.samcejko.kostka 2>/dev/null; echo ok' | Out-Null
    Copy-ToIPad -LocalPath $DebPath -RemotePath '/tmp/Kostka.deb' -IPadHost $IPadHost
    $out = Invoke-IPad -IPadHost $IPadHost -Command 'dpkg -i /tmp/Kostka.deb 2>&1; rm -f /tmp/Kostka.deb; su mobile -c uicache 2>/dev/null; echo DEB_OK' | Out-String
    Write-Host $out
    if ($out -notmatch 'DEB_OK') { throw "Nothing installed" }
    Write-Host "Done. Tap the Kostka icon on the iPad."
}

function Get-IPadCrashLogs {
    param([string]$IPadHost = $script:IPadDefaultHost, [string]$OutDir = '')
    if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'packages\crashlogs' }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    # (the iPad has no head/tail/wc/awk; sed does their work)
    $list = Invoke-IPad -IPadHost $IPadHost -Command "ls -t /var/mobile/Library/Logs/CrashReporter/ 2>/dev/null | grep -i Kostka | sed -n '1,5p'"
    foreach ($f in (@($list) -join "`n" -split "`n" | Where-Object { $_.Trim() })) {
        $name = $f.Trim()
        Copy-FromIPad -IPadHost $IPadHost -RemotePath "/var/mobile/Library/Logs/CrashReporter/$name" -LocalPath (Join-Path $OutDir $name)
        Write-Host "Fetched $name"
    }
    Get-ChildItem $OutDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

# Everything the system logged about Kostka (crashes, jetsam, sandbox), the last $Lines lines
function Get-IPadSyslog {
    param([string]$IPadHost = $script:IPadDefaultHost, [int]$Lines = 200)
    $tail = "sed -e :a -e '`$q;N;$($Lines + 1),`$D;ba'"   # (tail -n emulated: the iPad has no tail)
    Invoke-IPad -IPadHost $IPadHost -Command "grep -i kostka /var/log/syslog | $tail"
}

# The app's own log lines ([Kostka] prefix), the last $Lines of them
function Get-KostkaLog {
    param([int]$Lines = 40, [string]$IPadHost = $script:IPadDefaultHost)
    Invoke-IPad -IPadHost $IPadHost -Command "grep '\[Kostka\]' /var/log/syslog | sed -e :a -e '`$q;N;$($Lines + 1),`$D;ba'"
}

# Opens a kostka: URL in the app (uiopen); -WaitSeconds sleeps on the iPad afterwards
function Invoke-Kostka {
    param([Parameter(Mandatory = $true)][string]$Url, [int]$WaitSeconds = 0, [string]$IPadHost = $script:IPadDefaultHost)
    $cmd = "uiopen '$Url'"
    if ($WaitSeconds -gt 0) { $cmd += "; sleep $WaitSeconds" }
    Invoke-IPad -IPadHost $IPadHost -Command $cmd
}
