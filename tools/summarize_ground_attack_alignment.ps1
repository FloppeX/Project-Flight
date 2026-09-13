param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_]+$')][string]$RunTag,
    [switch]$AsJson
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$logRoot = Join-Path $env:APPDATA 'Godot\app_userdata\Land Carrier'
$reports = @(Get-ChildItem -LiteralPath $logRoot -Filter ($RunTag + '_*.json') | Sort-Object Name)
$rows = @(foreach ($file in $reports) {
    $r = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $currentSource = $true
    foreach ($property in $r.hashes.PSObject.Properties) {
        $path = Join-Path $projectPath $property.Name.Substring(6)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $property.Value) { $currentSource = $false }
    }
    $errorLog = Join-Path $logRoot ($file.BaseName + '.stderr.log')
    $scriptErrors = if (Test-Path -LiteralPath $errorLog) {
        @(Select-String -LiteralPath $errorLog -Pattern 'SCRIPT ERROR|Parse Error|Invalid call|Invalid access').Count
    } else { -1 }
    $damage = ($r.targets | Measure-Object damage -Sum).Sum
    $impacted = @($r.projectiles | Where-Object status -eq 'collision')
    $miss = if ($impacted.Count -gt 0) { [math]::Round(($impacted | Measure-Object actual_miss_m -Average).Average, 2) } else { $null }
    $axisCommits = @($r.commit_events | Where-Object { $_.axis_capture.valid -and $_.axis_capture.captured }).Count
    [pscustomobject]@{
        Case=$file.BaseName.Substring($RunTag.Length + 1)
        Status=$r.status
        Seconds=[math]::Round($r.duration_s, 2)
        WallSeconds=[math]::Round($r.wall_duration_s, 2)
        Heading=$r.requested_heading_deg
        Speed=$r.requested_speed_mps
        Alive=$r.aircraft_alive
        Valid=($r.status -eq 'COMPLETE' -and $r.hashes_verified -and $currentSource -and $scriptErrors -eq 0)
        ScriptErrors=$scriptErrors
        Damage=[math]::Round($damage, 2)
        FirstDamage=[math]::Round($r.first_damage_s, 2)
        Releases=$r.releases
        Commits=$r.commits
        AxisCommits=$axisCommits
        ShortJoins=($r.trace | Where-Object { $_.PSObject.Properties.Name -contains 'short_join_count' } | Measure-Object short_join_count -Maximum).Maximum
        MaxShortJoinCheckMs=($r.trace | Where-Object { $_.PSObject.Properties.Name -contains 'short_join_check_ms' } | Measure-Object short_join_check_ms -Maximum).Maximum
        MaxAxisSearchMs=($r.trace | Measure-Object axis_search_ms -Maximum).Maximum
        DirectRevalidations=($r.trace | Where-Object { $_.PSObject.Properties.Name -contains 'direct_revalidations' } | Measure-Object direct_revalidations -Maximum).Maximum
        MaxDirectRevalidationMs=($r.trace | Where-Object { $_.PSObject.Properties.Name -contains 'direct_revalidation_ms' } | Measure-Object direct_revalidation_ms -Maximum).Maximum
        AxisGuidanceSeconds=0.5 * @($r.trace | Where-Object { $_.state -eq 'ATTACK_POSITIONING' -and $_.axis_guidance_active }).Count
        AlignmentAbortsSeconds=$r.end_reasons_s.axis_alignment
        MeanImpactMiss=$miss
        Pending=@($r.projectiles | Where-Object status -eq 'in_flight').Count
        MinAGL=[math]::Round($r.min_agl_m, 2)
        TerrainSeconds=[math]::Round($r.terrain_intervention_s, 2)
        LastState=$r.trace[-1].state
        LastGate=$r.trace[-1].commit
    }
})
if ($AsJson) { $rows | ConvertTo-Json -Depth 4 } else {
    $rows | Format-Table Case,Status,Seconds,Alive,Valid,Damage,FirstDamage,Releases,Commits,AxisCommits,LastGate -AutoSize
}
