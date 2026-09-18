# Lightweight UnrealScript sanity checks that catch the most common ucc
# failures without needing the compiler: brace balance, misplaced "local"
# declarations, duplicate function names per class, and references to
# MilRP.* classes that do not exist in the package.
param([string]$ClassesDir = (Join-Path $PSScriptRoot '..\MilRP\Classes'))

$ErrorActionPreference = 'Stop'
$files = Get-ChildItem -LiteralPath $ClassesDir -Filter *.uc
$classNames = $files | ForEach-Object { $_.BaseName }
$problems = 0

function Strip-CommentsAndStrings([string]$text) {
    $text = [regex]::Replace($text, '/\*.*?\*/', '', 'Singleline')
    $text = [regex]::Replace($text, '//[^\r\n]*', '')
    $text = [regex]::Replace($text, '"(\\.|[^"\\])*"', '""')
    $text = [regex]::Replace($text, "'[^'\r\n]*'", "''")
    return $text
}

foreach ($f in $files) {
    $raw = Get-Content -LiteralPath $f.FullName -Raw
    $code = Strip-CommentsAndStrings $raw

    # 1. brace / paren balance
    $open = ([regex]::Matches($code, '\{')).Count
    $close = ([regex]::Matches($code, '\}')).Count
    if ($open -ne $close) { Write-Host "[$($f.Name)] brace mismatch: { $open vs } $close"; $problems++ }
    $po = ([regex]::Matches($code, '\(')).Count
    $pc = ([regex]::Matches($code, '\)')).Count
    if ($po -ne $pc) { Write-Host "[$($f.Name)] paren mismatch: ( $po vs ) $pc"; $problems++ }

    # 2. "local" after a statement inside a function body
    $lines = $code -split "`r?`n"
    $inFunc = $false; $depth = 0; $sawStatement = $false; $funcName = ''
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        if (-not $inFunc) {
            if ($l -match '^(simulated\s+|static\s+|exec\s+|final\s+|private\s+|protected\s+|native\s+|event\s+|function\s+)+.*\)\s*$' -or
                $l -match '^(simulated\s+|static\s+|exec\s+|final\s+|private\s+|protected\s+)*(function|event)\s+[^;]*\)\s*$') {
                $inFunc = $true; $depth = 0; $sawStatement = $false; $funcName = $l
            }
            continue
        }
        $depth += ([regex]::Matches($l, '\{')).Count
        $depth -= ([regex]::Matches($l, '\}')).Count
        if ($l -eq '' -or $l -eq '{') { }
        elseif ($l -match '^local\s') {
            if ($sawStatement) { Write-Host "[$($f.Name):$($i+1)] 'local' after statement in: $funcName"; $problems++ }
        }
        elseif ($l -ne '}') { $sawStatement = $true }
        if ($depth -le 0 -and $l -match '\}') { $inFunc = $false }
    }

    # 3. duplicate function names in the same class (state-scoped ones are scoped to their state)
    $names = @()
    $stateStack = @()
    $depth = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i].Trim()
        $open = ([regex]::Matches($l, '\{')).Count
        $close = ([regex]::Matches($l, '\}')).Count
        $depth += $open - $close

        # track state entry / exit so we can scope state function names
        if ($l -match '^(?:auto\s+)?state\s+(\w+)') {
            $stateStack += $Matches[1]
        }
        if ($stateStack.Count -gt 0 -and $depth -le 0 -and $l -match '\}') {
            $stateStack = @()
        }

        if ($l -match '^\s*(?:simulated\s+|static\s+|exec\s+|final\s+|private\s+|protected\s+)*(?:function|event)\s+(?:[\w<>]+\s+)?(\w+)\s*\(') {
            $funcName = $Matches[1]
            if ($stateStack.Count -gt 0) {
                $funcName = $stateStack[$stateStack.Count - 1] + '.' + $funcName
            }
            $names += $funcName
        }
    }
    $dupes = $names | Group-Object | Where-Object { $_.Count -gt 1 }
    foreach ($d in $dupes) { Write-Host "[$($f.Name)] duplicate function name: $($d.Name) x$($d.Count)"; $problems++ }

    # 4. references to MilRP.* or class'MilRP...' that do not exist
    $noComments = [regex]::Replace([regex]::Replace($raw, '/\*.*?\*/', '', 'Singleline'), '//[^\r\n]*', '')
    $refs = [regex]::Matches($noComments, "(?:class'MilRP\.(\w+)'|MilRP\.(\w+))") | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } } | Sort-Object -Unique
    foreach ($r in $refs) {
        if ($classNames -notcontains $r) { Write-Host "[$($f.Name)] references missing class MilRP.$r"; $problems++ }
    }

    # 5. class declaration matches file name
    if ($raw -notmatch "(?m)^class\s+$([regex]::Escape($f.BaseName))\s+extends\s+\w+") {
        Write-Host "[$($f.Name)] class declaration does not match file name"; $problems++
    }
}

if ($problems -eq 0) { Write-Host "lint OK - $($files.Count) files, no issues found" } else { Write-Host "lint found $problems issue(s)"; exit 1 }
