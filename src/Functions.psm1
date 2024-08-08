#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

."$PSScriptRoot/Paths.ps1"

#region Platform-Tools

function Set-PlatformTools {
  [CmdletBinding()]
  param()
  process {
    $adbFromPATH = (Get-Command -Name 'adb' -ErrorAction 'SilentlyContinue').Source
    if ($adbFromPATH) {
      $Env:adb = $adbFromPATH
      return
    }
   
    $Env:adb = $AdbFromResources

    $Parameters = @{
      Path     = $AdbFromResources
      PathType = 'Leaf'
    }
    if (-not (Test-Path @Parameters -ErrorAction 'SilentlyContinue')) {
      Get-PlatformTools
    }
  }
}

function Get-PlatformTools {
  [CmdletBinding()]
  param()
  begin {
    $platformToolsArchive = "$Resources/platform-tools.zip"
  }
  process {
    $Parameters = @{
      Uri             = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
      OutFile         = $platformToolsArchive
      UseBasicParsing = $true
    }
    Invoke-WebRequest @Parameters

    $Parameters = @{
      Path            = $platformToolsArchive
      DestinationPath = $Resources
      Force           = $true
    }
    Expand-Archive @Parameters
  }
  end {
    Remove-Item -Path $platformToolsArchive -Force
  }
}

#endregion

#region ADB

function Start-Adb {
  [CmdletBinding()]
  param()
  process {
    .$Env:adb start-server | Out-Null
  }
}

function Stop-Adb {
  [CmdletBinding()]
  param()
  process {
    .$Env:adb kill-server | Out-Null
  }
}

function Test-AdbConnection {
  [CmdletBinding()]
  [OutputType([string])]
  param()
  process {
    $devices = .$Env:adb devices
 
    if ($devices.Length -gt 3) {
      return 'multiple'
    }

    switch ($devices[1]) {
      { $PSItem -match 'device' } {
        return 'connected'
      }
      { $PSItem -match 'unauthorized' } {
        return 'unauthorized'
      }
      { $PSItem -match 'offline' } {
        return 'offline'
      }
      { $PSItem -eq '' } {
        return 'disconnected'
      }
      Default {
        throw 'Unknown device status'
      }
    }
  }
}

function Get-InstalledPackages {
  [CmdletBinding()]
  [OutputType([array])]
  param()
  process {
    .$Env:adb shell pm list packages | ForEach-Object -Process {
      $PSItem.Replace('package:', '')
    }
  }
}

function Get-EnabledPackages {
  [CmdletBinding()]
  [OutputType([array])]
  param()
  process {
    .$Env:adb shell pm list packages -e | ForEach-Object -Process {
      $PSItem.Replace('package:', '')
    }
  }
}

function Get-DisabledPackages {
  [CmdletBinding()]
  [OutputType([array])]
  param()
  process {
    .$Env:adb shell pm list packages -d | ForEach-Object -Process {
      $PSItem.Replace('package:', '')
    }
  }
}

function Get-AppsToProcess {
  [CmdletBinding()]
  [OutputType([array])]
  param (
    [Parameter(Mandatory)]
    [array]$Packages,

    [Parameter(Mandatory)]
    [array]$BloatwareList
  )
  begin {
    $targetLanguage = $PSUICulture.Split('-')[0]
    $appsToProcess = @()
  }
  process {
    $i = 0
    foreach ($bloatwareApp in $BloatwareList) {
      $found = $false

      foreach ($package in $Packages) {
        if ($package -in $bloatwareApp.Packages) {
          $found = $true

          if (-not $appsToProcess[$i]) {
            $appsToProcess += @{}
            $appsToProcess[$i].Packages = @()
          }

          $appsToProcess[$i].Name = if ($bloatwareApp.Name.$targetLanguage) {
            $bloatwareApp.Name.$targetLanguage
          }
          else {
            $bloatwareApp.Name.en
          }
          $appsToProcess[$i].Packages += $package
        }
      }

      if ($found) { $i++ }
    }
  }
  end {
    $appsToProcess
  }
}

function Remove-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Packages
  )
  $Packages | ForEach-Object -Process {
    .$Env:adb shell pm uninstall --user 0 $PSItem
    Write-Verbose -Message "Uninstalled $PSItem"
  }
}

function Disable-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Packages
  )
  $Packages | ForEach-Object -Process {
    .$Env:adb shell pm disable-user --user 0 $PSItem
    Write-Verbose -Message "Disabled $PSItem"
  }
}

function Enable-Packages {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Packages
  )
  $Packages | ForEach-Object -Process {
    .$Env:adb shell pm enable --user 0 $PSItem
    Write-Verbose -Message "Enabled $PSItem"
  }
}

#endregion

#region UI

