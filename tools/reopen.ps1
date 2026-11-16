# Rebuild GoDash.rbxlx from src/ and reopen it in the Studio window this script owns.
# Only the Studio process recorded in tools/.studio_pid is ever closed.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
python -I tools/build_place.py
if ($LASTEXITCODE -ne 0) { throw 'build failed' }
$pidFile = Join-Path $PSScriptRoot '.studio_pid'
if (Test-Path $pidFile) {
    $id = [int](Get-Content $pidFile)
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -eq 'RobloxStudioBeta') { Stop-Process -Id $id -Force; Start-Sleep -Seconds 3 }
}
$exe = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Recurse -Filter RobloxStudioBeta.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$n = Start-Process -FilePath $exe.FullName -ArgumentList '-task', 'EditFile', '-localPlaceFile', ('"' + (Join-Path $root 'GoDash.rbxlx') + '"') -PassThru
$n.Id | Out-File -Encoding ascii $pidFile
"PID $($n.Id)"
