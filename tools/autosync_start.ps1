# GoDash auto sync (GitHub main -> Roblox Studio) on the owner's PC.
#   powershell -ExecutionPolicy Bypass -File tools\autosync_start.ps1              start it now (hidden)
#   powershell -ExecutionPolicy Bypass -File tools\autosync_start.ps1 -Install     also start it at every logon
#   powershell -ExecutionPolicy Bypass -File tools\autosync_start.ps1 -Uninstall   stop it and remove everything
# Each start also copies tools\studio_plugin\GoDashAutoSync.lua into Studio's local Plugins folder.
param([switch]$Install, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pluginDir = Join-Path $env:LOCALAPPDATA 'Roblox\Plugins'
$pluginFile = Join-Path $pluginDir 'GoDashAutoSync.lua'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'GoDash AutoSync.lnk'

function Get-AutoSyncProcess {
    Get-CimInstance Win32_Process -Filter "Name like 'python%'" |
        Where-Object { $_.CommandLine -like '*tools*autosync.py*' }
}

if ($Uninstall) {
    Get-AutoSyncProcess | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    if (Test-Path $startup) { Remove-Item $startup -Confirm:$false }
    if (Test-Path $pluginFile) { Remove-Item $pluginFile -Confirm:$false }
    Write-Output 'GoDash auto sync removed (process, logon shortcut, Studio plugin).'
    return
}

New-Item -ItemType Directory -Force $pluginDir | Out-Null
Copy-Item (Join-Path $root 'tools\studio_plugin\GoDashAutoSync.lua') $pluginFile -Force

$pythonw = & python -c "import os,sys; print(os.path.join(os.path.dirname(sys.executable), 'pythonw.exe'))"
if (-not (Test-Path $pythonw)) { throw "pythonw.exe not found next to python ($pythonw)" }

if ($Install) {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($startup)
    $lnk.TargetPath = (Get-Command powershell).Source
    $lnk.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $root 'tools\autosync_start.ps1') + '"'
    $lnk.WorkingDirectory = $root
    $lnk.WindowStyle = 7
    $lnk.Description = 'GoDash: sync GitHub main into Roblox Studio'
    $lnk.Save()
    Write-Output "Logon shortcut: $startup"
}

if (Get-AutoSyncProcess) {
    Write-Output 'GoDash auto sync is already running.'
} else {
    Start-Process -FilePath $pythonw -ArgumentList @('-I', ('"' + (Join-Path $root 'tools\autosync.py') + '"')) -WorkingDirectory $root -WindowStyle Hidden
    Write-Output 'GoDash auto sync started (log: tools\.synced\autosync.log).'
}
