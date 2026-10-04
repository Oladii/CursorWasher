$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'build.ps1') -Diagnostics
$exe = Join-Path $windowsRoot '.build\Diagnostics\CursorWasher.Diagnostics.exe'
$probe = Start-Process -FilePath $exe -ArgumentList '--smoke' -WindowStyle Hidden -Wait -PassThru
Get-Content (Join-Path $windowsRoot '.build\Diagnostics\CursorWasher.log') -Tail 5
if ($probe.ExitCode -ne 0) { throw "Window smoke test failed (exit $($probe.ExitCode)). Close other CursorWasher instances first." }
Write-Output 'PASS: native windows, focus, hit testing, hide/reopen and GDI lifetime.'
