#Requires -RunAsAdministrator
#Requires -Version 5.1

function Get-PlatformTools {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $Parameters = @{
        Uri             = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
        OutFile         = "$PSScriptRoot\platform-tools.zip"
        UseBasicParsing = $true
    }
    Invoke-WebRequest @Parameters

    $Parameters = @{
        Path            = "$PSScriptRoot\platform-tools.zip"
        DestinationPath = $PSScriptRoot
        Force           = $true
    }
    Expand-Archive @Parameters

    Remove-Item -Path "$PSScriptRoot\platform-tools.zip" -Force
}

function Start-Adb {
    $Env:adb = "$PSScriptRoot\platform-tools\adb.exe"
    .$Env:adb start-server
}

function Stop-Adb {
    .$Env:adb kill-server
}

function Test-AdbConnection {
    $devices = .$Env:adb devices
    if ($devices.Length -gt 3) {
        return "multiple"
    }
    switch ($devices[1]) {
        { $PSItem -match "device" } { return "connected" }
        { $PSItem -match "unauthorized" } { return "unauthorized" }
        { $PSItem -eq "" } { return "disconnected" }
    }
}

function Get-InstalledPackages {
    $packages = @()
    .$Env:adb shell pm list packages | ForEach-Object {
        $packages += $PSItem -replace ("package:", "")
    }
    return $packages
}

function Wait-Retry {
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ -gt 0 })]
        [int]$Seconds
    )
    Write-Host -Object "Retry after $seconds seconds..."
    for ($i = 0; $i -lt $seconds; $i++) {
        $Parameters = @{
            Activity        = "Waiting..."
            Status          = "Seconds remaining:$($seconds-$i)"
            PercentComplete = $([int]$i / $seconds * 100)
        }
        # PowerShell displays 0% as 100%
        if ($Parameters.PercentComplete -eq 0) {
            $Parameters.PercentComplete = 1
        }
        Write-Progress @Parameters
        Start-Sleep -Seconds 1
    }
}

function Get-PackagesToUninstall {
    param (
        [Parameter(Mandatory)]
        [array]$Packages,

        [Parameter(Mandatory)]
        [array]$List
    )

    $i = 0
    $packagesToUninstall = @()

    foreach ($app in $List) {
        $found = $false

        foreach ($package in $Packages) {
            if ($package -in $app.Package) {
                $found = $true
                if ( -not ($packagesToUninstall[$i]) ) {
                    $packagesToUninstall += @{}
                    $packagesToUninstall[$i].Package = @()
                }
                $packagesToUninstall[$i].Name = $app.Name
                $packagesToUninstall[$i].Package += $package
            }
        }

        if ($found) { $i++ }
    }

    return $packagesToUninstall
}

function RemoveDialog {
    param (
        [Parameter(Mandatory)]
        [array]$Packages
    )

    Add-Type -AssemblyName PresentationFramework
    [System.Collections.ArrayList]$PackagesToRemove = @()
    
    [xml]$XAML = Get-Content -Path "$PSScriptRoot\XAML" -Raw
    $Reader = (New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML)
    $Form = [Windows.Markup.XamlReader]::Load($Reader)
    $XAML.SelectNodes("//*[@*[contains(translate(name(.),'n','N'),'Name')]]") | ForEach-Object -Process {
        Set-Variable -Name ($_.Name) -Value $Form.FindName($_.Name)
    }

    function ButtonUninstallSetIsEnabled {
        if ($PackagesToRemove.Count -gt 0) {
            $ButtonUninstall.IsEnabled = $true
        }
        else {
            $ButtonUninstall.IsEnabled = $false
        }
    }

    function CheckBoxClick {
        $CheckBox = $_.Source

        if ($CheckBox.IsChecked) {
            $PackagesToRemove.Add($CheckBox.Tag) | Out-Null
        }
        else {
            $PackagesToRemove.Remove($CheckBox.Tag)
        }

        ButtonUninstallSetIsEnabled
    }

    function CheckBoxSelectAllClick {
        $CheckBox = $_.Source

        if ($CheckBox.IsChecked) {
            $PackagesToRemove.Clear()

            foreach ($Item in $PanelContainer.Children.Children) {
                if ($Item -is [System.Windows.Controls.CheckBox]) {
                    $Item.IsChecked = $true
                    foreach ($tag in $Item.Tag) {
                        $PackagesToRemove.Add($tag)
                    }
                }
            }
        }
        else {
            $PackagesToRemove.Clear()

            foreach ($Item in $PanelContainer.Children.Children) {
                if ($Item -is [System.Windows.Controls.CheckBox]) {
                    $Item.IsChecked = $false
                }
            }
        }

        ButtonUninstallSetIsEnabled
    }

    function ButtonUninstallClick {
        Write-Host -Object "Please wait..."
        $Window.Close() | Out-Null
        Remove-Packages $PackagesToRemove
    }

    foreach ($Package in $Packages) {
        $CheckBox = New-Object -TypeName System.Windows.Controls.CheckBox
        $CheckBox.Tag = $Package.Package

        $TextBlock = New-Object -TypeName System.Windows.Controls.TextBlock
        $TextBlock.Text = $Package.Name

        $StackPanel = New-Object -TypeName System.Windows.Controls.StackPanel
        $StackPanel.Children.Add($CheckBox) | Out-Null
        $StackPanel.Children.Add($TextBlock) | Out-Null

        $PanelContainer.Children.Add($StackPanel) | Out-Null

        $CheckBox.IsChecked = $false
        $CheckBox.Add_Click({ CheckBoxClick })
    }

    $ButtonUninstall.Content = "Uninstall"
    $TextBlockSelectAll.Text = "Select all"
    $ButtonUninstall.Add_Click({ ButtonUninstallClick })
    $CheckBoxSelectAll.Add_Click({ CheckBoxSelectAllClick })

    $Window.Add_Loaded({ $Window.Activate() })
    $Form.ShowDialog() | Out-Null
}

function Remove-Packages {
    param (
        [Parameter(Mandatory)]
        [array]$Packages
    )
    $Packages | ForEach-Object {
        .$Env:adb shell pm uninstall --user 0 $PSItem
        Write-Verbose -Message "Uninstalled $PSItem" -Verbose
    }
}