# Starts a host and a guest of tests/net_selftest.tscn side by side (loopback) and reports both results.
# Usage: powershell -File tools/run_net_test.ps1 [-Godot "C:\App\Godot_v4.7.2-stable_win64.exe"] [-Port 24999]
param(
    [string]$Godot = "C:\App\Godot_v4.7.2-stable_win64.exe",
    [int]$Port = 24999
)
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\elementalist")).Path
$out = Join-Path $env:TEMP "elementalist_net_test"
New-Item -ItemType Directory -Force $out | Out-Null
$hostArgs = @("--headless", "--path", "`"$project`"", "res://tests/net_selftest.tscn", "--", "--role=host", "--port=$Port")
$guestArgs = @("--headless", "--path", "`"$project`"", "res://tests/net_selftest.tscn", "--", "--role=client", "--port=$Port")
$h = Start-Process -FilePath $Godot -ArgumentList $hostArgs -RedirectStandardOutput "$out\host.log" -RedirectStandardError "$out\host.err" -PassThru -NoNewWindow
$g = Start-Process -FilePath $Godot -ArgumentList $guestArgs -RedirectStandardOutput "$out\guest.log" -RedirectStandardError "$out\guest.err" -PassThru -NoNewWindow
$null = $h.Handle  # (touching the handle keeps ExitCode readable after the process ends)
$null = $g.Handle
$h | Wait-Process -Timeout 90 -ErrorAction SilentlyContinue
$g | Wait-Process -Timeout 90 -ErrorAction SilentlyContinue
Get-Content "$out\host.log" | Select-String "NETTEST|FAIL"
Get-Content "$out\guest.log" | Select-String "NETTEST|FAIL"
Write-Host ("host exit: {0}  guest exit: {1}" -f $h.ExitCode, $g.ExitCode)
# a run fails if either side exited non-zero, never finished, or printed a failing summary
$summary = (Get-Content "$out\host.log", "$out\guest.log" | Select-String "NETTEST .*: \d+ passed, (\d+) failed")
$failed = ($summary | Where-Object { $_.Matches[0].Groups[1].Value -ne "0" }).Count -gt 0
exit ([int]($failed -or $summary.Count -ne 2 -or $h.ExitCode -ne 0 -or $g.ExitCode -ne 0))
