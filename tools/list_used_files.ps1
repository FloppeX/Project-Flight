param(
    [string]$Example = "res://example/Example1_Simple.tscn",
    [string]$Out = "used_files.txt"
)

$ErrorActionPreference = 'Stop'

function Normalize-ResPath([string]$resPath) {
    if ($resPath -like 'res://*') {
        $rel = $resPath.Substring(6)
        return Join-Path -Path (Get-Location) -ChildPath $rel
    }
    if ([System.IO.Path]::IsPathRooted($resPath)) { return $resPath }
    return Join-Path -Path (Get-Location) -ChildPath $resPath
}

$queue = New-Object System.Collections.Generic.Queue[string]
$visited = New-Object System.Collections.Generic.HashSet[string]

$extRes = New-Object System.Text.RegularExpressions.Regex 'ext_resource[\s\S]*?path="(res://[^"]+)"', ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline)
$preload = New-Object System.Text.RegularExpressions.Regex 'preload\(\s*"(res://[^"]+)"\s*\)'
$load = New-Object System.Text.RegularExpressions.Regex 'load\(\s*"(res://[^"]+)"\s*\)'

$rootAbs = Normalize-ResPath $Example
$queue.Enqueue($rootAbs)

function Enqueue-Path([string]$p) {
    $abs = Normalize-ResPath $p
    if (-not $visited.Contains($abs)) { $queue.Enqueue($abs) }
}

while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    if ($visited.Contains($cur)) { continue }
    $visited.Add($cur) | Out-Null

    if (-not (Test-Path -LiteralPath $cur)) { continue }
    $ext = [System.IO.Path]::GetExtension($cur).ToLowerInvariant()
    if ($ext -eq '.tscn' -or $ext -eq '.tres' -or $ext -eq '.gd') {
        $text = Get-Content -LiteralPath $cur -Raw
        foreach ($m in $extRes.Matches($text)) { Enqueue-Path $m.Groups[1].Value }
        if ($ext -eq '.tscn' -or $ext -eq '.tres') {
            foreach ($m in [regex]::Matches($text, 'script="(res://[^"]+)"')) { Enqueue-Path $m.Groups[1].Value }
        }
        if ($ext -eq '.gd') {
            foreach ($m in $preload.Matches($text)) { Enqueue-Path $m.Groups[1].Value }
            foreach ($m in $load.Matches($text)) { Enqueue-Path $m.Groups[1].Value }
        }
    }
}

$projectRoot = Get-Location
$usedRelPaths = $visited | ForEach-Object { $_.Substring($projectRoot.Path.Length).TrimStart('\','/') } | Sort-Object -Unique
$usedRelPaths | Set-Content -LiteralPath (Join-Path $projectRoot $Out)

Write-Host "Wrote" $usedRelPaths.Count "entries to" $Out


