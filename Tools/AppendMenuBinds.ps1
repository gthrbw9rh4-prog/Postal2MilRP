# AppendMenuBinds.ps1
# Patches Engine.Input bindings so arrow keys / Enter / Escape can drive the
# MilRP Admin Menu exec functions while preserving the native menu fallbacks.

param(
    [string]$RetailDir = "C:\Program Files (x86)\Steam\steamapps\common\POSTAL2Complete\System"
)

$files = @(
    (Join-Path $RetailDir "DefUser.ini"),
    (Join-Path $RetailDir "User.ini")
)

$section = "[Engine.Input]"

$binds = @{
    "Up"    = "MenuUp | MenuUpButton"
    "Down"  = "MenuDown | MenuDownButton"
    "Left"  = "MenuLeft | MenuLeftButton"
    "Right" = "MenuRight | MenuRightButton"
    "A"     = "MenuLeft | StrafeLeft"
    "D"     = "MenuRight | StrafeRight"
    "W"     = "MenuUp | MoveForward"
    "S"     = "MenuDown | MoveBackward"
    "Enter" = "MenuEnter | InventoryActivate | WantsToSkip | ConfirmButton"
    "Escape"= "MenuClose"
    # 'E' -> custom Interact exec: runs the client-side look-at trace and the
    # reliable ServerInteractWithTarget RPC for solid interact points, then
    # falls back to the native ServerUse path for everything else.
    "E"     = "Interact"
    # 'Tab' -> MilRP roleplay scoreboard (replaces the native frag board and
    # the inventory-menu bind). Hold to view; release auto-closes.
    "Tab"   = "Scoreboard"
}

foreach ($path in $files)
{
    if (!(Test-Path $path))
    {
        Write-Host "Skipping missing file: $path"
        continue
    }

    $lines = Get-Content $path
    $sectionStart = -1
    $sectionEnd = $lines.Length

    for ($i = 0; $i -lt $lines.Length; $i++)
    {
        if ($lines[$i].Trim() -eq $section)
        {
            $sectionStart = $i
            for ($j = $i + 1; $j -lt $lines.Length; $j++)
            {
                if ($lines[$j].StartsWith("["))
                {
                    $sectionEnd = $j
                    break
                }
            }
            break
        }
    }

    if ($sectionStart -lt 0)
    {
        Write-Host "No $section in $path; appending it."
        $lines += ""
        $lines += $section
        $sectionStart = $lines.Length - 1
        $sectionEnd = $lines.Length
    }

    $replaced = @{}
    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++)
    {
        $trim = $lines[$i].Trim()
        foreach ($key in $binds.Keys)
        {
            if ($trim -match "^$key\s*=\s*")
            {
                $lines[$i] = "$key=$($binds[$key])"
                $replaced[$key] = $true
                break
            }
        }
    }

    $newLines = @()
    foreach ($key in $binds.Keys)
    {
        if (!$replaced.ContainsKey($key))
        {
            $newLines += "$key=$($binds[$key])"
        }
    }

    if ($newLines.Length -gt 0)
    {
        $before = $lines[0..($sectionStart)]
        $middle = $lines[($sectionStart + 1)..($sectionEnd - 1)]
        $after = @()
        if ($sectionEnd -lt $lines.Length)
        {
            $after = $lines[$sectionEnd..($lines.Length - 1)]
        }
        $lines = $before + $middle + $newLines + $after
    }

    Set-Content -Path $path -Value $lines -Encoding ASCII
    Write-Host "Patched $path"
}
