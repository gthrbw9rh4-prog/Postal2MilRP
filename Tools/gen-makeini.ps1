param(
    [Parameter(Mandatory = $true)][string]$SourceIni,
    [Parameter(Mandatory = $true)][string]$OutIni,
    [Parameter(Mandatory = $true)][string]$Package
)

# Builds a ucc "make" ini from the game's own ini so the EditPackages chain
# always matches the installed Postal 2 build, then appends our package last.
$lines = Get-Content -LiteralPath $SourceIni
$out = New-Object System.Collections.Generic.List[string]
$inEditor = $false
$lastEditIdx = -1
$alreadyListed = $false

foreach ($line in $lines) {
    if ($line -match '^\s*\[(.+)\]\s*$') {
        if ($inEditor -and -not $alreadyListed) {
            $out.Insert($lastEditIdx + 1, "EditPackages=$Package")
            $alreadyListed = $true
        }
        $inEditor = ($Matches[1] -ieq 'Editor.EditorEngine')
    }
    elseif ($inEditor -and $line -match '^\s*EditPackages\s*=\s*(.+?)\s*$') {
        if ($Matches[1] -ieq $Package) { $alreadyListed = $true }
        $lastEditIdx = $out.Count
    }
    $out.Add($line)
}

if ($inEditor -and -not $alreadyListed) {
    $out.Insert($lastEditIdx + 1, "EditPackages=$Package")
    $alreadyListed = $true
}

if ($lastEditIdx -lt 0) {
    Write-Error "No [Editor.EditorEngine] EditPackages entries found in $SourceIni"
    exit 1
}

Set-Content -LiteralPath $OutIni -Value $out -Encoding ASCII
Write-Host "[MilRP] Wrote $OutIni ($($out.Count) lines, EditPackages=$Package appended)"
exit 0
