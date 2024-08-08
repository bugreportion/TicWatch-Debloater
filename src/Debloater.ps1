#Requires -Version 5.1

#region Preparation

$ErrorActionPreference = 'Stop'

$previousWindowTitle = $Host.UI.RawUI.WindowTitle
$Host.UI.RawUI.WindowTitle = 'ADB Debloater'

Remove-Module -Name 'Functions' -Force -ErrorAction 'SilentlyContinue'
Import-Module -Name "$PSScriptRoot/Functions.psm1"
."$PSScriptRoot/Paths.ps1"

$Parameters = @{
  BindingVariable = 'Localization'
  BaseDirectory   = $Localizations
  FileName        = 'Strings'
}
Import-LocalizedData @Parameters

#endregion

#region Main

Set-PlatformTools
Start-Adb

do {
  $connectionStatus = Test-AdbConnection
  Clear-Host
  switch -Exact ($connectionStatus) {
    'connected' {
      Write-Host -Object $Localization.DeviceConnected -ForegroundColor 'Green'
      break
    }
    'unauthorized' {
      Write-Host -Object $Localization.DeviceUnauthorized -ForegroundColor 'Red'
      Write-Host -Object $Localization.DeviceUnauthorizedInstructions
      Pause
      break
    }
    'offline' {
      Write-Host -Object $Localization.DeviceOffline -ForegroundColor 'Red'
      Write-Host -Object $Localization.DeviceOfflineInstructions
      Pause
      break
    }
    'disconnected' {
      Write-Host -Object $Localization.DeviceDisconnected -ForegroundColor 'Red'
      Write-Host -Object $Localization.DeviceDisconnectedInstructions
      Pause
      break
    }
    'multiple' {
      Write-Host -Object $Localization.MultipleDevicesConnected -ForegroundColor 'Red'
      Write-Host -Object $Localization.MultipleDevicesConnectedInstructions
      Pause
      break
    }
  }
} until ($connectionStatus -eq 'connected')


$Host.UI.RawUI.Flushinputbuffer()
$choice = $Host.UI.PromptForChoice(
  '',
  $Localization.ChooseActionDialogTitle,
  (
    "&1 $($Localization.UninstallPackages)",
    "&2 $($Localization.DisablePackages)",
    "&3 $($Localization.EnablePackages)"
  ),
  0
)
switch ($choice) {
  0 {
    $chosenAction = 'uninstall'
    $packages = Get-InstalledPackages
    break
  }
  1 {
    $chosenAction = 'disable'
    $packages = Get-EnabledPackages
    break
  }
  2 {
    $chosenAction = 'enable'
    $packages = Get-DisabledPackages
    break
  }
}

$Parameters = @{
  Packages      = $packages
  BloatwareList = Get-Content -Path $BloatwareList -Raw | ConvertFrom-Json
}
if (!($Parameters.Packages)) {
  Write-Host -Object $Localization.NoPackagesFound -ForegroundColor 'Yellow'
  Stop-Adb
  Pause
  return
}
Show-Dialog -Apps (Get-AppsToProcess @Parameters) -Action $chosenAction

#endregion

Stop-Adb
$Host.UI.RawUI.WindowTitle = $previousWindowTitle
