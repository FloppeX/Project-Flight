param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$TopHitches = 8
)
$ErrorActionPreference = 'Stop'
$capture = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
function Get-Percentile($Values, [double]$Fraction) {
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0) { return 0 }
    return [math]::Round($ordered[[math]::Min($ordered.Count - 1, [math]::Ceiling($ordered.Count * $Fraction) - 1)], 3)
}
$phases = foreach ($group in ($capture.rows | Group-Object phase)) {
    $frames = @($group.Group)
    $rootViews = @($frames | ForEach-Object { $_.render.viewports | Where-Object path -eq '/root' })
    [pscustomobject]@{
        Phase = $group.Name
        Frames = $frames.Count
        P95ms = Get-Percentile $frames.frame_ms 0.95
        MaxMs = Get-Percentile $frames.frame_ms 1
        Over33ms = @($frames | Where-Object frame_ms -gt 33).Count
        RootGpuP95ms = Get-Percentile $rootViews.gpu_ms 0.95
        RootGpuMaxMs = Get-Percentile $rootViews.gpu_ms 1
        RootCpuMaxMs = Get-Percentile $rootViews.cpu_ms 1
        SetupCpuMaxMs = Get-Percentile $frames.render.frame_setup_cpu_ms 1
        DrawWallMaxMs = Get-Percentile $frames.render.draw_wall_ms 1
    }
}
$hitches = foreach ($frame in ($capture.rows | Sort-Object frame_ms -Descending | Select-Object -First $TopHitches)) {
    [pscustomobject]@{
        Phase = $frame.phase
        TimeUs = $frame.time_us
        FrameMs = [math]::Round($frame.frame_ms, 3)
        TransitionPhase = $frame.transition_phase
        SetupCpuMs = $frame.render.frame_setup_cpu_ms
        DrawWallMs = $frame.render.draw_wall_ms
        Viewports = @($frame.render.viewports | Where-Object { $_.mode -ne 0 } | Sort-Object cpu_ms -Descending | Select-Object -First 5)
        Pipelines = $frame.render.pipelines
        Scopes = $frame.scopes
        Terrain = $frame.terrain
    }
}
[pscustomobject]@{
    Status = $capture.status
    Failures = $capture.failures
    Phases = @($phases)
    WorstFrames = @($hitches)
    Pool = $capture.pool
    MaxTraceSampleUs = Get-Percentile $capture.rows.render.trace_sample_us 1
    Note = 'GPU/render queries can lag script frames; disabled/WHEN_VISIBLE viewport timings can be stale. Compare neighborhoods, not one-row attribution.'
} | ConvertTo-Json -Depth 15