function Show-Dialog {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [array]$Apps,

    [Parameter(Mandatory)]
    [ValidateSet('uninstall', 'disable', 'enable')]
    [string]$Action
  )
  begin {
    Add-Type -AssemblyName 'PresentationFramework'
    [System.Collections.ArrayList]$packagesToProcess = @()
  }
  process {
    [xml]$xaml = Get-Content -Path $DialogWindow
    $reader = (New-Object -TypeName 'System.Xml.XmlNodeReader' -ArgumentList $xaml)
    $form = [Windows.Markup.XamlReader]::Load($reader)
    $xaml.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
      Set-Variable -Name ($PSItem.Name) -Value $form.FindName($PSItem.Name)
    }

    $SelectAllCheckBox.Content = $Localization.SelectAll
    $ActionButton.Content = $Localization.$Action

    function Set-ActionButtonState {
      [CmdletBinding()]
      param()
      process {
        $ActionButton.IsEnabled = $packagesToProcess.Count -gt 0
      }
    }

    function OnCheckBoxClick {
      [CmdletBinding()]
      param()
      begin {
        $CheckBox = $PSItem.Source
      }
      process {
        if ($CheckBox.IsChecked) {
          $packagesToProcess.Add($CheckBox.Tag) | Out-Null
        }
        else {
          $packagesToProcess.Remove($CheckBox.Tag) | Out-Null
        }
      }
      end {
        Set-ActionButtonState
      }
    }

    function OnSelectAllClick {
      [CmdletBinding()]
      param()
      begin {
        $CheckBox = $PSItem.Source
      }
      process {
        if ($CheckBox.IsChecked) {
          $packagesToProcess.Clear()

          foreach ($Item in $PanelContainer.Children.Children) {
            if ($Item -is [System.Windows.Controls.CheckBox]) {
              $Item.IsChecked = $true
              foreach ($tag in $Item.Tag) {
                $packagesToProcess.Add($tag)
              }
            }
          }
        }
        else {
          $packagesToProcess.Clear()

          foreach ($Item in $PanelContainer.Children.Children) {
            if ($Item -is [System.Windows.Controls.CheckBox]) {
              $Item.IsChecked = $false
            }
          }
        }
      }
      end {
        Set-ActionButtonState
      }
    }

    function OnUninstallButtonClick {
      [CmdletBinding()]
      param()
      process {
        $Window.Close() | Out-Null
        Remove-Packages -Packages $packagesToProcess
      }
    }

    function OnDisableButtonClick {
      [CmdletBinding()]
      param()
      process {
        $Window.Close() | Out-Null
        Disable-Packages -Packages $packagesToProcess
      }
    }

    function OnEnableButtonClick {
      [CmdletBinding()]
      param()
      process {
        $Window.Close() | Out-Null
        Enable-Packages -Packages $packagesToProcess
      }
    }

    foreach ($app in $Apps) {
      $CheckBox = New-Object -TypeName 'System.Windows.Controls.CheckBox'
      $CheckBox.Content = $app.Name
      $CheckBox.Tag = $app.Packages

      $StackPanel = New-Object -TypeName 'System.Windows.Controls.StackPanel'
      $StackPanel.Children.Add($CheckBox) | Out-Null

      $PanelContainer.Children.Add($StackPanel) | Out-Null

      $CheckBox.IsChecked = $false
      $CheckBox.Add_Click({ OnCheckBoxClick })
    }

    $SelectAllCheckBox.Add_Click({ OnSelectAllClick })
    switch -Exact ($Action) {
      'uninstall' {
        $ActionButton.Add_Click({ OnUninstallButtonClick })
        break
      }
      'disable' {
        $ActionButton.Add_Click({ OnDisableButtonClick })
        break
      }
      'enable' {
        $ActionButton.Add_Click({ OnEnableButtonClick })
        break
      }
    }

    Set-MicaBackdrop -WindowName $Window.Title
    $Window.Add_Loaded({ $Window.Activate() })
    $form.ShowDialog() | Out-Null
  }
}

function Set-MicaBackdrop {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [string]$WindowName
  )
  begin {
    Add-Type -TypeDefinition @'
    using System;
    using System.Threading;
    using System.Runtime.InteropServices;
    
    public class DWM {
      [DllImport("dwmapi.dll")]
      private static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        uint dwAttribute,
        ref int pvAttribute,
        uint cbAttribute
      );

      [DllImport("user32.dll")]
      private static extern IntPtr FindWindow(
        string lpClassName,
        string lpWindowName
      );
    
      private static void _SetMicaBackdrop(string lpWindowName, int useDarkMode) {
        IntPtr hwnd;
        do {
          hwnd = FindWindow(null, lpWindowName);
          Thread.Sleep(35);
        } while (hwnd == 0);
    
        int micaBackdrop = 2;
        DwmSetWindowAttribute(hwnd, 38, ref micaBackdrop, sizeof(int));
        DwmSetWindowAttribute(hwnd, 20, ref useDarkMode, sizeof(int));
      }

      public static void SetMicaBackdrop(string lpWindowName, int useDarkMode) {
        Thread thread = new Thread(() => DWM._SetMicaBackdrop(lpWindowName, useDarkMode));
        thread.Start();
      }
    }
'@
  }
  process {
    $Parameters = @{
      Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
      Name = 'AppsUseLightTheme'
    }
    $useDarkMode = (Get-ItemPropertyValue @Parameters) -bxor 1
    [DWM]::SetMicaBackdrop($WindowName, $useDarkMode)
  }
}

#endregion
