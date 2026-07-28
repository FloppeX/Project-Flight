$runnerName = "run_landing_ga_overnight.ps1"
$watchdogs = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq "powershell.exe" -and $_.CommandLine -like ("*" + $runnerName + "*")
}

if (-not $watchdogs) {
    Write-Host "No landing GA overnight watchdog is running."
    exit 0
}

foreach ($watchdog in $watchdogs) {
    $children = Get-CimInstance Win32_Process | Where-Object {
        $_.ParentProcessId -eq $watchdog.ProcessId -and $_.Name -like "Godot*"
    }
    foreach ($child in $children) {
        Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped landing GA Godot process $($child.ProcessId)."
    }
    Stop-Process -Id $watchdog.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped landing GA watchdog $($watchdog.ProcessId)."
}
