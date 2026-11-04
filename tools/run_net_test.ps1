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
$h | Wait-Process -Timeout 90 -ErrorAction SilentlyContinue
$g | Wait-Process -Timeout 90 -ErrorAction SilentlyContinue
Get-Content "$out\host.log" | Select-String "NETTEST|FAIL"
Get-Content "$out\guest.log" | Select-String "NETTEST|FAIL"
Write-Host ("host exit: {0}  guest exit: {1}" -f $h.ExitCode, $g.ExitCode)
exit ([int]($h.ExitCode -ne 0 -or $g.ExitCode -ne 0))
