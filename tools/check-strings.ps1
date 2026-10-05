# Lists the L(@"...") keys of the sources that have no Czech translation yet (and translations nothing uses).
# Usage: .\tools\check-strings.ps1
$root = Split-Path -Parent $PSScriptRoot
$sources = @(Get-ChildItem (Join-Path $root 'src') -Recurse -Include *.m | Where-Object { $_.FullName -notmatch '\\vendor\\' })
# (LWJGL's iOS backend takes its texts from the app's strings too: KOText(@"..."))
$sources += @(Get-ChildItem (Join-Path $root 'lwjgl\native') -Include *.m -Recurse -ErrorAction SilentlyContinue)
$keys = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $sources) {
    $text = [IO.File]::ReadAllText($f.FullName)
    foreach ($m in [regex]::Matches($text, '(?:\bL|KOText)\(@"((?:[^"\\]|\\.)*)"\)')) { [void]$keys.Add($m.Groups[1].Value) }
}
$stringsPath = Join-Path $root 'Resources\cs.lproj\Localizable.strings'
$strings = [IO.File]::ReadAllText($stringsPath)
$translated = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in [regex]::Matches($strings, '(?m)^"((?:[^"\\]|\\.)*)"\s*=')) { [void]$translated.Add($m.Groups[1].Value) }
$missing = @($keys | Where-Object { -not $translated.Contains($_) } | Sort-Object)
$unused = @($translated | Where-Object { -not $keys.Contains($_) } | Sort-Object)
"keys in sources: $($keys.Count), translated: $($translated.Count), missing: $($missing.Count), unused: $($unused.Count)"
if ($missing) { "--- missing:"; $missing | ForEach-Object { "`"$_`" = `"`";" } }
if ($unused) { "--- unused:"; $unused }
